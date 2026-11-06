import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/location/location_guard.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/session_store.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/data/office_sync.dart';
import '../../attendance/data/offline_queue.dart';

class AuthUser {
  const AuthUser({required this.employeeId, required this.name});
  final String employeeId;
  final String name;
}

/// Login was refused because the account is bound to another phone and a
/// request for this phone is now waiting for HR / Admin approval.
class DevicePendingException extends ApiException {
  const DevicePendingException(super.message, {this.registeredDevice});
  final String? registeredDevice;
}

/// Why the user was sent back to the login screen without asking to log out
/// (expired token, or the account was opened on another phone).
class LogoutNoticeNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? message) => state = message;
}

final logoutNoticeProvider = NotifierProvider<LogoutNoticeNotifier, String?>(
  LogoutNoticeNotifier.new,
);

/// Session restored from secure storage before the app starts (see main.dart).
final initialSessionProvider = Provider<StoredSession?>((ref) => null);

class AuthNotifier extends Notifier<AuthUser?> {
  @override
  AuthUser? build() {
    final s = ref.watch(initialSessionProvider);
    return s == null ? null : AuthUser(employeeId: s.employeeId, name: s.name);
  }

  /// Throws [ApiException] with a message fit to show the user.
  Future<void> login(String employeeCode, String password) async {
    final session = ref.read(sessionStoreProvider);
    final position = await LocationGuard.tryCurrentPosition();

    final Json json;
    try {
      json = await ref.read(apiClientProvider).post('login-process', {
        'employee_code': employeeCode,
        'employee_password': password,
        'device_token': await session.deviceToken(),
        'device_name': await _deviceName(),
        'login_history_latitude': '${position?.latitude ?? 0}',
        'login_history_longitude': '${position?.longitude ?? 0}',
      });
    } on ApiException catch (e) {
      final data = e.data;
      if (data is Map && data['device_status'] == 'pending') {
        throw DevicePendingException(
          e.message,
          registeredDevice: data['registered_device']?.toString(),
        );
      }
      rethrow;
    }

    final token = json['token']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException('Login failed. No token received.');
    }
    final name = _employeeName(json['data']) ?? employeeCode;
    await session.save(
      StoredSession(token: token, employeeId: employeeCode, name: name),
    );

    // Login needs the internet, so this is the moment to take this employee's
    // office locations for the offline location check. Whatever an earlier
    // login left on the phone is thrown away first, so a stale copy can never
    // be used: it is either fresh or missing.
    final offices = OfficeCache.forEmployee(employeeCode);
    await offices.clear();
    try {
      await downloadOffices(
        ApiAttendanceRepository(ref.read(apiClientProvider)),
        offices,
      );
    } catch (_) {
      // Retried on the next refresh.
    }

    state = AuthUser(employeeId: employeeCode, name: name);
  }

  Future<void> logout() async {
    final id = state?.employeeId;
    if (id != null) {
      await OfficeCache.forEmployee(id).clear();
      try {
        await const FlutterSecureStorage().delete(key: 'profile_$id');
      } catch (_) {}
    }
    await ref.read(sessionStoreProvider).clear();
    state = null;
  }

  static Future<String> _deviceName() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return '${a.brand} ${a.model}';
      }
      if (Platform.isIOS) return (await info.iosInfo).utsname.machine;
    } catch (_) {}
    return 'Unknown device';
  }

  /// The login `data` shape is not documented, so look for common keys.
  static String? _employeeName(dynamic data) {
    final map = data is List && data.isNotEmpty ? data.first : data;
    if (map is! Map) return null;
    for (final key in [
      'employee_name',
      'name',
      'full_name',
      'employee_fullname',
    ]) {
      final v = map[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    final first = map['employee_first_name']?.toString().trim() ?? '';
    final last = map['employee_last_name']?.toString().trim() ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? null : full;
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthUser?>(
  AuthNotifier.new,
);
