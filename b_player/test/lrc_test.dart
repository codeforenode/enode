import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/state/lrc.dart';

void main() {
  group('parseLrc', () {
    test('识别 mm:ss / mm:ss.x / mm:ss.xx / mm:ss.xxx', () {
      final lines = parseLrc('[00:00.00]a\n[01:02]b\n[03:04.5]c\n[05:06.75]d\n[07:08.500]e');
      expect(lines.map((l) => l.startMs), [0, 62000, 184500, 306750, 428500]);
      expect(lines.map((l) => l.text), ['a', 'b', 'c', 'd', 'e']);
    });

    test('同一行多个标签展开成多条并按时间排序', () {
      final lines = parseLrc('[00:20.00][00:10.00]副歌');
      expect(lines.length, 2);
      expect(lines.first.startMs, 10000);
      expect(lines.last.startMs, 20000);
      expect(lines.every((l) => l.text == '副歌'), isTrue);
    });

    test('忽略元信息行、空文本与非法时间戳', () {
      final lines = parseLrc('[ti:歌名]\n[ar:歌手]\n[by:某人]\n[00:05.00]\n[ab:cd]坏行\n[00:08.00]正文');
      expect(lines.map((l) => l.text), ['正文']);
    });

    test('CRLF 与行首空格不影响解析', () {
      final lines = parseLrc('  [00:03.00]第一行\r\n[00:06.00]第二行\r\n');
      expect(lines.map((l) => l.startMs), [3000, 6000]);
      expect(lines.first.text, '第一行');
    });
  });

  group('lyricIndexAt', () {
    final lines = parseLrc('[00:08.00]一\n[00:16.00]二\n[01:20.00]三');

    test('第一句之前返回 -1', () {
      expect(lyricIndexAt(lines, 7999), -1);
      expect(lyricIndexAt(lines, 0), -1);
    });

    test('命中最近一句且含边界', () {
      expect(lyricIndexAt(lines, 8000), 0);
      expect(lyricIndexAt(lines, 15999), 0);
      expect(lyricIndexAt(lines, 20000), 1);
      expect(lyricIndexAt(lines, 80000), 2);
      expect(lyricIndexAt(lines, 999999), 2);
    });

    test('空歌词返回 -1', () {
      expect(lyricIndexAt(const [], 1000), -1);
    });
  });

  group('逐字格式', () {
    List<List<Object>> words(LyricLine line) =>
        [for (final w in line.words) [w.startMs, w.endMs, w.text]];

    test('YRC：标记在前，字时间是绝对毫秒', () {
      final lines = parseLyric(
        '[1000,3000](1000,500,0)你(1500,400,0)好\n[4000,2000](4000,800,0)再见',
        format: 'yrc',
      );
      expect(lines.map((l) => l.text), ['你好', '再见']);
      expect(lines.map((l) => l.startMs), [1000, 4000]);
      expect(lines.map((l) => l.endMs), [4000, 6000]);
      expect(words(lines.first), [
        [1000, 1500, '你'],
        [1500, 1900, '好'],
      ]);
      expect(words(lines.last), [
        [4000, 4800, '再见'],
      ]);
    });

    test('KRC：尖括号偏移相对行首', () {
      final lines = parseLyric('[1000,3000]<0,500,0>你<500,400,0>好', format: 'krc');
      expect(lines.single.text, '你好');
      expect(lines.single.endMs, 4000);
      expect(words(lines.single), [
        [1000, 1500, '你'],
        [1500, 1900, '好'],
      ]);
    });

    test('QRC：文字在前，标记在后且为绝对时间', () {
      final lines = parseLyric(
        '[1000,3000]你(1000,500)好(1500,400)\n[4000,2000]再见(4000,800)',
        format: 'qrc',
      );
      expect(lines.map((l) => l.text), ['你好', '再见']);
      expect(words(lines.first), [
        [1000, 1500, '你'],
        [1500, 1900, '好'],
      ]);
      expect(words(lines.last), [
        [4000, 4800, '再见'],
      ]);
    });

    test('MRC：标记在文字之后，字时间绝对', () {
      final lines = parseLyric(
        '[1000,3000]你(1000,500)好(1500,400)\n[5000,2000]再(5000,300)见(5300,300)',
        format: 'mrc',
      );
      expect(lines.map((l) => l.text), ['你好', '再见']);
      expect(words(lines.first), [
        [1000, 1500, '你'],
        [1500, 1900, '好'],
      ]);
    });

    test('酷我：八进制基数换算字起止', () {
      final lines = parseLyric(
        '[kuwo:25]\n[00:01.00]<1400,600,0>你\n[00:04.00]<1400,600,0>好',
        format: 'kuwo',
      );
      expect(lines.map((l) => l.text), ['你', '好']);
      expect(words(lines.first), [
        [1500, 1900, '你'],
      ]);
      expect(words(lines.last), [
        [4500, 4900, '好'],
      ]);
    });

    test('AWLRC：尖括号偏移相对行首', () {
      final lines = parseLyric('[00:01.00]你<0,500>好<500,400>', format: 'awlrc');
      expect(lines.single.text, '你好');
      expect(lines.single.endMs, 1900);
      expect(words(lines.single), [
        [1000, 1500, '你'],
        [1500, 1900, '好'],
      ]);
    });

    test('增强 LRC：行内 <mm:ss.xx> 标签', () {
      final lines = parseLrc('[00:01.00]<00:01.00>你<00:01.50>好');
      expect(lines.single.words.length, 2);
      expect(words(lines.single), [
        [1000, 1500, '你'],
        [1500, 2000, '好'],
      ]);
    });

    test('offset 同时平移行与字', () {
      expect(parseLrc('[offset:200]\n[00:01.00]一').single.startMs, 800);
      final shifted = parseLrc('[offset:200][00:01.00]<00:01.00>你<00:01.50>好');
      expect(shifted.single.words.first.startMs, 800);
      expect(shifted.single.words.last.startMs, 1300);
    });

    test('toLrcText 输出毫秒级时间戳', () {
      final lines = parseLyric('[1000,3000](1000,500,0)你(1500,400,0)好', format: 'yrc');
      expect(toLrcText(lines), '[00:01.000]你好');
      expect(parseLrc(toLrcText(lines)).single.text, '你好');
    });
  });
}
