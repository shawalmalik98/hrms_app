import 'package:flutter/foundation.dart';

class AppConfig {
  /// Test server. Change for production.
  static const baseUrl = 'http://192.168.88.71:8001/api/v1/';

  /// Where the app looks for a newer version of itself. Put `version.json` and
  /// the APK there (see build_release.sh). No file there means no update.
  static const updateUrl = 'http://192.168.88.71:8001/app/version.json';

  /// Sent as `apk-version`. Must be listed in the portal under
  /// System Settings -> Mobile App Version, otherwise every call gets 403.
  static const appVersion = '1.0.0';

  /// Release builds block attendance on developer mode / mock location.
  /// Debug builds skip that check, otherwise a dev machine could never test.
  static const enforceDeviceIntegrity = !kDebugMode;

  /// Whether the app asks the server for a newer APK (and requires it).
  /// Off in debug builds: `flutter run` always has a low build number, so it
  /// would be told to update every time. To test the update flow anyway:
  /// `flutter run --dart-define=CHECK_UPDATES=true`.
  static const checkForUpdates = bool.fromEnvironment(
    'CHECK_UPDATES',
    defaultValue: !kDebugMode,
  );

  /// Adds distance, radius and GPS accuracy to the offline "not at your
  /// office" message so a wrong refusal can be diagnosed. Turn off once done.
  static const showLocationDetails = false;

  /// Reject a GPS fix that is less accurate than this (meters).
  static const maxAccuracyMeters = 50.0;
}
