import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/desktop/cast_canvas.dart';
import 'package:b_player/state/cast_settings.dart';

void main() {
  const mat = CastMaterial(id: 'u1', type: CastMaterialType.url, url: 'https://ktv.example.com');
  // 与 CastCanvas.ensure 同一套布局：屏矩形（画布 px），screenIds 同序。
  const layout = <Map<String, Object?>>[
    {'x': 0.0, 'y': 0.0, 'w': 1920.0, 'h': 1040.0, 'k': 1.0},
    {'x': 1920.0, 'y': 0.0, 'w': 1600.0, 'h': 852.0, 'k': 1.0},
  ];
  final screenIds = ['main', 'second'];

  CastSettings settingsWith(List<CastPlacement> placements) => CastSettings(
        enabled: true,
        targets: const [
          CastTarget(monitorId: 'main', name: 'main'),
          CastTarget(monitorId: 'second', name: 'second'),
        ],
        materials: const [mat],
        placements: placements,
      );

  test('按百分比换算成画布像素矩形', () {
    final s = settingsWith(const [
      CastPlacement(id: 'p1', materialId: 'u1', screenId: 'main', x: 0.1, y: 0.2, width: 0.5, height: 0.4),
    ]);
    expect(urlMirrorCanvasRect(s, screenIds, layout, 'u1'),
        Rect.fromLTWH(0 + 192, 0 + 208, 960, 416));
  });

  test('跳过隐藏投放项，取第一块含它的屏', () {
    final s = settingsWith(const [
      CastPlacement(id: 'p0', materialId: 'u1', screenId: 'main', visible: false),
      CastPlacement(id: 'p1', materialId: 'u1', screenId: 'second', x: 0.0, y: 0.0, width: 1.0, height: 1.0),
    ]);
    expect(urlMirrorCanvasRect(s, screenIds, layout, 'u1'), Rect.fromLTWH(1920, 0, 1600, 852));
  });

  test('素材没投到任何屏时返回 null', () {
    final s = settingsWith(const []);
    expect(urlMirrorCanvasRect(s, screenIds, layout, 'u1'), isNull);
  });

  test('别的不相干投放项不参与匹配', () {
    const other = CastMaterial(id: 'u2', type: CastMaterialType.url, url: 'https://b.com');
    final s = CastSettings(
      materials: const [mat, other],
      placements: const [
        CastPlacement(id: 'p1', materialId: 'u2', screenId: 'main', x: 0.5, y: 0.5, width: 0.1, height: 0.1),
      ],
    );
    expect(urlMirrorCanvasRect(s, screenIds, layout, 'u1'), isNull);
  });
}
