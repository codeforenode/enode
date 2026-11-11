import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_chromium_webview/flutter_chromium_webview.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../state/cast_settings.dart';
import '../state/lrc.dart';

/// 投放层的网页侧：把 Flutter 的投放设置翻译成 `assets/cast/lyric.html` 认识的 payload。
///
/// 页面只吃三段信息：样式（含几何）、歌词、进度锚点。画面上的每一帧都由页面自己按
/// 锚点推导，Dart 侧不再逐帧推——多屏同步靠的是同一个锚点，不是同一次推送。

/// CEF 运行时是整个进程一份：先由主 isolate 把它起来，投放窗那边再调只会幂等返回。
/// 失败不重试也不抛：调用方退回 Flutter 自绘，画面不能因此空着。
Future<bool> castWebInitialize() {
  if (!Platform.isWindows) return Future.value(false);
  return _cefInit ??= () async {
    try {
      final support = await getApplicationSupportDirectory();
      final cache = Directory('${support.path}${Platform.pathSeparator}cef');
      if (!cache.existsSync()) cache.createSync(recursive: true);
      return await ChromiumWebViewController.initialize(cachePath: cache.absolute.path);
    } catch (_) {
      return false;
    }
  }();
}

Future<bool>? _cefInit;

/// 投放页面在打包产物里的相对位置（旧的一屏一窗回退仍用它）。
const castAssetPagePath = 'data/flutter_assets/assets/cast/lyric.html';

/// canvas 宿主页：一块画布里摆 N 份屏页（iframe），由它按屏分发构图。
const castCanvasAssetPagePath = 'data/flutter_assets/assets/cast/canvas.html';

/// 单屏的合成页：一句屏幕拿到自己的素材叠层 + 共享歌词/时钟。
const castScreenAssetPagePath = 'data/flutter_assets/assets/cast/screen.html';

/// 页面自身的 file:// 地址。用 file:// 而不是 loadHtmlString，是因为 loadHtmlString 要求
/// https 的 baseUrl，而 https 页面里读不到本地背景图（file:// 子资源被 Chromium 拦掉）。
String castPageUrl({String? executablePath}) => castFileUrl(_join(
      File(executablePath ?? Platform.resolvedExecutable).parent.path,
      castAssetPagePath,
    ));

String castCanvasPageUrl({String? executablePath}) => castFileUrl(_join(
      File(executablePath ?? Platform.resolvedExecutable).parent.path,
      castCanvasAssetPagePath,
    ));

/// 本地背景图 → 页面能加载的 file:// 地址（中文与空格会被百分号编码）。
String castFileUrl(String path) {
  final p = path.trim();
  if (p.isEmpty) return '';
  return Uri.file(File(p).absolute.path, windows: Platform.isWindows).toString();
}

/// 正斜杠写法在 Windows 上也能拼出可用路径。
String _join(String dir, String rel) => rel.split('/').fold(dir, (a, b) => '$a${Platform.pathSeparator}$b');

Map<String, Object?> castWebGeometry(Size design) => {
      'k': design.height <= 0 ? 1.0 : design.height / castRefHeight,
      'w': design.width,
      'h': design.height,
    };

/// CastStyle 逐字段映射；枚举用名字传，颜色用 ARGB 整数传，页面自己转 CSS。
Map<String, Object?> castWebStyle(CastStyle s) => {
      'lines': s.lines,
      'fontFamily': s.fontFamily,
      'fontSize': s.fontSize,
      'lineGap': s.lineGap,
      'textWidth': s.textWidth,
      'textHeight': s.textHeight,
      'fontWeight': s.fontWeight,
      'currentColor': s.currentColor,
      'otherColor': s.otherColor,
      'otherOpacity': s.otherOpacity,
      'strokeWidth': s.strokeWidth,
      'shadow': s.shadow,
      'background': s.background.name,
      'solidColor': s.solidColor,
      'gradientTop': s.gradientTop,
      'gradientBottom': s.gradientBottom,
      'imagePath': castFileUrl(s.imagePath),
      'imageFit': s.imageFit,
      'align': s.align.name,
      'vertical': s.vertical,
      'showTitle': s.showTitle,
      'showArtist': s.showArtist,
      'showSeat': s.showSeat,
      'offsetMs': s.offsetMs,
    };

Map<String, Object?> castWebLyric(
  List<LyricLine> lines, {
  String? title,
  String? artist,
  String? seat,
  int durationMs = 0,
  bool hasTrack = false,
  bool idle = false,
}) =>
    {
      // 行 = [起点, 文本, 行尾, 逐字?]；逐字 = [起点, 终点, 文本]，空行省掉最后一段。
      'lines': [
        for (final l in lines)
          [
            l.startMs,
            l.text,
            l.endMs,
            if (l.words.isNotEmpty)
              [
                for (final w in l.words) [w.startMs, w.endMs, w.text],
              ],
          ],
      ],
      // 无歌词时页面显示的占位文案；有曲目才显示，待机态保持空白。
      'noLyrics': l10n.castNoLyrics,
      'nowPlaying': {
        'title': title ?? '',
        'artist': artist ?? '',
        'seat': seat ?? '',
        'durationMs': durationMs,
        'hasTrack': hasTrack,
      },
      // 闲时引导语靠它决定显不显示：页面自己判断，多屏因此天然一致。
      'idle': idle,
    };

/// ARGB → CSS 颜色。CSS 的 8 位十六进制是 #RRGGBBAA，和 Flutter 的 AARRGGBB 字节序相反，
/// 所以带透明度时统一写成 rgba()，别让预制色在投放端变成另一个颜色。
String castCssColor(int argb) {
  final a = (argb >>> 24) & 0xFF;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  if (a >= 255) {
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }
  return 'rgba($r,$g,$b,${(a / 255).toStringAsFixed(3)})';
}

/// 一个素材投到某屏时的画面描述。几何用百分比，字体/圆角用 1080 基准的设计像素，
/// 页面拿到该屏的 k 后自己折算——同一份素材在不同分辨率上视觉大小一致。
Map<String, Object?> castWebItem(CastMaterial m, CastPlacement p) => {
      'id': p.id,
      't': m.type.name,
      'x': p.x,
      'y': p.y,
      'w': p.width,
      'h': p.height,
      'op': p.opacity,
      'z': p.z,
      // 座位号已从歌词附加信息里移除：新投放层不再显示它（旧一屏一窗回退仍按原样式）。
      if (m.type == CastMaterialType.lyric) 'style': {...castWebStyle(m.style), 'showSeat': false},
      if (m.type == CastMaterialType.text || m.type == CastMaterialType.idleText) ...{
        // 闲时引导语和文字素材共用同一套排版字段，区别只在页面按 idle 决定显隐。
        'text': m.text,
        'size': m.fontSize,
        'weight': m.fontWeight,
        'color': castCssColor(m.color),
        'align': m.align.name,
        'shadow': m.shadow,
        'font': m.fontFamily,
      },
      if (m.isMedia) ...{
        'src': m.source == CastMediaSource.local ? castFileUrl(m.path) : m.url.trim(),
        'fit': m.fit.name,
        'r': m.radius,
      },
      if (m.type == CastMaterialType.video) ...{
        'loop': m.loop,
        'auto': m.autoplay,
        'snd': p.sound,
        'vol': p.volume,
      },
      if (m.type == CastMaterialType.url) ...{
        'url': m.url.trim(),
        'refresh': m.refreshSec,
        'rev': m.rev,
      },
    };

/// 每块在投的屏一份构图：底色 + 按层级排好的素材。只发可见项，隐藏素材等下次改设置再重发。
List<Map<String, Object?>> castWebScreens(CastSettings s, List<CastMonitor> monitors) {
  final byId = {for (final m in monitors) m.id: m};
  final out = <Map<String, Object?>>[];
  for (final t in s.activeTargets(monitors)) {
    final monitor = byId[t.monitorId];
    if (monitor == null) continue;
    final design = castDesignSize(monitor, t);
    out.add({
      'id': t.monitorId,
      'k': castScaleFor(design),
      'w': design.width.round(),
      'h': design.height.round(),
      'bg': castCssColor(t.backgroundColor),
      'items': [
        for (final p in s.placementsOn(t.monitorId))
          if (p.visible)
            if (s.materialById(p.materialId) case final material?) castWebItem(material, p),
      ],
    });
  }
  return out;
}

Map<String, Object?> castWebTick({required int positionMs, required int wallMs, required bool playing}) => {
      'tick': {'positionMs': positionMs, 'wallMs': wallMs, 'playing': playing},
    };

/// 拼一段 `window.enode.apply(...)`；payload 里缺的段，页面保留上一份。
String castApplyScript(Map<String, Object?> section) => 'window.enode.apply(${jsonEncode(section)});';
