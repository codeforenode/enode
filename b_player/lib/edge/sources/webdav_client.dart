import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';

import '../../l10n/l10n.dart';
import 'webdav_config.dart';

class WebDavException implements Exception {
  const WebDavException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// PROPFIND 返回的一条资源。目录的 [uri] 不保证带尾斜杠，递归前要补。
class DavEntry {
  const DavEntry({
    required this.uri,
    required this.isCollection,
    this.size = 0,
    this.modifiedMs = 0,
    this.displayName = '',
  });

  final Uri uri;
  final bool isCollection;
  final int size;
  final int modifiedMs;
  final String displayName;

  /// 文件/目录名（百分比解码后的最后一段）。
  String get name {
    final trimmed = displayName.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? '' : segments.last;
  }

  Uri get collectionUri {
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: path);
  }
}

/// 只做 WebDAV 需要的最小集合：PROPFIND 深一层、GET 文件、探测连通性。
class WebDavClient {
  WebDavClient({
    required this.server,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? _createClient(server.allowSelfSigned),
        _ownsClient = client == null;

  final WebDavServer server;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  static http.Client _createClient(bool allowSelfSigned) {
    final io = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    if (allowSelfSigned) {
      io.badCertificateCallback = (_, _, _) => true;
    }
    return IOClient(io);
  }

  static const _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:displayname/><d:resourcetype/><d:getcontentlength/><d:getlastmodified/>'
      '</d:prop></d:propfind>';

  /// 播放器打开 http(s) 音频时要带的请求头；账号密码不进 URL，避免写进日志。
  Map<String, String> get audioHeaders {
    if (server.username.isEmpty && server.password.isEmpty) return const {};
    final token = base64Encode(utf8.encode('${server.username}:${server.password}'));
    return {'Authorization': 'Basic $token'};
  }

  Map<String, String> get _headers => {
        ...audioHeaders,
        'Accept': 'application/xml, text/xml, */*',
        'User-Agent': 'eNode',
      };

  /// 列一层。[depth] 0 只返回自身，1 返回直接子项。
  Future<List<DavEntry>> list(Uri uri, {int depth = 1}) async {
    final request = http.Request('PROPFIND', uri)
      ..headers.addAll({
        ..._headers,
        'Depth': '$depth',
        'Content-Type': 'application/xml; charset=utf-8',
      })
      ..body = _propfindBody;
    final response = await _send(request);
    final status = response.statusCode;
    if (status == 401 || status == 403) {
      throw WebDavException(l10n.webdavAuthFailed(status), status: status);
    }
    if (status == 404) {
      throw WebDavException(l10n.webdavNotFound, status: status);
    }
    if (status == 405 || status == 501) {
      throw WebDavException(l10n.webdavNotDav, status: status);
    }
    if (status != 200 && status != 207) {
      throw WebDavException(l10n.webdavHttpError(status), status: status);
    }
    return _parseMultiStatus(response.bodyBytes, uri);
  }

  /// 连通性探测：能 PROPFIND 出子项就算通；返回根目录下的条目数。
  Future<int> probe() async {
    final base = server.baseUri;
    final entries = await list(base, depth: 1);
    final self = _trimSlash(base.path);
    return entries.where((entry) => _trimSlash(entry.uri.path) != self).length;
  }

  Future<String> getText(Uri uri) async {
    final response = await _get(uri);
    var text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    return text;
  }

  Future<List<int>> getBytes(Uri uri) async => (await _get(uri)).bodyBytes;

  Future<http.Response> _get(Uri uri) async {
    final request = http.Request('GET', uri)..headers.addAll(_headers);
    final response = await _send(request);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw WebDavException(l10n.webdavAuthFailed(response.statusCode), status: response.statusCode);
    }
    if (response.statusCode != 200) {
      throw WebDavException(l10n.webdavHttpError(response.statusCode), status: response.statusCode);
    }
    return response;
  }

  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw WebDavException(l10n.webdavTimeout);
    } on HandshakeException catch (e) {
      throw WebDavException(l10n.webdavTlsFailed(e.message));
    } on SocketException catch (e) {
      throw WebDavException(l10n.webdavConnectFailed(e.message));
    } on http.ClientException catch (e) {
      throw WebDavException(l10n.webdavConnectFailed(e.message));
    }
  }

  List<DavEntry> _parseMultiStatus(List<int> bytes, Uri requestUri) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    XmlDocument document;
    try {
      document = XmlDocument.parse(text);
    } catch (_) {
      throw WebDavException(l10n.webdavInvalidXml);
    }
    final out = <DavEntry>[];
    for (final response in document.findAllElements('response', namespace: '*')) {
      final href = response
          .findElements('href', namespace: '*')
          .map((e) => e.innerText.trim())
          .firstWhere((v) => v.isNotEmpty, orElse: () => '');
      if (href.isEmpty) continue;
      final prop = _okProp(response);
      if (prop == null) continue;
      final resourceType = _firstOrNull(prop.findElements('resourcetype', namespace: '*'));
      final isCollection =
          resourceType?.findElements('collection', namespace: '*').isNotEmpty ?? false;
      final size = int.tryParse(
            _firstOrNull(prop.findElements('getcontentlength', namespace: '*'))?.innerText.trim() ?? '',
          ) ??
          0;
      final modified = _parseHttpDate(
        _firstOrNull(prop.findElements('getlastmodified', namespace: '*'))?.innerText.trim() ?? '',
      );
      final display =
          _firstOrNull(prop.findElements('displayname', namespace: '*'))?.innerText.trim() ?? '';
      out.add(DavEntry(
        uri: _resolveHref(requestUri, href),
        isCollection: isCollection,
        size: size,
        modifiedMs: modified,
        displayName: display,
      ));
    }
    return out;
  }

  static XmlElement? _okProp(XmlElement response) {
    for (final propstat in response.findElements('propstat', namespace: '*')) {
      final status = _firstOrNull(propstat.findElements('status', namespace: '*'))?.innerText ?? '';
      final code = int.tryParse(RegExp(r'\s(\d{3})\s').firstMatch(status)?.group(1) ?? '');
      if (code != 200) continue;
      final prop = _firstOrNull(propstat.findElements('prop', namespace: '*'));
      if (prop != null) return prop;
    }
    return null;
  }

  /// 反向代理常回内网绝对地址；只保留 path/query，再拼回用户填的入口地址。
  static Uri _resolveHref(Uri base, String href) {
    final parsed = Uri.tryParse(href);
    if (parsed == null) return base;
    if (parsed.hasScheme && parsed.host.isNotEmpty) {
      if (parsed.host == base.host && parsed.scheme == base.scheme && parsed.port == base.port) {
        return parsed;
      }
      return base.replace(
        path: parsed.path,
        query: parsed.hasQuery ? parsed.query : null,
        fragment: null,
      );
    }
    return base.resolve(href);
  }

  static int _parseHttpDate(String value) {
    if (value.isEmpty) return 0;
    try {
      return HttpDate.parse(value).millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  static T? _firstOrNull<T>(Iterable<T> items) {
    final iterator = items.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  static String _trimSlash(String path) =>
      path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
