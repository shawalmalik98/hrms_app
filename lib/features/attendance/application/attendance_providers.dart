import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/config/app_config.dart';
import '../../../core/location/location_guard.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/security/device_integrity.dart';
import '../../auth/application/auth_provider.dart';
import '../data/attendance_repository.dart';
import '../data/office_sync.dart';
import '../data/offline_queue.dart';
import '../domain/attendance_models.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => ApiAttendanceRepository(ref.watch(apiClientProvider)),
);

/// Office locations saved on the phone for the offline location check.
final officeCacheProvider = Provider<OfficeCache>((ref) {
  final id = ref.watch(authProvider)?.employeeId ?? 'none';
  return OfficeCache.forEmployee(id);
});

/// Punches made offline, one queue per employee.
final offlineQueueProvider = Provider<OfflineQueue>((ref) {
  final id = ref.watch(authProvider)?.employeeId ?? 'none';
  return OfflineQueue('offline_punches_$id');
});

// Each of these watches authProvider so that a logout / different login
// never shows the previous employee's data.
final attendanceHistoryProvider = FutureProvider<List<AttendanceRecord>>((ref) {
  ref.watch(authProvider);
  return loadList(ref.watch(attendanceRepositoryProvider).history);
});

final attendanceRequestsProvider = FutureProvider<List<AttendanceRequest>>((
  ref,
) {
  ref.watch(authProvider);
  return loadList(ref.watch(attendanceRepositoryProvider).requests);
});

enum PunchKind { checkIn, checkOut }

class TodayState {
  const TodayState({
    this.record,
    this.busy = false,
    this.kind,
    this.error,
    this.notice,
    this.offline = false,
  });

  final AttendanceRecord? record;
  final bool busy;

  /// Which punch is in progress while [busy].
  final PunchKind? kind;
  final String? error;

  /// Not an error, e.g. "saved offline, will be sent later".
  final String? notice;

  /// The server could not be reached the last time we tried.
  final bool offline;

  bool get checkedIn => record?.checkIn != null;
  bool get checkedOut => record?.checkOut != null;
}

class TodayAttendanceNotifier extends Notifier<TodayState> {
  bool _syncing = false;
  bool _refreshing = false;

  @override
  TodayState build() {
    ref.watch(authProvider);
    // After build returns: refresh() reads the state, which does not exist yet.
    Future.microtask(refresh);
    return const TodayState();
  }

  AttendanceRepository get _repo => ref.read(attendanceRepositoryProvider);
  OfflineQueue get _queue => ref.read(offlineQueueProvider);
  OfficeCache get _offices => ref.read(officeCacheProvider);

  /// Downloads the office locations so they are available offline. Failing
  /// (e.g. offline) is fine, the last saved copy stays.
  Future<void> _cacheOffices() async {
    final id = ref.read(authProvider)?.employeeId;
    if (id == null) return;
    try {
      // Someone else may have logged in while this was loading: never save
      // one employee's locations under another's name.
      await downloadOffices(
        _repo,
        OfficeCache.forEmployee(id),
        shouldSave: () => ref.read(authProvider)?.employeeId == id,
      );
    } catch (_) {}
  }

  /// Refreshes what the offline location check relies on (offices, geofencing
  /// and work from home days). Called after a work from home request.
  Future<void> refreshOfficeData() => _cacheOffices();

  static const _offlineNotice =
      'You are offline. Attendance is saved and sent later.';

  /// Reloads today's attendance, sends punches saved offline and re-downloads
  /// the office locations. Called on start, when the connection changes, when
  /// the app comes back to the foreground and while the server is unreachable.
  Future<void> refresh() async {
    if (_refreshing || state.busy) return;
    _refreshing = true;
    try {
      unawaited(_cacheOffices());
      await syncPending();
      final pending = await _queue.load();
      try {
        final record = await _repo.today();
        state = TodayState(record: _overlay(record, pending));
      } on ApiException catch (e) {
        state = e.network
            ? TodayState(
                record: _overlay(state.record, pending),
                notice: _offlineNotice,
                offline: true,
              )
            : TodayState(record: state.record, error: e.message);
      }
    } finally {
      _refreshing = false;
    }
  }

  /// The phone lost its connection: show it right away instead of waiting for
  /// the next request to fail.
  void markOffline() {
    if (state.busy || state.offline) return;
    state = TodayState(
      record: state.record,
      notice: _offlineNotice,
      offline: true,
    );
  }

  /// Shows today's punches that are still waiting to be sent as if they were
  /// already on the server, so the boxes keep their times while offline.
  AttendanceRecord? _overlay(
    AttendanceRecord? base,
    List<OfflinePunch> pending,
  ) {
    final now = DateTime.now();
    var record = base;
    for (final p in pending) {
      final sameDay =
          p.time.year == now.year &&
          p.time.month == now.month &&
          p.time.day == now.day;
      if (!sameDay) continue;
      record ??= AttendanceRecord(
        date: DateTime(now.year, now.month, now.day),
        status: AttendanceStatus.notMarked,
        statusLabel: 'Pending sync',
      );
      record = p.isCheckIn
          ? record.copyWith(checkIn: p.time)
          : record.copyWith(checkOut: p.time);
    }
    return record;
  }

  /// Sends the offline punches. Safe to call any time: does nothing when the
  /// queue is empty, and keeps the queue when the server cannot be reached.
  Future<void> syncPending() async {
    if (_syncing) return;
    final pending = await _queue.load();
    if (pending.isEmpty) return;

    _syncing = true;
    try {
      await _repo.pushOffline(pending);
      await _queue.clear();
      state = TodayState(record: await _repo.today());
      ref.invalidate(attendanceHistoryProvider);
    } on ApiException catch (e) {
      if (e.network) return; // still offline, try again later
      if (e.data is List) {
        // Some punches were refused (e.g. outside the office). The server
        // saved the rest, so the queue is done either way.
        await _queue.clear();
        ref.invalidate(attendanceHistoryProvider);
        state = TodayState(record: state.record, error: _rejected(e));
      } else {
        state = TodayState(record: state.record, error: e.message);
      }
    } finally {
      _syncing = false;
    }
  }

  /// The reasons the server gave for each refused offline entry, one per line
  /// ("03 Nov 2026 06:05 PM: Please check in first…"). Falls back to the
  /// general message when the list is empty.
  static String _rejected(ApiException e) {
    final entries = (e.data as List)
        .map((x) => x.toString().trim())
        .where((x) => x.isNotEmpty)
        // Keep the time of the entry but not the distance in metres.
        .map(
          (x) => x.replaceAll(
            RegExp(
              r'You are [\d,]+\s*m away from[^.]*\.(\s*Attendance can be marked within [\d,]+\s*m of your office\.)?',
              caseSensitive: false,
            ),
            'You are not at your office location.',
          ),
        )
        .toList();
    return entries.isEmpty ? _friendly(e.message) : entries.join('\n');
  }

  /// The server's out-of-range message includes the distance
  /// ("You are 11,621 m away from Head Office…"). Show a plain one instead.
  static String _friendly(String message) =>
      RegExp(r'\d+\s*m away from', caseSensitive: false).hasMatch(message)
      ? 'You are not at your office location.'
      : message;

  /// Check in happens once a day.
  Future<void> checkIn() async {
    if (state.busy || state.checkedIn) return;
    await _punch(PunchKind.checkIn, _repo.checkIn);
  }

  /// Needs a check in first. Can be repeated: the last check out of the
  /// day counts. At midnight the day rolls over and it starts again.
  Future<void> checkOut() async {
    if (state.busy || !state.checkedIn) return;
    await _punch(PunchKind.checkOut, _repo.checkOut);
  }

  Future<void> _punch(
    PunchKind kind,
    Future<void> Function({required double latitude, required double longitude})
    action,
  ) async {
    state = TodayState(record: state.record, busy: true, kind: kind);
    // Keep the offline copy of the office locations fresh while online.
    unawaited(_cacheOffices());
    Position? position;
    try {
      final issue = await DeviceIntegrity.check();
      if (issue != null) throw LocationException(issue.message);

      // Older offline punches go first so the server sees them in order.
      await syncPending();

      position = await LocationGuard.currentPosition();
      await action(latitude: position.latitude, longitude: position.longitude);
      unawaited(_learnFromServer(position));
      state = TodayState(record: await _repo.today());
      ref.invalidate(attendanceHistoryProvider);
    } on LocationException catch (e) {
      state = TodayState(record: state.record, error: e.message);
    } on ApiException catch (e) {
      if (e.network && position != null) {
        await _saveOffline(kind, position);
      } else {
        // The server did check this time, so any earlier "it is not checking
        // today" guess is wrong.
        if (_friendly(e.message) != e.message) {
          await _offices.clearServerSkips();
        }
        state = TodayState(record: state.record, error: _friendly(e.message));
      }
    } catch (_) {
      state = TodayState(
        record: state.record,
        error: 'Could not mark attendance. Please try again.',
      );
    }
  }

  ({OfficeLocation office, double distance})? _nearest(
    Position position,
    List<OfficeLocation> offices,
  ) {
    ({OfficeLocation office, double distance})? best;
    for (final o in offices.where((o) => o.hasCoordinates)) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        o.latitude,
        o.longitude,
      );
      if (best == null || distance < best.distance) {
        best = (office: o, distance: distance);
      }
    }
    return best;
  }

  /// An online punch was accepted by the server. If the app thinks the phone
  /// was clearly outside every office, the server is not checking this
  /// employee today (e.g. an approved remote work day): remember that, so the
  /// same punch is not refused when it is made offline.
  Future<void> _learnFromServer(Position position) async {
    final data = await _offices.load();
    if (data == null || data.enforce == false) return;
    final near = _nearest(position, data.offices);
    if (near == null) return;
    if (near.distance > near.office.radiusMeters + position.accuracy + 30) {
      await _offices.markServerSkipsToday();
    }
  }

  /// Same rule as the server: a punch is accepted within the allowed radius
  /// of one of the employee's offices. Not checked at all when the server does
  /// not check this employee (geofencing off, Home job, or a remote work day),
  /// so online and offline always give the same answer.
  Future<String?> _offlineLocationError(Position position) async {
    final data = await _offices.load();
    if (data == null) {
      return 'Office locations are not saved on this phone yet. Connect to '
          'the internet once and try again.';
    }
    if (data.enforce == false) return null;
    if (await _offices.serverSkipsToday()) return null;

    // An approved work from home day: any location is accepted.
    final when = await ref.read(trustedClockProvider).now() ?? DateTime.now();
    if (await _offices.isWfhDay(when)) return null;

    final near = _nearest(position, data.offices);
    if (near == null) {
      return null; // no office with coordinates, nothing to check
    }

    final inside = data.offices
        .where((o) => o.hasCoordinates)
        .any(
          (o) =>
              Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                o.latitude,
                o.longitude,
              ) <=
              o.radiusMeters,
        );
    if (inside) return null;

    const message = 'You are not at your office location.';
    if (!AppConfig.showLocationDetails) return message;
    return '$message\n'
        'Nearest: ${near.office.title} (${near.office.latitude}, ${near.office.longitude}), '
        '${near.distance.round()} m away, allowed ${near.office.radiusMeters.round()} m.\n'
        'Your GPS: ${position.latitude}, ${position.longitude} '
        '(accuracy ${position.accuracy.round()} m)';
  }

  /// No internet: keep the punch on the phone (GPS still works offline). The
  /// server checks the location of each punch when it receives it.
  Future<void> _saveOffline(PunchKind kind, Position position) async {
    // Same location rule as the server, using the saved office locations.
    final locationError = await _offlineLocationError(position);
    if (locationError != null) {
      state = TodayState(record: state.record, error: locationError);
      return;
    }

    // The phone's own clock can be changed, so the punch time comes from the
    // trusted clock (server time + uptime since the last server contact).
    final time = await ref.read(trustedClockProvider).now();
    if (time == null) {
      state = TodayState(
        record: state.record,
        error:
            'No internet, and the time cannot be verified. Connect to the '
            'internet once and try again.',
      );
      return;
    }

    await _queue.add(
      OfflinePunch(
        isCheckIn: kind == PunchKind.checkIn,
        time: time,
        latitude: position.latitude,
        longitude: position.longitude,
      ),
    );
    final pending = await _queue.load();
    state = TodayState(
      record: _overlay(state.record, pending),
      notice:
          'No internet. Saved on your phone, it will be sent when you '
          'are back online.',
      offline: true,
    );
  }
}

final todayAttendanceProvider =
    NotifierProvider<TodayAttendanceNotifier, TodayState>(
      TodayAttendanceNotifier.new,
    );
