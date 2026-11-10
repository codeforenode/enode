import 'dart:convert';

import 'package:b_player/state/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('版本比较', () {
    test('从标签里取数字段', () {
      expect(parseAppVersion('v1.5.0'), [1, 5, 0]);
      expect(parseAppVersion('eNode-1.5.0'), [1, 5, 0]);
      expect(parseAppVersion('1.4.0+3'), [1, 4, 0]);
      expect(parseAppVersion('nightly'), isNull);
    });

    test('只有更高的数字段才算新版本', () {
      expect(isNewerVersion('1.5.0', '1.4.0'), isTrue);
      expect(isNewerVersion('1.4.1', '1.4.0'), isTrue);
      expect(isNewerVersion('1.4.10', '1.4.9'), isTrue);
      expect(isNewerVersion('1.6', '1.5.9'), isTrue);
      expect(isNewerVersion('1.4.0', '1.4.0'), isFalse);
      expect(isNewerVersion('1.4', '1.4.0'), isFalse);
      expect(isNewerVersion('v1.4.0', '1.4.0'), isFalse);
      expect(isNewerVersion('1.4.0', '1.4.0+3'), isFalse);
      expect(isNewerVersion('1.4.0', '1.4.1'), isFalse);
      expect(isNewerVersion('bad', '1.4.0'), isFalse);
    });
  });

  group('发布资产', () {
    const assets = <dynamic>[
      {
        'name': 'eNode-1.5.0-win-x64.zip',
        'browser_download_url': 'https://example.test/eNode.zip',
      },
      {
        'name': 'eNode-1.5.0-win-x64-setup.exe',
        'browser_download_url': 'https://example.test/eNode-setup.exe',
      },
      {
        'name': 'eNode-1.5.0-android.apk',
        'browser_download_url': 'https://example.test/eNode.apk',
      },
    ];

    test('Windows 优先安装包，其次便携包', () {
      expect(pickReleaseAsset(assets, const ['setup.exe', '.zip', '.exe']),
          'https://example.test/eNode-setup.exe');
      expect(pickReleaseAsset(assets, const ['.zip']), 'https://example.test/eNode.zip');
    });

    test('Android 挑 apk', () {
      expect(pickReleaseAsset(assets, const ['.apk']), 'https://example.test/eNode.apk');
    });

    test('没有匹配的后缀就回落到发布页', () {
      expect(pickReleaseAsset(assets, const ['.dmg']), isNull);
      expect(pickReleaseAsset(const <dynamic>[], const ['.apk']), isNull);
    });
  });

  group('更新检查', () {
    AppUpdateController controller(MockClient client) =>
        AppUpdateController(client: client, currentVersion: () => '1.4.0');

    MockClient release(Map<String, dynamic> body, {int code = 200}) =>
        MockClient((request) async {
          expect(request.url, Uri.parse(appUpdateFeedUrl));
          expect(request.headers['User-Agent'], 'eNode-update-check');
          return http.Response(jsonEncode(body), code,
              headers: {'content-type': 'application/json'});
        });

    test('高版本可用，带规范化版本号和下载地址', () async {
      final c = controller(release({
        'tag_name': 'v1.5.0',
        'html_url': 'https://example.test/releases/v1.5.0',
        'body': 'notes',
        'assets': [
          {
            'name': 'eNode-1.5.0-win-x64-setup.exe',
            'browser_download_url': 'https://example.test/setup.exe',
          },
        ],
      }));
      await c.check();
      expect(c.status, AppUpdateStatus.available);
      expect(c.available?.version, '1.5.0');
      expect(c.available?.tag, 'v1.5.0');
      expect(c.available?.pageUrl, 'https://example.test/releases/v1.5.0');
      expect(c.available?.downloadUrl, isNotEmpty);
      expect(c.error, isNull);
      c.dispose();
    });

    test('同版本或更低版本都算已是最新', () async {
      for (final tag in ['v1.4.0', 'v1.3.9']) {
        final c = controller(release({
          'tag_name': tag,
          'html_url': 'https://example.test/releases/$tag',
          'assets': const [],
        }));
        await c.check();
        expect(c.status, AppUpdateStatus.latest, reason: tag);
        expect(c.available, isNull);
        c.dispose();
      }
    });

    test('仓库还没发版时给出暂无发布', () async {
      final c = controller(MockClient((request) async => http.Response('', 404)));
      await c.check();
      expect(c.status, AppUpdateStatus.noRelease);
      expect(c.available, isNull);
      expect(c.error, isNull);
      c.dispose();
    });

    test('接口报错或标签无法解析时给出失败原因', () async {
      final httpError = controller(release(const {}, code: 500));
      await httpError.check();
      expect(httpError.status, AppUpdateStatus.failed);
      expect(httpError.error, contains('500'));
      httpError.dispose();

      final badTag = controller(release(const {'tag_name': 'nightly'}));
      await badTag.check();
      expect(badTag.status, AppUpdateStatus.failed);
      expect(badTag.error, isNotEmpty);
      badTag.dispose();
    });
  });
}
