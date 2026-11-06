import 'dart:convert';

import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../leave/domain/time_off_models.dart';
import '../domain/attendance_models.dart';

abstract class AttendanceRepository {
  Future<AttendanceRecord?> today();
  Future<void> checkIn({required double latitude, required double longitude});
  Future<void> checkOut({required double latitude, required double longitude});
  Future<List<AttendanceRecord>> history();
  Future<List<AttendanceRequest>> requests();
  Future<void> submitRequest(NewAttendanceRequest request);

  /// Changes a pending attendance request.
  Future<void> updateRequest(String id, NewAttendanceRequest request);

  /// Sends punches made offline. Throws [ApiException] with a list in `data`
  /// when some were refused (the accepted ones are saved by the server).
  Future<void> pushOffline(List<OfflinePunch> punches);

  /// The employee's office locations and allowed radius.
  Future<List<OfficeLocation>> officeLocations();

  /// Whether the server checks this employee's location (geofencing on and
  /// an Office job). Null when the answer cannot be found in the response.
  Future<bool?> geofenceEnforced();

  /// `yyyy-MM-dd` days (from today, 2 months ahead) on which the employee's
  /// work from home is approved. On those days the server accepts attendance
  /// from any location.
  Future<List<String>> wfhApprovedDates();
}

class ApiAttendanceRepository implements AttendanceRepository {
  ApiAttendanceRepository(this._api);

  final ApiClient _api;

  static final _day = DateFormat('yyyy-MM-dd');

  @override
  Future<AttendanceRecord?> today() async {
    final json = await _api.get('get-my-todays-attendance');
    final data = json['data'];
    if (data is! List || data.isEmpty || data.first is! Map) return null;
    final row = Map<String, dynamic>.from(data.first as Map);

    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day);
    final checkIn = row['check_in_status'].toString() == '1'
        ? _combine(date, row['check_in_time'])
        : null;
    final checkOut = row['check_out_status'].toString() == '1'
        ? _combine(date, row['check_out_time'])
        : null;
    final label = row['attendance_status']?.toString() ?? '';
    return AttendanceRecord(
      date: date,
      status: AttendanceStatus.fromApi(label),
      statusLabel: label,
      checkIn: checkIn,
      checkOut: checkOut,
    );
  }

  @override
  Future<void> checkIn({
    required double latitude,
    required double longitude,
  }) async {
    await _api.post('checkinattendance', {
      'location_latitude': '$latitude',
      'location_longitude': '$longitude',
    });
  }

  @override
  Future<void> checkOut({
    required double latitude,
    required double longitude,
  }) async {
    await _api.post('checkoutattendance', {
      'location_latitude': '$latitude',
      'location_longitude': '$longitude',
    });
  }

  @override
  Future<List<AttendanceRecord>> history() async {
    final json = await _api.get('my-attendance');
    final days = (json['data'] as Map?)?['days'];
    if (days is! List) return const [];

    final records = <AttendanceRecord>[];
    for (final d in days.whereType<Map>()) {
      final label = d['status']?.toString() ?? '';
      if (label == '-') continue; // before joining / future
      final date = DateTime.tryParse(d['date']?.toString() ?? '');
      if (date == null) continue;
      records.add(
        AttendanceRecord(
          date: date,
          status: AttendanceStatus.fromApi(label),
          statusLabel: label,
          checkIn: _combine(date, d['check_in_time']),
          checkOut: _combine(date, d['check_out_time']),
        ),
      );
    }
    return records.reversed.toList();
  }

  @override
  Future<List<AttendanceRequest>> requests() async {
    final json = await _api.get('my-attendance-request');
    final data = json['data'];
    final rows = data is Map && data['my_requests'] is List
        ? _rows(data['my_requests'])
        : _rows(data);
    final responded = {
      ...responseIds(data is Map ? data['responsed_request'] : null),
      ...responseIds(data is Map ? data['get_manager_response'] : null),
    };

    String? pick(Map row, List<String> keys) {
      for (final k in keys) {
        final v = row[k]?.toString().trim();
        if (v != null && v.isNotEmpty && v != 'null') return v;
      }
      return null;
    }

    return rows.map((row) {
      final id = pick(row, ['attendance_request_id', 'id']) ?? '';
      return AttendanceRequest(
        id: id,
        responded: responded.contains(id),
        appliedFor: DateTime.tryParse(
          pick(row, [
                'request_attendance_date',
                'attendance_date',
                'attendance_request_date',
                'request_date',
                'date',
              ]) ??
              '',
        ),
        typeLabel:
            pick(row, [
              'request_attendance_status',
              'attendance_type',
              'attendance_request_type',
              'request_type',
              'type',
            ]) ??
            'Attendance Request',
        message:
            pick(row, [
              'request_attendance_message',
              'attendance_message',
              'message',
              'reason',
            ]) ??
            '',
        status: RequestStatus.fromApi(
          pick(row, [
            'request_approved_by_hr',
            'attendance_request_status',
            'request_status',
            'approval_status',
            'status',
          ]),
        ),
        checkIn: pick(row, ['attendance_checkin_time', 'check_in_time']),
        checkOut: pick(row, ['attendance_checkout_time', 'check_out_time']),
      );
    }).toList();
  }

  @override
  Future<void> submitRequest(NewAttendanceRequest request) async {
    await _api.post('submit-attendance-request', {
      'days_assign': 'single',
      'attendance_date': _day.format(request.date),
      'attendance_type': request.type.apiValue,
      'attendance_message': request.message,
      if (request.type.needsCheckIn) 'check_in_time': request.checkIn,
      if (request.type.needsCheckOut) 'check_out_time': request.checkOut,
    });
  }

  @override
  Future<void> updateRequest(String id, NewAttendanceRequest request) async {
    await _api.post('update-attendance-request', {
      'attendance_id': id,
      'edit_attendance_date': _day.format(request.date),
      'edit_attendance_type': request.type.apiValue,
      'edit_attendance_message': request.message,
      if (request.type.needsCheckIn) 'check_in_time': request.checkIn,
      if (request.type.needsCheckOut) 'check_out_time': request.checkOut,
    });
  }

  @override
  Future<void> pushOffline(List<OfflinePunch> punches) async {
    // The server refuses a check out that has no check in before it, so
    // check ins go first, then everything in time order.
    final ordered = [...punches]
      ..sort((a, b) {
        final byDay = DateTime(
          a.time.year,
          a.time.month,
          a.time.day,
        ).compareTo(DateTime(b.time.year, b.time.month, b.time.day));
        if (byDay != 0) return byDay;
        if (a.isCheckIn != b.isCheckIn) return a.isCheckIn ? -1 : 1;
        return a.time.compareTo(b.time);
      });
    await _api.post('offline-attendance', {
      'attendance_object': jsonEncode(ordered.map((p) => p.toApi()).toList()),
    });
  }

  @override
  Future<List<OfficeLocation>> officeLocations() async {
    final json = await _api.get('employee-mapped-location');
    final data = json['data'];
    if (data is! List) return const [];
    return data
        .map(OfficeLocation.fromApi)
        .whereType<OfficeLocation>()
        .toList();
  }

  @override
  Future<bool?> geofenceEnforced() async {
    final json = await _api.get('get-employee-detail');
    final geofencing = _find(json['data'], 'employee_geofencing_enability');
    if (!geofencing.found) return null;

    final on = switch (geofencing.value?.toString().toLowerCase()) {
      '1' || 'true' || 'on' || 'yes' => true,
      _ => false,
    };
    final job = _find(
      json['data'],
      'employee_jobtype',
    ).value?.toString().toLowerCase();
    final isHome = job != null && job.startsWith('home');
    return on && !isHome;
  }

  @override
  Future<List<String>> wfhApprovedDates() async {
    // `status` is false when today is not a work from home day; the list is
    // still in `data`, so it is read from the error too.
    dynamic data;
    try {
      data = (await _api.get('wfh-today'))['data'];
    } on ApiException catch (e) {
      if (e.network) rethrow;
      data = e.data;
    }
    final dates = data is Map ? data['approved_dates'] : null;
    return dates is List ? dates.map((d) => '$d').toList() : const [];
  }

  /// Looks for [key] anywhere in a JSON value (the shape of the response is
  /// not documented).
  static ({bool found, dynamic value}) _find(dynamic node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return (found: true, value: node[key]);
      for (final v in node.values) {
        final r = _find(v, key);
        if (r.found) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _find(v, key);
        if (r.found) return r;
      }
    }
    return (found: false, value: null);
  }

  /// `HH:mm:ss` on [date]. Null for missing or `00:00:00`.
  static DateTime? _combine(DateTime date, dynamic raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty || text == '00:00:00') return null;
    final parts = text.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    if (h == null || m == null) return null;
    return DateTime(date.year, date.month, date.day, h, m, s);
  }

  /// The request list shape is not documented: accept a list of rows, or a
  /// map that wraps one.
  static List<Map> _rows(dynamic data) {
    if (data is List) return data.whereType<Map>().toList();
    if (data is Map) {
      for (final v in data.values) {
        if (v is List && v.isNotEmpty && v.first is Map) {
          return v.whereType<Map>().toList();
        }
      }
    }
    return const [];
  }
}
