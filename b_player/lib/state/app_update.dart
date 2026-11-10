import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';

/// 发布源是公开仓的 GitHub Release；仓库还没发版时接口返回 404。
const String appUpdateFeedUrl =
    'https://api.github.com/repos/codeforenode/enode/releases/latest';
const String appReleasesUrl = 'https://github.com/codeforenode/enode/releases';

/// 从标签里取数字版本：`v1.5.0`、`eNode-1.5.0` 都得到 [1, 5, 0]。
List<int>? parseAppVersion(String raw) {
  final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(raw);
  if (match == null) return null;
  return [for (final part in match.group(0)!.split('.')) int.parse(part)];
}

/// 只比数字段，缺的段按 0 算；构建号（+3）不参与，发版仍应递增版本号。
bool isNewerVersion(String candidate, String current) {
  final a = parseAppVersion(candidate);
  final b = parseAppVersion(current);
  if (a == null || b == null) return false;
  final count = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < count; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// 按后缀优先级挑资产；没有匹配就回落到发布页。
String? pickReleaseAsset(List<dynamic> assets, List<String> suffixes) {
  for (final suffix in suffixes) {
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String && url is String && name.toLowerCase().endsWith(suffix)) {
        return url;
      }
    }
  }
  return null;
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.pageUrl,
    required this.downloadUrl,
  });

  /// 规范化后的数字版本，例如 1.5.0。
  final String version;
  final String pageUrl;

  /// 平台对应的安装包；没有匹配资产时等同于 [pageUrl]。
  final String downloadUrl;

  String get tag => 'v$version';
}

enum AppUpdateStatus { idle, checking, latest, available, noRelease, failed }

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({http.Client? client, String Function()? currentVersion})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _currentVersion = currentVersion ?? (() => appVersion);

  final http.Client _client;
  final bool _ownsClient;
  final String Function() _currentVersion;

  AppUpdateStatus status = AppUpdateStatus.idle;

  /// 仅在 [status] 为 [AppUpdateStatus.available] 时非空。
  AppRelease? available;
  String? error;
  bool _disposed = false;

  bool get checking => status == AppUpdateStatus.checking;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> check() async {
    if (checking) return;
    status = AppUpdateStatus.checking;
    error = null;
    _notify();
    try {
      final res = await _client.get(
        Uri.parse(appUpdateFeedUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'eNode-update-check',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 404) {
        available = null;
        status = AppUpdateStatus.noRelease;
      } else if (res.statusCode != 200) {
        throw http.ClientException('HTTP ${res.statusCode}');
      } else {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is! Map<String, dynamic>) throw const FormatException('release json');
        _apply(body);
      }
    } catch (e) {
      error = '$e';
      status = AppUpdateStatus.failed;
    }
    _notify();
  }

  void _apply(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    final latest = tag is String ? parseAppVersion(tag) : null;
    if (latest == null) throw const FormatException('release tag');
    final page = json['html_url'] is String ? json['html_url'] as String : appReleasesUrl;
    final assets = json['assets'] is List ? json['assets'] as List : const <dynamic>[];
    final suffixes = Platform.isAndroid
        ? const <String>['.apk']
        : Platform.isWindows
            ? const <String>['setup.exe', '.zip', '.exe']
            : const <String>[];
    final version = latest.join('.');
    if (isNewerVersion(version, _currentVersion())) {
      available = AppRelease(
        version: version,
        pageUrl: page,
        downloadUrl: pickReleaseAsset(assets, suffixes) ?? page,
      );
      status = AppUpdateStatus.available;
    } else {
      available = null;
      status = AppUpdateStatus.latest;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
