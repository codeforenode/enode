import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/state/cast_settings.dart';

void main() {
  const m1 = CastMonitor(
    id: r'MONITOR\BOE0A74\0001',
    name: r'\\.\DISPLAY2',
    workOrigin: Offset(-1920, 0),
    workSize: Size(1920, 1152),
    fullSize: Size(1920, 1200),
    scale: 1,
  );
  const m2 = CastMonitor(
    id: r'MONITOR\DEL41A8\0004',
    name: r'\\.\DISPLAY1',
    workOrigin: Offset(0, 0),
    workSize: Size(1600, 852),
    fullSize: Size(1600, 900),
    scale: 1.5,
  );

  group('CastRegion', () {
    test('百分比与工作区像素互转', () {
      const region = CastRegion(left: .1, top: .2, width: .5, height: .3);
      final rect = region.toRect(m2.workSize);
      expect(rect, const Rect.fromLTWH(160, 170.4, 800, 255.6));
      expect(CastRegion.fromRect(m2.workSize, rect), region);
    });

    test('拖出屏外的框被裁回工作区', () {
      final region = CastRegion.fromRect(const Size(1000, 1000), const Rect.fromLTRB(-50, 900, 1200, 1400));
      expect(region.left, 0);
      expect(region.width, 1);
      expect(region.top, .9);
      expect(region.height, .1);
    });

    test('零宽高的存档退回整屏', () {
      expect(CastRegion.fromJson({'l': .5, 't': .5, 'w': 0, 'h': 0}), CastRegion.full);
      expect(CastRegion.fromJson(null), CastRegion.full);
    });
  });

  group('CastSettings', () {
    test('编码后再解码，样式与每台屏的设置都不丢', () {
      const lyric = CastMaterial(
        id: 'lyric-1',
        type: CastMaterialType.lyric,
        name: '歌词',
        style: CastStyle(
          lines: 3,
          fontSize: 120,
          lineGap: 24,
          textWidth: 130,
          textHeight: 90,
          otherOpacity: 45,
          background: CastBackground.image,
          imagePath: r'D:\pic\bg.jpg',
          align: CastAlign.right,
          vertical: 80,
          offsetMs: -350,
        ),
      );
      const settings = CastSettings(
        enabled: true,
        materials: [lyric],
        targets: [
          CastTarget(monitorId: r'MONITOR\BOE0A74\0001', name: 'B', enabled: true, mode: CastMode.fullscreen),
          CastTarget(
            monitorId: r'MONITOR\DEL41A8\0004',
            name: 'D',
            enabled: true,
            mode: CastMode.region,
            region: CastRegion.bottomStrip,
          ),
        ],
        placements: [
          CastPlacement(
            id: 'p1',
            materialId: 'lyric-1',
            screenId: r'MONITOR\BOE0A74\0001',
            x: .05,
            y: .7,
            width: .9,
            height: .24,
            z: 3,
            opacity: .8,
            sound: true,
            volume: 40,
          ),
        ],
      );
      expect(CastSettings.decode(settings.toJsonString()), settings);
    });

    test('坏数据与缺字段都退回默认，不炸启动', () {
      expect(CastSettings.decode('not json').style, CastStyle.defaults);
      expect(CastSettings.decode('{"targets":[{"id":"x","mode":"nonsense"}]}').targets.single.mode,
          CastMode.fullscreen);
      expect(CastSettings.decode('{"targets":[{"id":"","name":"没 id 的丢掉"}]}').targets, isEmpty);
      final clamped = CastSettings.decode('{"style":{"lines":99,"size":9999,"gap":999,"tw":1,"th":999,"otherAlpha":999}}').style;
      expect(clamped.lines, 4);
      expect(clamped.lineGap, 160);
      expect(clamped.textWidth, 40);
      expect(clamped.textHeight, 200);
      expect(clamped.otherOpacity, 100);
    });

    test('扫描对齐：新屏给未勾选默认，拔掉的屏保留配置排在后面', () {
      const saved = CastSettings(targets: [
        CastTarget(monitorId: 'gone', name: '旧屏', enabled: true, mode: CastMode.region, region: CastRegion.centerStrip),
        CastTarget(monitorId: r'MONITOR\BOE0A74\0001', name: '', enabled: true),
      ]);
      final aligned = saved.alignedTo([m2, m1]);
      // 顺序跟着扫描结果走。
      expect(aligned.targets.map((t) => t.monitorId), [m2.id, m1.id, 'gone']);
      expect(aligned.targetFor(m1.id).enabled, isTrue, reason: '已存配置要保留');
      expect(aligned.targetFor(m2.id).enabled, isFalse, reason: '新屏默认不投放');
      expect(aligned.targetFor(m2.id).name, m2.name);
      expect(aligned.targetFor('gone').region, CastRegion.centerStrip, reason: '拔屏别丢用户的框');
    });

    test('只有勾选且在线的屏才开窗', () {
      final settings = const CastSettings(targets: [
        CastTarget(monitorId: r'MONITOR\BOE0A74\0001', name: 'B', enabled: true),
        CastTarget(monitorId: r'MONITOR\DEL41A8\0004', name: 'D', enabled: false),
        CastTarget(monitorId: 'gone', name: '旧屏', enabled: true),
      ]);
      expect(settings.activeTargets([m1, m2]).map((t) => t.monitorId), [m1.id]);
    });

    test('右键关本屏：只落这一屏，最后一屏关掉时投放一起停', () {
      var settings = const CastSettings(enabled: true, targets: [
        CastTarget(monitorId: r'MONITOR\BOE0A74\0001', name: 'B', enabled: true),
        CastTarget(monitorId: r'MONITOR\DEL41A8\0004', name: 'D', enabled: true),
      ]);
      settings = settings.withoutScreen(m1.id);
      expect(settings.targetFor(m1.id).enabled, isFalse);
      expect(settings.targetFor(m2.id).enabled, isTrue);
      expect(settings.enabled, isTrue, reason: '还有屏在投，投放不能停');
      settings = settings.withoutScreen(m2.id);
      expect(settings.enabled, isFalse);
      expect(settings.targets.where((t) => t.enabled), isEmpty);
    });

    test('右键关全部：取消所有勾选，素材和布局保留', () {
      const settings = CastSettings(
        enabled: true,
        targets: [
          CastTarget(monitorId: r'MONITOR\BOE0A74\0001', name: 'B', enabled: true),
        ],
        placements: [
          CastPlacement(id: 'p1', materialId: 'lyric', screenId: r'MONITOR\BOE0A74\0001', x: .05, y: .6, width: .9, height: .3, z: 1),
        ],
      );
      final off = settings.withCastingOff();
      expect(off.enabled, isFalse);
      expect(off.targetFor(m1.id).enabled, isFalse);
      expect(off.placements, settings.placements, reason: '关投放不动布局');
    });

    test('勾任一屏即投放，最后一屏取消就停', () {
      var settings = const CastSettings();
      settings = settings.toggled(m1.id, m1.name, true);
      expect(settings.enabled, isTrue);
      settings = settings.toggled(m2.id, m2.name, true);
      expect(settings.enabled, isTrue);
      settings = settings.toggled(m1.id, m1.name, false);
      expect(settings.enabled, isTrue, reason: '还有一屏在投');
      settings = settings.toggled(m2.id, m2.name, false);
      expect(settings.enabled, isFalse);
    });

    test('勾选/模式/区域改动都落在对应屏上', () {
      var settings = const CastSettings();
      settings = settings.toggled(m1.id, m1.name, true);
      settings = settings.withMode(m1.id, CastMode.region);
      settings = settings.withRegion(m1.id, m1.name, CastRegion.bottomStrip);
      expect(settings.targets.length, 1);
      expect(settings.targetFor(m1.id),
          const CastTarget(monitorId: r'MONITOR\BOE0A74\0001', name: r'\\.\DISPLAY2',
              enabled: true, mode: CastMode.region, region: CastRegion.bottomStrip));
      // 改 m1 不该动 m2。
      expect(settings.toggled(m2.id, m2.name, true).targets.length, 2);
    });
  });

  group('投放尺寸折算', () {
    test('字号按投放区高度等比缩放', () {
      expect(castScaleFor(const Size(1920, 1080)), 1);
      expect(castScaleFor(const Size(1600, 540)), .5);
      expect(castScaleFor(Size.zero), 1, reason: '零高度不能把字号变成 0');
      expect(const CastStyle(fontSize: 88).fontSizeAt(const Size(1600, 900)), closeTo(73.33, .01));
    });

    test('工作区矩形用系统给的原点', () {
      expect(m1.workRect, const Rect.fromLTWH(-1920, 0, 1920, 1152));
      expect(m2.label, r'\\.\DISPLAY1 · 1600x852 · 150%');
    });
  });

  group('闲时引导语', () {
    const idle = CastMaterial(
      id: 'idle-1',
      type: CastMaterialType.idleText,
      name: '闲时引导语',
      text: '扫码点歌，想听什么自己点',
      fontSize: 72,
      fontWeight: 700,
      color: 0xFFFFE082,
      align: CastAlign.left,
      shadow: false,
      fontFamily: 'SimHei',
    );

    test('编码后解码回来，类型与排版都不丢', () {
      final back = CastSettings.decode(
        jsonEncode(const CastSettings(materials: [idle]).toJson()),
      ).materials.single;
      expect(back.type, CastMaterialType.idleText);
      expect(back.text, '扫码点歌，想听什么自己点');
      expect(back.fontSize, 72);
      expect(back.fontWeight, 700);
      expect(back.color, 0xFFFFE082);
      expect(back.align, CastAlign.left);
      expect(back.shadow, false);
      expect(back.fontFamily, 'SimHei');
      expect(back.isIdleOnly, isTrue);
    });

    test('排版字段和静态文字完全同构，只是类型串不同', () {
      const text = CastMaterial(id: 't1', type: CastMaterialType.text, text: '通告', fontSize: 72);
      expect(idle.toJson().keys.toSet(), text.toJson().keys.toSet());
      expect(idle.toJson()['t'], 'idleText');
      expect(text.toJson()['t'], 'text');
      expect(text.isIdleOnly, isFalse);
    });

    test('空内容的闲时引导语仍算「没东西可显示」', () {
      expect(const CastMaterial(id: 'e', type: CastMaterialType.idleText).hasContent, isFalse);
      expect(
        const CastMaterial(id: 'e', type: CastMaterialType.idleText, text: '  ').hasContent,
        isFalse,
      );
      expect(idle.hasContent, isTrue);
    });
  });
}
