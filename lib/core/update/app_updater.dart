import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';

/// Describes the newest APK, read from `version.json` on the server:
///
/// Every update is mandatory (see UpdateGate). `force` in the file is only
/// there for phones still running an older build that honours it.
///
/// ```json
/// {"version_code": 29600000, "version_name": "1.0.1",
///  "apk_url": "http://192.168.88.71:8001/app/hrms.apk",
///  "notes": "What is new", "force": true}
/// ```
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.notes = '',
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String notes;

  /// True when this is a newer build than the one installed.
  bool isNewerThan(int installedBuildNumber) =>
      versionCode > installedBuildNumber;

  static UpdateInfo? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final code = int.tryParse('${raw['version_code']}');
    final url = raw['apk_url']?.toString();
    if (code == null || url == null || url.isEmpty) return null;
    return UpdateInfo(
      versionCode: code,
      versionName: raw['version_name']?.toString() ?? '',
      apkUrl: url,
      notes: raw['notes']?.toString() ?? '',
    );
  }
}

class AppUpdater {
  /// The newer version, or null when this app is up to date (or the server
  /// has no `version.json`, or cannot be reached).
  static Future<UpdateInfo?> check() async {
    if (!AppConfig.checkForUpdates || !Platform.isAndroid) return null;
    try {
      final res = await Dio().get<dynamic>(
        AppConfig.updateUrl,
        // The timestamp keeps a proxy or browser cache from serving old data.
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
        options: Options(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final body = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      final info = UpdateInfo.fromJson(body);
      if (info == null) return null;

      final current =
          int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      return info.isNewerThan(current) ? info : null;
    } catch (_) {
      return null;
    }
  }
}
