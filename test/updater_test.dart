import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/update/app_updater.dart';

void main() {
  test('version.json is read', () {
    final info = UpdateInfo.fromJson({
      'version_code': 29600001,
      'version_name': '1.0.1',
      'apk_url': 'http://192.168.88.71:8001/app/hrms.apk',
      'notes': 'Fixes',
    });

    expect(info, isNotNull);
    expect(info!.versionCode, 29600001);
    expect(info.versionName, '1.0.1');
    expect(info.apkUrl, endsWith('hrms.apk'));
  });

  test('a broken version.json is ignored', () {
    expect(UpdateInfo.fromJson({'version_name': '1.0.1'}), isNull);
    expect(UpdateInfo.fromJson({'version_code': 1}), isNull);
    expect(UpdateInfo.fromJson('not json'), isNull);
  });

  test('only a higher build number counts as an update', () {
    const info = UpdateInfo(versionCode: 100, versionName: '1', apkUrl: 'x');

    expect(info.isNewerThan(99), isTrue);
    expect(info.isNewerThan(100), isFalse); // already on this build
    expect(info.isNewerThan(101), isFalse); // phone is newer than the server
  });
}
