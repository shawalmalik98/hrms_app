import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  const StoredSession({
    required this.token,
    required this.employeeId,
    required this.name,
  });

  final String token;
  final String employeeId;
  final String name;
}

/// Keeps the Bearer-Token, the logged in employee and a stable per-install
/// device id (the server binds an account to an approved device).
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kToken = 'token';
  static const _kEmployeeId = 'employee_id';
  static const _kName = 'name';
  static const _kDeviceToken = 'device_token';

  String? _token;
  String? get token => _token;

  Future<StoredSession?> load() async {
    try {
      final token = await _storage.read(key: _kToken);
      final id = await _storage.read(key: _kEmployeeId);
      final name = await _storage.read(key: _kName);
      if (token == null || id == null) return null;
      _token = token;
      return StoredSession(token: token, employeeId: id, name: name ?? id);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(StoredSession s) async {
    _token = s.token;
    await _storage.write(key: _kToken, value: s.token);
    await _storage.write(key: _kEmployeeId, value: s.employeeId);
    await _storage.write(key: _kName, value: s.name);
  }

  Future<void> clear() async {
    _token = null;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kEmployeeId);
    await _storage.delete(key: _kName);
  }

  String? _deviceToken;

  /// Available synchronously once [deviceToken] has run (main.dart does this
  /// at startup) so the HTTP client can send it as the `Device-Token` header.
  String? get cachedDeviceToken => _deviceToken;

  Future<String> deviceToken() async {
    final cached = _deviceToken;
    if (cached != null) return cached;

    var value = await _storage.read(key: _kDeviceToken);
    if (value == null) {
      final r = Random.secure();
      value = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
      await _storage.write(key: _kDeviceToken, value: value);
    }
    return _deviceToken = value;
  }
}
