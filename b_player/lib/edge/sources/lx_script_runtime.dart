import 'dart:async';
import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import '../../l10n/l10n.dart';

/// 自定义音源脚本的一次调用失败。
class LxScriptException implements Exception {
  const LxScriptException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `inited` 里声明的单平台能力，已按脚本宿主的白名单过滤。
class LxSourceCapability {
  const LxSourceCapability({required this.actions, required this.qualitys});

  final Set<String> actions;
  final Set<String> qualitys;

  bool supports(String action) => actions.contains(action);
}

/// 脚本自己检查到新版时通过 `updateAlert` 上报的内容。
class LxUpdateAlert {
  const LxUpdateAlert({required this.log, this.url = ''});

  final String log;
  final String url;
}

/// 脚本初始化结果：平台 → 能力。
class LxInitResult {
  const LxInitResult({required this.sources, this.message});

  final Map<String, LxSourceCapability> sources;
  final String? message;

  Iterable<String> get platforms => sources.keys;

  bool can(String platform, String action) => sources[platform]?.supports(action) ?? false;
}

const _allowedSources = {'kw', 'kg', 'tx', 'wy', 'mg', 'local'};
const _qualityWhitelist = {'128k', '320k', 'flac', 'flac24bit'};
const _defaultActions = {'musicUrl'};
const _localActions = {'musicUrl', 'lyric', 'pic'};

/// 自定义音源脚本宿主的最小实现。
///
/// 对应上游桌面端的 `src/main/modules/userApi/renderer/preload.js`：
/// 提供 `lx.on/send/request/utils`，把 HTTP 交给 Dart 的 http 客户端，
/// 脚本本身拿不到任何宿主密钥或文件系统能力。
///
/// 一个实例对应一个 JS 上下文；并发调用在本类内部串行化，
/// 避免多个取链请求互相覆盖 `__lxResult`。
class LxScriptRuntime {
  LxScriptRuntime({
    http.Client? client,
    this.defaultHttpTimeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const _channel = 'lx.http';
  static const _initTimeout = Duration(seconds: 20);
  static const _pollInterval = Duration(milliseconds: 10);

  final http.Client _client;
  final bool _ownsClient;
  final Duration defaultHttpTimeout;

  JavascriptRuntime? _rt;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// 加载脚本并等待 `inited` 事件。
  Future<LxInitResult> init(
    String script, {
    String name = '',
    String version = '',
    String author = '',
    String description = '',
    String homepage = '',
  }) =>
      _serial(() async {
        _ensureRuntime();
        final rt = _rt!;
        final host = rt.evaluate(_hostShim, sourceUrl: 'lx-host.js');
        if (host.isError) {
          throw LxScriptException(l10n.jsHostFailed(_firstLine(host.stringResult)));
        }
        rt.evaluate(
          '__lxHostInit(${jsonEncode({
            'name': name,
            'version': version,
            'author': author,
            'description': description,
            'homepage': homepage,
            'env': 'mobile',
            'lxVersion': '2.0.0',
          })})',
          sourceUrl: 'lx-host-init.js',
        );

        _initialized = false;
        final loaded = rt.evaluate(script, sourceUrl: 'lx-source.js');
        if (loaded.isError) {
          throw LxScriptException(l10n.scriptRunFailed(_firstLine(loaded.stringResult)));
        }

        await _pumpUntil(() {
          final inited = _evalJson('JSON.stringify(__lxInited)');
          return inited is Map;
        }, _initTimeout, l10n.scriptInit);

        final inited = _evalJson('JSON.stringify(__lxInited)');
        if (inited is! Map) {
          throw LxScriptException(l10n.scriptNoInited);
        }
        final message = inited['message'] is String ? inited['message'] as String : null;
        final sources = _parseSources(inited['sources']);
        if (sources.isEmpty) {
          throw LxScriptException(message?.trim().isNotEmpty == true ? message! : l10n.scriptNoPlatforms);
        }
        _initialized = true;
        return LxInitResult(sources: sources, message: message);
      });

  /// 调用脚本的 `musicUrl` 动作，返回通过脚本宿主校验的播放地址。
  Future<String> musicUrl({
    required String platform,
    required Map<String, Object?> musicInfo,
    required String quality,
    Duration timeout = const Duration(seconds: 15),
  }) =>
      _serial(() async {
        if (!_initialized) throw LxScriptException(l10n.sourceNotInitialized);
        final rt = _rt!;
        final call = '__lxCall(${jsonEncode(platform)}, "musicUrl", '
            '${jsonEncode(musicInfo)}, ${jsonEncode(quality)})';
        final ev = rt.evaluate(call, sourceUrl: 'lx-call.js');
        if (ev.isError) {
          throw LxScriptException(l10n.scriptCallFailed(_firstLine(ev.stringResult)));
        }

        await _pumpUntil(() {
          final result = _readResult();
          return result != null && result['status'] != 'pending';
        }, timeout, l10n.playbackResolve);

        final result = _readResult();
        if (result == null) throw LxScriptException(l10n.scriptNoResult);
        if (result['status'] == 'error') {
          final error = result['error'];
          throw LxScriptException(error is String && error.isNotEmpty ? error : l10n.scriptError);
        }
        final data = result['data'];
        final url = data is String ? data : '';
        // 与脚本宿主一致：只接受 http(s) 且长度不超过 2048。
        if (url.length > 2048 || !(url.startsWith('http://') || url.startsWith('https://'))) {
          throw LxScriptException(l10n.scriptBadUrl);
        }
        return url;
      });

  /// 读取脚本在初始化后自行检查更新时上报的 `updateAlert`。
  ///
  /// 这些脚本一般在 `inited` 之后才异步请求版本接口；这里最多驱动 [budget]，
  /// 一旦脚本的 HTTP 请求落地就立刻收手，没有更新检查的脚本几乎不额外耗时。
  Future<LxUpdateAlert?> readUpdateAlert({
    Duration budget = const Duration(seconds: 3),
  }) =>
      _serial(() async {
        if (!_initialized || _disposed) return null;
        final rt = _rt;
        if (rt == null) return null;
        final deadline = DateTime.now().add(budget);
        const settle = Duration(milliseconds: 250);
        DateTime? idleSince;
        while (true) {
          try {
            rt.executePendingJob();
            final alert = _readUpdateAlert();
            if (alert != null) return alert;
            if (_pendingHttpCount() > 0) {
              idleSince = null;
            } else {
              idleSince ??= DateTime.now();
              // 请求结束后 Promise 回调还要再跑几轮微任务。
              if (DateTime.now().difference(idleSince) >= settle) return null;
            }
          } on LxScriptException {
            return null;
          }
          if (!DateTime.now().isBefore(deadline)) return null;
          await Future<void>.delayed(_pollInterval);
        }
      });

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _initialized = false;
    try {
      _rt?.dispose();
    } catch (_) {
      // 引擎已析构时忽略。
    }
    _rt = null;
    if (_ownsClient) _client.close();
  }

  // ---------------- 内部 ----------------

  void _ensureRuntime() {
    if (_rt != null) return;
    try {
      // xhr/fetch 扩展会异步注入全局函数，与脚本无关且会干扰 evaluate 时序，关掉。
      final rt = getJavascriptRuntime(xhr: false);
      rt.setupBridge(_channel, _onHttp);
      _rt = rt;
    } catch (e) {
      throw LxScriptException(l10n.jsUnavailable('$e'));
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      if (_disposed) {
        completer.completeError(LxScriptException(l10n.runtimeDisposed));
        return;
      }
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> _pumpUntil(bool Function() done, Duration timeout, String what) async {
    final rt = _rt;
    if (rt == null) throw LxScriptException(l10n.runtimeDisposed);
    final deadline = DateTime.now().add(timeout);
    while (true) {
      // 每次 evaluate 不会自动跑微任务，必须显式驱动 Promise 队列。
      rt.executePendingJob();
      if (done()) return;
      if (!DateTime.now().isBefore(deadline)) {
        throw LxScriptException(l10n.scriptTimeout(what));
      }
      await Future<void>.delayed(_pollInterval);
    }
  }

  Map<String, Object?>? _readResult() {
    final value = _evalJson('JSON.stringify(__lxResult)');
    return value is Map ? Map<String, Object?>.from(value) : null;
  }

  LxUpdateAlert? _readUpdateAlert() {
    final value = _evalJson('JSON.stringify(__lxUpdateAlert)');
    if (value is! Map) return null;
    final rawLog = value['log'] is String ? value['log'] as String : '';
    final rawUrl = value['updateUrl'] is String ? value['updateUrl'] as String : '';
    // 与官方宿主一致：日志和地址都限制在 1024 以内，地址只接受 http(s)。
    final log = rawLog.length > 1024 ? rawLog.substring(0, 1024) : rawLog;
    final url = rawUrl.length <= 1024 &&
            (rawUrl.startsWith('http://') || rawUrl.startsWith('https://'))
        ? rawUrl
        : '';
    if (log.trim().isEmpty && url.isEmpty) return null;
    return LxUpdateAlert(log: log, url: url);
  }

  int _pendingHttpCount() {
    final rt = _rt;
    if (rt == null) return 0;
    final res = rt.evaluate('Object.keys(__pendingHttp).length');
    if (res.isError) return 0;
    return int.tryParse(res.stringResult.trim()) ?? 0;
  }

  Object? _evalJson(String code) {
    final rt = _rt;
    if (rt == null) return null;
    final res = rt.evaluate(code);
    if (res.isError) {
      throw LxScriptException(_firstLine(res.stringResult));
    }
    final text = res.stringResult.trim();
    if (text.isEmpty || text == 'null' || text == 'undefined') return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      throw LxScriptException(l10n.scriptBadJson);
    }
  }

  void _onHttp(dynamic args) {
    if (_disposed) return;
    if (args is! Map) return;
    final payload = Map<String, Object?>.from(args);
    final id = payload['id'];
    if (id is! int) return;
    unawaited(_performHttp(id, payload));
  }

  Future<void> _performHttp(int id, Map<String, Object?> payload) async {
    Map<String, Object?>? response;
    String? error;
    try {
      response = await _send(payload);
    } on LxScriptException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    }
    if (_disposed) return;
    final rt = _rt;
    if (rt == null) return;
    try {
      if (error != null) {
        rt.evaluate('__lxHttpDone($id, ${jsonEncode(error)}, null)');
      } else {
        rt.evaluate('__lxHttpDone($id, null, ${jsonEncode(jsonEncode(response))})');
      }
    } catch (_) {
      // 运行时可能在请求返回前被释放。
    }
  }

  Future<Map<String, Object?>> _send(Map<String, Object?> payload) async {
    final rawUrl = payload['url'];
    if (rawUrl is! String) throw LxScriptException(l10n.requestBadUrl);
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw LxScriptException(l10n.requestHttpOnly);
    }
    if (payload['formData'] != null) {
      throw LxScriptException(l10n.requestNoMultipart);
    }

    final method = '${payload['method'] ?? 'GET'}'.toUpperCase();
    final request = http.Request(method, uri);
    final headers = payload['headers'];
    if (headers is Map) {
      headers.forEach((key, value) => request.headers['$key'] = '$value');
    }

    final body = payload['body'];
    final form = payload['form'];
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else {
        request.body = jsonEncode(body);
        request.headers.putIfAbsent('content-type', () => 'application/json');
      }
    } else if (form is Map) {
      request.bodyFields = {
        for (final entry in form.entries) '${entry.key}': '${entry.value}',
      };
    }

    final timeout = _timeoutOf(payload['timeout']);
    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    return {
      'statusCode': response.statusCode,
      'statusMessage': response.reasonPhrase ?? '',
      'headers': response.headers,
      'body': utf8.decode(response.bodyBytes, allowMalformed: true),
    };
  }

  Duration _timeoutOf(Object? value) {
    if (value is! num || value <= 0) return defaultHttpTimeout;
    final requested = Duration(milliseconds: value.toInt());
    return requested > const Duration(seconds: 60) ? const Duration(seconds: 60) : requested;
  }

  static Map<String, LxSourceCapability> _parseSources(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, LxSourceCapability>{};
    for (final entry in raw.entries) {
      final platform = '${entry.key}';
      if (!_allowedSources.contains(platform)) continue;
      final value = entry.value;
      if (value is! Map) continue;
      if ('${value['type']}' != 'music') continue;

      final allowed = platform == 'local' ? _localActions : _defaultActions;
      final actions = <String>{};
      final declaredActions = value['actions'];
      if (declaredActions is List) {
        for (final action in declaredActions) {
          if (action is String && allowed.contains(action)) actions.add(action);
        }
      }
      if (actions.isEmpty) continue;

      final qualitys = <String>{};
      final declaredQualitys = value['qualitys'];
      if (declaredQualitys is List) {
        for (final quality in declaredQualitys) {
          if (quality is String && _qualityWhitelist.contains(quality)) qualitys.add(quality);
        }
      }
      out[platform] = LxSourceCapability(actions: actions, qualitys: qualitys);
    }
    return out;
  }

  static String _firstLine(String raw) {
    final line = raw.split('\n').first.trim();
    return line.isEmpty ? raw.trim() : line;
  }

  /// 与上游桌面端的 preload 行为对齐的最小宿主。
  ///
  /// 注意：`Buffer`/`btoa`/`atob` 是脚本的常见依赖，必须在脚本执行前挂到全局。
  static const _hostShim = r'''
(function () {
  var B64CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  function utf8Encode(str) {
    var out = [];
    for (var i = 0; i < str.length; i++) {
      var c = str.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
        var c2 = str.charCodeAt(i + 1);
        if (c2 >= 0xdc00 && c2 <= 0xdfff) {
          c = 0x10000 + ((c - 0xd800) << 10) + (c2 - 0xdc00);
          i++;
        }
      }
      if (c < 0x80) out.push(c);
      else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
      else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
    return out;
  }

  function utf8Decode(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i++) {
      var c = bytes[i];
      if (c < 0x80) {
        out += String.fromCharCode(c);
      } else if (c >= 0xc0 && c < 0xe0 && i + 1 < bytes.length) {
        out += String.fromCharCode(((c & 0x1f) << 6) | (bytes[++i] & 0x3f));
      } else if (c >= 0xe0 && c < 0xf0 && i + 2 < bytes.length) {
        out += String.fromCharCode(((c & 0x0f) << 12) | ((bytes[++i] & 0x3f) << 6) | (bytes[++i] & 0x3f));
      } else if (c >= 0xf0 && i + 3 < bytes.length) {
        var cp = ((c & 0x07) << 18) | ((bytes[++i] & 0x3f) << 12) | ((bytes[++i] & 0x3f) << 6) | (bytes[++i] & 0x3f);
        cp -= 0x10000;
        out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
      } else {
        out += '\ufffd';
      }
    }
    return out;
  }

  function b64Encode(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i += 3) {
      var b0 = bytes[i], b1 = i + 1 < bytes.length ? bytes[i + 1] : 0, b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      out += B64CHARS[b0 >> 2];
      out += B64CHARS[((b0 & 3) << 4) | (b1 >> 4)];
      out += i + 1 < bytes.length ? B64CHARS[((b1 & 15) << 2) | (b2 >> 6)] : '=';
      out += i + 2 < bytes.length ? B64CHARS[b2 & 63] : '=';
    }
    return out;
  }

  function b64Decode(str) {
    var clean = String(str).replace(/[\r\n\t ]/g, '').replace(/=+$/, '');
    var out = new Uint8Array(Math.floor((clean.length * 3) / 4));
    var pos = 0, buffer = 0, bits = 0;
    for (var i = 0; i < clean.length; i++) {
      var idx = B64CHARS.indexOf(clean.charAt(i));
      if (idx < 0) continue;
      buffer = (buffer << 6) | idx;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out[pos++] = (buffer >> bits) & 0xff;
      }
    }
    return out.subarray(0, pos);
  }

  function hexDecode(str) {
    var clean = String(str).replace(/[^0-9a-fA-F]/g, '');
    var out = new Uint8Array(clean.length >> 1);
    for (var i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16);
    return out;
  }

  function hexEncode(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i++) out += (bytes[i] < 16 ? '0' : '') + bytes[i].toString(16);
    return out;
  }

  function latin1Encode(str) {
    var out = new Uint8Array(str.length);
    for (var i = 0; i < str.length; i++) out[i] = str.charCodeAt(i) & 0xff;
    return out;
  }

  function latin1Decode(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i++) out += String.fromCharCode(bytes[i]);
    return out;
  }

  function toBytes(input) {
    if (input instanceof LxBuffer || input instanceof Uint8Array) return new Uint8Array(input);
    if (typeof ArrayBuffer !== 'undefined' && input instanceof ArrayBuffer) return new Uint8Array(input.slice(0));
    if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView && ArrayBuffer.isView(input)) {
      return new Uint8Array(input.buffer.slice(input.byteOffset, input.byteOffset + input.byteLength));
    }
    if (Object.prototype.toString.call(input) === '[object Array]') return new Uint8Array(input);
    if (typeof input === 'string') return latin1Encode(input);
    return new Uint8Array(0);
  }

  var MD5_S = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];
  var MD5_K = (function () {
    var k = [];
    for (var i = 0; i < 64; i++) k[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) | 0;
    return k;
  })();

  function md5Hex(bytes) {
    var bitLenLo = (bytes.length << 3) >>> 0;
    var bitLenHi = Math.floor((bytes.length * 8) / 4294967296);
    var total = (((bytes.length + 8) >> 6) + 1) * 64;
    var buf = new Uint8Array(total);
    buf.set(bytes);
    buf[bytes.length] = 0x80;
    buf[total - 8] = bitLenLo & 0xff;
    buf[total - 7] = (bitLenLo >>> 8) & 0xff;
    buf[total - 6] = (bitLenLo >>> 16) & 0xff;
    buf[total - 5] = (bitLenLo >>> 24) & 0xff;
    buf[total - 4] = bitLenHi & 0xff;

    var a0 = 0x67452301, b0 = 0xefcdab89 | 0, c0 = 0x98badcfe | 0, d0 = 0x10325476 | 0;
    var M = new Int32Array(16);
    for (var off = 0; off < total; off += 64) {
      for (var j = 0; j < 16; j++) {
        M[j] = buf[off + j * 4] | (buf[off + j * 4 + 1] << 8) | (buf[off + j * 4 + 2] << 16) | (buf[off + j * 4 + 3] << 24);
      }
      var A = a0, B = b0, C = c0, D = d0;
      for (var i = 0; i < 64; i++) {
        var F, g;
        if (i < 16) { F = (B & C) | (~B & D); g = i; }
        else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
        else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
        else { F = C ^ (B | ~D); g = (7 * i) % 16; }
        F = (F + A + MD5_K[i] + M[g]) | 0;
        var s = MD5_S[(i >> 4) * 4 + (i % 4)];
        A = D; D = C; C = B;
        B = (B + ((F << s) | (F >>> (32 - s)))) | 0;
      }
      a0 = (a0 + A) | 0; b0 = (b0 + B) | 0; c0 = (c0 + C) | 0; d0 = (d0 + D) | 0;
    }
    function wordHex(w) {
      var out = '';
      for (var i = 0; i < 4; i++) out += ((w >>> (i * 8)) & 0xff).toString(16).padStart(2, '0');
      return out;
    }
    return wordHex(a0) + wordHex(b0) + wordHex(c0) + wordHex(d0);
  }

  class LxBuffer extends Uint8Array {
    static from(input, encoding) {
      var enc = (encoding || 'utf-8').toLowerCase();
      if (typeof input === 'string') {
        if (enc === 'base64') return new LxBuffer(b64Decode(input));
        if (enc === 'hex') return new LxBuffer(hexDecode(input));
        if (enc === 'latin1' || enc === 'binary') return new LxBuffer(latin1Encode(input));
        return new LxBuffer(utf8Encode(input));
      }
      return new LxBuffer(toBytes(input));
    }
    static alloc(size) { return new LxBuffer(new Uint8Array(size)); }
    static concat(list) {
      var total = 0;
      for (var i = 0; i < list.length; i++) total += list[i].length;
      var out = new LxBuffer(new Uint8Array(total));
      var pos = 0;
      for (var j = 0; j < list.length; j++) { out.set(list[j], pos); pos += list[j].length; }
      return out;
    }
    static isBuffer(obj) { return obj instanceof LxBuffer; }
    toString(encoding) {
      var enc = (encoding || 'utf-8').toLowerCase();
      if (enc === 'base64') return b64Encode(this);
      if (enc === 'hex') return hexEncode(this);
      if (enc === 'latin1' || enc === 'binary') return latin1Decode(this);
      return utf8Decode(this);
    }
  }

  globalThis.Buffer = LxBuffer;
  globalThis.btoa = function (str) { return b64Encode(utf8Encode(str)); };
  globalThis.atob = function (str) { return latin1Decode(b64Decode(str)); };

  globalThis.__lxInited = null;
  globalThis.__lxUpdateAlert = null;
  globalThis.__lxResult = { status: 'pending', data: null, error: null };
  globalThis.__lxHandlers = {};
  globalThis.__pendingHttp = {};
  globalThis.__seq = 0;

  globalThis.__lxHostInit = function (meta) {
    __lxInited = null;
    __lxUpdateAlert = null;
    __lxResult = { status: 'pending', data: null, error: null };
    __lxHandlers = {};
    __pendingHttp = {};

    var lx = {
      EVENT_NAMES: { request: 'request', inited: 'inited', updateAlert: 'updateAlert' },
      version: meta.lxVersion || '2.0.0',
      env: meta.env || 'mobile',
      currentScriptInfo: meta,
      on: function (name, handler) {
        if (name !== 'request') return Promise.reject(new Error('The event is not supported: ' + name));
        __lxHandlers.request = handler;
        return Promise.resolve();
      },
      send: function (name, data) {
        if (name === 'inited') {
          if (__lxInited !== null) return Promise.reject(new Error('Script is inited'));
          __lxInited = data;
          return Promise.resolve();
        }
        if (name === 'updateAlert') {
          if (__lxUpdateAlert !== null) return Promise.reject(new Error('The update alert can only be called once.'));
          __lxUpdateAlert = data;
          return Promise.resolve();
        }
        return Promise.reject(new Error('The event is not supported: ' + name));
      },
      request: function (url, options, callback) {
        options = options || {};
        var id = ++__seq;
        var payload = {
          id: id,
          url: String(url),
          method: String(options.method || 'get').toUpperCase(),
          headers: options.headers || {},
          timeout: typeof options.timeout === 'number' ? options.timeout : 0
        };
        if (options.body !== undefined && options.body !== null) payload.body = options.body;
        if (options.form !== undefined && options.form !== null) payload.form = options.form;
        if (options.formData !== undefined && options.formData !== null) payload.formData = true;
        __pendingHttp[id] = callback;
        sendMessage('lx.http', JSON.stringify(payload));
        return function () {
          delete __pendingHttp[id];
        };
      },
      utils: {
        crypto: {
          md5: function (str) { return md5Hex(utf8Encode(String(str))); },
          randomBytes: function (size) {
            var out = new LxBuffer(new Uint8Array(size));
            for (var i = 0; i < size; i++) out[i] = Math.floor(Math.random() * 256);
            return out;
          },
          aesEncrypt: function () { throw new Error('lx.utils.crypto.aesEncrypt is not supported'); },
          rsaEncrypt: function () { throw new Error('lx.utils.crypto.rsaEncrypt is not supported'); }
        },
        buffer: {
          from: function (input, encoding) { return LxBuffer.from(input, encoding); },
          bufToString: function (buf, format) { return LxBuffer.from(buf).toString(format); }
        },
        zlib: {
          inflate: function () { return Promise.reject(new Error('lx.utils.zlib.inflate is not supported')); },
          deflate: function () { return Promise.reject(new Error('lx.utils.zlib.deflate is not supported')); }
        }
      }
    };
    globalThis.lx = lx;
    globalThis.window = globalThis;
    globalThis.window.lx = lx;
  };

  globalThis.__lxHttpDone = function (id, err, jsonText) {
    var cb = __pendingHttp[id];
    if (!cb) return;
    delete __pendingHttp[id];
    if (err) { cb(new Error(String(err)), null, null); return; }
    var resp;
    try { resp = JSON.parse(jsonText); } catch (e) { resp = { statusCode: 0, body: String(jsonText) }; }
    var body = resp.body;
    if (typeof body === 'string' && /^\s*[\[{]/.test(body)) {
      try { body = JSON.parse(body); } catch (e) {}
    }
    resp.body = body;
    cb(null, resp, body);
  };

  globalThis.__lxCall = function (source, action, musicInfo, quality) {
    __lxResult = { status: 'pending', data: null, error: null };
    if (!__lxHandlers.request) {
      __lxResult = { status: 'error', data: null, error: 'Request event is not defined' };
      return true;
    }
    try {
      var p = __lxHandlers.request({
        source: source,
        action: action,
        info: { type: quality, musicInfo: musicInfo }
      });
      Promise.resolve(p).then(function (res) {
        __lxResult = { status: 'ok', data: res, error: null };
      }, function (e) {
        __lxResult = { status: 'error', data: null, error: String((e && e.message) || e) };
      });
    } catch (e) {
      __lxResult = { status: 'error', data: null, error: String((e && e.message) || e) };
    }
    return true;
  };
})();
''';
}
