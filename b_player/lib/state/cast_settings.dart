import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../desktop/monitor_rects.dart';
import '../edge/atomic_json.dart';

/// Windows 歌词投放的设置模型（一次性存成 cast.settings.v1 一个 JSON 串）。
///
/// 分成两层：
/// - 每台屏各自的几何（[CastTarget]：模式 + 投放区），因为屏与屏之间只有位置不同；
/// - 全局共享的样式与背景（[CastStyle]），保证多屏画面 100% 同步。
///
/// 投放区存的是「相对该屏工作区的百分比」，所以换分辨率、插拔屏都能重算，不会存死像素。
/// 字号/描边存的是「按 1080 高折算的设计像素」，渲染时再乘该投放区的实际高度比例，
/// 这样同一套设置在 1600x900 和 4K 电视上是同一个视觉大小。

/// 字号与描边的折算基准高度（逻辑像素）。
const double castRefHeight = 1080;

/// 设计像素 → 该投放区实际像素的倍数。字号、描边都乘它，
/// 这样同一套设置在 1600x900 和 4K 电视上是同一个视觉大小，多屏画面才对得上。
double castScaleFor(Size regionSize) =>
    regionSize.height <= 0 ? 1 : regionSize.height / castRefHeight;

/// 投放窗在虚拟桌面里的落位矩形（逻辑 px）。
/// 全屏模式给的是整屏尺寸，但原点只能按 rcWork 估（screen_retriever 拿不到 rcMonitor 原点），
/// 任务栏在顶部时会偏一截——所以这种模式要再让 setFullScreen 去对齐整屏。
Rect castWindowBounds(CastMonitor m, CastTarget t) {
  if (t.mode == CastMode.fullscreen) {
    return Rect.fromLTWH(m.workOrigin.dx, m.workOrigin.dy, m.fullSize.width, m.fullSize.height);
  }
  final r = t.region.toRect(m.workSize);
  return Rect.fromLTWH(m.workOrigin.dx + r.left, m.workOrigin.dy + r.top, r.width, r.height);
}

/// 投放区尺寸：字号、描边都按它的高度折算。预览和投放窗共用这一个基准，
/// 才不会「预览里刚好，投出去偏了」。
Size castDesignSize(CastMonitor m, CastTarget t) => t.mode == CastMode.fullscreen
    ? m.fullSize
    : t.region.toRect(m.workSize).size;

enum CastMode {
  /// 整屏投放：盖住包括任务栏在内的整个屏幕。
  fullscreen,

  /// 区域投放：只在该屏工作区里的一块矩形内画。
  region,
}

enum CastBackground {
  black,
  gradient,
  color,
  image,
}

enum CastAlign {
  left,
  center,
  right,
}

/// 投放区：相对该屏工作区的百分比矩形，0..1。
@immutable
class CastRegion {
  const CastRegion({
    this.left = 0,
    this.top = 0,
    this.width = 1,
    this.height = 1,
  });

  static const full = CastRegion();

  /// 底部字幕条：左右各留 5%，高度约 22%，贴着屏底。
  static const bottomStrip = CastRegion(left: .05, top: .7, width: .9, height: .24);

  /// 居中窄条：屏幕正中一行。
  static const centerStrip = CastRegion(left: .05, top: .42, width: .9, height: .16);

  final double left;
  final double top;
  final double width;
  final double height;

  /// 折成该屏工作区里的逻辑像素矩形。
  Rect toRect(Size work) => Rect.fromLTWH(
        left * work.width, top * work.height, width * work.width, height * work.height,
      );

  /// 用工作区像素矩形反推百分比（拖框结束后回写）。
  static CastRegion fromRect(Size work, Rect rect) {
    if (work.width <= 0 || work.height <= 0) return full;
    final clamped = rect.intersect(Offset.zero & work);
    return CastRegion(
      left: clamped.left / work.width,
      top: clamped.top / work.height,
      width: clamped.width / work.width,
      height: clamped.height / work.height,
    );
  }

  Map<String, double> toJson() => {
        'l': _r4(left),
        't': _r4(top),
        'w': _r4(width),
        'h': _r4(height),
      };

  static CastRegion fromJson(Object? raw) {
    if (raw is! Map) return full;
    double read(String k, double fallback) {
      final v = (raw[k] as num?)?.toDouble();
      return v == null ? fallback : v.clamp(0.0, 1.0);
    }

    var region = CastRegion(
      left: read('l', 0),
      top: read('t', 0),
      width: read('w', 1),
      height: read('h', 1),
    );
    // 手工改过的存档可能出现 l=0.8,w=1 这种右/下溢出的组合：
    // 折回边界，别让投放窗超出工作区。
    region = CastRegion(
      left: region.left,
      top: region.top,
      width: (region.left + region.width).clamp(0.0, 1.0) - region.left,
      height: (region.top + region.height).clamp(0.0, 1.0) - region.top,
    );
    // 宽高为 0 的存档没意义，退回整屏，避免投放窗变成一条看不见的缝。
    return region.width < 0.01 || region.height < 0.01 ? full : region;
  }

  @override
  bool operator ==(Object other) =>
      other is CastRegion &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

double _r4(double v) => (v * 10000).roundToDouble() / 10000;

/// 一台屏的投放配置。monitorId 用系统给的 DeviceID，name 只用于展示和拔屏后的提示。
@immutable
class CastTarget {
  const CastTarget({
    required this.monitorId,
    required this.name,
    this.enabled = false,
    this.mode = CastMode.fullscreen,
    this.region = CastRegion.full,
    this.backgroundColor = 0xFF000000,
  });

  final String monitorId;
  final String name;
  final bool enabled;
  final CastMode mode;
  final CastRegion region;

  /// 这块屏的底色。素材里的图片/影片要透出桌面是做不到的（Windows 只支持整窗 alpha），
  /// 所以屏幕必须自带一层实在的背景色；歌词自己不画背景，靠叠在别的素材上。
  final int backgroundColor;

  CastTarget copyWith({
    bool? enabled,
    CastMode? mode,
    CastRegion? region,
    String? name,
    int? backgroundColor,
  }) =>
      CastTarget(
        monitorId: monitorId,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        region: region ?? this.region,
        backgroundColor: backgroundColor ?? this.backgroundColor,
      );

  Map<String, dynamic> toJson() => {
        'id': monitorId,
        'name': name,
        'on': enabled,
        'mode': mode.name,
        'region': region.toJson(),
        'bg': backgroundColor,
      };

  static CastTarget fromJson(Map raw) => CastTarget(
        monitorId: '${raw['id'] ?? ''}',
        name: '${raw['name'] ?? ''}',
        enabled: raw['on'] == true,
        mode: _enumByName(CastMode.values, raw['mode'], CastMode.fullscreen),
        region: CastRegion.fromJson(raw['region']),
        backgroundColor: (raw['bg'] as num?)?.toInt() ?? 0xFF000000,
      );

  @override
  bool operator ==(Object other) =>
      other is CastTarget &&
      other.monitorId == monitorId &&
      other.name == name &&
      other.enabled == enabled &&
      other.mode == mode &&
      other.region == region &&
      other.backgroundColor == backgroundColor;

  @override
  int get hashCode => Object.hash(monitorId, name, enabled, mode, region, backgroundColor);
}

/// 全局样式 + 静态背景。所有投放窗共用一份，画面内容因此天然同步。
@immutable
class CastStyle {
  const CastStyle({
    this.lines = 2,
    this.fontFamily = 'AlibabaPuHuiTi',
    this.fontSize = 88,
    this.lineGap = 0,
    this.textWidth = 100,
    this.textHeight = 100,
    this.fontWeight = 600,
    this.currentColor = 0xFF3DDC84,
    this.otherColor = 0xFF8B979F,
    this.otherOpacity = 100,
    this.strokeWidth = 3,
    this.shadow = true,
    this.background = CastBackground.black,
    this.solidColor = 0xFF000000,
    this.gradientTop = 0xFF101720,
    this.gradientBottom = 0xFF000000,
    this.imagePath = '',
    this.imageFit = true,
    this.align = CastAlign.center,
    this.vertical = 50,
    this.showSeat = false,
  });

  /// 同时显示几行歌词（当前行 + 前后各取）。
  final int lines;
  final String fontFamily;

  /// 按 [castRefHeight] 折算的设计像素字号，渲染时再乘投放区高度比例。
  final double fontSize;

  /// 行与行之间额外的空白（设计像素），0 表示沿用字号的 1.5 倍行高。
  final double lineGap;

  /// 字形横向/纵向拉伸百分比，100 = 原始比例。
  final double textWidth;
  final double textHeight;

  final int fontWeight;
  final int currentColor;
  final int otherColor;

  /// 非当前句整体的不透明度（0-100），连描边与阴影一起淡出；100 = 不透明。
  final double otherOpacity;
  final double strokeWidth;
  final bool shadow;
  final CastBackground background;
  final int solidColor;
  final int gradientTop;
  final int gradientBottom;

  /// 图片背景的本地路径；读不到就退回纯黑。
  final String imagePath;

  /// true = 铺满（裁边），false = 完整显示（留黑边）。
  final bool imageFit;
  final CastAlign align;

  /// 歌词块在投放区里的垂直位置（0=贴顶，100=贴底）。
  final double vertical;
  final bool showSeat;

  static const defaults = CastStyle();

  bool get hasImage => background == CastBackground.image && imagePath.isNotEmpty;

  /// 设计像素折算到某个投放区后的实际字号/描边。
  double fontSizeAt(Size region) => fontSize * castScaleFor(region);

  double strokeWidthAt(Size region) => strokeWidth * castScaleFor(region);

  CastStyle copyWith({
    int? lines,
    String? fontFamily,
    double? fontSize,
    double? lineGap,
    double? textWidth,
    double? textHeight,
    int? fontWeight,
    int? currentColor,
    int? otherColor,
    double? otherOpacity,
    double? strokeWidth,
    bool? shadow,
    CastBackground? background,
    int? solidColor,
    int? gradientTop,
    int? gradientBottom,
    String? imagePath,
    bool? imageFit,
    CastAlign? align,
    double? vertical,
    bool? showSeat,
  }) =>
      CastStyle(
        lines: lines ?? this.lines,
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        lineGap: lineGap ?? this.lineGap,
        textWidth: textWidth ?? this.textWidth,
        textHeight: textHeight ?? this.textHeight,
        fontWeight: fontWeight ?? this.fontWeight,
        currentColor: currentColor ?? this.currentColor,
        otherColor: otherColor ?? this.otherColor,
        otherOpacity: otherOpacity ?? this.otherOpacity,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        shadow: shadow ?? this.shadow,
        background: background ?? this.background,
        solidColor: solidColor ?? this.solidColor,
        gradientTop: gradientTop ?? this.gradientTop,
        gradientBottom: gradientBottom ?? this.gradientBottom,
        imagePath: imagePath ?? this.imagePath,
        imageFit: imageFit ?? this.imageFit,
        align: align ?? this.align,
        vertical: vertical ?? this.vertical,
        showSeat: showSeat ?? this.showSeat,
      );

  Map<String, dynamic> toJson() => {
        'lines': lines,
        'font': fontFamily,
        'size': fontSize,
        'gap': lineGap,
        'tw': textWidth,
        'th': textHeight,
        'weight': fontWeight,
        'color': currentColor,
        'color2': otherColor,
        'otherAlpha': otherOpacity,
        'stroke': strokeWidth,
        'shadow': shadow,
        'bg': background.name,
        'bgColor': solidColor,
        'gradTop': gradientTop,
        'gradBottom': gradientBottom,
        'image': imagePath,
        'fit': imageFit,
        'align': align.name,
        'vpos': vertical,
        'seat': showSeat,
      };

  static CastStyle fromJson(Map raw) => CastStyle(
        lines: ((raw['lines'] as num?)?.toInt() ?? 2).clamp(1, 4),
        fontFamily: '${raw['font'] ?? 'AlibabaPuHuiTi'}',
        fontSize: ((raw['size'] as num?)?.toDouble() ?? 88).clamp(12.0, 400.0),
        lineGap: ((raw['gap'] as num?)?.toDouble() ?? 0).clamp(0.0, 160.0),
        textWidth: ((raw['tw'] as num?)?.toDouble() ?? 100).clamp(40.0, 200.0),
        textHeight: ((raw['th'] as num?)?.toDouble() ?? 100).clamp(40.0, 200.0),
        fontWeight: ((raw['weight'] as num?)?.toInt() ?? 600).clamp(100, 900),
        currentColor: (raw['color'] as num?)?.toInt() ?? 0xFF3DDC84,
        otherColor: (raw['color2'] as num?)?.toInt() ?? 0xFF8B979F,
        otherOpacity: ((raw['otherAlpha'] as num?)?.toDouble() ?? 100).clamp(0.0, 100.0),
        strokeWidth: ((raw['stroke'] as num?)?.toDouble() ?? 3).clamp(0.0, 24.0),
        shadow: raw['shadow'] != false,
        background: _enumByName(CastBackground.values, raw['bg'], CastBackground.black),
        solidColor: (raw['bgColor'] as num?)?.toInt() ?? 0xFF000000,
        gradientTop: (raw['gradTop'] as num?)?.toInt() ?? 0xFF101720,
        gradientBottom: (raw['gradBottom'] as num?)?.toInt() ?? 0xFF000000,
        imagePath: '${raw['image'] ?? ''}',
        imageFit: raw['fit'] != false,
        align: _enumByName(CastAlign.values, raw['align'], CastAlign.center),
        vertical: ((raw['vpos'] as num?)?.toDouble() ?? 50).clamp(0.0, 100.0),
        showSeat: raw['seat'] == true,
      );

  // 样式字段有二十来个，逐个写 == 容易漏；toJson 里全是原始值，直接比映射最稳。
  @override
  bool operator ==(Object other) => other is CastStyle && mapEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hashAll(toJson().entries);
}

/// 素材类型。歌词只是其中一种，其余素材负责背景、看板、片头与字幕。
///
/// [idleText] 是「闲时引导语」：配置方式和 [text] 完全一样，区别只在显示时机——
/// 没有曲目在播、队列也空着（刚开机、点的歌播完了）时才出现，有歌就自动让位。
enum CastMaterialType { lyric, url, image, video, text, idleText }

/// 图片/影片的来源：本地文件或网络地址。
enum CastMediaSource { local, url }

/// 画面适应方式。
enum CastFit { cover, contain, stretch }

int _castIdSeq = 0;

/// 设置页新增素材/投放项时用的 id；进程内唯一即可，不需要全局 UUID。
String newCastId(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_castIdSeq++).toRadixString(36)}';

/// 一个可复用的素材。同一份素材可以投到多块屏：内容与样式只有一份，
/// 每块屏各自记一条 [CastPlacement]（位置/大小/层级/声音）。
@immutable
class CastMaterial {
  const CastMaterial({
    required this.id,
    required this.type,
    this.name = '',
    this.style = CastStyle.defaults,
    this.text = '',
    this.fontSize = 56,
    this.fontWeight = 600,
    this.color = 0xFFE8EDF1,
    this.align = CastAlign.center,
    this.shadow = true,
    this.fontFamily = 'AlibabaPuHuiTi',
    this.source = CastMediaSource.local,
    this.path = '',
    this.url = '',
    this.fit = CastFit.cover,
    this.radius = 0,
    this.loop = true,
    this.autoplay = true,
    this.rev = 0,
    this.viewportW = 0,
    this.viewportH = 0,
  });

  final String id;
  final CastMaterialType type;

  /// 用户可改的显示名；空串时界面按类型显示默认名。
  final String name;

  /// 歌词样式（仅歌词素材使用）。
  final CastStyle style;

  /// 文字素材。
  final String text;
  final double fontSize;
  final int fontWeight;
  final int color;
  final CastAlign align;
  final bool shadow;
  final String fontFamily;

  /// 图片/影片素材。
  final CastMediaSource source;
  final String path;
  final String url;
  final CastFit fit;

  /// 圆角（设计像素，按 1080 高折算）。
  final double radius;
  final bool loop;
  final bool autoplay;

  /// 手动重载计数：加一就让投放页丢掉旧 document，重新载入同一条网址。
  final int rev;

  /// 网址素材的浏览器页面尺寸（px）。页面按这个视口排版，再等比缩放塞进投放框；
  /// 0 表示不固定，页面视口跟随投放框大小（旧版行为，未设置过的素材走这条）。
  final int viewportW;
  final int viewportH;

  static const defaultLyric =
      CastMaterial(id: 'lyric', type: CastMaterialType.lyric);

  bool get isMedia => type == CastMaterialType.image || type == CastMaterialType.video;

  /// 闲时引导语只在「没有曲目、队列也空」的时候出现，由投放页按这个标记隐藏。
  bool get isIdleOnly => type == CastMaterialType.idleText;

  /// 素材是否已有可显示的内容（空素材仍然保留在架子上，方便先放位置再填）。
  bool get hasContent => switch (type) {
        CastMaterialType.lyric => true,
        CastMaterialType.text || CastMaterialType.idleText => text.trim().isNotEmpty,
        CastMaterialType.url => url.trim().isNotEmpty,
        CastMaterialType.image || CastMaterialType.video =>
          source == CastMediaSource.local ? path.trim().isNotEmpty : url.trim().isNotEmpty,
      };

  String get effectiveUrl => source == CastMediaSource.local ? '' : url.trim();

  CastMaterial copyWith({
    String? name,
    CastStyle? style,
    String? text,
    double? fontSize,
    int? fontWeight,
    int? color,
    CastAlign? align,
    bool? shadow,
    String? fontFamily,
    CastMediaSource? source,
    String? path,
    String? url,
    CastFit? fit,
    double? radius,
    bool? loop,
    bool? autoplay,
    int? rev,
    int? viewportW,
    int? viewportH,
  }) =>
      CastMaterial(
        id: id,
        type: type,
        name: name ?? this.name,
        style: style ?? this.style,
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
        fontWeight: fontWeight ?? this.fontWeight,
        color: color ?? this.color,
        align: align ?? this.align,
        shadow: shadow ?? this.shadow,
        fontFamily: fontFamily ?? this.fontFamily,
        source: source ?? this.source,
        path: path ?? this.path,
        url: url ?? this.url,
        fit: fit ?? this.fit,
        radius: radius ?? this.radius,
        loop: loop ?? this.loop,
        autoplay: autoplay ?? this.autoplay,
        rev: rev ?? this.rev,
        viewportW: viewportW ?? this.viewportW,
        viewportH: viewportH ?? this.viewportH,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        't': type.name,
        'n': name,
        if (type == CastMaterialType.lyric) 'st': style.toJson(),
        if (type == CastMaterialType.url) 'url': url,
        if (isMedia) 'src': source.name,
        if (type == CastMaterialType.text || type == CastMaterialType.idleText) 'text': text,
        if (type == CastMaterialType.url) ...{
          'rev': rev,
          if (viewportW > 0 && viewportH > 0) ...{
            'vw': viewportW,
            'vh': viewportH,
          },
        },
        if (isMedia) ...{
          'path': path,
          'url': url,
          'fit': fit.name,
          'r': radius,
        },
        if (type == CastMaterialType.video) ...{
          'loop': loop,
          'auto': autoplay,
        },
        if (type == CastMaterialType.text || type == CastMaterialType.idleText) ...{
          'size': fontSize,
          'weight': fontWeight,
          'color': color,
          'align': align.name,
          'shadow': shadow,
          'font': fontFamily,
        },
      };

  static CastMaterial fromJson(Map raw) {
    final type = _enumByName(CastMaterialType.values, raw['t'], CastMaterialType.lyric);
    final style = raw['st'] is Map ? CastStyle.fromJson(raw['st'] as Map) : CastStyle.defaults;
    return CastMaterial(
      id: '${raw['id'] ?? ''}',
      type: type,
      name: '${raw['n'] ?? ''}',
      style: style,
      text: '${raw['text'] ?? ''}',
      fontSize: ((raw['size'] as num?)?.toDouble() ?? 56).clamp(8.0, 400.0),
      fontWeight: ((raw['weight'] as num?)?.toInt() ?? 600).clamp(100, 900),
      color: (raw['color'] as num?)?.toInt() ?? 0xFFE8EDF1,
      align: _enumByName(CastAlign.values, raw['align'], CastAlign.center),
      shadow: raw['shadow'] != false,
      fontFamily: '${raw['font'] ?? 'AlibabaPuHuiTi'}',
      source: _enumByName(CastMediaSource.values, raw['src'], CastMediaSource.local),
      path: '${raw['path'] ?? ''}',
      url: '${raw['url'] ?? ''}',
      fit: _enumByName(CastFit.values, raw['fit'], CastFit.cover),
      radius: ((raw['r'] as num?)?.toDouble() ?? 0).clamp(0.0, 400.0),
      loop: raw['loop'] != false,
      autoplay: raw['auto'] != false,
      rev: ((raw['rev'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      viewportW: ((raw['vw'] as num?)?.toInt() ?? 0).clamp(0, 10000),
      viewportH: ((raw['vh'] as num?)?.toInt() ?? 0).clamp(0, 10000),
    );
  }

  /// 复制成一个独立素材：之后改这份不会影响原素材。
  CastMaterial duplicate(String newId, {String? name}) => CastMaterial.fromJson({
        ...toJson(),
        'id': newId,
        'n': ?name,
      });

  // 歌词素材带一层嵌套的 style map，浅层 mapEquals 会把同值当成不同；比编码后的串最稳。
  @override
  bool operator ==(Object other) =>
      other is CastMaterial && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// 素材投到某块屏上的一条记录：几何（百分比）、层级、透明度、显隐与声音。
@immutable
class CastPlacement {
  const CastPlacement({
    required this.id,
    required this.materialId,
    required this.screenId,
    this.x = 0,
    this.y = 0,
    this.width = 1,
    this.height = 1,
    this.z = 1,
    this.opacity = 1,
    this.visible = true,
    this.locked = false,
    this.sound = false,
    this.volume = 60,
  });

  final String id;
  final String materialId;
  final String screenId;

  /// 相对投放区的百分比，0..1。
  final double x;
  final double y;
  final double width;
  final double height;
  final int z;
  final double opacity;
  final bool visible;
  final bool locked;

  /// 影片素材是否出声；别的素材忽略这一项。
  final bool sound;
  final int volume;

  CastPlacement copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    int? z,
    double? opacity,
    bool? visible,
    bool? locked,
    bool? sound,
    int? volume,
  }) =>
      CastPlacement(
        id: id,
        materialId: materialId,
        screenId: screenId,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        z: z ?? this.z,
        opacity: opacity ?? this.opacity,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        sound: sound ?? this.sound,
        volume: volume ?? this.volume,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'm': materialId,
        's': screenId,
        'x': _r4(x),
        'y': _r4(y),
        'w': _r4(width),
        'h': _r4(height),
        'z': z,
        'op': _r4(opacity),
        'on': visible,
        'lock': locked,
        'snd': sound,
        'vol': volume,
      };

  static CastPlacement fromJson(Map raw) {
    double read(String k, double fallback) =>
        ((raw[k] as num?)?.toDouble() ?? fallback).clamp(0.0, 1.0);
    final w = read('w', 1);
    final h = read('h', 1);
    return CastPlacement(
      id: '${raw['id'] ?? ''}',
      materialId: '${raw['m'] ?? ''}',
      screenId: '${raw['s'] ?? ''}',
      x: read('x', 0),
      y: read('y', 0),
      width: w < 0.01 ? 0.01 : w,
      height: h < 0.01 ? 0.01 : h,
      z: ((raw['z'] as num?)?.toInt() ?? 1).clamp(0, 999),
      opacity: ((raw['op'] as num?)?.toDouble() ?? 1).clamp(0.0, 1.0),
      visible: raw['on'] != false,
      locked: raw['lock'] == true,
      sound: raw['snd'] == true,
      volume: ((raw['vol'] as num?)?.toInt() ?? 60).clamp(0, 100),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CastPlacement &&
      other.id == id &&
      other.materialId == materialId &&
      other.screenId == screenId &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.z == z &&
      other.opacity == opacity &&
      other.visible == visible &&
      other.locked == locked &&
      other.sound == sound &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(id, materialId, screenId, x, y, width, height, z, opacity,
      visible, locked, sound, volume);
}

/// 一次显示器扫描的结果。
///
/// screen_retriever 0.2.2 只给整屏尺寸和「工作区」原点/尺寸（Windows 的 rcMonitor / rcWork），
/// 拿不到 rcMonitor 的原点，所以这里的工作区矩形是唯一可信的坐标基准；
/// 整屏投放交给 window_manager 的 setFullScreen，由它自己按 MonitorFromWindow 取 rcMonitor。
@immutable
class CastMonitor {
  const CastMonitor({
    required this.id,
    required this.name,
    required this.workOrigin,
    required this.workSize,
    required this.fullSize,
    required this.scale,
    this.primary = false,
    this.model = '',
  });

  factory CastMonitor.fromDisplay(Display d) => CastMonitor(
        id: d.id,
        name: d.name ?? d.id,
        workOrigin: d.visiblePosition ?? Offset.zero,
        workSize: d.visibleSize ?? d.size,
        fullSize: d.size,
        scale: (d.scaleFactor ?? 1).toDouble(),
      );

  static List<CastMonitor> scan(List<Display> displays) =>
      [for (final d in displays) CastMonitor.fromDisplay(d)];

  final String id;
  final String name;
  final Offset workOrigin;
  final Size workSize;
  final Size fullSize;
  final double scale;

  /// Windows 主显示器的标记；screen_retriever 不提供，由 user32 补齐。
  final bool primary;

  /// EDID 型号串（如 `DELL U2415`）。Windows 没有可靠的「内置 / 外接」标志，
  /// 拔插后同名屏的 id 也会变，这里是用户唯一能认屏的线索。
  final String model;

  /// 该屏工作区在虚拟桌面里的矩形（投放区的坐标基准）。
  Rect get workRect => Rect.fromLTWH(workOrigin.dx, workOrigin.dy, workSize.width, workSize.height);

  String get label =>
      '$name · ${workSize.width.round()}x${workSize.height.round()} · ${(scale * 100).round()}%';

  CastMonitor copyWith({bool? primary, String? model}) => CastMonitor(
        id: id,
        name: name,
        workOrigin: workOrigin,
        workSize: workSize,
        fullSize: fullSize,
        scale: scale,
        primary: primary ?? this.primary,
        model: model ?? this.model,
      );
}

/// 扫一次显示器。没有插件环境（单元测试）时返回空列表，投放入口随之关闭，不抛异常。
///
/// screen_retriever 不给「主屏」和显示器型号，这里用 user32 按物理工作区对位补齐：
/// 两套坐标只差该屏缩放（逻辑 × scale = 物理），±3px 内视为同一块屏。
Future<List<CastMonitor>> scanCastMonitors() async {
  final List<CastMonitor> monitors;
  try {
    monitors = CastMonitor.scan(await screenRetriever.getAllDisplays());
  } catch (_) {
    return const [];
  }
  if (monitors.isEmpty) return monitors;
  final physical = physicalMonitorRects();
  if (physical.isEmpty) return monitors;
  return [
    for (final m in monitors)
      switch (matchPhysicalRect(predictedWork: _physicalWork(m), all: physical)) {
        final p? => m.copyWith(primary: p.primary, model: p.model),
        null => m,
      },
  ];
}

Rect _physicalWork(CastMonitor m) => Rect.fromLTWH(m.workOrigin.dx * m.scale, m.workOrigin.dy * m.scale,
    m.workSize.width * m.scale, m.workSize.height * m.scale);

/// 屏幕管理设置本体：每台屏的勾选/几何/底色 + 共享素材 + 每屏的投放项。
///
/// 歌词不再独占一份全局样式，而是一种普通素材：样式跟着素材走，同一素材投到多块屏
/// 时文字与样式天然一致，位置/层级/显隐则各自独立。
@immutable
class CastSettings {
  const CastSettings({
    this.enabled = false,
    this.targets = const [],
    this.materials = const [CastMaterial.defaultLyric],
    this.placements = const [],
    this.frameRate = 60,
  });

  static const _key = 'cast.settings.v2';
  static const _legacyKey = 'cast.settings.v1';

  /// 是否投放：跟着屏幕勾选走（勾上任意一屏就开投），没有可用目标时不会真的开窗。
  final bool enabled;
  final List<CastTarget> targets;
  final List<CastMaterial> materials;
  final List<CastPlacement> placements;

  /// 画布浏览器的最高渲染帧率。整块画布共用一个 CEF 浏览器，所以它是全局的：
  /// 网页、歌词动画都受它限制（对应 OBS 浏览器源的 FPS，但无法按素材分档）。
  final int frameRate;

  static const defaults = CastSettings();

  /// 兼容旧调用：取第一份歌词素材的样式（旧版全局样式 / 一屏一窗回退）。
  CastStyle get style =>
      (_firstOrNull(materials.where((m) => m.type == CastMaterialType.lyric)) ?? CastMaterial.defaultLyric).style;

  CastMaterialsView get materialsView => CastMaterialsView(materials);

  CastSettings copyWith({
    bool? enabled,
    List<CastTarget>? targets,
    List<CastMaterial>? materials,
    List<CastPlacement>? placements,
    int? frameRate,
  }) =>
      CastSettings(
        enabled: enabled ?? this.enabled,
        targets: targets ?? this.targets,
        materials: materials ?? this.materials,
        placements: placements ?? this.placements,
        frameRate: frameRate ?? this.frameRate,
      );

  /// 取某台屏的配置；没存过就返回一个未勾选的默认值（调用方再补 name）。
  CastTarget targetFor(String monitorId) =>
      targets.firstWhere((t) => t.monitorId == monitorId, orElse: () => CastTarget(monitorId: monitorId, name: ''));

  CastMaterial? materialById(String id) {
    for (final m in materials) {
      if (m.id == id) return m;
    }
    return null;
  }

  CastPlacement? placementById(String id) {
    for (final p in placements) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 某块屏的投放项，按层级从低到高（先画的在前）。
  List<CastPlacement> placementsOn(String screenId) {
    final list = [for (final p in placements) if (p.screenId == screenId) p];
    final order = {for (var i = 0; i < list.length; i++) list[i].id: i};
    list.sort((a, b) {
      final c = a.z.compareTo(b.z);
      return c != 0 ? c : order[a.id]!.compareTo(order[b.id]!);
    });
    return list;
  }

  /// 某块屏下一次新增素材时的层级。
  int nextZ(String screenId) {
    var z = 0;
    for (final p in placements) {
      if (p.screenId == screenId && p.z > z) z = p.z;
    }
    return z + 1;
  }

  CastSettings withTarget(CastTarget target) {
    final next = [for (final t in targets) if (t.monitorId == target.monitorId) target else t];
    if (!next.any((t) => t.monitorId == target.monitorId)) next.add(target);
    return copyWith(targets: next);
  }

  CastSettings withMaterial(CastMaterial material) {
    final next = [for (final m in materials) if (m.id == material.id) material else m];
    if (!next.any((m) => m.id == material.id)) next.add(material);
    return copyWith(materials: next);
  }

  /// 删除素材时连带删掉它在各屏的投放项，避免留下引用不到素材的空框。
  CastSettings withoutMaterial(String materialId) => copyWith(
        materials: [for (final m in materials) if (m.id != materialId) m],
        placements: [for (final p in placements) if (p.materialId != materialId) p],
      );

  /// 复制素材：新素材是独立的一份，投到同样的屏、同样的位置，层级放到最上面。
  CastSettings duplicateMaterial(String materialId) {
    final src = materialById(materialId);
    if (src == null) return this;
    final newId = newCastId('m');
    var next = withMaterial(src.duplicate(newId));
    for (final p in placements.where((p) => p.materialId == materialId).toList()) {
      next = next.withPlacement(CastPlacement(
        id: newCastId('p'),
        materialId: newId,
        screenId: p.screenId,
        x: p.x,
        y: p.y,
        width: p.width,
        height: p.height,
        z: next.nextZ(p.screenId),
        opacity: p.opacity,
        visible: p.visible,
        locked: p.locked,
        sound: p.sound,
        volume: p.volume,
      ));
    }
    return next;
  }

  CastSettings withPlacement(CastPlacement placement) {
    final next = [for (final p in placements) if (p.id == placement.id) placement else p];
    if (!next.any((p) => p.id == placement.id)) next.add(placement);
    return copyWith(placements: next);
  }

  CastSettings withoutPlacement(String placementId) =>
      copyWith(placements: [for (final p in placements) if (p.id != placementId) p]);

  /// 图层上移/下移一位（delta=+1 往上）。只在同一块屏内换位。
  CastSettings movePlacement(String placementId, int delta) {
    final p = placementById(placementId);
    if (p == null) return this;
    final list = placementsOn(p.screenId);
    final from = list.indexWhere((e) => e.id == placementId);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= list.length) return this;
    final moved = list.removeAt(from);
    list.insert(to, moved);
    return _withZOrder(p.screenId, list);
  }

  CastSettings placementToFront(String placementId) {
    final p = placementById(placementId);
    if (p == null) return this;
    final list = placementsOn(p.screenId);
    final moved = _firstOrNull(list.where((e) => e.id == placementId));
    if (moved == null) return this;
    list.removeWhere((e) => e.id == placementId);
    list.add(moved);
    return _withZOrder(p.screenId, list);
  }

  CastSettings placementToBack(String placementId) {
    final p = placementById(placementId);
    if (p == null) return this;
    final list = placementsOn(p.screenId);
    final moved = _firstOrNull(list.where((e) => e.id == placementId));
    if (moved == null) return this;
    list.removeWhere((e) => e.id == placementId);
    list.insert(0, moved);
    return _withZOrder(p.screenId, list);
  }

  /// 图层面板拖拽后的顺序（从底到顶）一次性落盘，层级重新写成 1..n。
  CastSettings withZOrder(String screenId, List<String> idsBottomToTop) {
    final byId = {for (var i = 0; i < idsBottomToTop.length; i++) idsBottomToTop[i]: i + 1};
    final next = [
      for (final p in placements)
        if (p.screenId == screenId && byId.containsKey(p.id)) p.copyWith(z: byId[p.id]) else p,
    ];
    return copyWith(placements: next);
  }

  CastSettings _withZOrder(String screenId, List<CastPlacement> ordered) =>
      withZOrder(screenId, [for (final p in ordered) p.id]);

  CastSettings withScreenBackground(String monitorId, int color) =>
      withTarget(targetFor(monitorId).copyWith(backgroundColor: color));

  /// 打开一块屏时，如果它还没有任何素材，补一条默认歌词，别让人对着空屏发呆。
  CastSettings ensureLyricOn(String screenId) {
    if (placements.any((p) => p.screenId == screenId)) return this;
    final lyric = _firstOrNull(materials.where((m) => m.type == CastMaterialType.lyric));
    if (lyric == null) return this;
    return withPlacement(CastPlacement(
      id: newCastId('p'),
      materialId: lyric.id,
      screenId: screenId,
      x: .05,
      y: .58,
      width: .9,
      height: .34,
      z: 1,
    ));
  }

  /// 勾选一台屏就直接开始投放；最后一屏取消勾选时投放随之停止。
  CastSettings toggled(String monitorId, String name, bool on) {
    final next = withTarget(targetFor(monitorId).copyWith(enabled: on, name: name));
    final anyOn = next.targets.any((t) => t.enabled);
    if (!on) return next.copyWith(enabled: enabled && anyOn);
    return next.copyWith(enabled: true).ensureLyricOn(monitorId);
  }

  /// 投放屏右键「关闭本屏投放」：取消这一屏；没有别的屏在投时投放一并停止。
  CastSettings withoutScreen(String monitorId) {
    final next = [for (final t in targets) if (t.monitorId == monitorId) t.copyWith(enabled: false) else t];
    return copyWith(targets: next, enabled: enabled && next.any((t) => t.enabled));
  }

  /// 投放屏右键「关闭全部投放」：各屏取消勾选，素材与布局都留着，重新勾选即恢复。
  CastSettings withCastingOff() =>
      copyWith(enabled: false, targets: [for (final t in targets) t.copyWith(enabled: false)]);

  CastSettings withMode(String monitorId, CastMode mode) => withTarget(targetFor(monitorId).copyWith(mode: mode));

  CastSettings withRegion(String monitorId, String name, CastRegion region) =>
      withTarget(targetFor(monitorId).copyWith(region: region, name: name));

  /// 勾选了、而且这次真的扫到的屏——投放窗只按这个列表开。
  List<CastTarget> activeTargets(List<CastMonitor> monitors) {
    final online = {for (final m in monitors) m.id};
    return [for (final t in targets) if (t.enabled && online.contains(t.monitorId)) t];
  }

  /// 把已存配置和这次扫描对齐：新屏补默认（未勾选），拔掉的屏保留配置但不参与投放，
  /// 顺序按扫描结果走，设置页的屏列表才和系统显示设置里看到的一致。
  CastSettings alignedTo(List<CastMonitor> monitors) {
    final online = {for (final m in monitors) m.id};
    final next = <CastTarget>[
      // 屏名跟着这次扫描走（拔插后 \\.\DISPLAYn 会变），其余配置保持用户存的那份。
      for (final m in monitors) targetFor(m.id).copyWith(name: m.name),
      for (final t in targets)
        if (!online.contains(t.monitorId)) t,
    ];
    return copyWith(targets: next);
  }

  /// 放应用自身数据目录：素材与投放配置会随使用增长，不再和所有小配置一起
  /// 挤在 prefs 里整包重写。拿不到目录（单元测试/桌面预览）时仍读写旧 prefs。
  static Future<File?> _file() async {
    try {
      final support = await getApplicationSupportDirectory();
      return File(p.join(support.path, 'data', 'cast.json'));
    } catch (_) {
      return null;
    }
  }

  static Future<CastSettings> load() async {
    try {
      final file = await _file();
      if (file != null) {
        final raw = await AtomicJsonFile(file).read();
        if (raw is Map) return _decodeMap(raw);
        final legacy = await _loadPrefs();
        if (legacy == null) return defaults;
        final migrated = decode(legacy);
        await migrated.save();
        return migrated;
      }
      final legacy = await _loadPrefs();
      if (legacy == null) return defaults;
      final migrated = decode(legacy);
      await migrated.save();
      return migrated;
    } catch (_) {
      // 无插件环境（单元测试/安卓侧编译）下用默认值，不阻断启动。
      return defaults;
    }
  }

  static Future<String?> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key) ?? prefs.getString(_legacyKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final text = toJsonString();
    final file = await _file();
    if (file != null) {
      try {
        await AtomicJsonFile(file).writeText(text);
        return;
      } catch (_) {
        // 文件名被占用等情况下退回 prefs，至少本次会话的配置不丢。
      }
    }
    try {
      (await SharedPreferences.getInstance()).setString(_key, text);
    } catch (_) {}
  }

  String toJsonString() => jsonEncode(toJson());

  /// 同时接受 v2 与 v1：v1 的全局歌词样式迁移成一份歌词素材 + 每屏一条投放项。
  static CastSettings decode(String text) {
    try {
      final raw = jsonDecode(text);
      if (raw is! Map) return defaults;
      return _decodeMap(raw);
    } catch (_) {
      return defaults;
    }
  }

  static CastSettings _decodeMap(Map raw) =>
      raw['materials'] is List || raw['v'] == 2 ? _fromV2(raw) : _fromV1(raw);

  static CastSettings _fromV2(Map raw) {
    final materials = <CastMaterial>[
      for (final m in (raw['materials'] as List? ?? const []))
        if (m is Map && '${m['id'] ?? ''}'.isNotEmpty) CastMaterial.fromJson(m),
    ];
    if (materials.isEmpty) materials.add(CastMaterial.defaultLyric);
    final ids = {for (final m in materials) m.id};
    return CastSettings(
      enabled: raw['on'] == true,
      targets: _targetsFrom(raw['targets']),
      materials: materials,
      placements: [
        for (final p in (raw['placements'] as List? ?? const []))
          if (p is Map && '${p['id'] ?? ''}'.isNotEmpty && ids.contains('${p['m'] ?? ''}'))
            CastPlacement.fromJson(p),
      ],
      frameRate: ((raw['fps'] as num?)?.toInt() ?? 60).clamp(24, 60),
    );
  }

  static CastSettings _fromV1(Map raw) {
    final style = raw['style'] is Map ? CastStyle.fromJson(raw['style'] as Map) : CastStyle.defaults;
    final targets = _targetsFrom(raw['targets']).map((t) => t.copyWith(
          backgroundColor: switch (style.background) {
            CastBackground.color => style.solidColor,
            CastBackground.gradient => style.gradientBottom,
            _ => 0xFF000000,
          },
        )).toList();
    final materials = <CastMaterial>[
      CastMaterial(id: 'lyric', type: CastMaterialType.lyric, style: style),
      if (style.hasImage)
        CastMaterial(
          id: 'legacy-bg',
          type: CastMaterialType.image,
          source: CastMediaSource.local,
          path: style.imagePath,
          fit: style.imageFit ? CastFit.cover : CastFit.contain,
        ),
    ];
    final placements = <CastPlacement>[];
    for (final t in targets.where((t) => t.enabled)) {
      if (style.hasImage) {
        placements.add(CastPlacement(
          id: newCastId('p'),
          materialId: 'legacy-bg',
          screenId: t.monitorId,
          z: 1,
        ));
      }
      final y = ((style.vertical - 15) / 100).clamp(0.0, .68).toDouble();
      placements.add(CastPlacement(
        id: newCastId('p'),
        materialId: 'lyric',
        screenId: t.monitorId,
        x: .05,
        y: y,
        width: .9,
        height: .3,
        z: style.hasImage ? 2 : 1,
      ));
    }
    return CastSettings(
      enabled: raw['on'] == true,
      targets: targets,
      materials: materials,
      placements: placements,
    );
  }

  static List<CastTarget> _targetsFrom(Object? list) => [
        if (list is List)
          for (final t in list)
            if (t is Map && '${t['id'] ?? ''}'.isNotEmpty) CastTarget.fromJson(t),
      ];

  Map<String, dynamic> toJson() => {
        'v': 2,
        'on': enabled,
        'targets': [for (final t in targets) t.toJson()],
        'materials': [for (final m in materials) m.toJson()],
        'placements': [for (final p in placements) p.toJson()],
        'fps': frameRate,
      };

  @override
  bool operator ==(Object other) =>
      other is CastSettings &&
      other.enabled == enabled &&
      other.frameRate == frameRate &&
      _sameList(other.targets, targets) &&
      _sameList(other.materials, materials) &&
      _sameList(other.placements, placements);

  @override
  int get hashCode => Object.hash(
      enabled, frameRate, Object.hashAll(targets), Object.hashAll(materials), Object.hashAll(placements));
}

/// 只读视图：给界面按 id 快速取素材，避免每帧线性查找。
class CastMaterialsView {
  CastMaterialsView(List<CastMaterial> materials) : _byId = {for (final m in materials) m.id: m};

  final Map<String, CastMaterial> _byId;

  CastMaterial? operator [](String id) => _byId[id];
}

T? _firstOrNull<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}

bool _sameList<T extends Object>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
