import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../music_source.dart';
import '../../l10n/l10n.dart';
import 'lx_config.dart';

/// 在线音源的 HTTP 层：统一超时、一次重试与稳定错误文案。
///
/// 只对超时/网络错误/5xx 重试；4xx（含 429）直接上抛，避免把限频放大成请求风暴。
class LxHttp {
  LxHttp(this.client);

  final http.Client client;

  Future<String> text(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = lxHttpTimeout,
    int retries = 1,
  }) =>
      _send(
        () => client.get(uri, headers: {'User-Agent': lxUserAgent, ...?headers}),
        timeout: timeout,
        retries: retries,
      );

  /// 酷我逐字接口返回的是「文本头 + zlib 二进制」，不能按 UTF-8 解。
  Future<List<int>> bytes(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = lxHttpTimeout,
    int retries = 1,
  }) async =>
      (await _request(
        () => client.get(uri, headers: {'User-Agent': lxUserAgent, ...?headers}),
        timeout: timeout,
        retries: retries,
      ))
          .bodyBytes;

  /// 咪咕资源详情只收表单 POST。
  Future<String> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String>? headers,
    Duration timeout = lxHttpTimeout,
    int retries = 1,
  }) =>
      _send(
        () => client.post(
          uri,
          headers: {
            'User-Agent': lxUserAgent,
            'Content-Type': 'application/x-www-form-urlencoded',
            ...?headers,
          },
          body: form,
        ),
        timeout: timeout,
        retries: retries,
      );

  /// QQ 音乐的检索接口只接受 JSON POST；其余平台仍走 GET。
  Future<String> postJson(
    Uri uri,
    Object body, {
    Map<String, String>? headers,
    Duration timeout = lxHttpTimeout,
    int retries = 1,
  }) =>
      _send(
        () => client.post(
          uri,
          headers: {
            'User-Agent': lxUserAgent,
            'Content-Type': 'application/json',
            ...?headers,
          },
          body: jsonEncode(body),
        ),
        timeout: timeout,
        retries: retries,
      );

  Future<Map<String, Object?>> json(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = lxHttpTimeout,
    int retries = 1,
  }) async {
    final body = await text(uri, headers: headers, timeout: timeout, retries: retries);
    return _decode(body);
  }

  Future<Map<String, Object?>> postJsonMap(
    Uri uri,
    Object body, {
    Map<String, String>? headers,
    Duration timeout = lxHttpTimeout,
    int retries = 1,
  }) async {
    final text = await postJson(uri, body, headers: headers, timeout: timeout, retries: retries);
    return _decode(text);
  }

  Future<Map<String, Object?>> postFormMap(
    Uri uri,
    Map<String, String> form, {
    Map<String, String>? headers,
    Duration timeout = lxHttpTimeout,
    int retries = 1,
  }) async {
    final text = await postForm(uri, form, headers: headers, timeout: timeout, retries: retries);
    return _decode(text);
  }

  Map<String, Object?> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on FormatException {
      // 落到下面统一报错。
    }
    throw MusicSourceException(l10n.httpBadJson);
  }

  Future<String> _send(
    Future<http.Response> Function() send, {
    required Duration timeout,
    required int retries,
  }) async {
    final res = await _request(send, timeout: timeout, retries: retries);
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  Future<http.Response> _request(
    Future<http.Response> Function() send, {
    required Duration timeout,
    required int retries,
  }) async {
    for (var attempt = 0;; attempt++) {
      try {
        final res = await send().timeout(timeout);
        if (res.statusCode == 429) {
          throw MusicSourceException(l10n.httpRateLimited);
        }
        if (res.statusCode >= 500) {
          if (attempt < retries) {
            await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
            continue;
          }
          final detail = _serverMessage(res.bodyBytes);
          throw MusicSourceException(
            detail.isEmpty ? l10n.httpUnavailable(res.statusCode) : '$detail（HTTP ${res.statusCode}）',
          );
        }
        if (res.statusCode != 200) {
          throw MusicSourceException(l10n.httpFailed(res.statusCode));
        }
        return res;
      } on TimeoutException {
        if (attempt < retries) continue;
        throw MusicSourceException(l10n.httpTimeout);
      } on http.ClientException {
        if (attempt < retries) continue;
        throw MusicSourceException(l10n.httpError);
      } on SocketException {
        if (attempt < retries) continue;
        throw MusicSourceException(l10n.networkUnavailable);
      }
    }
  }
}

/// 5xx 响应体常带 `{code, message}`，把服务端原因带进错误文案，便于排查密钥/上游问题。
String _serverMessage(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is! Map) return '';
    for (final key in const ['message', 'msg', 'info', 'error']) {
      final value = decoded[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
  } catch (_) {}
  return '';
}

Map<String, Object?> asMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

List<Object?> asList(Object? value) => value is List ? value : const [];
