import 'dart:ui';

import 'package:b_player/state/cast_settings.dart';
import 'package:b_player/state/lrc.dart';
import 'package:b_player/desktop/cast_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('样式逐字段进页面：颜色保持 ARGB 整数，枚举用名字', () {
    final map = castWebStyle(const CastStyle(
      lines: 3,
      fontFamily: 'SimHei',
      fontSize: 96,
      fontWeight: 700,
      currentColor: 0xFF3DDC84,
      otherColor: 0x808B979F,
      otherOpacity: 40,
      strokeWidth: 4,
      shadow: false,
      background: CastBackground.gradient,
      align: CastAlign.right,
      vertical: 62,
      offsetMs: -180,
    ));
    expect(map['lines'], 3);
    expect(map['fontFamily'], 'SimHei');
    expect(map['fontSize'], 96);
    expect(map['fontWeight'], 700);
    expect(map['currentColor'], 0xFF3DDC84);
    expect(map['otherColor'], 0x808B979F);
    expect(map['otherOpacity'], 40);
    expect(map['strokeWidth'], 4);
    expect(map['shadow'], false);
    expect(map['background'], 'gradient');
    expect(map['align'], 'right');
    expect(map['vertical'], 62);
    expect(map['offsetMs'], -180);
  });

  test('背景图换成页面能读的 file:// 地址，空路径就是空串', () {
    final map = castWebStyle(const CastStyle(background: CastBackground.image, imagePath: r'D:\Music\背景 图.jpg'));
    final url = map['imagePath'] as String;
    expect(url, startsWith('file://'));
    expect(Uri.parse(url).toFilePath(), endsWith(r'背景 图.jpg'));
    expect(castWebStyle(CastStyle.defaults)['imagePath'], '');
  });

  test('几何折算：k 是投放区高度对 1080 的比', () {
    expect(castWebGeometry(const Size(1920, 1080)), {'k': 1.0, 'w': 1920.0, 'h': 1080.0});
    final small = castWebGeometry(const Size(800, 450));
    expect(small['k'], closeTo(0.4167, 0.0002));
    expect(castWebGeometry(const Size(800, 0))['k'], 1);
  });

  test('锚点整包推给页面：位置 + 墙钟 + 是否在放', () {
    expect(
      castApplyScript(castWebTick(positionMs: 4200, wallMs: 999, playing: true)),
      contains('"tick":{"positionMs":4200,"wallMs":999,"playing":true}'),
    );
  });

  test('歌词推 [起始, 文本, 行尾, 逐字?]，附带歌名与时长', () {
    final payload = castWebLyric(
      const [
        (
          startMs: 0,
          endMs: 3500,
          text: '第一句',
          words: [(startMs: 0, endMs: 1000, text: '第一'), (startMs: 1000, endMs: 3000, text: '句')],
        ),
        (startMs: 3500, endMs: 7000, text: '第二句', words: <LyricWord>[]),
      ],
      title: '青花瓷',
      artist: '周杰伦',
      seat: 'A12',
      durationMs: 210000,
    );
    expect(payload['lines'], [
      [
        0,
        '第一句',
        3500,
        [
          [0, 1000, '第一'],
          [1000, 3000, '句'],
        ],
      ],
      [3500, '第二句', 7000],
    ]);
    expect(payload['nowPlaying'], {'title': '青花瓷', 'artist': '周杰伦', 'seat': 'A12', 'durationMs': 210000});
    // 行文本走 JSON 转义，引号与换行不会把 JS 拼坏。
    final js = castApplyScript(castWebLyric(const [
      (startMs: 0, endMs: 5000, text: '说"唱"\n下一行', words: <LyricWord>[]),
    ]));
    expect(js, contains(r'\"'));
    expect(js, contains(r'\n'));
  });

  test('投放页地址落在打包产物的 flutter_assets 里', () {
    final url = castPageUrl(executablePath: r'C:\Program Files\eNode\eNode.exe');
    final path = Uri.parse(url).toFilePath().replaceAll(r'\', '/');
    expect(path, endsWith('/data/flutter_assets/assets/cast/lyric.html'));
  });
}
