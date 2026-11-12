import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../state/cast_settings.dart';
import '../theme.dart';
import 'form_bits.dart';

/// 屏幕管理里共用的小件：颜色选择、字型清单、投放区缩略图。

String castHex(int argb) {
  final a = (argb >> 24) & 0xFF;
  final body = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  return a == 0xFF ? '#$body' : '#${a.toRadixString(16).padLeft(2, '0').toUpperCase()}$body';
}

Color castColor(int argb) => Color(argb);

/// 字体下拉：前六个是 Windows 自带、KTV 机器上一定有的系统字体；
/// AlibabaPuHuiTi 是随包分发的普惠体 3.0（pubspec fonts + 投放页 @font-face），
/// 不依赖客户机器是否安装，Flutter 自绘回退与 CEF 网页用的是同一份字体文件。
Map<String, String> castFontChoices(AppL10n txt) => {
      'AlibabaPuHuiTi': 'Alibaba PuHuiTi 3.0',
      'Microsoft YaHei': txt.castFontYaHei,
      'SimHei': txt.castFontHei,
      'SimSun': txt.castFontSong,
      'KaiTi': txt.castFontKai,
      'DengXian': txt.castFontDeng,
      'Arial': 'Arial',
    };

String castAlignLabel(AppL10n txt, CastAlign a) => switch (a) {
      CastAlign.left => txt.castAlignLeft,
      CastAlign.center => txt.castAlignCenter,
      CastAlign.right => txt.castAlignRight,
    };

/// 颜色选择：仓库里没有取色插件，用一个「十六进制 + 常用色」的小弹窗，
/// 绿幕色 #00B140 直接放在快捷里，方便接 OBS 色度键。
Future<int?> showCastColorPicker(BuildContext context, int initial) => showDialog<int>(
      context: context,
      builder: (_) => _CastColorDialog(initial: initial),
    );

class _CastColorDialog extends StatefulWidget {
  const _CastColorDialog({required this.initial});
  final int initial;

  @override
  State<_CastColorDialog> createState() => _CastColorDialogState();
}

class _CastColorDialogState extends State<_CastColorDialog> {
  static const _quick = <int>[
    0xFFFFFFFF,
    0xFF3DDC84,
    0xFF8B979F,
    0xFFFFD54F,
    0xFF4AA8FF,
    0xFFF2555A,
    0xFFFF64C8,
    0xFF00E5FF,
    0xFF00B140,
    0xFF000000,
  ];

  late final TextEditingController _input;
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _input = TextEditingController(text: castHex(widget.initial));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool _apply(String text) {
    final t = text.trim().replaceFirst('#', '');
    final parsed = int.tryParse(t, radix: 16);
    if (parsed == null) return false;
    final argb = t.length == 6 ? 0xFF000000 | parsed : parsed;
    setState(() => _value = argb);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final txt = AppL10n.of(context);
    return AlertDialog(
      backgroundColor: C.panel,
      title: Text(txt.castPickColor, style: kCardTitle),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(_value),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: C.line),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: FormInput(controller: _input, onChanged: _apply)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final q in _quick)
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  onTap: () {
                    setState(() => _value = q);
                    _input.text = castHex(q);
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(q),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: q == _value ? C.acc : C.line, width: q == _value ? 2 : 1),
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Text(txt.castColorHint, style: kMini),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(txt.cancel, style: TextStyle(color: C.dim))),
        FilledButton(
          onPressed: () => Navigator.pop(context, _value),
          style: FilledButton.styleFrom(backgroundColor: C.acc, foregroundColor: C.onAcc),
          child: Text(txt.confirm),
        ),
      ],
    );
  }
}

// ---------------- 桌面地图：只画勾选的屏，框内拖动 / 八向把手 / 空白处重新框选 ----------------

/// region 是该屏工作区内的像素矩形，原点在该屏工作区左上角。
class CastMapItem {
  const CastMapItem({required this.monitor, required this.mode, required this.region});
  final CastMonitor monitor;
  final CastMode mode;
  final Rect region;

  Rect get regionVirtual => region.translate(monitor.workOrigin.dx, monitor.workOrigin.dy);
}

enum _DragKind { none, move, resize, draw }

/// 设置页在滚动视图里，普通 pan 会和外层竖向滚动抢识别器：往上拖改区域时，
/// 页面反而被带着滚。按下就直接认领这场竞技——按在地图上的手势只属于地图。
class _EagerPan extends PanGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerDownEvent) resolve(GestureDisposition.accepted);
  }
}

/// 虚拟桌面等比缩略图。逻辑像素与地图像素之间只有一个比例 k，
/// 所有拖动先换算回「该屏工作区 px」再写进设置，地图自己不留任何几何状态。
class CastDesktopMap extends StatefulWidget {
  const CastDesktopMap({
    super.key,
    required this.items,
    required this.editingId,
    required this.onSelect,
    required this.onRegion,
    required this.onCommit,
  });

  final List<CastMapItem> items;
  final String? editingId;
  final ValueChanged<String> onSelect;
  final void Function(CastMonitor monitor, Rect workPx) onRegion;
  final VoidCallback onCommit;

  @override
  State<CastDesktopMap> createState() => _CastDesktopMapState();
}

class _CastDesktopMapState extends State<CastDesktopMap> {
  static const _pad = 8.0;
  static const _maxHeight = 200.0;
  static const _handle = 16.0;
  static const _slop = 20.0;
  static const _minSide = 40.0;
  static const _edges = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];

  CastMapItem? _dragItem;
  _DragKind _kind = _DragKind.none;
  String _edge = '';
  Offset _startWork = Offset.zero;
  Rect _orig = Rect.zero;
  Offset? _hover;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final bbox = _bbox(widget.items);
      final k = math
          .min((math.max(80, c.maxWidth) - _pad * 2) / math.max(1, bbox.width),
              (_maxHeight - _pad * 2) / math.max(1, bbox.height))
          .clamp(.0002, 4.0);
      final dx = (c.maxWidth - bbox.width * k) / 2;
      final geom = _Geom(k: k, origin: bbox.topLeft, dx: dx > _pad ? dx : _pad, dy: _pad);
      return MouseRegion(
        cursor: _cursor(geom),
        onHover: (d) => setState(() => _hover = d.position),
        onExit: (_) => setState(() => _hover = null),
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {_EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
            () => _EagerPan(),
            (rec) {
              rec.onStart = (d) => _start(d.localPosition, geom);
              rec.onUpdate = (d) => _drag(d.localPosition, geom);
              rec.onEnd = (_) => _end();
            },
          )},
          child: SizedBox(
            width: c.maxWidth,
            height: bbox.height * k + _pad * 2,
            child: CustomPaint(
              painter: _MapPainter(
                items: widget.items,
                geom: geom,
                editingId: widget.editingId,
                showHandles: _editingIsRegion,
                fullscreenLabel: AppL10n.of(context).castFullscreen,
              ),
            ),
          ),
        ),
      );
    });
  }

  bool get _editingIsRegion {
    for (final i in widget.items) {
      if (i.monitor.id == widget.editingId) return i.mode == CastMode.region;
    }
    return false;
  }

  static Rect _bbox(List<CastMapItem> items) {
    var out = items.first.monitor.workRect;
    for (final i in items) {
      out = out.expandToInclude(i.monitor.workRect);
    }
    return out;
  }

  CastMapItem? _itemAt(Offset virtual) {
    for (final i in widget.items) {
      if (i.monitor.workRect.contains(virtual)) return i;
    }
    return null;
  }

  void _start(Offset local, _Geom g) {
    final v = g.toVirtual(local);
    final hit = _itemAt(v);
    _dragItem = null;
    _kind = _DragKind.none;
    _edge = '';
    if (hit == null) return;
    // 点到别的屏只把它设为「编辑中」，这一枪不带拖动，免得误改别的屏。
    if (hit.monitor.id != widget.editingId) {
      widget.onSelect(hit.monitor.id);
      return;
    }
    _dragItem = hit;
    _orig = hit.region;
    _startWork = v - hit.monitor.workOrigin;
    if (hit.mode == CastMode.fullscreen) return;
    final localRect = g.toLocal(hit.regionVirtual);
    final edge = _edgeAt(local, localRect);
    if (edge != null) {
      _kind = _DragKind.resize;
      _edge = edge;
    } else {
      _kind = localRect.contains(local) ? _DragKind.move : _DragKind.draw;
    }
  }

  void _drag(Offset local, _Geom g) {
    final item = _dragItem;
    if (item == null || _kind == _DragKind.none) return;
    final work = item.monitor.workSize;
    final now = g.toVirtual(local) - item.monitor.workOrigin;
    final delta = now - _startWork;
    final Rect next;
    switch (_kind) {
      case _DragKind.move:
        next = _orig.shift(delta);
      case _DragKind.resize:
        next = _resized(delta);
      case _DragKind.draw:
        next = Rect.fromPoints(_startWork, now);
      case _DragKind.none:
        return;
    }
    final clamped = _clampWork(next, work);
    // 缩到看不见不如不动：小于一行字的高度就没意义了。
    if (clamped.width < _minSide - 1 || clamped.height < _minSide - 1) return;
    widget.onRegion(item.monitor, clamped);
  }

  Rect _resized(Offset d) {
    var left = _orig.left, top = _orig.top, right = _orig.right, bottom = _orig.bottom;
    if (_edge.contains('w')) left = _orig.left + d.dx;
    if (_edge.contains('e')) right = _orig.right + d.dx;
    if (_edge.contains('n')) top = _orig.top + d.dy;
    if (_edge.contains('s')) bottom = _orig.bottom + d.dy;
    return Rect.fromLTRB(
      math.min(left, right - _minSide),
      math.min(top, bottom - _minSide),
      math.max(right, left + _minSide),
      math.max(bottom, top + _minSide),
    );
  }

  static Rect _clampWork(Rect r, Size work) {
    final w = math.min(r.width, work.width);
    final h = math.min(r.height, work.height);
    return Rect.fromLTWH(
      r.left.clamp(0.0, math.max(0.0, work.width - w)).toDouble(),
      r.top.clamp(0.0, math.max(0.0, work.height - h)).toDouble(),
      w,
      h,
    );
  }

  void _end() {
    if (_kind != _DragKind.none) widget.onCommit();
    _dragItem = null;
    _kind = _DragKind.none;
    _edge = '';
  }

  String? _edgeAt(Offset local, Rect r) {
    for (final e in _edges) {
      if ((local - _handlePos(r, e)).distance <= _slop) return e;
    }
    return null;
  }

  MouseCursor _cursor(_Geom g) {
    final p = _hover;
    if (p == null) return MouseCursor.defer;
    final item = _itemAt(g.toVirtual(p));
    if (item == null || item.monitor.id != widget.editingId || item.mode != CastMode.region) {
      return SystemMouseCursors.click;
    }
    final rect = g.toLocal(item.regionVirtual);
    final edge = _edgeAt(p, rect);
    if (edge != null) return _edgeCursor(edge);
    return rect.contains(p) ? SystemMouseCursors.move : SystemMouseCursors.precise;
  }

  static MouseCursor _edgeCursor(String e) => switch (e) {
        'nw' || 'se' => SystemMouseCursors.resizeUpLeftDownRight,
        'ne' || 'sw' => SystemMouseCursors.resizeUpRightDownLeft,
        'n' || 's' => SystemMouseCursors.resizeUpDown,
        _ => SystemMouseCursors.resizeLeftRight,
      };
}

Offset _handlePos(Rect r, String edge) => switch (edge) {
      'nw' => r.topLeft,
      'n' => Offset(r.center.dx, r.top),
      'ne' => r.topRight,
      'e' => Offset(r.right, r.center.dy),
      'se' => r.bottomRight,
      's' => Offset(r.center.dx, r.bottom),
      'sw' => r.bottomLeft,
      _ => Offset(r.left, r.center.dy),
    };

class _Geom {
  const _Geom({required this.k, required this.origin, required this.dx, required this.dy});
  final double k;
  final Offset origin;
  final double dx;
  final double dy;

  Offset toVirtual(Offset p) => (p - Offset(dx, dy)) / k + origin;

  Rect toLocal(Rect r) => Rect.fromLTWH(
        (r.left - origin.dx) * k + dx,
        (r.top - origin.dy) * k + dy,
        r.width * k,
        r.height * k,
      );

  @override
  bool operator ==(Object other) =>
      other is _Geom && other.k == k && other.origin == origin && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(k, origin, dx, dy);
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.items,
    required this.geom,
    required this.editingId,
    required this.showHandles,
    required this.fullscreenLabel,
  });

  final List<CastMapItem> items;
  final _Geom geom;
  final String? editingId;
  final bool showHandles;
  final String fullscreenLabel;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final rect = geom.toLocal(item.monitor.workRect);
      final editing = item.monitor.id == editingId;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = editing ? C.acc.withValues(alpha: .10) : C.panel2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = editing ? 2 : 1
          ..color = editing ? C.acc : C.line,
      );
      _label(canvas, rect, '${i + 1} · ${item.monitor.name}', top: true, editing: editing);
      _label(canvas, rect, '${item.monitor.workSize.width.round()}×${item.monitor.workSize.height.round()}',
          top: false, editing: editing);
      final region = geom.toLocal(item.regionVirtual);
      if (item.mode == CastMode.fullscreen) {
        _hint(canvas, region, fullscreenLabel);
        continue;
      }
      canvas.drawRect(region, Paint()..color = C.acc.withValues(alpha: .20));
      canvas.drawRect(region, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = C.acc);
      if (!editing || !showHandles) continue;
      for (final e in _CastDesktopMapState._edges) {
        final center = _handlePos(region, e);
        final box = Rect.fromLTWH(
            center.dx - _CastDesktopMapState._handle / 2, center.dy - _CastDesktopMapState._handle / 2,
            _CastDesktopMapState._handle, _CastDesktopMapState._handle);
        final rrect = RRect.fromRectAndRadius(box, const Radius.circular(4));
        canvas.drawRRect(rrect, Paint()..color = const Color(0xFFF2F6F8));
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = C.acc2,
        );
      }
    }
  }

  void _label(Canvas canvas, Rect r, String text, {required bool top, required bool editing}) {
    if (r.width < 78) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 10.5, height: 1.1, color: editing ? C.acc : C.faint)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (tp.width > r.width - 10) return;
    final at = top
        ? Offset(r.left + 5, r.top + 4)
        : Offset(r.right - tp.width - 5, r.bottom - tp.height - 4);
    tp.paint(canvas, at);
  }

  void _hint(Canvas canvas, Rect r, String text) {
    if (r.width < 60) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 10.5, color: C.dim)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      !identical(old.items, items) ||
      old.editingId != editingId ||
      old.geom != geom ||
      old.showHandles != showHandles ||
      old.fullscreenLabel != fullscreenLabel;
}
