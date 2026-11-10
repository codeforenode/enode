import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/state/cast_settings.dart';
import 'package:b_player/state/lrc.dart';
import 'package:b_player/ui/cast_lyric_view.dart';

const _style = CastStyle(
  lines: 1,
  fontSize: 88,
  strokeWidth: 0,
  shadow: false,
  showTitle: false,
  showArtist: false,
);

final _lines = <LyricLine>[
  (
    startMs: 0,
    endMs: 2000,
    text: 'ABC',
    words: const [
      (startMs: 400, endMs: 900, text: 'A'),
      (startMs: 900, endMs: 1400, text: 'B'),
      (startMs: 1400, endMs: 1900, text: 'C'),
    ],
  ),
];

Future<({int current, int other})> _paint(WidgetTester tester, int positionMs) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: Colors.black,
            child: CastLyricLayer(
              style: _style,
              box: const Size(600, 160),
              scale: 1,
              lines: _lines,
              index: 0,
              positionMs: positionMs,
            ),
          ),
        ),
      ),
    ),
  );
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final data = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
  final bytes = data!.buffer.asUint8List();
  var current = 0;
  var other = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
    if (r == 61 && g == 220 && b == 132) current++;
    if (r == 139 && g == 151 && b == 159) other++;
  }
  return (current: current, other: other);
}

void main() {
  group('显示行数', () {
    const lines = <LyricLine>[
      (startMs: 0, endMs: 1000, text: '上一句', words: <LyricWord>[]),
      (startMs: 1000, endMs: 2000, text: '当前句', words: <LyricWord>[]),
      (startMs: 2000, endMs: 3000, text: '下一句', words: <LyricWord>[]),
    ];
    List<String> texts(CastStyle style, int index) =>
        [for (final row in castLyricRows(style, lines, index)) row.text];

    test('1 行只显示当前句', () {
      expect(texts(const CastStyle(lines: 1), 1), ['当前句']);
    });

    test('2 行显示当前句与下一句', () {
      expect(texts(const CastStyle(lines: 2), 1), ['当前句', '下一句']);
    });

    test('3 行显示上一句、当前句与下一句', () {
      expect(texts(const CastStyle(lines: 3), 1), ['上一句', '当前句', '下一句']);
    });

    test('最后一句没有下一句时只留当前句', () {
      expect(texts(const CastStyle(lines: 2), 2), ['下一句']);
    });
  });

  group('超宽横滚', () {
    test('不超宽不滚', () {
      expect(castLyricScrollOffset(textWidth: 400, avail: 600, focus: 300), 0);
    });

    test('唱到前半句前不提前滚', () {
      expect(castLyricScrollOffset(textWidth: 1200, avail: 600, focus: 200), 0);
      expect(castLyricScrollOffset(textWidth: 1200, avail: 600, focus: 390), 0);
    });

    test('焦点保持在可视区 65% 处', () {
      expect(castLyricScrollOffset(textWidth: 1200, avail: 600, focus: 600), 210);
      expect(castLyricScrollOffset(textWidth: 1200, avail: 600, focus: 900, anchor: .5), 600);
    });

    test('滚到行尾就停在最大位移，最后一个字停在右边缘', () {
      expect(castLyricScrollOffset(textWidth: 1200, avail: 600, focus: 1200), 600);
      expect(castLyricScrollOffset(textWidth: 1200, avail: 600, focus: 5000), 600);
    });
  });

  testWidgets('超长当前句：字号不变，随演唱向左滚动', (tester) async {
    const long = '这是一句特别长的歌词用来确认它不会被程序缩小而是跟着演唱向左滚动显示';
    const lines = <LyricLine>[(startMs: 0, endMs: 4000, text: long, words: <LyricWord>[])];

    Future<Uint8List> shot(int positionMs) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: Colors.black,
                child: CastLyricLayer(
                  style: _style,
                  box: const Size(600, 160),
                  scale: 1,
                  lines: lines,
                  index: 0,
                  positionMs: positionMs,
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
      return data!.buffer.asUint8List();
    }

    ({int top, int bottom}) glyphBox(Uint8List bytes) {
      var top = 1 << 30, bottom = -1;
      for (var y = 0; y < 160; y++) {
        for (var x = 0; x < 600; x++) {
          final i = (y * 600 + x) * 4;
          if (bytes[i] == 61 && bytes[i + 1] == 220 && bytes[i + 2] == 132) {
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
      }
      return (top: top, bottom: bottom);
    }

    final start = await shot(0);
    final end = await shot(3900);
    // 旧实现会把这行缩到十几像素；现在必须保持 88 号字的高度（Ahem 字形约 88px）。
    expect(glyphBox(start).bottom - glyphBox(start).top, greaterThan(60));
    expect(glyphBox(end).bottom - glyphBox(end).top, greaterThan(60));
    // 同一句在不同演唱进度下画面必须变化，证明字在向左走。
    expect(end, isNot(equals(start)));
  });

  testWidgets('非当前句透明度：下一句变淡，当前句不受影响', (tester) async {
    const lines = <LyricLine>[
      (startMs: 0, endMs: 2000, text: 'AAA', words: <LyricWord>[]),
      (startMs: 2000, endMs: 4000, text: 'BBB', words: <LyricWord>[]),
    ];

    Future<Uint8List> shot(double opacity) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: Colors.black,
                  child: CastLyricLayer(
                    style: CastStyle(
                      lines: 2,
                      fontSize: 88,
                      fontWeight: 400,
                      strokeWidth: 0,
                      shadow: false,
                      showTitle: false,
                      showArtist: false,
                      otherOpacity: opacity,
                    ),
                    box: const Size(600, 400),
                    scale: 1,
                    lines: lines,
                    index: 0,
                    positionMs: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
      return data!.buffer.asUint8List();
    }

    int brightest(Uint8List bytes, int y0, int y1) {
      var max = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = 0; x < 600; x++) {
          final i = (y * 600 + x) * 4;
          final sum = bytes[i] + bytes[i + 1] + bytes[i + 2];
          if (sum > max) max = sum;
        }
      }
      return max;
    }

    List<int> band(Uint8List bytes, int y0, int y1) => bytes.sublist(y0 * 600 * 4, y1 * 600 * 4);

    final full = await shot(100);
    final dim = await shot(30);
    expect(brightest(full, 200, 340), greaterThan(300), reason: '默认下一句不透明');
    expect(brightest(dim, 200, 340), lessThan(200), reason: '30% 后下一句明显变暗');
    expect(band(dim, 60, 200), band(full, 60, 200), reason: '当前句不跟着变淡');
  });

  testWidgets('逐字扫光：未唱到亮色，唱到的宽度按时间增长', (tester) async {
    final before = await _paint(tester, 0);
    expect(before.current, 0, reason: '第一字还没开始，整句都是暗色');
    expect(before.other, greaterThan(0));

    final early = await _paint(tester, 650);
    final late = await _paint(tester, 1900);
    expect(early.current, greaterThan(0));
    expect(late.current, greaterThan(early.current), reason: '唱得越久扫光越宽');
    expect(late.other, 0, reason: '整句唱完不留暗色');
  });

  testWidgets('逐字扫光：没有逐字时间的行仍按整行高亮', (tester) async {
    const plain = <LyricLine>[(startMs: 0, endMs: 2000, text: 'ABC', words: <LyricWord>[])];
    final key = GlobalKey();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: Colors.black,
              child: CastLyricLayer(
                style: _style,
                box: const Size(600, 160),
                scale: 1,
                lines: plain,
                index: 0,
                positionMs: 0,
              ),
            ),
          ),
        ),
      ),
    );
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
    final bytes = data!.buffer.asUint8List();
    var current = 0;
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      if (bytes[i] == 61 && bytes[i + 1] == 220 && bytes[i + 2] == 132) current++;
    }
    expect(current, greaterThan(0), reason: '行级歌词沿用旧行为：当前句整行亮色');
  });
}
