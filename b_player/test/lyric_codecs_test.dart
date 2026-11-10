import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/state/lrc.dart';
import 'package:b_player/state/lyric_codecs.dart';

// 由已知明文 + 各平台密钥离线生成，固定住「字节 → 明文」这一段，改错密钥/压缩顺序会立刻失败。
const _krcFixture = 'AQIDBDjb6kGOA0B3Yb6EHB7jW1mQdtEMhwK1QZW0wbNgT2Bp13NonA==';
const _kuwoFixture =
    'VFA9Y29udGVudA0KDQp4nPNMNwl0L48Ki3AtN0l0j6yMMDR1CQsLcg4Ps6gKCgsKinDLcQl3zQkLDquIyCg1L0j3zTKPcg+1BQAK1hKF';

void main() {
  test('decodeKrc：跳过 4 字节头 → 异或 → zlib', () {
    final text = decodeKrc(_krcFixture);
    expect(text, '[0,1000]<0,500,0>逐<500,500,0>字');

    final lines = parseLyric(text!, format: 'krc');
    expect(lines, hasLength(1));
    expect(lines.first.text, '逐字');
    expect(lines.first.words, hasLength(2));
    expect(lines.first.words.first, (startMs: 0, endMs: 500, text: '逐'));
    expect(lines.first.words.last, (startMs: 500, endMs: 1000, text: '字'));
  });

  test('decodeKrc：坏数据返回 null，交给调用方回退 LRC', () {
    expect(decodeKrc(''), isNull);
    expect(decodeKrc('不是 base64'), isNull);
    expect(decodeKrc(base64Encode(utf8.encode('plain lrc'))), isNull);
  });

  test('decodeKuwoWord：TP 头 + zlib + base64 + yeelion 异或', () {
    final text = decodeKuwoWord(base64Decode(_kuwoFixture));
    expect(text, contains('[kuwo:25]'));
    expect(text, contains('逐字'));

    final lines = parseLyric(text!, format: 'kuwo');
    expect(lines, hasLength(1));
    expect(lines.first.startMs, 1000);
    expect(lines.first.words.single, (startMs: 1500, endMs: 1900, text: '逐字'));
  });

  test('decodeKuwoWord：没有 TP 头或 body 损坏时返回 null', () {
    expect(decodeKuwoWord(utf8.encode('{"data":{}}')), isNull);
    expect(decodeKuwoWord(utf8.encode('TP=content\r\n\r\nnot zlib')), isNull);
  });

  test('decodeMiguMrc：明文 LRC 原样带回，坏 hex 返回 null', () {
    expect(decodeMiguMrc('[00:01.00]咪咕'), '[00:01.00]咪咕');
    expect(decodeMiguMrc('zzzz'), isNull);
    expect(decodeMiguMrc('0123'), isNull);
  });
}
