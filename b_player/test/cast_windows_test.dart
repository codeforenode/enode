import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/desktop/cast_window_main.dart';
import 'package:b_player/desktop/cast_windows.dart';
import 'package:b_player/l10n/l10n.dart';
import 'package:b_player/state/app_state.dart';
import 'package:b_player/state/cast_settings.dart';
import 'package:b_player/state/lrc.dart';

const _main = CastMonitor(
  id: 'main',
  name: r'\\.\DISPLAY1',
  workOrigin: Offset.zero,
  workSize: Size(1920, 1040),
  fullSize: Size(1920, 1080),
  scale: 1,
);

/// 副屏在右边：投放窗原点必须带虚拟桌面的偏移，否则两扇都落在主屏上。
const _second = CastMonitor(
  id: 'second',
  name: r'\\.\DISPLAY2',
  workOrigin: Offset(1920, 0),
  workSize: Size(1600, 852),
  fullSize: Size(1600, 900),
  scale: 1.5,
);

CastTarget _on(String id, String name, {CastMode mode = CastMode.fullscreen, CastRegion region = CastRegion.full}) =>
    CastTarget(monitorId: id, name: name, enabled: true, mode: mode, region: region);

CastSettings _settings({bool enabled = true, List<CastTarget> targets = const []}) =>
    CastSettings(enabled: enabled, targets: targets);

List<double> _box(Rect r) => [r.left, r.top, r.width, r.height];

void main() {
  group('开窗名单', () {
    test('没启用就一扇都不开', () {
      final s = _settings(enabled: false, targets: [_on('main', 'a'), _on('second', 'b')]);
      expect(castWindowPlan(s, [_main, _second]), isEmpty);
    });

    test('只开勾选了、而且这次真扫到的屏', () {
      final s = _settings(targets: [
        _on('main', 'a'),
        CastTarget(monitorId: 'second', name: 'b'),
        _on('ghost', '拔掉的屏'),
      ]);
      expect(castWindowPlan(s, [_main, _second]), ['main']);
    });
  });

  group('落位与画布', () {
    test('整屏用整屏尺寸，原点取该屏工作区原点', () {
      final t = _on('second', 'b');
      final b = castWindowBounds(_second, t);
      expect(_box(b), [1920, 0, 1600, 900]);
      expect(castDesignSize(_second, t), const Size(1600, 900));
    });

    test('区域用该屏工作区里的百分比矩形，原点带上屏偏移', () {
      final t = _on('second', 'b', mode: CastMode.region, region: CastRegion.bottomStrip);
      final b = castWindowBounds(_second, t);
      expect(b.left, closeTo(1920 + 1600 * .05, 0.01));
      expect(b.top, closeTo(852 * .7, 0.01));
      expect(b.width, closeTo(1600 * .9, 0.01));
      expect(b.height, closeTo(852 * .24, 0.01));
      expect(castDesignSize(_second, t), Size(b.width, b.height));
    });

    test('预览和投放窗共用同一个 design 基准', () {
      final t = _on('main', 'a', mode: CastMode.region, region: CastRegion.centerStrip);
      expect(castDesignSize(_main, t), t.region.toRect(_main.workSize).size);
    });
  });

  group('跨 isolate 载荷', () {
    test('建窗 payload 带标记、主窗 id 和这台屏的几何', () {
      final t = _on('second', 'b', mode: CastMode.region, region: CastRegion.bottomStrip);
      final style = CastStyle.defaults.copyWith(fontSize: 64, offsetMs: 1200);
      final p = castWindowPayload(mainId: 'win-1', monitor: _second, target: t, style: style);
      expect(p['tag'], castWindowTag);
      expect(p['main'], 'win-1');
      expect(p['monitorId'], 'second');
      // 子引擎是独立 isolate，标题和语言都得随载荷带过去。
      expect(p['title'], l10n.castWindowTitle(_second.name));
      expect(p['locale'], currentLocale.toLanguageTag());
      expect(p['fullscreen'], false);
      expect(p['bounds'], _box(castWindowBounds(_second, t)));
      expect(p['design'], [castDesignSize(_second, t).width, castDesignSize(_second, t).height]);
      expect((p['style'] as Map)['size'], 64);
      // payload 是要 jsonEncode 过通道的一份 JSON 安全值。
      expect(jsonDecode(jsonEncode(p))['tag'], castWindowTag);
    });

    test('样式推送里所有屏共用同一份 style，但 bounds 各自算', () {
      final style = CastStyle.defaults.copyWith(lines: 3);
      final a = castStylePush(monitor: _main, target: _on('main', 'a'), style: style);
      final b = castStylePush(monitor: _second, target: _on('second', 'b'), style: style);
      expect(jsonEncode(a['style']), jsonEncode(b['style']));
      expect(a['bounds'], isNot(b['bounds']));
      expect(a['fullscreen'], true);
    });

    test('歌词整包只有一份，座位没带就不下发', () {
      final payload = castLyricPush(
        lines: const [
          (
            startMs: 0,
            endMs: 4000,
            text: '第一句',
            words: [(startMs: 0, endMs: 1200, text: '第一'), (startMs: 1200, endMs: 3000, text: '句')],
          ),
          (startMs: 4000, endMs: 8000, text: '第二句', words: <LyricWord>[]),
        ],
        nowPlaying: QueueItem(trackKey: 'k', title: '甜蜜蜜', artist: '邓丽君', durationMs: 61000),
      );
      expect(payload['lines'], [
        [
          0,
          '第一句',
          4000,
          [
            [0, 1200, '第一'],
            [1200, 3000, '句'],
          ],
        ],
        [4000, '第二句', 8000],
      ]);
      // 没带桌号就不下发 seat，投放页的 trim() 判断会自动跳过这一段；
      // 不要再兜成「本机」这种标签，那会把缺失当成一种身份。
      expect(payload['seat'], isNull);
      expect(payload['durationMs'], 61000);
      expect(payload['hasTrack'], true);
      final fromSeat = castLyricPush(
        lines: const [],
        nowPlaying: QueueItem(trackKey: 'k', title: 't', artist: 'a', durationMs: 0, seat: 'A-07'),
      );
      expect(fromSeat['seat'], 'A-07');
      expect(castLyricPush(lines: const [])['title'], isNull);
      expect(castLyricPush(lines: const [])['hasTrack'], false);
    });

    test('锚点是「位置 + 当时的墙钟 + 是否在播」三件套', () {
      final t = castTickPush(positionMs: 12345, playing: true, wallMs: 999);
      expect(t['positionMs'], 12345);
      expect(t['wallMs'], 999);
      expect(t['playing'], true);
      expect(castTickPush(positionMs: 0, playing: false)['playing'], false);
    });
  });

  group('投放窗本地时钟', () {
    CastWindowModel modelAt(Rect bounds) => CastWindowModel(
          design: const Size(1600, 900),
          style: CastStyle.defaults,
          bounds: bounds,
          fullscreen: false,
        );

    test('歌词进来就能算行号，偏移跟着同一份 style 走', () async {
      final bounds = const Rect.fromLTWH(1920, 0, 1600, 900);
      final model = modelAt(bounds);
      addTearDown(model.dispose);
      await model.handle('lyric', {
        'lines': [
          [0, '第一句'],
          [4000, '第二句'],
          [8000, '第三句'],
        ],
        'title': '甜蜜蜜',
        'artist': '邓丽君',
        'seat': 'A-07',
        'durationMs': 61000,
      });
      expect(model.lines.length, 3);
      expect(model.seat, 'A-07');

      await model.handle('tick', {'positionMs': 5000, 'wallMs': 1000, 'playing': false});
      expect(model.positionMs, 5000);
      expect(model.lyricIndex, 1);

      // 负偏移把词往前压：同一个位置退回上一句。bounds 没变就不该碰窗口。
      final style = CastStyle.defaults.copyWith(offsetMs: -2000);
      await model.handle('style', {
        'bounds': _box(bounds),
        'design': [1600, 900],
        'fullscreen': false,
        'style': jsonDecode(jsonEncode(style.toJson())),
      });
      expect(model.style.offsetMs, -2000);
      expect(model.lyricIndex, 0);
      expect(model.design, const Size(1600, 900));
    });

    test('暂停时钉在锚点，播放时按墙钟自己往前走', () async {
      final model = modelAt(const Rect.fromLTWH(1920, 0, 1600, 900));
      addTearDown(model.dispose);
      final wall = DateTime.now().millisecondsSinceEpoch;
      await model.handle('tick', {'positionMs': 10000, 'wallMs': wall - 5000, 'playing': true});
      expect(model.positionMs, inInclusiveRange(14800, 15400));
      // 关掉播放要顺手停掉重绘定时器，否则画面会僵在锚点。
      await model.handle('tick', {'positionMs': 15000, 'wallMs': wall, 'playing': false});
      expect(model.positionMs, 15000);
    });

    test('坏载荷不炸：空参数只当没收到', () async {
      final model = modelAt(const Rect.fromLTWH(1920, 0, 1600, 900));
      addTearDown(model.dispose);
      await model.handle('lyric', null);
      expect(model.lines, isEmpty);
      await model.handle('unknown', {});
      expect(model.positionMs, 0);
    });
  });
}
