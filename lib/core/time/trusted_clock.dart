import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A clock that does not depend on the phone's date / time setting.
///
/// Every time the server answers, its time (the HTTP `Date` header) is saved
/// together with the phone's monotonic uptime. Offline, the time is the saved
/// server time plus the uptime that passed since. Changing the phone's clock
/// does not move the uptime, so it cannot be used to fake a punch time.
///
/// Android only. When the clock cannot be trusted [now] returns null: the
/// phone restarted since the last contact with the server, the last contact
/// is too old, or the platform has no uptime counter.
class TrustedClock {
  TrustedClock([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _channel = MethodChannel('hrms/clock');
  static const _key = 'time_anchor';

  /// Offline punches are refused when the last server contact is older.
  static const maxAge = Duration(hours: 24);

  final FlutterSecureStorage _storage;
  final Stopwatch _sinceAnchor = Stopwatch();
  bool _anchored = false;

  Future<({int elapsed, int boot})?> _snapshot() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('snapshot');
      final elapsed = (map?['elapsed'] as num?)?.toInt();
      if (elapsed == null) return null;
      return (elapsed: elapsed, boot: (map?['boot'] as num?)?.toInt() ?? -1);
    } catch (_) {
      return null;
    }
  }

  /// Call with the server time whenever the server answers.
  Future<void> anchor(DateTime serverTime) async {
    // Saving on every response is wasteful, once in a while is plenty.
    if (_anchored && _sinceAnchor.elapsed < const Duration(seconds: 30)) return;
    final snap = await _snapshot();
    if (snap == null) return;
    _anchored = true;
    _sinceAnchor
      ..reset()
      ..start();
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'server': serverTime.toUtc().millisecondsSinceEpoch,
          'elapsed': snap.elapsed,
          'boot': snap.boot,
        }),
      );
    } catch (_) {}
  }

  /// The real current time, or null if it cannot be worked out safely.
  Future<DateTime?> now() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final a = jsonDecode(raw) as Map<String, dynamic>;
      final snap = await _snapshot();
      if (snap == null) return null;

      final anchorElapsed = (a['elapsed'] as num).toInt();
      final sameBoot = snap.boot == (a['boot'] as num).toInt();
      if (!sameBoot || snap.elapsed < anchorElapsed) return null; // rebooted

      final passed = Duration(milliseconds: snap.elapsed - anchorElapsed);
      if (passed > maxAge) return null;

      return DateTime.fromMillisecondsSinceEpoch(
        (a['server'] as num).toInt(),
        isUtc: true,
      ).add(passed).toLocal();
    } catch (_) {
      return null;
    }
  }
}
