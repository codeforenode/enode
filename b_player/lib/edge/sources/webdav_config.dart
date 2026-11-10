import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个 WebDAV 服务器条目。密码只落本机 SharedPreferences，不进日志、不进提交。
class WebDavServer {
  const WebDavServer({
    required this.id,
    required this.name,
    required this.url,
    this.username = '',
    this.password = '',
    this.allowSelfSigned = false,
    this.createdAt = 0,
  });

  final String id;
  final String name;
  final String url;
  final String username;
  final String password;
  final bool allowSelfSigned;
  final int createdAt;

  /// 扫描出的曲目以此为 sourceId 前缀，站点地址不变 id 就不变。
  static String idFor(String url) {
    final digest = sha256.convert(utf8.encode(url.trim())).toString();
    return 'dav_${digest.substring(0, 10)}';
  }

  static String normalizeUrl(String raw) {
    var value = raw.trim();
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static bool validUrl(String raw) {
    final uri = Uri.tryParse(normalizeUrl(raw));
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  String get displayName => name.trim().isEmpty ? hostLabel : name.trim();

  /// 列表里没空间展示整条地址时用它：host[:port]/path。
  String get hostLabel {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final port = uri.hasPort ? ':${uri.port}' : '';
    final path = uri.path == '/' ? '' : uri.path;
    return '${uri.host}$port$path';
  }

  /// 集合地址补尾斜杠，PROPFIND 子项解析才不会把最后一段当文件名。
  Uri get baseUri {
    final uri = Uri.parse(normalizeUrl(url));
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }

  WebDavServer copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    bool? allowSelfSigned,
  }) =>
      WebDavServer(
        id: url == null ? id : idFor(url),
        name: name ?? this.name,
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
        allowSelfSigned: allowSelfSigned ?? this.allowSelfSigned,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
        'password': password,
        'allowSelfSigned': allowSelfSigned,
        'createdAt': createdAt,
      };

  static WebDavServer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'] is String ? normalizeUrl(raw['url'] as String) : '';
    if (!validUrl(url)) return null;
    final name = raw['name'] is String ? (raw['name'] as String).trim() : '';
    return WebDavServer(
      id: WebDavServer.idFor(url),
      name: name,
      url: url,
      username: raw['username'] is String ? raw['username'] as String : '',
      password: raw['password'] is String ? raw['password'] as String : '',
      allowSelfSigned: raw['allowSelfSigned'] is bool ? raw['allowSelfSigned'] as bool : false,
      createdAt: (raw['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class WebDavServerStore {
  static const _key = 'webdav.servers.v1';

  Future<List<WebDavServer>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded) ?WebDavServer.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<WebDavServer> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([for (final server in servers) server.toJson()]));
    } catch (_) {
      // 无插件环境（单元测试/桌面预览）下不阻断。
    }
  }
}
