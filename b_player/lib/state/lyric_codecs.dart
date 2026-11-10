import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 平台二进制歌词的解码层：酷狗 KRC / 酷我逐字 / 咪咕 MRC。
///
/// 这里只做「字节 → 明文」，明文的时间轴解析在 lrc.dart。
/// 解不出来一律返回 null，由调用方回退到行级 LRC——投放画面不能因为逐字失败而空着。

const List<int> _krcKey = [
  64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105,
];

/// 酷狗 KRC：base64 → 跳过 4 字节头 → 与密钥异或 → zlib → UTF-8。
String? decodeKrc(String base64Content) {
  final raw = base64Content.trim();
  if (raw.isEmpty) return null;
  try {
    return _krcFromBytes(base64Decode(raw));
  } catch (_) {
    return null;
  }
}

String? _krcFromBytes(List<int> raw) {
  if (raw.length <= 4) return null;
  final compressed = Uint8List(raw.length - 4);
  for (var i = 0; i < compressed.length; i++) {
    compressed[i] = (raw[i + 4] ^ _krcKey[i % _krcKey.length]) & 0xFF;
  }
  final text = _inflateText(compressed);
  return text?.replaceAll('\uFEFF', '');
}

const List<int> _kuwoKey = [121, 101, 101, 108, 105, 111, 110]; // "yeelion"

/// 酷我逐字：`TP=content\r\n...\r\n\r\n` + zlib → base64 → 与 "yeelion" 异或。
String? decodeKuwoWord(List<int> raw) {
  if (raw.length < 15) return null;
  final head = ascii.decode(raw.sublist(0, 10), allowInvalid: true).toLowerCase();
  if (!head.startsWith('tp=content')) return null;
  var body = -1;
  for (var i = 0; i + 3 < raw.length; i++) {
    if (raw[i] == 13 && raw[i + 1] == 10 && raw[i + 2] == 13 && raw[i + 3] == 10) {
      body = i + 4;
      break;
    }
  }
  if (body < 0) return null;
  final inflated = _inflateBytes(raw.sublist(body));
  if (inflated == null) return null;
  try {
    final b64 = utf8.decode(inflated).replaceAll(RegExp(r'\s'), '');
    final decoded = base64Decode(b64);
    for (var i = 0; i < decoded.length; i++) {
      decoded[i] = (decoded[i] ^ _kuwoKey[i % _kuwoKey.length]) & 0xFF;
    }
    return utf8.decode(decoded, allowMalformed: true).replaceAll('\uFEFF', '');
  } catch (_) {
    return null;
  }
}

const int _teaDelta = 0x9E3779B9;
const List<int> _miguKey = [
  27303562373562475,
  18014862372307051,
  22799692160172081,
  34058940340699235,
  30962724186095721,
  27303523720101991,
  27303523720101998,
  31244139033526382,
  28992395054481524,
];

/// 咪咕 MRC：hex → TEA（64 位分组）→ UTF-16LE 文本。
/// 部分曲目返回的已经是明文 LRC，直接原样带回。
String? decodeMiguMrc(String encrypted) {
  final raw = encrypted.trim();
  if (raw.isEmpty) return null;
  if (raw.startsWith('[')) return raw;
  final hex = raw.replaceAll(RegExp(r'\s'), '');
  if (hex.length < 32 || hex.length % 16 != 0) return null;
  final length = hex.length ~/ 16;
  if (length < 2 || length > 65536) return null;

  final data = Int64List(length);
  for (var i = 0; i < length; i++) {
    final high = int.tryParse(hex.substring(i * 16, i * 16 + 8), radix: 16);
    final low = int.tryParse(hex.substring(i * 16 + 8, i * 16 + 16), radix: 16);
    if (high == null || low == null) return null;
    data[i] = (high << 32) | low;
  }

  var sum = (6 + 52 ~/ length) * _teaDelta;
  var last = data[0];
  while (sum != 0) {
    final e = (sum >> 2) & 3;
    for (var i = length - 1; i > 0; i--) {
      final before = data[i - 1];
      last = data[i] - _teaMix(last, before, sum, _miguKey[(i & 3) ^ e]);
      data[i] = last;
    }
    last = data[0] - _teaMix(last, data[length - 1], sum, _miguKey[e]);
    data[0] = last;
    sum -= _teaDelta;
  }

  final units = <int>[];
  for (final value in data) {
    units
      ..add(value & 0xFFFF)
      ..add((value >> 16) & 0xFFFF)
      ..add((value >> 32) & 0xFFFF)
      ..add((value >> 48) & 0xFFFF);
  }
  return String.fromCharCodes(units).replaceAll('\u0000', '').replaceAll('\uFEFF', '');
}

int _teaMix(int current, int previous, int sum, int key) =>
    ((current ^ sum) + (previous ^ key)) ^
    (((previous >> 5) ^ (current << 2)) + ((current >> 3) ^ (previous << 4)));

String? _inflateText(List<int> data) {
  try {
    return utf8.decode(ZLibDecoder().convert(data), allowMalformed: true);
  } catch (_) {
    return null;
  }
}

List<int>? _inflateBytes(List<int> data) {
  try {
    return ZLibDecoder().convert(data);
  } catch (_) {
    return null;
  }
}
