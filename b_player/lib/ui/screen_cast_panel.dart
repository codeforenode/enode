import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../state/cast_settings.dart';
import '../state/lrc.dart';
import '../theme.dart';
import 'cards.dart';
import 'cast_bits.dart';
import 'cast_lyric_view.dart';
import 'form_bits.dart';
import 'image_path_picker.dart';

/// 螢幕管理：左邊選屏、中間畫布、右邊圖層與屬性。
///
/// 一次改動立刻寫進 cast.settings.v2（拖動這類高頻操作攢 250ms）；
/// 投放窗讀的是同一份，所以不需要另外按保存。
class ScreenCastPanel extends StatefulWidget {
  const ScreenCastPanel({super.key, required this.state});
  final AppState state;

  @override
  State<ScreenCastPanel> createState() => _ScreenCastPanelState();
}

class _ScreenCastPanelState extends State<ScreenCastPanel> {
  // 2026-11-05 實測：一塊 canvas 驅動多屏時額外佔約 140MB，加屏不再加瀏覽器。
  static const _mbCanvas = 145;

  late CastSettings _draft;
  late CastSettings _saved;
  String? _screenId;
  String? _placementId;
  Timer? _debounce;
  Timer? _demoTick;
  Timer? _uiTick;
  String? _error;

  final bool _demoPlaying = true;
  int _demoMs = 0;

  // 拖動/縮放中的位置只走這個 notifier：面板其餘部分不隨指針事件重建，
  // 否則每 8ms 一次的全面板 build + layout 會把「跟手」吃掉。
  final _liveDrag = ValueNotifier<_LiveDrag>(_LiveDrag.none);

  final _stageKey = GlobalKey();
  final _stageFocus = FocusNode(debugLabel: 'cast-stage');

  final _name = TextEditingController();
  final _pxX = TextEditingController();
  final _pxY = TextEditingController();
  final _pxW = TextEditingController();
  final _pxH = TextEditingController();
  final _regL = TextEditingController();
  final _regT = TextEditingController();
  final _regW = TextEditingController();
  final _regH = TextEditingController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.state.cast;
    _saved = _draft;
    _screenId = _pickScreen();
    _placementId = _pickPlacement();
    _syncAll();
    widget.state.addListener(_onApp);
    _startDemoClock();
    _uiTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_onApp);
    _debounce?.cancel();
    _demoTick?.cancel();
    _uiTick?.cancel();
    _stageFocus.dispose();
    _liveDrag.dispose();
    for (final c in [_name, _pxX, _pxY, _pxW, _pxH, _regL, _regT, _regW, _regH]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------- 狀態同步 ----------------

  void _onApp() {
    if (!mounted) return;
    // 投放屏右鍵可能在面板外面改了設置；不跟上，下一次自動保存會把關掉的屏又打開。
    final latest = widget.state.cast;
    if (!identical(latest, _saved) && !identical(latest, _draft)) {
      _debounce?.cancel();
      _draft = latest;
      _saved = latest;
      _screenId ??= _pickScreen();
      if (_placementId != null && _draft.placementById(_placementId!) == null) _placementId = null;
      _syncAll();
    }
    if (_live && _demoTick != null) _demoTick!.cancel();
    setState(() {});
  }

  List<CastMonitor> get _monitors => widget.state.castMonitors;

  CastMonitor? get _mon {
    for (final m in _monitors) {
      if (m.id == _screenId) return m;
    }
    return _monitors.isEmpty ? null : _monitors.first;
  }

  CastTarget get _target {
    final m = _mon;
    return m == null ? const CastTarget(monitorId: '', name: '') : _draft.targetFor(m.id);
  }

  CastPlacement? get _sel {
    final id = _placementId;
    return id == null ? null : _draft.placementById(id);
  }

  CastMaterial? get _selMat {
    final p = _sel;
    return p == null ? null : _draft.materialById(p.materialId);
  }

  String? _pickScreen() {
    for (final m in _monitors) {
      if (_draft.targetFor(m.id).enabled) return m.id;
    }
    return _monitors.isEmpty ? null : _monitors.first.id;
  }

  String? _pickPlacement() {
    final s = _screenId;
    if (s == null) return null;
    final list = _draft.placementsOn(s);
    return list.isEmpty ? null : list.last.id;
  }

  void _persistSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _persistNow);
  }

  Future<void> _persistNow() async {
    try {
      await widget.state.saveCast(_draft);
      _saved = widget.state.cast;
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = l10n.saveFailed('$e'));
    }
  }

  Future<void> _rescan() async {
    _debounce?.cancel();
    await _persistNow();
    await widget.state.rescanCastMonitors();
    if (!mounted) return;
    setState(() {
      _draft = widget.state.cast;
      _saved = _draft;
      _screenId = _pickScreen();
      _placementId = _pickPlacement();
      _error = _monitors.isEmpty ? l10n.castNoMonitorsFound : null;
    });
    _syncAll();
  }

  void _edit(CastSettings Function(CastSettings) change, {bool persist = true}) {
    setState(() => _draft = change(_draft));
    if (persist) _persistSoon();
  }

  void _editMaterial(String id, CastMaterial Function(CastMaterial) change) {
    final m = _draft.materialById(id);
    if (m == null) return;
    _edit((s) => s.withMaterial(change(m)));
  }

  void _editPlacement(String id, CastPlacement Function(CastPlacement) change, {bool persist = true}) {
    final p = _draft.placementById(id);
    if (p == null) return;
    _edit((s) => s.withPlacement(change(p)), persist: persist);
  }

  void _select(String? placementId) {
    setState(() => _placementId = placementId);
    _syncAll();
    if (placementId != null) _stageFocus.requestFocus();
  }

  void _selectScreen(String id) {
    setState(() {
      _screenId = id;
      _placementId = null;
    });
    _syncAll();
  }

  void _syncAll() {
    _syncGeoFields();
    _syncRegionFields();
    final m = _selMat;
    _syncing = true;
    _name.text = m?.name ?? '';
    _syncing = false;
  }

  Size get _design => _mon == null ? const Size(1920, 1080) : castDesignSize(_mon!, _target);

  void _syncGeoFields() {
    final p = _sel;
    final design = _design;
    _syncing = true;
    if (p == null) {
      for (final c in [_pxX, _pxY, _pxW, _pxH]) {
        c.text = '';
      }
    } else {
      _pxX.text = (p.x * design.width).round().toString();
      _pxY.text = (p.y * design.height).round().toString();
      _pxW.text = (p.width * design.width).round().toString();
      _pxH.text = (p.height * design.height).round().toString();
    }
    _syncing = false;
  }

  void _syncRegionFields() {
    final m = _mon;
    if (m == null) return;
    final r = _regionInWork(m);
    _syncing = true;
    _regL.text = r.left.round().toString();
    _regT.text = r.top.round().toString();
    _regW.text = r.width.round().toString();
    _regH.text = r.height.round().toString();
    _syncing = false;
  }

  // ---------------- 預覽時鐘 ----------------

  bool get _live => widget.state.lyricLines.isNotEmpty && widget.state.nowPlaying != null;

  void _startDemoClock() {
    _demoTick?.cancel();
    if (_live || !_demoPlaying) return;
    _demoTick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _demoMs = (_demoMs + 200) % _demoDuration);
    });
  }

  static const _demoDuration = 44000;
  static final List<LyricLine> _demoLyric = _buildDemoLyric();

  static List<LyricLine> _buildDemoLyric() {
    const texts = [
      '夜色落在酒杯上',
      '你把旋律调到很低',
      '走廊尽头有人点了一首老歌',
      '我们没有说话',
      '只是把杯子举起来',
      '晚风不歇 吹过整个城市',
      '每一盏灯都认识你的影子',
      '如果明天还要赶路',
      '今晚就允许我停顿一次',
      '空瓶替我数着时间',
      '唱完这首就回家',
    ];
    const span = 4000;
    return [
      for (var i = 0; i < texts.length; i++)
        (
          startMs: i * span,
          endMs: (i + 1) * span,
          text: texts[i],
          words: _demoWords(texts[i], i * span, span),
        ),
    ];
  }

  /// 预演也走逐字：没有真歌词时用等分时间模拟扫光效果。
  static List<LyricWord> _demoWords(String text, int startMs, int spanMs) {
    final chars = text.split('');
    if (chars.isEmpty) return const [];
    final each = spanMs ~/ chars.length;
    return [
      for (var i = 0; i < chars.length; i++)
        (
          startMs: startMs + i * each,
          endMs: startMs + (i + 1) * each,
          text: chars[i],
        ),
    ];
  }

  int get _positionMs => _live ? (widget.state.nowPlaying?.positionMs ?? 0) : _demoMs;

  List<LyricLine> get _lyricSource => _live ? widget.state.lyricLines : _demoLyric;

  int get _durationMs => _live ? (widget.state.nowPlaying?.durationMs ?? 0) : _demoDuration;

  String _lyricMeta(AppL10n t, CastStyle style) {
    final np = widget.state.nowPlaying;
    return [
      if (style.showTitle) _live ? (np?.title ?? '') : t.castDemoTitle,
      if (style.showArtist) _live ? (np?.artist ?? '') : t.castDemoArtist,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
  }

  // ---------------- 素材操作 ----------------

  String _typeLabel(AppL10n t, CastMaterialType type) => switch (type) {
        CastMaterialType.lyric => t.screenTypeLyric,
        CastMaterialType.url => t.screenTypeUrl,
        CastMaterialType.image => t.screenTypeImage,
        CastMaterialType.video => t.screenTypeVideo,
        CastMaterialType.text => t.screenTypeText,
      };

  String _typeDesc(AppL10n t, CastMaterialType type) => switch (type) {
        CastMaterialType.lyric => t.screenTypeLyricDesc,
        CastMaterialType.url => t.screenTypeUrlDesc,
        CastMaterialType.image => t.screenTypeImageDesc,
        CastMaterialType.video => t.screenTypeVideoDesc,
        CastMaterialType.text => t.screenTypeTextDesc,
      };

  String _typeTag(AppL10n t, CastMaterialType type) => switch (type) {
        CastMaterialType.lyric || CastMaterialType.text => t.screenTagLight,
        CastMaterialType.url || CastMaterialType.video => t.screenTagHeavy,
        CastMaterialType.image => t.screenTagNormal,
      };

  IconData _typeIcon(CastMaterialType type) => switch (type) {
        CastMaterialType.lyric => Icons.lyrics_rounded,
        CastMaterialType.url => Icons.public_rounded,
        CastMaterialType.image => Icons.image_outlined,
        CastMaterialType.video => Icons.movie_outlined,
        CastMaterialType.text => Icons.title_rounded,
      };

  Color _typeColor(CastMaterialType type) {
    final light = Theme.of(context).brightness == Brightness.light;
    return switch (type) {
      CastMaterialType.lyric => C.acc,
      CastMaterialType.url => light ? const Color(0xFF7C4DDB) : const Color(0xFFA78BFA),
      CastMaterialType.image => C.info,
      CastMaterialType.video => C.warn,
      CastMaterialType.text => light ? const Color(0xFFC04C8A) : const Color(0xFFF0A6CA),
    };
  }

  String _materialName(AppL10n t, CastMaterial m) => m.name.trim().isEmpty ? _typeLabel(t, m.type) : m.name;

  String _uniqueName(AppL10n t, CastMaterialType type) {
    final base = _typeLabel(t, type);
    if (!_draft.materials.any((m) => m.name == base)) return base;
    var n = 2;
    while (_draft.materials.any((m) => m.name == '$base $n')) {
      n++;
    }
    return '$base $n';
  }

  ({double x, double y, double w, double h}) _defaultGeo(CastMaterialType type) => switch (type) {
        CastMaterialType.lyric => (x: .25, y: .6, w: .5, h: .3),
        CastMaterialType.url => (x: .1, y: .2, w: .8, h: .5),
        CastMaterialType.image => (x: .3, y: .3, w: .4, h: .3),
        CastMaterialType.video => (x: .3, y: .3, w: .4, h: .3),
        CastMaterialType.text => (x: .2, y: .4, w: .6, h: .15),
      };

  CastMaterial _newMaterial(CastMaterialType type, String name) => switch (type) {
        CastMaterialType.lyric => CastMaterial(id: newCastId('m'), type: type, name: name),
        CastMaterialType.url =>
          CastMaterial(id: newCastId('m'), type: type, name: name, url: 'https://'),
        CastMaterialType.image => CastMaterial(
            id: newCastId('m'), type: type, name: name, fit: CastFit.cover),
        CastMaterialType.video => CastMaterial(
            id: newCastId('m'), type: type, name: name, fit: CastFit.cover, loop: true, autoplay: true),
        CastMaterialType.text => CastMaterial(id: newCastId('m'), type: type, name: name, text: ''),
      };

  void _addMaterial(CastMaterialType type, {Offset? at}) {
    final mon = _mon;
    if (mon == null) return;
    final t = AppL10n.of(context);
    final material = _newMaterial(type, _uniqueName(t, type));
    final geo = _defaultGeo(type);
    var x = geo.x;
    var y = geo.y;
    if (at != null) {
      x = (at.dx - geo.w / 2).clamp(0.0, 1 - geo.w).toDouble();
      y = (at.dy - geo.h / 2).clamp(0.0, 1 - geo.h).toDouble();
    }
    var next = _draft.withMaterial(material);
    final placement = CastPlacement(
      id: newCastId('p'),
      materialId: material.id,
      screenId: mon.id,
      x: x,
      y: y,
      width: geo.w,
      height: geo.h,
      z: next.nextZ(mon.id),
    );
    next = next.withPlacement(placement);
    setState(() {
      _draft = next;
      _placementId = placement.id;
    });
    _syncAll();
    _persistSoon();
  }

  void _placeMaterial(CastMaterial material, {Offset? at}) {
    final mon = _mon;
    if (mon == null) return;
    CastPlacement? existing;
    for (final p in _draft.placementsOn(mon.id)) {
      if (p.materialId == material.id) {
        existing = p;
        break;
      }
    }
    if (existing != null && at == null) {
      _select(existing.id);
      return;
    }
    final geo = _defaultGeo(material.type);
    var x = geo.x;
    var y = geo.y;
    if (at != null) {
      x = (at.dx - geo.w / 2).clamp(0.0, 1 - geo.w).toDouble();
      y = (at.dy - geo.h / 2).clamp(0.0, 1 - geo.h).toDouble();
    }
    final placement = CastPlacement(
      id: newCastId('p'),
      materialId: material.id,
      screenId: mon.id,
      x: x,
      y: y,
      width: geo.w,
      height: geo.h,
      z: _draft.nextZ(mon.id),
    );
    setState(() {
      _draft = _draft.withPlacement(placement);
      _placementId = placement.id;
    });
    _syncAll();
    _persistSoon();
  }

  void _deletePlacement(CastPlacement p) {
    setState(() {
      _draft = _draft.withoutPlacement(p.id);
      if (_placementId == p.id) _placementId = null;
    });
    _syncAll();
    _persistSoon();
  }

  /// 只清没投到任何屏的素材；还在用的先让它保持可拖，避免误删正在投放的内容。
  void _removeMaterial(CastMaterial m) {
    setState(() => _draft = _draft.withoutMaterial(m.id));
    _syncAll();
    _persistSoon();
  }

  void _duplicatePlacement(CastPlacement p) {
    final before = {for (final m in _draft.materials) m.id};
    var next = _draft.duplicateMaterial(p.materialId);
    String? created;
    for (final q in next.placementsOn(p.screenId)) {
      if (!before.contains(q.materialId)) created = q.id;
    }
    setState(() {
      _draft = next;
      _placementId = created ?? _placementId;
    });
    _syncAll();
    _persistSoon();
  }

  void _setSound(CastPlacement p, bool on) {
    var next = _draft;
    if (on) {
      // 同一屏只保留一路有聲，否則影片會疊在一起。
      for (final q in _draft.placementsOn(p.screenId)) {
        if (q.id != p.id && q.sound) next = next.withPlacement(q.copyWith(sound: false));
      }
    }
    next = next.withPlacement(p.copyWith(sound: on));
    setState(() => _draft = next);
    _persistSoon();
  }

  void _toggleOnScreen(CastMaterial m, String screenId, bool on) {
    final mon = _mon;
    if (on) {
      final r = _defaultGeo(m.type);
      _edit((s) => s.withPlacement(CastPlacement(
            id: newCastId('p'),
            materialId: m.id,
            screenId: screenId,
            x: r.x,
            y: r.y,
            width: r.w,
            height: r.h,
            z: s.nextZ(screenId),
          )));
      return;
    }
    CastPlacement? target;
    for (final p in _draft.placementsOn(screenId)) {
      if (p.materialId == m.id) {
        target = p;
        break;
      }
    }
    if (target == null) return;
    final id = target.id;
    if (mon?.id == screenId && _placementId == id) _placementId = null;
    _edit((s) => s.withoutPlacement(id));
    _syncAll();
  }

  // ---------------- 幾何 ----------------

  void _moveBy(CastPlacement p, Offset delta, Size stage) {
    final cur = _dragBase(p);
    if (cur == null || cur.locked) return;
    final x = (cur.x + delta.dx / stage.width).clamp(0.0, 1 - cur.width).toDouble();
    final y = (cur.y + delta.dy / stage.height).clamp(0.0, 1 - cur.height).toDouble();
    _liveDrag.value = _LiveDrag(placement: cur.copyWith(x: x, y: y));
  }

  /// 指針事件要接著上一次的結果算，不能回讀 _draft（拖動期間它不動）。
  CastPlacement? _dragBase(CastPlacement p) {
    final live = _liveDrag.value.placement;
    if (live != null && live.id == p.id) return live;
    return _draft.placementById(p.id);
  }

  void _resizeBy(CastPlacement p, String edge, Offset delta, Size stage) {
    final cur = _dragBase(p);
    if (cur == null || cur.locked) return;
    var left = cur.x, top = cur.y, right = cur.x + cur.width, bottom = cur.y + cur.height;
    final dx = delta.dx / stage.width;
    final dy = delta.dy / stage.height;
    if (edge.contains('w')) left += dx;
    if (edge.contains('e')) right += dx;
    if (edge.contains('n')) top += dy;
    if (edge.contains('s')) bottom += dy;
    left = left.clamp(0.0, 1.0);
    right = right.clamp(0.0, 1.0);
    top = top.clamp(0.0, 1.0);
    bottom = bottom.clamp(0.0, 1.0);
    const minSide = .015;
    if (right - left < minSide) {
      if (edge.contains('w')) {
        left = right - minSide;
      } else {
        right = left + minSide;
      }
    }
    if (bottom - top < minSide) {
      if (edge.contains('n')) {
        top = bottom - minSide;
      } else {
        bottom = top + minSide;
      }
    }
    final next =
        cur.copyWith(x: left, y: top, width: right - left, height: bottom - top);
    _liveDrag.value = _LiveDrag(placement: next);
  }

  void _endDrag() {
    final live = _liveDrag.value.placement;
    final changed = live != null && _draft.placementById(live.id) != live;
    _liveDrag.value = _LiveDrag.none;
    if (changed) setState(() => _draft = _draft.withPlacement(live));
    _syncGeoFields();
    // 拖拽期间不动磁盘，松手才保存一次。
    if (changed) _persistSoon();
  }

  void _setGeoField(CastPlacement p, String key, String raw) {
    if (_syncing) return;
    final v = double.tryParse(raw.trim());
    if (v == null) return;
    final design = _design;
    var x = p.x, y = p.y, w = p.width, h = p.height;
    switch (key) {
      case 'x':
        x = (v / design.width).clamp(0.0, 1 - w).toDouble();
      case 'y':
        y = (v / design.height).clamp(0.0, 1 - h).toDouble();
      case 'w':
        w = (v / design.width).clamp(.015, 1 - x).toDouble();
      case 'h':
        h = (v / design.height).clamp(.015, 1 - y).toDouble();
    }
    _editPlacement(p.id, (q) => q.copyWith(x: x, y: y, width: w, height: h));
  }

  void _z(CastPlacement p, String dir) {
    final next = switch (dir) {
      'top' => _draft.placementToFront(p.id),
      'bottom' => _draft.placementToBack(p.id),
      'up' => _draft.movePlacement(p.id, 1),
      _ => _draft.movePlacement(p.id, -1),
    };
    setState(() => _draft = next);
    _persistSoon();
  }

  // ---------------- 區域 ----------------

  Rect _regionInWork(CastMonitor m) {
    final t = _draft.targetFor(m.id);
    return t.mode == CastMode.fullscreen ? (Offset.zero & m.workSize) : t.region.toRect(m.workSize);
  }

  void _setMode(CastMonitor m, CastMode mode) {
    var next = _draft.withMode(m.id, mode);
    if (mode == CastMode.region && next.targetFor(m.id).region == CastRegion.full) {
      next = next.withRegion(m.id, m.name, CastRegion.bottomStrip);
    }
    setState(() => _draft = next);
    _syncRegionFields();
    _persistSoon();
  }

  void _setRegion(CastMonitor m, Rect workPx) {
    final r = Rect.fromLTWH(
      workPx.left,
      workPx.top,
      math.max(40, workPx.width),
      math.max(40, workPx.height),
    );
    setState(() => _draft = _draft.withRegion(m.id, m.name, CastRegion.fromRect(m.workSize, r)));
    _persistSoon();
  }

  void _usePreset(CastMonitor m, CastRegion region, bool fullscreen) {
    var next = _draft.withMode(m.id, fullscreen ? CastMode.fullscreen : CastMode.region);
    if (!fullscreen) next = next.withRegion(m.id, m.name, region);
    setState(() => _draft = next);
    _syncRegionFields();
    _persistSoon();
  }

  void _applyRegionField(CastMonitor m, String key, String raw) {
    if (_syncing) return;
    final v = double.tryParse(raw.trim());
    if (v == null) return;
    final r = _regionInWork(m);
    final next = switch (key) {
      'l' => Rect.fromLTWH(v, r.top, r.width, r.height),
      't' => Rect.fromLTWH(r.left, v, r.width, r.height),
      'w' => Rect.fromLTWH(r.left, r.top, math.max(40, v), r.height),
      _ => Rect.fromLTWH(r.left, r.top, r.width, math.max(40, v)),
    };
    _setRegion(m, _clampToWork(next, m.workSize));
  }

  static Rect _clampToWork(Rect r, Size work) {
    final w = math.min(r.width, work.width);
    final h = math.min(r.height, work.height);
    final left = r.left.clamp(0.0, math.max(0.0, work.width - w)).toDouble();
    final top = r.top.clamp(0.0, math.max(0.0, work.height - h)).toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }

  void _nudge(CastMonitor m, String dir) {
    const step = 10.0;
    final region = _draft.targetFor(m.id).region;
    final rect = region.toRect(m.workSize);
    final moved = switch (dir) {
      'l' => rect.shift(const Offset(-step, 0)),
      'r' => rect.shift(const Offset(step, 0)),
      't' => rect.shift(const Offset(0, -step)),
      'd' => rect.shift(const Offset(0, step)),
      'cx' => Rect.fromLTWH((m.workSize.width - rect.width) / 2, rect.top, rect.width, rect.height),
      _ => Rect.fromLTWH(rect.left, (m.workSize.height - rect.height) / 2, rect.width, rect.height),
    };
    _setRegion(m, _clampToWork(moved, m.workSize));
    _syncRegionFields();
  }

  // ---------------- 畫面 ----------------

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final mon = _mon;
    if (mon == null) {
      return Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.castNoMonitors, style: TextStyle(fontSize: 12.5, color: C.dim)),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: _ghost(t.rescan, _rescan)),
        ]),
      );
    }
    if (_placementId != null && _sel == null) _placementId = null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(t),
      const SizedBox(height: 10),
      Expanded(child: _body(t, mon)),
      if (_error != null || widget.state.castWindowsError != null) ...[
        const SizedBox(height: 8),
        Text(_error ?? widget.state.castWindowsError!,
            style: TextStyle(fontSize: 11.5, color: C.bad)),
      ],
    ]);
  }

  Widget _header(AppL10n t) {
    final enabled = _draft.targets.where((e) => e.enabled).length;
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.castTitle, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.txt)),
          const SizedBox(height: 3),
          Text(
            t.screenSummary(_monitors.length, _draft.materials.length, _draft.placements.length),
            style: TextStyle(fontSize: 11, color: C.faint),
          ),
        ]),
      ),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Dot(on: _draft.enabled),
        const SizedBox(width: 6),
        Text(_draft.enabled ? t.screenLiveSync : t.screenEditOnly,
            style: TextStyle(fontSize: 11, color: _draft.enabled ? C.acc : C.faint)),
        const SizedBox(width: 10),
        Text(t.screenCastingValue(enabled, _monitors.length),
            style: kNums.copyWith(fontSize: 11, color: C.dim)),
      ]),
    ]);
  }

  Widget _body(AppL10n t, CastMonitor mon) => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 1080;
        final mid = c.maxWidth >= 860;
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 206, child: _screensPane(t)),
            const SizedBox(width: 10),
            Expanded(child: _centerPane(t, mon)),
            const SizedBox(width: 10),
            SizedBox(width: 306, child: _rightPane(t, mon)),
          ]);
        }
        if (mid) {
          return Column(children: [
            SizedBox(height: 186, child: _screenStrip(t)),
            const SizedBox(height: 8),
            Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _centerPane(t, mon)),
              const SizedBox(width: 10),
              SizedBox(width: 296, child: _rightPane(t, mon)),
            ])),
          ]);
        }
        return SingleChildScrollView(
          child: Column(children: [
            _centerPane(t, mon, scroll: false),
            const SizedBox(height: 10),
            SizedBox(height: 190, child: _screenStrip(t)),
            const SizedBox(height: 10),
            _rightPane(t, mon, scroll: false),
          ]),
        );
      });

  // ---------------- 左欄：螢幕 ----------------

  Widget _screensPane(AppL10n t) => SingleChildScrollView(
        child: Column(children: [
          _panel(
            title: t.screenScreens,
            count: t.screenCount(_monitors.length),
            child: Column(children: [
              for (var i = 0; i < _monitors.length; i++) _screenCard(t, _monitors[i], i + 1),
              Text(t.screenScreenHint, style: kMini),
            ]),
          ),
          const SizedBox(height: 10),
          _panel(title: t.screenStatus, child: _statusGrid(t)),
          const SizedBox(height: 10),
          _panel(
            title: t.screenDetect,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ghost(t.rescan, _rescan),
              const SizedBox(height: 7),
              Text(t.screenRescanHint(_monitors.length), style: kMini),
            ]),
          ),
        ]),
      );

  Widget _screenStrip(AppL10n t) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < _monitors.length; i++)
            SizedBox(width: 190, child: _screenCard(t, _monitors[i], i + 1)),
          SizedBox(
            width: 150,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _ghost(t.rescan, _rescan),
              const SizedBox(height: 6),
              Text('${_monitors.length} · ${_draft.placements.length}', style: kMini),
            ]),
          ),
        ]),
      );

  Widget _panel({required String title, String? count, String? trailing, Widget? action, required Widget child}) => Panel(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title, style: kCardTitle),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(count, style: TextStyle(fontSize: 10.5, color: C.faint)),
            ],
            const Spacer(),
            if (trailing != null)
              Flexible(
                child: Text(trailing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 9.5, color: C.faint)),
              ),
            if (action != null) ...[const SizedBox(width: 4), action],
          ]),
          const SizedBox(height: 9),
          child,
        ]),
      );

  Widget _screenCard(AppL10n t, CastMonitor m, int index) {
    final target = _draft.targetFor(m.id);
    final editing = m.id == _mon?.id;
    final placements = _draft.placementsOn(m.id);
    final urls = placements.where((p) => _draft.materialById(p.materialId)?.type == CastMaterialType.url).length;
    final videos = placements.where((p) => _draft.materialById(p.materialId)?.type == CastMaterialType.video).length;
    final load = _loadLabel(t, placements.length, urls, videos);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: editing ? C.acc.withValues(alpha: .10) : C.panel2,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: () => _selectScreen(m.id),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: editing ? C.acc : C.line, width: editing ? 1.4 : 1),
            ),
            child: Opacity(
              opacity: target.enabled ? 1 : .55,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 19,
                    height: 19,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: target.enabled ? C.acc : C.panel,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: target.enabled ? C.acc : C.line),
                    ),
                    child: Text('$index',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: target.enabled ? C.onAcc : C.dim)),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.txt)),
                      Text(
                        '${m.fullSize.width.round()}×${m.fullSize.height.round()} · ${(m.scale * 100).round()}% · '
                        '${target.mode == CastMode.fullscreen ? t.screenFull : t.screenWork}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kNums.copyWith(fontSize: 9.8, color: C.faint),
                      ),
                    ]),
                  ),
                  Transform.scale(
                    scale: .72,
                    child: Switch(
                      value: target.enabled,
                      activeThumbColor: C.acc,
                      onChanged: (v) => _edit((s) => s.toggled(m.id, m.name, v)),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(fit: StackFit.expand, children: [
                      if ((target.backgroundColor >>> 24) == 0)
                        CustomPaint(painter: const _CheckerPainter(cell: 8)),
                      Container(
                        color: Color(target.backgroundColor),
                        child: LayoutBuilder(builder: (context, tc) {
                          final w = tc.maxWidth;
                          final h = tc.maxHeight;
                          return Stack(children: [
                            for (final p in placements)
                              if (p.visible)
                                Positioned(
                                  left: p.x * w,
                                  top: p.y * h,
                                  width: math.max(1, p.width * w),
                                  height: math.max(1, p.height * h),
                                  child: ColoredBox(
                                    color: _typeColor(_draft.materialById(p.materialId)?.type ??
                                            CastMaterialType.lyric)
                                        .withValues(alpha: .8),
                                  ),
                                ),
                          ]);
                        }),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  // 窄卡（206px 左欄）放不下「圖層 + 網頁 + 影片」時要換行，不能撐爆。
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(t.screenLayersCount(placements.length),
                            style: TextStyle(fontSize: 9.6, color: C.faint)),
                        if (urls > 0) _miniChip(t.screenUrlBadge(urls), C.info),
                        if (videos > 0) _miniChip(t.screenVideoBadge(videos), C.warn),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  _miniChip(load.label, load.color),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  ({String label, Color color}) _loadLabel(AppL10n t, int layers, int urls, int videos) {
    final score = layers + urls * 2 + videos * 2;
    if (score <= 4) return (label: t.screenLoadLight, color: C.dim);
    if (score <= 7) return (label: t.screenLoadMid, color: C.warn);
    return (label: t.screenLoadHeavy, color: C.bad);
  }

  Widget _miniChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label, style: TextStyle(fontSize: 9, color: color)),
      );

  Widget _statusGrid(AppL10n t) {
    final on = _draft.targets.where((e) => e.enabled).length;
    Widget cell(String label, String value) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: BoxDecoration(
            color: C.panel2,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 9.5, color: C.faint)),
            const SizedBox(height: 1),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kNums.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: C.txt)),
          ]),
        );
    return Column(children: [
      Row(children: [
        Expanded(child: cell(t.screenCastingScreens, '${_draft.enabled ? on : 0} / ${_monitors.length}')),
        const SizedBox(width: 7),
        Expanded(child: cell(t.screenSharedCanvas, '≈ $_mbCanvas MB')),
      ]),
      const SizedBox(height: 7),
      Row(children: [
        Expanded(child: cell(t.castSync, t.castSyncValue)),
        const SizedBox(width: 7),
        Expanded(child: cell(t.screenMaterials, t.screenMaterialsValue(_draft.materials.length))),
      ]),
      const SizedBox(height: 7),
      Text(_draft.enabled ? t.screenStatusHintOn : t.screenStatusHintOff, style: kMini),
    ]);
  }

  // ---------------- 中欄：工具列 + 畫布 + 素材庫 ----------------

  Widget _centerPane(AppL10n t, CastMonitor mon, {bool scroll = true}) {
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _toolbar(t, mon),
      if (_warning(t, mon) != null) ...[
        const SizedBox(height: 8),
        _warning(t, mon)!,
      ],
      const SizedBox(height: 8),
      _stageCard(t, mon),
      const SizedBox(height: 10),
      _shelf(t, mon),
    ]);
    return scroll ? SingleChildScrollView(child: content) : content;
  }

  /// 新增素材的类型菜单：工具列用大按钮，图层面板标题用紧凑按钮，菜单本体共用一份。
  Widget _addMaterialMenu(AppL10n t, Widget Function(VoidCallback toggle) builder) => MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(C.panel),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: C.line),
            ),
          ),
        ),
        menuChildren: [
          for (final type in CastMaterialType.values)
            MenuItemButton(
              onPressed: () => _addMaterial(type),
              child: SizedBox(
                width: 320,
                child: Row(children: [
                  Icon(_typeIcon(type), size: 15, color: _typeColor(type)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_typeLabel(t, type),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.txt)),
                      Text(_typeDesc(t, type), style: TextStyle(fontSize: 10.5, color: C.faint)),
                    ]),
                  ),
                  _miniChip(_typeTag(t, type), _typeTag(t, type) == t.screenTagHeavy ? C.warn : C.dim),
                ]),
              ),
            ),
        ],
        builder: (context, controller, _) =>
            builder(() => controller.isOpen ? controller.close() : controller.open()),
      );

  Widget _toolbar(AppL10n t, CastMonitor mon) {
    final placements = _draft.placementsOn(mon.id);
    final urls = placements.where((p) => _draft.materialById(p.materialId)?.type == CastMaterialType.url).length;
    final videos =
        placements.where((p) => _draft.materialById(p.materialId)?.type == CastMaterialType.video).length;
    return Row(children: [
      _addMaterialMenu(
        t,
        (toggle) => FilledButton.icon(
          onPressed: toggle,
          style: FilledButton.styleFrom(
            backgroundColor: C.acc,
            foregroundColor: C.onAcc,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.add_rounded, size: 15),
          label: Text(t.screenAddMaterial, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(width: 10),
      Text(t.screenToolbarCounts(placements.length, urls, videos),
          style: TextStyle(fontSize: 10.5, color: C.faint)),
    ]);
  }

  Widget? _warning(AppL10n t, CastMonitor mon) {
    final placements = _draft.placementsOn(mon.id);
    final urls = placements.where((p) => _draft.materialById(p.materialId)?.type == CastMaterialType.url).length;
    final videos =
        placements.where((p) => _draft.materialById(p.materialId)?.type == CastMaterialType.video).length;
    if (urls <= 1 && videos <= 1) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: C.warn.withValues(alpha: .10),
        border: Border.all(color: C.warn.withValues(alpha: .38)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, size: 13, color: C.warn),
        const SizedBox(width: 6),
        Expanded(
          child: Text(t.screenPerfWarning(urls, videos),
              style: TextStyle(fontSize: 10.3, height: 1.45, color: C.warn)),
        ),
      ]),
    );
  }

  Widget _stageCard(AppL10n t, CastMonitor mon) {
    final target = _draft.targetFor(mon.id);
    return Container(
      decoration: BoxDecoration(
        color: C.panel,
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(children: [
            Text(mon.name, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.txt)),
            const SizedBox(width: 8),
            Text('${mon.fullSize.width.round()}×${mon.fullSize.height.round()} · ${(mon.scale * 100).round()}%',
                style: kNums.copyWith(fontSize: 10, color: C.faint)),
            const SizedBox(width: 8),
            _miniChip(
              _draft.enabled && target.enabled ? t.screenCastingBadge : t.screenNotCasting,
              _draft.enabled && target.enabled ? C.acc : C.dim,
            ),
            const Spacer(),
            Text(_clock(), style: kNums.copyWith(fontSize: 10.5, color: C.faint)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(9),
          child: Focus(
            focusNode: _stageFocus,
            onKeyEvent: (node, event) => _onKey(event),
            child: _stage(t, mon),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
          child: Row(children: [
            Expanded(
              child: ValueListenableBuilder<_LiveDrag>(
                valueListenable: _liveDrag,
                builder: (context, live, _) => Text(
                  _footInfo(t, mon, live.placement),
                  style: TextStyle(fontSize: 10.2, color: C.faint),
                ),
              ),
            ),
            Text(
              target.mode == CastMode.fullscreen ? t.screenFull : t.screenWork,
              style: TextStyle(fontSize: 10.2, color: C.faint),
            ),
          ]),
        ),
      ]),
    );
  }

  static String _clock() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  String _footInfo(AppL10n t, CastMonitor mon, [CastPlacement? live]) {
    final p = live ?? _sel;
    if (p == null) return t.screenNoSelection;
    final design = castDesignSize(mon, _draft.targetFor(mon.id));
    final m = _draft.materialById(p.materialId);
    return t.screenSelectionInfo(
      m == null ? '' : _materialName(t, m),
      (p.x * design.width).round(),
      (p.y * design.height).round(),
      (p.width * design.width).round(),
      (p.height * design.height).round(),
    );
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final p = _sel;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (p == null) return KeyEventResult.ignored;
      _select(null);
      return KeyEventResult.handled;
    }
    if (p == null) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deletePlacement(p);
      return KeyEventResult.handled;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final stepX = (shift ? 10 : 1) / math.max(1, _design.width);
    final stepY = (shift ? 10 : 1) / math.max(1, _design.height);
    Offset? delta;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) delta = Offset(-stepX, 0);
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) delta = Offset(stepX, 0);
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) delta = Offset(0, -stepY);
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) delta = Offset(0, stepY);
    if (delta == null) return KeyEventResult.ignored;
    final x = (p.x + delta.dx).clamp(0.0, 1 - p.width).toDouble();
    final y = (p.y + delta.dy).clamp(0.0, 1 - p.height).toDouble();
    _editPlacement(p.id, (q) => q.copyWith(x: x, y: y));
    return KeyEventResult.handled;
  }

  // ---------------- 畫布 ----------------

  Widget _stage(AppL10n t, CastMonitor mon) {
    final target = _draft.targetFor(mon.id);
    final design = castDesignSize(mon, target);
    final ratio = design.width / math.max(1, design.height);
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      final height = width / ratio;
      final stage = Size(width, height);
      return DragTarget<CastMaterial>(
        onAcceptWithDetails: (d) {
          final box = _stageKey.currentContext?.findRenderObject() as RenderBox?;
          if (box == null) return;
          final local = box.globalToLocal(d.offset);
          _placeMaterial(
            d.data,
            at: Offset((local.dx / box.size.width).clamp(0.0, 1.0),
                (local.dy / box.size.height).clamp(0.0, 1.0)),
          );
        },
        builder: (context, candidate, rejected) => Container(
          key: _stageKey,
          width: width,
          height: height,
          clipBehavior: Clip.none,
          decoration: BoxDecoration(
            color: Color(target.backgroundColor),
            borderRadius: BorderRadius.circular(9),
            border: candidate.isNotEmpty ? Border.all(color: C.acc, width: 1.6) : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(fit: StackFit.expand, children: [
              // 透明底色时预览出来就是一块棋盘，和右侧的透明色块口径一致。
              if ((target.backgroundColor >>> 24) == 0)
                CustomPaint(painter: const _CheckerPainter(cell: 12)),
              // 单独成层：拖素材时只重绘画布，不带着整个设置页一起重绘。
              RepaintBoundary(
                child: ValueListenableBuilder<_LiveDrag>(
                  valueListenable: _liveDrag,
                  builder: (context, live, _) {
                    final liveP = live.placement;
                    final placements = [
                      for (final p in _draft.placementsOn(mon.id))
                        liveP != null && liveP.id == p.id ? liveP : p,
                    ];
                    final selected = liveP ?? _sel;
                    return Stack(clipBehavior: Clip.none, children: [
                      for (final p in placements)
                        if (p.visible)
                          Positioned(
                            left: p.x * width,
                            top: p.y * height,
                            width: math.max(1, p.width * width),
                            height: math.max(1, p.height * height),
                            child: _box(t, p, stage),
                          ),
                      if (selected != null && selected.visible && selected.screenId == mon.id)
                        _selectionOverlay(selected, stage),
                    ]);
                  },
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _box(AppL10n t, CastPlacement p, Size stage) {
    final m = _draft.materialById(p.materialId);
    if (m == null) return const SizedBox.shrink();
    final selected = p.id == _placementId;
    final decorated = Container(
      decoration: BoxDecoration(
        border: p.locked
            ? Border.all(color: Colors.white.withValues(alpha: .16))
            : (selected ? Border.all(color: C.acc, width: 1.4) : null),
      ),
      child: ClipRect(
        child: Opacity(opacity: p.opacity, child: _boxInner(t, m, p, stage)),
      ),
    );
    return RepaintBoundary(
      child: MouseRegion(
        cursor: p.locked ? SystemMouseCursors.basic : SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _select(p.id),
          onPanStart: p.locked ? null : (_) => _select(p.id),
          onPanUpdate: p.locked ? null : (d) => _moveBy(p, d.delta, stage),
          onPanEnd: p.locked ? null : (_) => _endDrag(),
          onPanCancel: p.locked ? null : _endDrag,
          child: decorated,
        ),
      ),
    );
  }

  Widget _boxInner(AppL10n t, CastMaterial m, CastPlacement p, Size stage) {
    final scale = stage.height / castRefHeight;
    final radius = m.radius * scale;
    switch (m.type) {
      case CastMaterialType.lyric:
        final lines = _lyricSource;
        final style = m.style;
        final pos = _positionMs + style.offsetMs;
        return CastLyricLayer(
          style: style,
          box: Size(stage.width * p.width, stage.height * p.height),
          scale: scale,
          lines: lines,
          index: lyricIndexAt(lines, math.max(0, pos)),
          meta: _lyricMeta(t, style),
          positionMs: _positionMs,
          durationMs: _durationMs,
          placeholder: widget.state.nowPlaying != null ? t.castNoLyrics : '',
        );
      case CastMaterialType.text:
        final color = Color(m.color);
        final align = switch (m.align) {
          CastAlign.left => TextAlign.left,
          CastAlign.center => TextAlign.center,
          CastAlign.right => TextAlign.right,
        };
        final box = Size(stage.width * p.width, stage.height * p.height);
        return Padding(
          padding: EdgeInsets.all(math.max(2, box.width * .02)),
          child: Align(
            alignment: switch (m.align) {
              CastAlign.left => Alignment.centerLeft,
              CastAlign.center => Alignment.center,
              CastAlign.right => Alignment.centerRight,
            },
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: math.max(1, box.width * .96),
                child: Text(
                  m.text.trim().isEmpty ? t.screenEmptyMaterial : m.text,
                  textAlign: align,
                  style: TextStyle(
                    fontFamily: m.fontFamily,
                    fontSize: math.max(1, m.fontSize * scale),
                    fontWeight: FontWeight(m.fontWeight),
                    color: m.text.trim().isEmpty ? color.withValues(alpha: .45) : color,
                    shadows: m.shadow
                        ? [
                            Shadow(
                                color: const Color(0xB3000000),
                                blurRadius: 10 * scale,
                                offset: Offset(0, 3 * scale))
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        );
      case CastMaterialType.image:
        final child = _imagePreview(t, m);
        return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
      case CastMaterialType.video:
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: _videoPreview(t, m, p, stage),
        );
      case CastMaterialType.url:
        return _urlPreview(t, m);
    }
  }

  Widget _imagePreview(AppL10n t, CastMaterial m) {
    final fit = switch (m.fit) {
      CastFit.cover => BoxFit.cover,
      CastFit.contain => BoxFit.contain,
      CastFit.stretch => BoxFit.fill,
    };
    Widget? image;
    if (m.source == CastMediaSource.local && m.path.trim().isNotEmpty) {
      image = Image.file(File(m.path), fit: fit, gaplessPlayback: true,
          errorBuilder: (_, _, _) => _emptyMedia(t, Icons.broken_image_outlined, m.path));
    } else if (m.source == CastMediaSource.url && m.url.trim().isNotEmpty) {
      image = Image.network(m.url.trim(), fit: fit, gaplessPlayback: true,
          errorBuilder: (_, _, _) => _emptyMedia(t, Icons.broken_image_outlined, m.url));
    }
    return image ?? _emptyMedia(t, Icons.image_outlined, m.path.isEmpty ? m.url : m.path);
  }

  Widget _videoPreview(AppL10n t, CastMaterial m, CastPlacement p, Size stage) {
    final has = m.source == CastMediaSource.local ? m.path.trim().isNotEmpty : m.url.trim().isNotEmpty;
    final caption = [
      m.loop ? t.screenLoop : t.screenPlayOnce,
      p.sound ? '${t.screenSound} · ${p.volume}%' : t.screenMuted,
    ].join(' · ');
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1B3D), Color(0xFF163042), Color(0xFF071018)],
          stops: [0, .48, 1],
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        Center(
          child: Container(
            width: math.min(stage.height * .14, 58),
            height: math.min(stage.height * .14, 58),
            decoration: BoxDecoration(
              color: const Color(0x8C080E12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: .35)),
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x8C000000)],
              ),
            ),
            child: Row(children: [
              Icon(p.sound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  size: 11, color: Colors.white70),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  has ? '${_materialName(t, m)} · $caption' : t.screenEmptyMaterial,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: math.max(7, stage.height * .012), color: Colors.white70),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _urlPreview(AppL10n t, CastMaterial m) {
    final url = m.url.trim();
    var host = url;
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) host = uri.host;
    } catch (_) {}
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1420), Color(0xFF080D14)],
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: url.isEmpty
          ? _emptyMedia(t, Icons.public_rounded, url)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: C.acc, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
                ),
                const Icon(Icons.public_rounded, size: 12, color: Colors.white38),
              ]),
              const Spacer(),
              Text(t.screenUrlPreviewHint,
                  style: const TextStyle(fontSize: 9.5, height: 1.5, color: Colors.white38)),
            ]),
    );
  }

  Widget _emptyMedia(AppL10n t, IconData icon, String hint) => Container(
        color: C.panel2,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(6),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: C.faint),
          const SizedBox(height: 4),
          Text(
            hint.trim().isEmpty ? t.screenEmptyMaterial : hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.5, color: C.faint),
          ),
        ]),
      );

  Widget _selectionOverlay(CastPlacement p, Size stage) {
    final m = _draft.materialById(p.materialId);
    final name = m == null ? '' : _materialName(AppL10n.of(context), m);
    return Positioned(
      left: p.x * stage.width,
      top: p.y * stage.height,
      width: p.width * stage.width,
      height: p.height * stage.height,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Container(decoration: BoxDecoration(border: Border.all(color: C.acc, width: 1.6))),
          ),
        ),
        Positioned(
          left: 2,
          top: 2,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xC6080C0E),
                border: Border.all(color: C.acc.withValues(alpha: .5)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$name${p.locked ? ' · ${AppL10n.of(context).screenLock}' : ''}',
                style: const TextStyle(fontSize: 9, color: Color(0xFFE8EDF1)),
              ),
            ),
          ),
        ),
        for (final edge in const ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'])
          if (!p.locked) _handle(p, edge, stage),
      ]),
    );
  }

  Widget _handle(CastPlacement p, String edge, Size stage) {
    const size = 11.0;
    final align = switch (edge) {
      'nw' => Alignment.topLeft,
      'n' => Alignment.topCenter,
      'ne' => Alignment.topRight,
      'e' => Alignment.centerRight,
      'se' => Alignment.bottomRight,
      's' => Alignment.bottomCenter,
      'sw' => Alignment.bottomLeft,
      _ => Alignment.centerLeft,
    };
    final cursor = switch (edge) {
      'nw' || 'se' => SystemMouseCursors.resizeUpLeftDownRight,
      'ne' || 'sw' => SystemMouseCursors.resizeUpRightDownLeft,
      'n' || 's' => SystemMouseCursors.resizeUpDown,
      _ => SystemMouseCursors.resizeLeftRight,
    };
    return Align(
      alignment: align,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => _resizeBy(p, edge, d.delta, stage),
          onPanEnd: (_) => _endDrag(),
          onPanCancel: _endDrag,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: C.acc,
              border: Border.all(color: const Color(0xFF04140B)),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- 素材庫 ----------------

  Widget _shelf(AppL10n t, CastMonitor mon) => Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
        decoration: BoxDecoration(
          color: C.panel,
          border: Border.all(color: C.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(t.screenShelf, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.dim)),
            const SizedBox(width: 6),
            Text(t.screenShelfHint, style: TextStyle(fontSize: 10.5, color: C.faint)),
            const Spacer(),
            Text(t.screenShelfCount(_draft.materials.length),
                style: TextStyle(fontSize: 10.2, color: C.faint)),
          ]),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, c) {
            final cols = math.max(1, (c.maxWidth / 155).floor());
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _draft.materials.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisExtent: 44,
                crossAxisSpacing: 7,
                mainAxisSpacing: 7,
              ),
              itemBuilder: (context, i) => _shelfItem(t, _draft.materials[i], mon),
            );
          }),
          const SizedBox(height: 7),
          Text(t.screenShelfMore, style: kMini),
        ]),
      );

  Widget _shelfItem(AppL10n t, CastMaterial m, CastMonitor mon) {
    var usage = 0;
    for (final p in _draft.placements) {
      if (p.materialId == m.id) usage++;
    }
    final onThis = _draft.placementsOn(mon.id).any((p) => p.materialId == m.id);
    final chip = usage > 1
        ? t.screenUsageShared
        : (onThis ? t.screenUsageHere : (usage > 0 ? t.screenUsageOther : t.screenUsageNone));
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: C.panel2,
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(children: [
        Icon(_typeIcon(m.type), size: 15, color: _typeColor(m.type)),
        const SizedBox(width: 7),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_materialName(t, m),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.txt)),
            Text(_typeLabel(t, m.type), style: TextStyle(fontSize: 9.4, color: C.faint)),
          ]),
        ),
        _miniChip(chip, usage > 1 ? C.acc : C.dim),
        if (usage == 0)
          _iconButton(Icons.close_rounded, t.screenDeleteMaterial, C.faint, () => _removeMaterial(m)),
      ]),
    );
    return Draggable<CastMaterial>(
      data: m,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: C.panel,
            border: Border.all(color: C.acc),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_typeIcon(m.type), size: 14, color: _typeColor(m.type)),
            const SizedBox(width: 6),
            Text(_materialName(t, m), style: TextStyle(fontSize: 11.5, color: C.txt)),
          ]),
        ),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: () => _placeMaterial(m),
          child: tile,
        ),
      ),
    );
  }

  // ---------------- 右欄：圖層 + 屬性 ----------------

  Widget _rightPane(AppL10n t, CastMonitor mon, {bool scroll = true}) {
    final content = Column(children: [
      _layersPanel(t, mon),
      const SizedBox(height: 10),
      Panel(padding: const EdgeInsets.all(12), child: _inspector(t, mon)),
    ]);
    return scroll ? SingleChildScrollView(child: content) : content;
  }

  Widget _layersPanel(AppL10n t, CastMonitor mon) {
    final placements = _draft.placementsOn(mon.id).reversed.toList();
    return _panel(
      title: t.screenLayers,
      count: '${placements.length}',
      trailing: t.screenLayersHint,
      action: _addMaterialMenu(
        t,
        (toggle) => _iconButton(Icons.add_rounded, t.screenAddLayer, C.dim, toggle),
      ),
      child: placements.isEmpty
          ? Text(t.screenLayersEmpty, style: kMini)
          : ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: placements.length,
              onReorderItem: (oldIndex, newIndex) => _reorder(mon.id, placements, oldIndex, newIndex),
              proxyDecorator: (child, index, animation) => Material(color: Colors.transparent, child: child),
              itemBuilder: (context, i) {
                final p = placements[i];
                final m = _draft.materialById(p.materialId);
                if (m == null) return const SizedBox.shrink(key: ValueKey('missing'));
                final on = p.id == _placementId;
                return Container(
                  key: ValueKey(p.id),
                  margin: const EdgeInsets.only(bottom: 3),
                  decoration: BoxDecoration(
                    color: on ? C.acc.withValues(alpha: .12) : Colors.transparent,
                    border: Border.all(color: on ? C.acc.withValues(alpha: .55) : Colors.transparent),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    onTap: () => _select(p.id),
                    child: Opacity(
                      opacity: p.visible ? 1 : .45,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        child: Row(children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Icon(Icons.drag_indicator_rounded, size: 13, color: C.faint),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(_typeIcon(m.type), size: 13, color: _typeColor(m.type)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(_materialName(t, m),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: C.txt)),
                          ),
                          if (p.sound) _miniChip(t.screenSound, C.acc),
                          _iconButton(
                            p.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            p.visible ? t.screenHide : t.screenShow,
                            p.visible ? C.dim : C.acc,
                            () => _editPlacement(p.id, (q) => q.copyWith(visible: !p.visible)),
                          ),
                          _iconButton(
                            p.locked ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                            p.locked ? t.screenUnlock : t.screenLock,
                            p.locked ? C.acc : C.dim,
                            () => _editPlacement(p.id, (q) => q.copyWith(locked: !p.locked)),
                          ),
                          _iconButton(Icons.delete_outline_rounded, t.screenDeleteLayer, C.dim,
                              () => _deletePlacement(p)),
                        ]),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _reorder(String screenId, List<CastPlacement> topFirst, int oldIndex, int newIndex) {
    final list = [...topFirst];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), moved);
    final bottomFirst = [for (final p in list.reversed) p.id];
    _edit((s) => s.withZOrder(screenId, bottomFirst));
  }

  Widget _iconButton(IconData icon, String tooltip, Color color, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 13),
        color: color,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(highlightColor: C.panel),
      );

  Widget _inspector(AppL10n t, CastMonitor mon) {
    final p = _sel;
    final m = _selMat;
    if (p == null || m == null) return _screenInspector(t, mon);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton.icon(
        onPressed: () => _select(null),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: C.faint,
        ),
        icon: const Icon(Icons.arrow_back_rounded, size: 12),
        label: Text(t.screenBackToScreen, style: const TextStyle(fontSize: 10.5)),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Icon(_typeIcon(m.type), size: 16, color: _typeColor(m.type)),
        const SizedBox(width: 7),
        Expanded(
          child: TextField(
            key: ValueKey('name-${m.id}'),
            controller: _name,
            onChanged: (v) => _editMaterial(m.id, (x) => x.copyWith(name: v)),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.txt),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              border: InputBorder.none,
              hintText: t.screenMaterialName,
              hintStyle: TextStyle(fontSize: 12, color: C.faint),
            ),
          ),
        ),
        _iconButton(Icons.copy_rounded, t.screenDuplicate, C.dim, () => _duplicatePlacement(p)),
        _iconButton(Icons.delete_outline_rounded, t.screenDeleteLayer, C.dim, () => _deletePlacement(p)),
      ]),
      Text(
        '${_typeLabel(t, m.type)} · ${_usageText(t, m)}',
        style: TextStyle(fontSize: 9.8, color: C.faint),
      ),
      const SizedBox(height: 8),
      ..._typeSections(t, m, p),
      _geometrySection(t, m, p, mon),
    ]);
  }

  String _usageText(AppL10n t, CastMaterial m) {
    var n = 0;
    for (final p in _draft.placements) {
      if (p.materialId == m.id) n++;
    }
    return n > 1 ? t.screenUsageScreens(n) : t.screenUsageSingle;
  }

  List<Widget> _typeSections(AppL10n t, CastMaterial m, CastPlacement p) => switch (m.type) {
        CastMaterialType.lyric => _lyricSections(t, m),
        CastMaterialType.url => _urlSections(t, m, p),
        CastMaterialType.image => _imageSections(t, m),
        CastMaterialType.video => _videoSections(t, m, p),
        CastMaterialType.text => _textSections(t, m),
      };

  Widget _section({required String title, String? trailing, required List<Widget> children}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 9),
        padding: const EdgeInsets.only(top: 9),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: C.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: .55, color: C.faint)),
            const Spacer(),
            if (trailing != null) Text(trailing, style: TextStyle(fontSize: 10, color: C.dim)),
          ]),
          const SizedBox(height: 7),
          ...children,
        ]),
      );

  Widget _row(String label, Widget child, {double labelWidth = 58}) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          SizedBox(width: labelWidth, child: Text(label, style: TextStyle(fontSize: 10.5, color: C.faint))),
          Expanded(child: child),
        ]),
      );

  Widget _sliderRow(String label, double value, double min, double max, int divisions, String suffix,
          ValueChanged<double> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: TextStyle(fontSize: 10.5, color: C.faint)),
            const Spacer(),
            Text(
              '${value == value.roundToDouble() ? value.round() : value.toStringAsFixed(1)} $suffix',
              style: kNums.copyWith(fontSize: 10, color: C.dim),
            ),
          ]),
          SizedBox(
            height: 22,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ]),
      );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 10.8, color: C.dim))),
          Transform.scale(
            scale: .78,
            child: Switch(value: value, activeThumbColor: C.acc, onChanged: onChanged),
          ),
        ]),
      );

  Widget _chips(String label, List<({String value, String label})> options, String current,
          ValueChanged<String> onPick, {double labelWidth = 58}) =>
      _row(
        label,
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final o in options)
            Choice(
              compact: true,
              fill: C.panel2,
              label: o.label,
              on: o.value == current,
              onTap: () => onPick(o.value),
            ),
        ]),
        labelWidth: labelWidth,
      );

  Widget _colorRow(String label, int value, ValueChanged<int> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          SizedBox(width: 118, child: Text(label, style: TextStyle(fontSize: 10.5, color: C.faint))),
          Expanded(
            child: Material(
              color: C.panel2,
              borderRadius: BorderRadius.circular(7),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                mouseCursor: WidgetStateMouseCursor.clickable,
                onTap: () async {
                  final picked = await showCastColorPicker(context, value);
                  if (picked != null) onChanged(picked);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Color(value),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: C.line),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(castHex(value), style: kNums.copyWith(fontSize: 10.5, color: C.dim)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _textField(String key, String initial, ValueChanged<String> onChanged,
          {String? hint, int maxLines = 1, TextInputType? keyboard}) =>
      TextFormField(
        key: ValueKey('$key-${_placementId ?? _screenId}'),
        initialValue: initial,
        maxLines: maxLines,
        keyboardType: keyboard,
        onChanged: onChanged,
        style: TextStyle(fontSize: 11.5, color: C.txt),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: C.panel2,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 11, color: C.faint),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: C.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: C.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: C.acc),
          ),
        ),
      );

  Widget _note(IconData icon, String text, {bool highlight = false}) => Container(
        margin: const EdgeInsets.only(top: 7),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: highlight ? C.acc.withValues(alpha: .10) : C.panel2,
          border: Border.all(color: highlight ? C.acc.withValues(alpha: .45) : C.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 12, color: highlight ? C.acc : C.faint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 10.3, height: 1.5, color: highlight ? C.dim : C.faint)),
          ),
        ]),
      );

  List<Widget> _lyricSections(AppL10n t, CastMaterial m) {
    final style = m.style;
    void set(CastStyle Function(CastStyle) change) =>
        _editMaterial(m.id, (x) => x.copyWith(style: change(x.style)));
    return [
      _section(title: t.screenSectionLyric, trailing: t.screenFollowNow, children: [
        _chips(t.castLines, [
          (value: '1', label: t.screenLineCount(1)),
          (value: '2', label: t.screenLineCount(2)),
          (value: '3', label: t.screenLineCount(3)),
        ], '${style.lines}', (v) => set((s) => s.copyWith(lines: int.parse(v)))),
        _sliderRow(t.castFontSize, style.fontSize, 24, 240, 54, 'px',
            (v) => set((s) => s.copyWith(fontSize: v))),
        _sliderRow(t.castLineGap, style.lineGap, 0, 100, 50, 'px',
            (v) => set((s) => s.copyWith(lineGap: v))),
        _sliderRow(t.castTextWidth, style.textWidth, 40, 200, 32, '%',
            (v) => set((s) => s.copyWith(textWidth: v))),
        _sliderRow(t.castTextHeight, style.textHeight, 40, 200, 32, '%',
            (v) => set((s) => s.copyWith(textHeight: v))),
        _chips(t.castWeight, [
          (value: '400', label: '400'),
          (value: '500', label: '500'),
          (value: '600', label: '600'),
          (value: '700', label: '700'),
        ], '${style.fontWeight}', (v) => set((s) => s.copyWith(fontWeight: int.parse(v)))),
        _row(
          t.castFont,
          DropdownButton<String>(
            value: castFontChoices(t).containsKey(style.fontFamily) ? style.fontFamily : 'Microsoft YaHei',
            isExpanded: true,
            isDense: true,
            dropdownColor: C.panel,
            style: TextStyle(fontSize: 11.5, color: C.txt),
            items: [
              for (final e in castFontChoices(t).entries)
                DropdownMenuItem(value: e.key, child: Text(e.value, style: TextStyle(fontSize: 11.5, color: C.txt))),
            ],
            onChanged: (v) {
              if (v != null) set((s) => s.copyWith(fontFamily: v));
            },
          ),
        ),
        _colorRow(t.castCurrentColor, style.currentColor,
            (v) => set((s) => s.copyWith(currentColor: v))),
        _colorRow(t.castOtherColor, style.otherColor, (v) => set((s) => s.copyWith(otherColor: v))),
        _sliderRow(t.castOtherOpacity, style.otherOpacity, 0, 100, 100, '%',
            (v) => set((s) => s.copyWith(otherOpacity: v))),
        _note(Icons.gradient_rounded, t.castKaraokeColorHint),
        _sliderRow(t.castStroke, style.strokeWidth, 0, 12, 24, 'px',
            (v) => set((s) => s.copyWith(strokeWidth: v))),
        _switchRow(t.castShadow, style.shadow, (v) => set((s) => s.copyWith(shadow: v))),
        _chips(t.castAlign, [
          (value: 'left', label: t.castAlignLeft),
          (value: 'center', label: t.castAlignCenter),
          (value: 'right', label: t.castAlignRight),
        ], style.align.name, (v) {
          set((s) => s.copyWith(align: CastAlign.values.firstWhere((a) => a.name == v)));
        }),
      ]),
      _section(title: t.castExtras, trailing: t.screenOverlayAbove, children: [
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final (on, label, change) in [
            (style.showTitle, t.castShowTitle, (bool v) => set((s) => s.copyWith(showTitle: v))),
            (style.showArtist, t.castShowArtist, (bool v) => set((s) => s.copyWith(showArtist: v))),
          ])
            Choice(
              compact: true,
              fill: C.panel2,
              label: label,
              on: on,
              onTap: () => change(!on),
            ),
        ]),
        const SizedBox(height: 7),
        _row(
          t.screenTimeOffset,
          SizedBox(
            width: 82,
            child: _textField('offset', '${style.offsetMs}', (v) {
              final n = int.tryParse(v.trim());
              if (n != null) set((s) => s.copyWith(offsetMs: n.clamp(-5000, 5000)));
            }, keyboard: TextInputType.number),
          ),
        ),
        _note(Icons.info_outline_rounded, t.screenLyricNoBgNote, highlight: true),
      ]),
    ];
  }

  List<Widget> _urlSections(AppL10n t, CastMaterial m, CastPlacement p) => [
        _section(title: t.screenSectionUrl, trailing: t.screenEmbedPage, children: [
          _textField('url', m.url,
              (v) => _editMaterial(m.id, (x) => x.copyWith(url: v.trim())),
              hint: t.screenUrlPlaceholder),
          const SizedBox(height: 7),
          Row(children: [
            Expanded(child: Text(t.screenUrlReloadHint, style: kMini)),
            _ghost(t.screenReload, () {
              _editMaterial(m.id, (x) => x.copyWith(rev: x.rev + 1));
            }),
          ]),
          const SizedBox(height: 6),
          _row(
            t.screenRefresh,
            Row(children: [
              SizedBox(
                width: 64,
                child: _textField('refresh', '${m.refreshSec}', (v) {
                  final n = int.tryParse(v.trim());
                  if (n != null) _editMaterial(m.id, (x) => x.copyWith(refreshSec: n.clamp(0, 86400)));
                }, keyboard: TextInputType.number),
              ),
              const SizedBox(width: 6),
              Text(t.screenSeconds, style: kMini),
            ]),
          ),
          _switchRow(t.screenScreenSound, p.sound, (v) => _setSound(p, v)),
          if (p.sound)
            _sliderRow(t.screenVolume, p.volume.toDouble(), 0, 100, 20, '%',
                (v) => _editPlacement(p.id, (q) => q.copyWith(volume: v.round()))),
          _note(Icons.public_rounded, t.screenUrlEmbedNote),
        ]),
      ];

  List<Widget> _imageSections(AppL10n t, CastMaterial m) => [
        _section(
          title: t.screenSectionImage,
          trailing: m.source == CastMediaSource.url ? t.screenImageUrl : t.screenLocalFile,
          children: [
            _chips(t.screenSource, [
              (value: 'local', label: t.screenLocalFile),
              (value: 'url', label: t.screenUrlSource),
            ], m.source.name, (v) {
              _editMaterial(m.id, (x) => x.copyWith(source: CastMediaSource.values.firstWhere((s) => s.name == v)));
            }),
            _row(
              m.source == CastMediaSource.url ? t.screenImageUrl : t.screenFilePath,
              Row(children: [
                Expanded(
                  child: _textField(
                    'path',
                    m.source == CastMediaSource.url ? m.url : m.path,
                    (v) => _editMaterial(
                      m.id,
                      (x) => m.source == CastMediaSource.url ? x.copyWith(url: v.trim()) : x.copyWith(path: v.trim()),
                    ),
                    hint: m.source == CastMediaSource.url
                        ? t.screenImageUrlPlaceholder
                        : t.screenImagePathPlaceholder,
                  ),
                ),
                if (m.source == CastMediaSource.local) ...[
                  const SizedBox(width: 5),
                  _ghost(t.castBrowse, () => _pickMedia(m, video: false)),
                ],
              ]),
            ),
            _chips(t.screenFill, [
              (value: 'cover', label: t.castFitCover),
              (value: 'contain', label: t.castFitContain),
              (value: 'stretch', label: t.screenFitStretch),
            ], m.fit.name, (v) {
              _editMaterial(m.id, (x) => x.copyWith(fit: CastFit.values.firstWhere((f) => f.name == v)));
            }),
            _sliderRow(t.screenRadius, m.radius, 0, 60, 60, 'px',
                (v) => _editMaterial(m.id, (x) => x.copyWith(radius: v))),
            _note(Icons.wallpaper_rounded, t.screenImageBgNote),
          ],
        ),
      ];

  List<Widget> _videoSections(AppL10n t, CastMaterial m, CastPlacement p) => [
        _section(
          title: t.screenSectionVideo,
          trailing: m.source == CastMediaSource.url ? t.screenVideoUrl : t.screenLocalFile,
          children: [
            _chips(t.screenSource, [
              (value: 'local', label: t.screenLocalFile),
              (value: 'url', label: t.screenUrlSource),
            ], m.source.name, (v) {
              _editMaterial(m.id, (x) => x.copyWith(source: CastMediaSource.values.firstWhere((s) => s.name == v)));
            }),
            _row(
              m.source == CastMediaSource.url ? t.screenVideoUrl : t.screenFilePath,
              Row(children: [
                Expanded(
                  child: _textField(
                    'path',
                    m.source == CastMediaSource.url ? m.url : m.path,
                    (v) => _editMaterial(
                      m.id,
                      (x) => m.source == CastMediaSource.url ? x.copyWith(url: v.trim()) : x.copyWith(path: v.trim()),
                    ),
                    hint: m.source == CastMediaSource.url
                        ? t.screenVideoUrlPlaceholder
                        : t.screenVideoPathPlaceholder,
                  ),
                ),
                if (m.source == CastMediaSource.local) ...[
                  const SizedBox(width: 5),
                  _ghost(t.castBrowse, () => _pickMedia(m, video: true)),
                ],
              ]),
            ),
            _switchRow(t.screenLoop, m.loop, (v) => _editMaterial(m.id, (x) => x.copyWith(loop: v))),
            _switchRow(t.screenAutoplay, m.autoplay,
                (v) => _editMaterial(m.id, (x) => x.copyWith(autoplay: v))),
            _chips(t.screenFill, [
              (value: 'cover', label: t.castFitCover),
              (value: 'contain', label: t.castFitContain),
              (value: 'stretch', label: t.screenFitStretch),
            ], m.fit.name, (v) {
              _editMaterial(m.id, (x) => x.copyWith(fit: CastFit.values.firstWhere((f) => f.name == v)));
            }),
            _sliderRow(t.screenRadius, m.radius, 0, 60, 60, 'px',
                (v) => _editMaterial(m.id, (x) => x.copyWith(radius: v))),
          ],
        ),
        _section(title: t.screenSectionSound, trailing: t.screenSoundFollowsScreen, children: [
          _switchRow(t.screenSound, p.sound, (v) => _setSound(p, v)),
          _sliderRow(t.screenVolume, p.sound ? p.volume.toDouble() : 0, 0, 100, 20, '%',
              (v) => _editPlacement(p.id, (q) => q.copyWith(volume: v.round()))),
          _note(Icons.volume_up_rounded, t.screenMuteOthersNote),
        ]),
      ];

  List<Widget> _textSections(AppL10n t, CastMaterial m) => [
        _section(title: t.screenSectionText, trailing: t.screenStaticContent, children: [
          _textField(
            'text',
            m.text,
            (v) => _editMaterial(m.id, (x) => x.copyWith(text: v)),
            hint: t.screenTextPlaceholder,
            maxLines: 3,
          ),
          const SizedBox(height: 6),
          _sliderRow(t.castFontSize, m.fontSize, 20, 200, 36, 'px',
              (v) => _editMaterial(m.id, (x) => x.copyWith(fontSize: v))),
          _chips(t.castWeight, [
            (value: '400', label: '400'),
            (value: '500', label: '500'),
            (value: '600', label: '600'),
            (value: '700', label: '700'),
          ], '${m.fontWeight}', (v) => _editMaterial(m.id, (x) => x.copyWith(fontWeight: int.parse(v)))),
          _colorRow(t.screenColor, m.color, (v) => _editMaterial(m.id, (x) => x.copyWith(color: v))),
          _chips(t.castAlign, [
            (value: 'left', label: t.castAlignLeft),
            (value: 'center', label: t.castAlignCenter),
            (value: 'right', label: t.castAlignRight),
          ], m.align.name, (v) {
            _editMaterial(m.id,
                (x) => x.copyWith(align: CastAlign.values.firstWhere((a) => a.name == v)));
          }),
          _switchRow(t.castShadow, m.shadow, (v) => _editMaterial(m.id, (x) => x.copyWith(shadow: v))),
          _row(
            t.castFont,
            DropdownButton<String>(
              value: castFontChoices(t).containsKey(m.fontFamily) ? m.fontFamily : 'Microsoft YaHei',
              isExpanded: true,
              isDense: true,
              dropdownColor: C.panel,
              style: TextStyle(fontSize: 11.5, color: C.txt),
              items: [
                for (final e in castFontChoices(t).entries)
                  DropdownMenuItem(
                      value: e.key, child: Text(e.value, style: TextStyle(fontSize: 11.5, color: C.txt))),
              ],
              onChanged: (v) {
                if (v != null) _editMaterial(m.id, (x) => x.copyWith(fontFamily: v));
              },
            ),
          ),
          _note(Icons.title_rounded, t.screenTextNote),
        ]),
      ];

  Widget _geometrySection(AppL10n t, CastMaterial m, CastPlacement p, CastMonitor mon) {
    final design = castDesignSize(mon, _draft.targetFor(mon.id));
    Widget geoField(String label, TextEditingController c, String key) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 9.6, color: C.faint)),
            const SizedBox(height: 2),
            SizedBox(
              height: 26,
              child: TextField(
                controller: c,
                onChanged: (v) => _setGeoField(p, key, v),
                style: kNums.copyWith(fontSize: 11, color: C.txt),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: C.panel2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: C.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: C.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: C.acc),
                  ),
                ),
              ),
            ),
          ]),
        );
    var usage = 0;
    for (final q in _draft.placements) {
      if (q.materialId == m.id) usage++;
    }
    return _section(
      title: t.screenGeometry,
      trailing: '${design.width.round()}×${design.height.round()}',
      children: [
        Row(children: [
          geoField(t.castLeftPx, _pxX, 'x'),
          const SizedBox(width: 5),
          geoField(t.castTopPx, _pxY, 'y'),
          const SizedBox(width: 5),
          geoField(t.castWidthPx, _pxW, 'w'),
          const SizedBox(width: 5),
          geoField(t.castHeightPx, _pxH, 'h'),
        ]),
        const SizedBox(height: 4),
        _sliderRow(t.screenOpacity, p.opacity * 100, 10, 100, 18, '%',
            (v) => _editPlacement(p.id, (q) => q.copyWith(opacity: v / 100))),
        _row(
          t.screenZOrder,
          Row(children: [
            _zButton(Icons.flip_to_front_rounded, t.screenZTop, () => _z(p, 'top')),
            _zButton(Icons.arrow_upward_rounded, t.screenZUp, () => _z(p, 'up')),
            _zButton(Icons.arrow_downward_rounded, t.screenZDown, () => _z(p, 'down')),
            _zButton(Icons.flip_to_back_rounded, t.screenZBottom, () => _z(p, 'bottom')),
          ]),
        ),
        _row(
          t.screenShownOn,
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final s in _monitors)
              Choice(
                compact: true,
                fill: C.panel2,
                label: s.name,
                on: _draft.placementsOn(s.id).any((q) => q.materialId == m.id),
                onTap: () {
                  final on = _draft.placementsOn(s.id).any((q) => q.materialId == m.id);
                  _toggleOnScreen(m, s.id, !on);
                },
              ),
          ]),
          labelWidth: 46,
        ),
        _switchRow(t.screenLockLayer, p.locked,
            (v) => _editPlacement(p.id, (q) => q.copyWith(locked: v))),
        if (usage > 1) _note(Icons.layers_outlined, t.screenSharedNote, highlight: true),
      ],
    );
  }

  Widget _zButton(IconData icon, String tooltip, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: C.panel2,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: onTap,
              child: Container(
                width: 30,
                height: 24,
                decoration: BoxDecoration(
                  border: Border.all(color: C.line),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 12, color: C.dim),
              ),
            ),
          ),
        ),
      );

  // ---------------- 螢幕屬性（未選中圖層時） ----------------

  Widget _screenInspector(AppL10n t, CastMonitor mon) {
    final target = _draft.targetFor(mon.id);
    final placements = _draft.placementsOn(mon.id);
    final urls = placements.where((p) => _draft.materialById(p.materialId)?.type == CastMaterialType.url).length;
    final videos =
        placements.where((p) => _draft.materialById(p.materialId)?.type == CastMaterialType.video).length;
    final audio = placements.where((p) => p.sound).length;
    final load = _loadLabel(t, placements.length, urls, videos);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.monitor_rounded, size: 16, color: C.info),
        const SizedBox(width: 7),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mon.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.txt)),
            Text(
              '${mon.fullSize.width.round()}×${mon.fullSize.height.round()} · ${(mon.scale * 100).round()}% · '
              '${t.screenLayersCount(placements.length)}',
              style: kNums.copyWith(fontSize: 9.8, color: C.faint),
            ),
          ]),
        ),
      ]),
      _section(title: t.screenCast, trailing: target.mode == CastMode.fullscreen ? t.screenFull : t.screenWork, children: [
        _switchRow(t.screenCastThisScreen, target.enabled,
            (v) => _edit((s) => s.toggled(mon.id, mon.name, v))),
        _chips(t.screenCoverage, [
          (value: 'full', label: t.screenFull),
          (value: 'work', label: t.screenWork),
        ], target.mode == CastMode.fullscreen ? 'full' : 'work', (v) {
          _setMode(mon, v == 'full' ? CastMode.fullscreen : CastMode.region);
        }),
      ]),
      _section(title: t.castRegionTitle, trailing: mon.name, children: [
        CastDesktopMap(
          items: [
            for (final m in _monitors)
              CastMapItem(
                monitor: m,
                mode: _draft.targetFor(m.id).mode,
                region: _regionInWork(m),
              ),
          ],
          editingId: mon.id,
          onSelect: _selectScreen,
          onRegion: _setRegion,
          onCommit: () {
            _syncRegionFields();
            _persistSoon();
          },
        ),
        const SizedBox(height: 7),
        Wrap(spacing: 4, runSpacing: 4, children: [
          Choice(
            compact: true,
            fill: C.panel2,
            label: t.castFullscreen,
            on: target.mode == CastMode.fullscreen,
            onTap: () => _usePreset(mon, CastRegion.full, true),
          ),
          Choice(
            compact: true,
            fill: C.panel2,
            label: t.castPresetBottomStrip,
            on: _isPreset(mon, CastRegion.bottomStrip),
            onTap: () => _usePreset(mon, CastRegion.bottomStrip, false),
          ),
          Choice(
            compact: true,
            fill: C.panel2,
            label: t.castPresetLowerHalf,
            on: _isPreset(mon, const CastRegion(top: .5, height: .5)),
            onTap: () => _usePreset(mon, const CastRegion(top: .5, height: .5), false),
          ),
          Choice(
            compact: true,
            fill: C.panel2,
            label: t.castPresetCenterStrip,
            on: _isPreset(mon, CastRegion.centerStrip),
            onTap: () => _usePreset(mon, CastRegion.centerStrip, false),
          ),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          _nudgeButton(Icons.arrow_back_rounded, t.castMoveLeft, () => _nudge(mon, 'l')),
          const SizedBox(width: 3),
          _nudgeButton(Icons.arrow_upward_rounded, t.castMoveUp, () => _nudge(mon, 't')),
          const SizedBox(width: 3),
          _nudgeButton(Icons.arrow_downward_rounded, t.castMoveDown, () => _nudge(mon, 'd')),
          const SizedBox(width: 3),
          _nudgeButton(Icons.arrow_forward_rounded, t.castMoveRight, () => _nudge(mon, 'r')),
          const SizedBox(width: 6),
          Expanded(child: _ghost(t.castCenterH, () => _nudge(mon, 'cx'))),
          const SizedBox(width: 3),
          Expanded(child: _ghost(t.castCenterV, () => _nudge(mon, 'cy'))),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          _regionBox(t.castLeftPx, _regL, 'l'),
          const SizedBox(width: 4),
          _regionBox(t.castTopPx, _regT, 't'),
          const SizedBox(width: 4),
          _regionBox(t.castWidthPx, _regW, 'w'),
          const SizedBox(width: 4),
          _regionBox(t.castHeightPx, _regH, 'h'),
        ]),
        const SizedBox(height: 6),
        Text(t.castMapHint, style: kMini),
      ]),
      _section(title: t.screenCanvasColor, children: [
        Row(children: [
          _swatch(0x00000000, t.screenTransparent, target.backgroundColor,
              () => _edit((s) => s.withScreenBackground(mon.id, 0x00000000))),
          const SizedBox(width: 6),
          _swatch(0xFF000000, t.screenBlack, target.backgroundColor,
              () => _edit((s) => s.withScreenBackground(mon.id, 0xFF000000))),
          const SizedBox(width: 6),
          _swatch(0xFF05070A, t.screenMidnight, target.backgroundColor,
              () => _edit((s) => s.withScreenBackground(mon.id, 0xFF05070A))),
          const SizedBox(width: 6),
          _swatch(0xFFF4F6F7, t.screenLightCanvas, target.backgroundColor,
              () => _edit((s) => s.withScreenBackground(mon.id, 0xFFF4F6F7))),
          const SizedBox(width: 8),
          _ghost(t.screenCustomColor, () async {
            final picked = await showCastColorPicker(context, target.backgroundColor);
            if (picked != null) _edit((s) => s.withScreenBackground(mon.id, picked));
          }),
        ]),
        _note(Icons.wallpaper_rounded, t.screenCanvasNote, highlight: true),
      ]),
      _section(title: t.screenPerformance, trailing: load.label, children: [
        Row(children: [
          _kv(t.screenPerfLayers, '${placements.length}'),
          const SizedBox(width: 5),
          _kv(t.screenPerfUrls, '$urls'),
          const SizedBox(width: 5),
          _kv(t.screenPerfVideos, '$videos'),
          const SizedBox(width: 5),
          _kv(t.screenPerfAudio, '$audio'),
        ]),
        const SizedBox(height: 6),
        Text(t.screenPerfHint, style: kMini),
      ]),
      _section(title: t.screenTips, children: [Text(t.screenTipsText, style: kMini)]),
    ]);
  }

  bool _isPreset(CastMonitor m, CastRegion region) {
    final t = _draft.targetFor(m.id);
    return t.mode == CastMode.region && t.region == region;
  }

  Widget _nudgeButton(IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
        message: tooltip,
        child: Material(
          color: C.panel2,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onTap,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                border: Border.all(color: C.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 13, color: C.txt),
            ),
          ),
        ),
      );

  Widget _regionBox(String label, TextEditingController c, String key) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 9, color: C.faint)),
          const SizedBox(height: 2),
          SizedBox(
            height: 26,
            child: TextField(
              controller: c,
              onChanged: (v) => _regionFieldChanged(key, v),
              style: kNums.copyWith(fontSize: 11, color: C.txt),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: C.panel2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: C.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: C.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: C.acc),
                ),
              ),
            ),
          ),
        ]),
      );

  void _regionFieldChanged(String key, String raw) {
    final m = _mon;
    if (m == null) return;
    _applyRegionField(m, key, raw);
  }

  Widget _swatch(int color, String tooltip, int current, VoidCallback onTap) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Color(color),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: C.line),
              boxShadow: color == current
                  ? [BoxShadow(color: C.acc, spreadRadius: 1.5), BoxShadow(color: C.acc, spreadRadius: 2.5)]
                  : null,
            ),
            // 全透明色块在深色面板上看不出边界，垫一层棋盘格表示「这里是空的」。
            child: (color >>> 24) == 0
                ? CustomPaint(painter: _CheckerPainter(cell: 6), child: const SizedBox.expand())
                : null,
          ),
        ),
      );

  Widget _kv(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: C.panel2,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 9.4, color: C.faint)),
            Text(value,
                style: kNums.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.txt)),
          ]),
        ),
      );

  // ---------------- 小件 ----------------

  Future<void> _pickMedia(CastMaterial m, {required bool video}) async {
    final path = await showMediaPathPicker(
      context,
      initialPath: m.source == CastMediaSource.local ? m.path : '',
      video: video,
    );
    if (path == null || !mounted) return;
    _editMaterial(m.id, (x) => x.copyWith(path: path));
  }

  Widget _ghost(String label, VoidCallback? onTap) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(7)),
            child: Text(label, style: TextStyle(fontSize: 11, color: C.txt)),
          ),
        ),
      );
}

// ---------------- 畫布輔助繪製 ----------------

/// 拖動/縮放中的臨時狀態：只給畫布和底部坐標讀，不進 CastSettings。
class _LiveDrag {
  const _LiveDrag({this.placement});

  static const none = _LiveDrag();

  final CastPlacement? placement;

  @override
  bool operator ==(Object other) => other is _LiveDrag && other.placement == placement;

  @override
  int get hashCode => placement.hashCode;
}

/// 透明底色的棋盘预览。只是让「这里什么都没有」看得见，不影响实际投放。
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter({this.cell = 8});

  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF20242A));
    final light = Paint()..color = const Color(0xFF2C3137);
    for (var y = 0.0; y < size.height; y += cell) {
      final odd = (y / cell).floor().isOdd;
      for (var x = odd ? cell : 0.0; x < size.width; x += cell * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), light);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => old.cell != cell;
}

