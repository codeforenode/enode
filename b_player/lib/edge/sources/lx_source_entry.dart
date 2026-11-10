import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'lx_config.dart';
import '../../l10n/l10n.dart';

/// 脚本头部注释里声明的元信息（`@name / @version / @author / @description / @homepage`）。
class LxSourceMeta {
  const LxSourceMeta({
    this.name = '',
    this.version = '',
    this.author = '',
    this.description = '',
    this.homepage = '',
  });

  final String name;
  final String version;
  final String author;
  final String description;
  final String homepage;

  /// 只扫文件开头的注释块，避免把脚本正文里的 `@xxx` 误当成元信息。
  static LxSourceMeta parse(String script) {
    final head = script.length > 8192 ? script.substring(0, 8192) : script;
    final end = head.indexOf('*/');
    final block = end < 0 ? head : head.substring(0, end);
    final values = <String, String>{};
    for (final match in RegExp(r'@(\w+)[ \t]+([^\r\n]+)').allMatches(block)) {
      final key = match.group(1)!.toLowerCase();
      values.putIfAbsent(key, () => match.group(2)!.trim());
    }
    return LxSourceMeta(
      name: values['name'] ?? '',
      version: values['version'] ?? '',
      author: values['author'] ?? '',
      description: values['description'] ?? '',
      homepage: values['homepage'] ?? '',
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        'homepage': homepage,
      };

  static LxSourceMeta fromJson(Object? raw) {
    if (raw is! Map) return const LxSourceMeta();
    String read(String key) => raw[key] is String ? raw[key] as String : '';
    return LxSourceMeta(
      name: read('name'),
      version: read('version'),
      author: read('author'),
      description: read('description'),
      homepage: read('homepage'),
    );
  }
}

/// 一条已导入的自定义音源脚本。
///
/// `script` 原样保存在本机（与脚本协议一致，不执行任何改写）；
/// `platforms` 是上一次初始化成功时声明的平台，用于跳过明显不匹配的取链。
class LxSourceEntry {
  const LxSourceEntry({
    required this.id,
    required this.url,
    required this.script,
    required this.meta,
    this.enabled = true,
    this.platforms = const {},
    this.lastError,
    this.updatedAt = 0,
    this.hash = '',
  });

  final String id;
  final String url;
  final String script;
  final LxSourceMeta meta;
  final bool enabled;
  final Set<String> platforms;
  final String? lastError;
  final int updatedAt;

  /// 下载时的脚本 sha256，用于判断同一地址是否换了内容；旧数据可能为空。
  final String hash;

  static String hashOf(String script) =>
      sha256.convert(utf8.encode(script)).toString();

  String get name => meta.name.trim().isEmpty ? url : meta.name.trim();

  /// 脚本作者常自己带 `v` 前缀，展示时不要叠成 `vv8.9.3`。
  String get versionLabel {
    final raw = meta.version.trim();
    if (raw.isEmpty) return '';
    return raw.startsWith('v') || raw.startsWith('V') ? raw : 'v$raw';
  }

  String get subtitle {
    final parts = <String>[
      if (versionLabel.isNotEmpty) versionLabel,
      if (meta.author.trim().isNotEmpty) meta.author.trim(),
    ];
    return parts.join(' · ');
  }

  static String idFor(String url) {
    final digest = sha256.convert(utf8.encode(url.trim())).toString();
    return 'lx_${digest.substring(0, 10)}';
  }

  LxSourceEntry copyWith({
    bool? enabled,
    Set<String>? platforms,
    String? lastError,
    bool clearError = false,
    int? updatedAt,
    String? hash,
  }) =>
      LxSourceEntry(
        id: id,
        url: url,
        script: script,
        meta: meta,
        enabled: enabled ?? this.enabled,
        platforms: platforms ?? this.platforms,
        lastError: clearError ? null : (lastError ?? this.lastError),
        updatedAt: updatedAt ?? this.updatedAt,
        hash: hash ?? this.hash,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'script': script,
        'meta': meta.toJson(),
        'enabled': enabled,
        'platforms': [...platforms],
        'lastError': ?lastError,
        'updatedAt': updatedAt,
        'hash': hash,
      };

  static LxSourceEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'] is String ? raw['url'] as String : '';
    final script = raw['script'] is String ? raw['script'] as String : '';
    if (url.trim().isEmpty || script.trim().isEmpty) return null;
    final metaRaw = raw['meta'];
    final meta = LxSourceMeta.fromJson(metaRaw);
    final platformsRaw = raw['platforms'];
    return LxSourceEntry(
      id: raw['id'] is String && (raw['id'] as String).isNotEmpty
          ? raw['id'] as String
          : idFor(url),
      url: url,
      script: script,
      meta: meta,
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      platforms: platformsRaw is List
          ? {
              for (final value in platformsRaw)
                if (value is String) value,
            }
          : const {},
      lastError: raw['lastError'] is String ? raw['lastError'] as String : null,
      updatedAt: (raw['updatedAt'] as num?)?.toInt() ?? 0,
      hash: raw['hash'] is String ? raw['hash'] as String : '',
    );
  }
}

/// 多音源的持久化：顺序即优先级，`enabled` 对应 UI 上的勾选。
class LxSourceStore {
  static const _key = 'lx.sources.v2';

  Future<List<LxSourceEntry>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded) ?LxSourceEntry.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<LxSourceEntry> sources) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([for (final source in sources) source.toJson()]),
      );
    } catch (_) {
      // 无插件环境（单元测试/桌面预览）下不阻断。
    }
  }

  /// 同地址再次导入视为更新：保留 id、勾选状态与排序，只换脚本。
  static List<LxSourceEntry> upsert(
    List<LxSourceEntry> current,
    LxSourceEntry incoming,
  ) {
    final index = current.indexWhere((source) => source.url == incoming.url);
    if (index < 0) return [...current, incoming];
    final next = [...current];
    // 同地址更新保持原排序，优先级不因重新导入而改变。
    next[index] = incoming.copyWith(enabled: current[index].enabled);
    return next;
  }
}

/// 按地址导入：只接受带 `@name` 头部的音源脚本。
Future<LxSourceEntry> fetchLxSource(
  String url, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final trimmed = url.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw FormatException(l10n.sourceUrlScheme);
  }
  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.get(
      uri,
      headers: {'User-Agent': lxUserAgent},
    ).timeout(timeout);
    if (response.statusCode != 200) {
      throw FormatException(l10n.downloadFailed(response.statusCode));
    }
    final script = utf8.decode(response.bodyBytes, allowMalformed: true);
    final meta = LxSourceMeta.parse(script);
    if (meta.name.isEmpty) {
      throw FormatException(l10n.sourceInvalid);
    }
    return LxSourceEntry(
      id: LxSourceEntry.idFor(trimmed),
      url: trimmed,
      script: script,
      meta: meta,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      hash: LxSourceEntry.hashOf(script),
    );
  } on TimeoutException {
    throw FormatException(l10n.downloadTimeout);
  } finally {
    if (ownsClient) httpClient.close();
  }
}

/// 给脚本用的 `musicInfo`：字段名沿用 脚本协议各平台的约定。
///
/// 真实桌面端会把检索结果原样交给脚本；我们只有统一的
/// `platform + songId`，因此按平台补齐脚本会读到的关键字段。
Map<String, Object?> buildLxMusicInfo({
  required String platform,
  required String songId,
  required String title,
  required String artist,
  required int durationMs,
  String album = '',
}) {
  final base = <String, Object?>{
    'name': title,
    'singer': artist,
    'albumName': album,
    'interval': durationMs > 0 ? (durationMs / 1000).round() : 0,
    'source': platform,
  };
  switch (platform) {
    case 'kg':
      return {...base, 'hash': songId, 'songmid': songId, 'albumId': ''};
    case 'kw':
    case 'tx':
      return {...base, 'songmid': songId, 'id': songId};
    case 'wy':
      return {...base, 'id': songId};
    case 'mg':
      return {...base, 'id': songId, 'songmid': songId};
    default:
      return {...base, 'songmid': songId, 'id': songId};
  }
}
