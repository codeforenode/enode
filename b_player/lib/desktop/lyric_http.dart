import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../log.dart';
import '../state/app_state.dart';
import 'cast_web.dart';

/// 局域网歌词页的默认端口。与单实例检测的 47621 相邻，避开常见服务端口。
const int defaultLyricSharePort = 47622;

/// 局域网歌词页的开关与端口。
///
/// 默认关闭：只有店主自己打开，端口才开始监听；打开后同一网络内任何人都能访问。
class LyricShareSettings {
  const LyricShareSettings({
    this.enabled = false,
    this.port = defaultLyricSharePort,
  });

  static const _key = 'lyric.share.v1';

  final bool enabled;
  final int port;

  bool get usable => enabled && port >= 1024 && port <= 65535;

  LyricShareSettings copyWith({bool? enabled, int? port}) => LyricShareSettings(
        enabled: enabled ?? this.enabled,
        port: port ?? this.port,
      );

  static Future<LyricShareSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const LyricShareSettings();
      final map = jsonDecode(raw) as Map<String, Object?>;
      return LyricShareSettings(
        enabled: map['enabled'] == true,
        port: (map['port'] as num?)?.toInt() ?? defaultLyricSharePort,
      );
    } catch (_) {
      // 无插件环境或数据损坏：当作未开启，不阻断启动。
      return const LyricShareSettings();
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode({'enabled': enabled, 'port': port}));
    } catch (e) {
      EnodeLog.w('lyric-http', '保存局域网歌词设置失败：$e');
    }
  }
}

/// 当前曲目的歌词载荷：样式 + 歌词行 + 时间锚点。
///
/// 与投放侧共用 [castWebLyric] / [castWebStyle]，页面拿到后直接 `window.enode.apply`，
/// 不另写一套渲染，样式改动不会两边分叉。
Map<String, Object?> lyricSharePayload(AppState state) {
  final np = state.nowPlaying;
  final now = DateTime.now().millisecondsSinceEpoch;
  return {
    // 页面会用自身视口覆盖 geometry；这里给投放基准尺寸，避免首次渲染算出 0。
    'geometry': {'k': 1.0, 'w': 1920.0, 'h': 1080.0},
    // 座位号不对外：投放层也已经关掉，局域网页面保持一致。
    'style': {...castWebStyle(state.cast.style), 'showSeat': false},
    ...castWebLyric(
      state.lyricLines,
      title: np?.title,
      artist: np?.artist,
      seat: np?.seat,
      durationMs: np?.durationMs ?? 0,
      hasTrack: np != null,
      idle: np == null && state.queue.isEmpty,
    ),
    'tick': {
      'positionMs': np?.positionMs ?? 0,
      'wallMs': now,
      'playing': state.playing && np != null,
    },
    // 给第三方留的元信息；页面本身不依赖。
    'track': {
      'trackKey': np?.trackKey,
      'title': np?.title ?? '',
      'artist': np?.artist ?? '',
      'durationMs': np?.durationMs ?? 0,
    },
    // 手机上没有"待机黑屏"的上下文，空画面会让人以为打不开；给一行可读提示。
    'share': {'idleText': np == null ? l10n.lyricShareIdle : ''},
  };
}

/// 只读的局域网 HTTP 服务：把**当前曲目**的歌词页暴露给同一网络里的浏览器。
///
/// 边界：
/// - 只有设置页显式开启才监听端口，默认关闭。
/// - 只服务白名单路径：`/`、`/v1/state`、`/fonts/<内置字体>`；不做目录映射，杜绝路径穿越。
/// - 只读 GET/HEAD，没有写入面；曲库列表与检索能力不暴露。
class LyricShareServer {
  LyricShareServer(this._state);

  final AppState _state;

  HttpServer? _http;
  int _port = defaultLyricSharePort;
  String? _lastError;
  String? _pageHtml;
  List<String> _urls = const [];

  bool get running => _http != null;
  String? get lastError => _lastError;
  int get port => _port;
  List<String> get urls => _urls;

  Future<void> start({required int port}) async {
    await stop();
    _port = port;
    _lastError = null;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: false);
      _http = server;
      server.listen(_handle, onError: (Object e) => EnodeLog.w('lyric-http', '服务异常：$e'));
      _urls = await _collectUrls();
      EnodeLog.i('lyric-http', '已启动 port=$port 地址=${_urls.length}');
    } on SocketException catch (e) {
      // 端口被占是最常见的失败：把可读原因留给设置页，不抛出中断启动流程。
      _lastError = e.osError?.message ?? '$e';
      EnodeLog.w('lyric-http', '端口 $port 监听失败：$_lastError');
    } catch (e, st) {
      _lastError = '$e';
      EnodeLog.e('lyric-http', '启动失败 port=$port', e, st);
    }
  }

  Future<void> stop() async {
    final server = _http;
    _http = null;
    _urls = const [];
    if (server == null) return;
    try {
      await server.close(force: true);
      EnodeLog.i('lyric-http', '已停止');
    } catch (e) {
      EnodeLog.w('lyric-http', '停止失败：$e');
    }
  }

  Future<List<String>> _collectUrls() async {
    // 本机回环固定排第一：同机浏览器/OBS 用它最稳，不受网卡增减影响。
    final out = <String>['http://127.0.0.1:$_port/'];
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('169.254.')) continue; // 链路本地地址，手机连不上
          final url = 'http://$ip:$_port/';
          if (!out.contains(url)) out.add(url);
        }
      }
    } catch (e) {
      EnodeLog.w('lyric-http', '枚举网卡失败：$e');
    }
    return out;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        await _text(req, HttpStatus.methodNotAllowed, 'method not allowed');
        return;
      }
      final path = req.uri.path;
      switch (path) {
        case '/':
        case '/index.html':
          await _servePage(req);
        case '/v1/state':
          await _serveState(req);
        default:
          if (path.startsWith('/fonts/')) {
            await _serveFont(req, path.substring('/fonts/'.length));
          } else {
            await _text(req, HttpStatus.notFound, 'not found');
          }
      }
    } catch (e, st) {
      EnodeLog.e('lyric-http', '处理请求失败 ${req.uri}', e, st);
      try {
        await _text(req, HttpStatus.internalServerError, 'internal error');
      } catch (_) {}
    }
  }

  Future<void> _servePage(HttpRequest req) async {
    final html = _pageHtml ??= _loadAndInject();
    if (html == null) {
      await _text(req, HttpStatus.internalServerError, 'page asset missing');
      return;
    }
    req.response.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    req.response.write(html);
    await req.response.close();
  }

  Future<void> _serveState(HttpRequest req) async {
    req.response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    req.response.write(jsonEncode(lyricSharePayload(_state)));
    await req.response.close();
  }

  /// 只放行内置的两套字重；文件名直接来自 URL，必须先对表，不能拼路径。
  static const _fonts = {
    'AlibabaPuHuiTi-3-55-Regular.otf': 'AlibabaPuHuiTi-3-55-Regular.otf',
    'AlibabaPuHuiTi-3-85-Bold.otf': 'AlibabaPuHuiTi-3-85-Bold.otf',
  };

  Future<void> _serveFont(HttpRequest req, String name) async {
    final file = _fonts[name];
    if (file == null) {
      await _text(req, HttpStatus.notFound, 'not found');
      return;
    }
    final path = _join(_assetDir(), 'fonts${Platform.pathSeparator}$file');
    final f = File(path);
    if (!await f.exists()) {
      await _text(req, HttpStatus.notFound, 'not found');
      return;
    }
    req.response.headers.contentType = ContentType('font', 'otf');
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'public, max-age=86400');
    await req.response.addStream(f.openRead());
    await req.response.close();
  }

  Future<void> _text(HttpRequest req, int status, String body) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
    req.response.write(body);
    await req.response.close();
  }

  String _assetDir() => _join(File(Platform.resolvedExecutable).parent.path,
      'data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}assets');

  String _join(String dir, String rel) => '$dir${Platform.pathSeparator}$rel';

  /// 复用投放页：注入轮询脚本 + 设置面板脚本，渲染逻辑仍由 `assets/cast/lyric.html`
  /// 单点维护。面板脚本读不到就跳过（页面照常工作，只是没有本地设置能力）。
  String? _loadAndInject() {
    // 与 castAssetPagePath 指向同一个文件；这里要的是磁盘路径，不是 file:// 地址。
    final path = _join(_assetDir(), 'cast${Platform.pathSeparator}lyric.html');
    try {
      final raw = File(path).readAsStringSync();
      // 投放页要黑底铺满屏，局域网页默认透明：`!important` 压住页面每帧重设的内联背景。
      const style = '<style id="enode-share-bg">'
          'html,body{background:transparent!important}'
          '</style>';
      var out = raw.contains('</head>')
          ? raw.replaceFirst('</head>', '$style</head>')
          : '$style$raw';
      final script = '<script>$_pollScript</script>';
      out = out.contains('</body>')
          ? out.replaceFirst('</body>', '$script</body>')
          : '$out$script';
      // 设置面板是局域网页独有的附加层：设置存浏览器本地（每块屏独立），不改服务端状态。
      final panel = _readAsset('cast${Platform.pathSeparator}share_panel.js');
      if (panel != null) {
        final panelTag = '<script>$panel</script>';
        out = out.contains('</body>')
            ? out.replaceFirst('</body>', '$panelTag</body>')
            : '$out$panelTag';
      }
      return out;
    } catch (e) {
      EnodeLog.w('lyric-http', '读取投放页失败 $path：$e');
      return null;
    }
  }

  String? _readAsset(String rel) {
    try {
      return File(_join(_assetDir(), rel)).readAsStringSync();
    } catch (e) {
      EnodeLog.w('lyric-http', '读取资源失败 $rel：$e');
      return null;
    }
  }
}

/// 页面里的轮询：每 500ms 取一次当前曲目，交给投放页自己的 `window.enode.apply`。
///
/// 时间进度的推算留在页面内（锚点 + wallMs），轮询频率不需要跟帧率挂钩。
const String _pollScript = '''
(function () {
  // 默认透明，方便直接叠加到 OBS；?bg=dark 恢复投放页的黑底/渐变背景。
  if (new URLSearchParams(location.search).get('bg') === 'dark') {
    var bgStyle = document.getElementById('enode-share-bg');
    if (bgStyle) bgStyle.remove();
  }
  function geometry() {
    return {
      k: Math.max(0.3, Math.min(3, (window.innerHeight || 1080) / 1080)),
      w: window.innerWidth || 1920,
      h: window.innerHeight || 1080
    };
  }
  var hint = null;
  function showHint(text) {
    if (!text) {
      if (hint) hint.style.display = 'none';
      return;
    }
    if (!hint) {
      hint = document.createElement('div');
      hint.style.cssText = 'position:fixed;left:0;right:0;bottom:28px;text-align:center;' +
        'color:rgba(140,150,160,.9);font:14px/1.4 sans-serif;pointer-events:none;z-index:9';
      document.body.appendChild(hint);
    }
    hint.style.display = 'block';
    hint.textContent = text;
  }
  function tick() {
    fetch('/v1/state', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('' + r.status); return r.json(); })
      .then(function (data) {
        if (!window.enode || !window.enode.apply) return;
        data.geometry = geometry();
        window.enode.apply(data);
        showHint(data.share && data.share.idleText);
      })
      .catch(function () {})
      .then(function () { setTimeout(tick, 500); });
  }
  tick();
})();
''';
