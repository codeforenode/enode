import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/cast_settings.dart';
import '../state/lrc.dart';

/// 投放画面的唯一绘制入口：设置页预览和真正的投放窗用的是同一个 widget，
/// 这样「看到的」就是「投出去的」。
///
/// [design] 是投放区的真实逻辑像素（投放窗里等于窗口自身尺寸）；[ratio] 只给预览用，
/// 把整块投放区缩进设置弹窗。字号/描边先按设计像素折算到 [design] 高度，再乘 [ratio]，
/// 所以预览和实投的字幕比例一致。
class CastLyricView extends StatelessWidget {
  const CastLyricView({
    super.key,
    required this.style,
    required this.design,
    required this.lines,
    required this.index,
    this.ratio = 1,
    this.title,
    this.artist,
    this.seat,
    this.positionMs = 0,
    this.durationMs = 0,
    this.placeholder = '',
  });

  final CastStyle style;
  final Size design;
  final double ratio;
  final List<LyricLine> lines;

  /// 有曲目但没有歌词时显示的一行占位；空串表示待机态不显示。
  final String placeholder;

  /// 当前句下标；<0（前奏）时按第一句显示。
  final int index;
  final String? title;
  final String? artist;

  /// 座位号原样显示（本机点歌时传「本机」）。
  final String? seat;
  final int positionMs;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    final box = Size(design.width * ratio, design.height * ratio);
    // 系统字号缩放不能碰投放画面：这里每个尺寸都是按屏幕分辨率算出来的。
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: box.width,
        height: box.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CastBackground(style: style),
            CustomPaint(
              painter: _LyricPainter(
                style: style,
                box: box,
                scale: castScaleFor(design) * ratio,
                rows: _rows(),
                meta: _metaText(),
                positionMs: positionMs,
                durationMs: durationMs,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _metaText() {
    final parts = <String>[
      if (style.showTitle && (title?.trim().isNotEmpty ?? false)) title!.trim(),
      if (style.showArtist && (artist?.trim().isNotEmpty ?? false)) artist!.trim(),
      if (style.showSeat && (seat?.trim().isNotEmpty ?? false)) seat!.trim(),
    ];
    return parts.join(' · ');
  }

  List<LyricRow> _rows() => castLyricRows(style, lines, index, placeholder: placeholder);
}

/// 一行歌词的绘制数据：文本、是否当前句、逐字时间（没有逐字时为空）。
typedef LyricRow = ({String text, bool current, List<LyricWord> words, int startMs, int endMs});

/// 1 句只当前；2 句=当前+下一句；3 句及以上=上一句+当前+下一句。
/// [placeholder] 只在完全没有歌词时给出一行非当前句样式的占位。
List<LyricRow> castLyricRows(CastStyle style, List<LyricLine> lines, int index,
    {String placeholder = ''}) {
  if (lines.isEmpty) {
    return placeholder.isEmpty
        ? const []
        : [(text: placeholder, current: false, words: const <LyricWord>[], startMs: 0, endMs: 0)];
  }
  final before = style.lines >= 3 ? 1 : 0;
  final after = style.lines == 1 ? 0 : 1;
  final i = index < 0 ? 0 : math.min(index, lines.length - 1);
  return [
    for (var j = i - before; j <= i + after; j++)
      if (j >= 0 && j < lines.length)
        (
          text: lines[j].text,
          current: j == i,
          words: lines[j].words,
          startMs: lines[j].startMs,
          endMs: lines[j].endMs,
        ),
  ];
}

/// 超宽行的横向位移：把唱到的横向位置保持在可视区约 [anchor] 处，
/// 两端夹住——开头不提前露右边，结尾不把最后一个字拖出左边。
double castLyricScrollOffset({
  required double textWidth,
  required double avail,
  required double focus,
  double anchor = .65,
}) {
  final max = math.max(0.0, textWidth - avail);
  final value = focus - avail * anchor;
  if (value <= 0) return 0;
  return value >= max ? max : value;
}

/// 屏幕管理里的歌词素材：只画字，不画背景。位置/大小由外层的投放项决定，
/// 字号按整屏的设计比例折算（[scale]），歌词块在框内居中；字号不随框缩放，
/// 横向超出就裁切并让当前句跟着演唱滚动。
class CastLyricLayer extends StatelessWidget {
  const CastLyricLayer({
    super.key,
    required this.style,
    required this.box,
    required this.scale,
    required this.lines,
    required this.index,
    this.meta = '',
    this.positionMs = 0,
    this.durationMs = 0,
    this.placeholder = '',
  });

  final CastStyle style;
  final Size box;

  /// 1080 基准的设计像素 → 本画面像素。
  final double scale;
  final List<LyricLine> lines;
  final int index;
  final String meta;

  /// 有曲目但没有歌词时显示的一行占位；空串表示待机态不显示。
  final String placeholder;
  final int positionMs;
  final int durationMs;

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
        child: CustomPaint(
          size: box,
          painter: _LyricPainter(
            style: style,
            box: box,
            scale: scale,
            rows: castLyricRows(style, lines, index, placeholder: placeholder),
            meta: meta,
            positionMs: positionMs,
            durationMs: durationMs,
            centered: true,
          ),
        ),
      );
}

/// 投放区背景。始终铺满一层实在的画面：Windows 的穿透窗只能整窗设 alpha，
/// 没有逐像素透明，所以背景必须自己画满，不能留空让后面的桌面透出来。
class _CastBackground extends StatelessWidget {
  const _CastBackground({required this.style});
  final CastStyle style;

  @override
  Widget build(BuildContext context) => switch (style.background) {
        CastBackground.black => const ColoredBox(color: Color(0xFF000000)),
        CastBackground.color => ColoredBox(color: Color(style.solidColor)),
        CastBackground.gradient => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(style.gradientTop), Color(style.gradientBottom)],
              ),
            ),
          ),
        CastBackground.image => _image(),
      };

  Widget _image() {
    final path = style.imagePath;
    if (path.isEmpty) return const ColoredBox(color: Color(0xFF000000));
    return Image.file(
      File(path),
      fit: style.imageFit ? BoxFit.cover : BoxFit.contain,
      gaplessPlayback: true,
      // 读不到（拔了 U 盘、改了目录）就退回纯黑，不能让投放窗整扇空掉。
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF000000)),
    );
  }
}

/// 歌词块 + 附加信息的排版；paint 时收到的尺寸已全部折算成实际像素。
class _LyricPainter extends CustomPainter {
  _LyricPainter({
    required this.style,
    required this.box,
    required this.scale,
    required this.rows,
    required this.meta,
    required this.positionMs,
    required this.durationMs,
    this.centered = false,
  });

  final CastStyle style;
  final Size box;

  /// 设计像素 → 本画面像素的倍数（已含预览缩放）。
  final double scale;
  final List<LyricRow> rows;
  final String meta;
  final int positionMs;
  final int durationMs;

  /// 屏幕管理的歌词素材用自己的框：整块居中；纵向装不下就靠外层裁切，不缩字。
  final bool centered;

  static const _outline = Color(0xFF000000);

  @override
  void paint(Canvas canvas, Size size) {
    if (box.width < 4 || box.height < 4) return;
    final k = scale;
    final pad = 20 * k;
    final avail = math.max(1.0, box.width - pad * 2);
    final gap = style.lineGap * k;
    final tw = (style.textWidth / 100).clamp(0.4, 2.0);
    final th = (style.textHeight / 100).clamp(0.4, 2.0);
    final otherAlpha = (style.otherOpacity / 100).clamp(0.0, 1.0);
    final base = style.fontSize * k;
    // 字高拉长时行高跟着长，行间距始终是额外的空白。
    double rowHFor(double b) => math.max(b * 1.5, b * 1.2 * th) + gap;
    double metaHFor(double b) => meta.isEmpty ? 0.0 : b * .34 + 12 * k;
    final rowH = rowHFor(base);
    final metaH = metaHFor(base);
    final total = metaH + rows.length * rowH;
    // vertical 指歌词块「中心」在投放区高度上的百分比；再夹回画面内，避免上下出血。
    var y = centered
        ? math.max(0.0, (box.height - total) / 2)
        : box.height * (style.vertical / 100) - total / 2;
    if (!centered) y = y.clamp(0.0, math.max(0.0, box.height - total));
    if (meta.isNotEmpty) {
      _draw(canvas, text: meta, fontSize: base * .34, weight: 500,
          color: Color(style.otherColor), top: y + (metaH - 12 * k) / 2, pad: pad, avail: avail, k: k,
          fitToWidth: true);
      y += metaH;
    }
    final ms = positionMs + style.offsetMs;
    for (final row in rows) {
      final karaoke = row.current && row.words.isNotEmpty;
      // 字号固定为用户设置值：超宽不缩字，当前句跟随演唱向左滚，其余行从左侧裁切。
      final probe = _painter(row.text, base, style.fontWeight, const Color(0xFF000000))..layout();
      final rowW = probe.width * tw;
      final overflow = math.max(0.0, rowW - avail);
      final shift = row.current && overflow > 0
          ? castLyricScrollOffset(textWidth: rowW, avail: avail, focus: _focusPx(probe, row, tw, ms))
          : 0.0;
      final left = overflow > 0 ? pad - shift : _leftFor(rowW, pad, avail);
      if (overflow > 0) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(pad, 0, avail, box.height));
      }
      _draw(
        canvas,
        text: row.text,
        fontSize: base,
        weight: style.fontWeight,
        color: Color(karaoke || !row.current ? style.otherColor : style.currentColor),
        top: y + (rowH - base * 1.2 * th) / 2,
        pad: pad,
        avail: avail,
        k: k,
        sx: tw,
        sy: th,
        left: left,
        opacity: row.current ? 1 : otherAlpha,
        highlight: karaoke ? Color(style.currentColor) : null,
        reveal: karaoke ? _revealOf(row) : null,
      );
      if (overflow > 0) canvas.restore();
      y += rowH;
    }
  }

  /// 跟随演唱的焦点：逐字行取当前唱到的横向位置，整行行按时间比例推进。
  double _focusPx(TextPainter probe, LyricRow row, double sx, int ms) {
    if (row.words.isNotEmpty) {
      final reveal = _revealOf(row);
      final x0 = _caretX(probe, reveal.before);
      final x1 = _caretX(probe, reveal.before + reveal.length);
      return (x0 + (x1 - x0) * reveal.p) * sx;
    }
    final span = row.endMs - row.startMs;
    final p = span > 0 ? ((ms - row.startMs) / span).clamp(0.0, 1.0) : 0.0;
    return probe.width * sx * p;
  }

  double _caretX(TextPainter tp, int index) =>
      tp.getOffsetForCaret(TextPosition(offset: index.clamp(0, tp.plainText.length)), Rect.zero).dx;

  /// 描边走一层、填充走一层：黑描边 + 亮字是为了 OBS「Screen」混合能直接滤掉底色。
  /// [highlight] + [reveal] 同时给出时，在已唱到的宽度上再叠一层亮色（逐字扫光）。
  void _draw(Canvas canvas,
      {required String text,
      required double fontSize,
      required int weight,
      required Color color,
      required double top,
      required double pad,
      required double avail,
      required double k,
      double sx = 1,
      double sy = 1,
      double? left,
      double opacity = 1,
      bool fitToWidth = false,
      Color? highlight,
      ({int before, int length, double p})? reveal}) {
    // 只有附加信息（歌名/歌手）还做宽度贴合；歌词行一律用用户设置的固定字号。
    final size = fitToWidth ? _fitFontSize(text, fontSize, weight, avail, sx) : fontSize;
    final strokeW = style.strokeWidth * k * 2;
    final shadowed = style.shadow;
    final fade = opacity.clamp(0.0, 1.0);
    final fillColor = fade >= .999 ? color : color.withValues(alpha: color.a * fade);
    final fitWidth = fitToWidth ? avail / sx : double.infinity;
    TextPainter layer(Color? color, {Paint? foreground, bool shadows = false}) =>
        _painter(text, size, weight, color,
            foreground: foreground, shadows: shadows, shadowOpacity: fade)
          ..layout(maxWidth: fitWidth);
    final stroke = strokeW > 0.5
        ? layer(null,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeW
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..color = fade >= .999 ? _outline : _outline.withValues(alpha: fade),
            shadows: shadowed)
        : null;
    final fill = layer(fillColor, shadows: strokeW <= 0.5 && shadowed);
    final startX = left ?? _leftFor(fill.width * sx, pad, avail);

    void paint(TextPainter tp) {
      canvas.save();
      canvas.translate(startX, top);
      canvas.scale(sx, sy);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    if (stroke != null) paint(stroke);
    paint(fill);
    if (highlight == null || reveal == null) return;
    final width = _revealWidth(fill, text, reveal);
    if (width <= 0) return;
    final lit = layer(highlight, shadows: strokeW <= 0.5 && shadowed);
    canvas.save();
    canvas.translate(startX, top);
    canvas.scale(sx, sy);
    canvas.clipRect(Rect.fromLTWH(0, 0, width, lit.height));
    lit.paint(canvas, Offset.zero);
    canvas.restore();
  }

  /// 已唱宽度：用排版后的光标位置换算，处理字距时不会被估算拉开。
  double _revealWidth(TextPainter tp, String text, ({int before, int length, double p}) reveal) {
    final total = text.length;
    final before = reveal.before.clamp(0, total);
    final length = reveal.length.clamp(0, total - before);
    final x0 = tp.getOffsetForCaret(TextPosition(offset: before), Rect.zero).dx;
    final x1 = length > 0
        ? tp.getOffsetForCaret(TextPosition(offset: before + length), Rect.zero).dx
        : x0;
    return x0 + (x1 - x0) * reveal.p.clamp(0.0, 1.0);
  }

  /// 当前句唱到哪：已完成的字数 + 当前字内的进度；整句唱完返回满宽。
  ({int before, int length, double p}) _revealOf(LyricRow row) {
    final ms = positionMs + style.offsetMs;
    var before = 0;
    for (final word in row.words) {
      if (ms < word.startMs) return (before: before, length: 0, p: 0);
      if (ms < word.endMs && word.endMs > word.startMs) {
        return (
          before: before,
          length: word.text.length,
          p: (ms - word.startMs) / (word.endMs - word.startMs),
        );
      }
      before += word.text.length;
    }
    return (before: before, length: 0, p: 1);
  }

  double _leftFor(double width, double pad, double avail) => switch (style.align) {
        CastAlign.left => pad,
        CastAlign.center => pad + (avail - width) / 2,
        CastAlign.right => pad + avail - width,
      };

  /// 附加信息（歌名/歌手）放不下就等比缩字号；歌词行不缩，超宽靠横向滚动。
  /// 横向拉伸后按拉伸后的宽度判断，缩完的字号仍要再乘 [sx] 才落进可用宽度。
  double _fitFontSize(String text, double fontSize, int weight, double avail, double sx) {
    if (fontSize <= 0 || avail <= 0) return math.max(1, fontSize);
    final probe = _painter(text, fontSize, weight, const Color(0xFF000000))..layout();
    final width = probe.width * sx;
    if (width <= avail) return fontSize;
    return math.max(1, fontSize * avail / width);
  }

  TextPainter _painter(String text, double size, int weight, Color? color,
      {Paint? foreground, bool shadows = false, double shadowOpacity = 1}) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: style.fontFamily,
            fontSize: size,
            fontWeight: FontWeight(weight),
            color: color,
            foreground: foreground,
            letterSpacing: size * .01,
            height: 1.2,
            shadows: shadows
                ? [
                    Shadow(
                      color: Color.fromARGB((0xB3 * shadowOpacity).round(), 0, 0, 0),
                      blurRadius: 10 * scale,
                      offset: Offset(0, 3 * scale),
                    ),
                  ]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );

  @override
  bool shouldRepaint(_LyricPainter old) =>
      old.style != style ||
      old.box != box ||
      old.meta != meta ||
      old.positionMs != positionMs ||
      old.durationMs != durationMs ||
      old.centered != centered ||
      !identical(old.rows, rows);
}
