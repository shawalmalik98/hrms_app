import 'package:safe_device/safe_device.dart';

import '../config/app_config.dart';

enum IntegrityIssue { developerMode, mockLocation, notRealDevice }

extension IntegrityIssueMessage on IntegrityIssue {
  String get message => switch (this) {
    IntegrityIssue.developerMode =>
      'Developer options are turned on. Turn them off to mark attendance.',
    IntegrityIssue.mockLocation =>
      'Fake location detected. Disable mock location apps to continue.',
    IntegrityIssue.notRealDevice =>
      'Attendance cannot be marked from an emulator.',
  };
}

class DeviceIntegrity {
  /// Returns the first problem found, or null when the device is clean.
  static Future<IntegrityIssue?> check() async {
    if (!AppConfig.enforceDeviceIntegrity) return null;

    if (!await SafeDevice.isRealDevice) return IntegrityIssue.notRealDevice;
    if (await SafeDevice.isDevelopmentModeEnable) {
      return IntegrityIssue.developerMode;
    }
    if (await SafeDevice.isMockLocation) return IntegrityIssue.mockLocation;
    return null;
  }
}
