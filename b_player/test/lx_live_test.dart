import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:b_player/edge/sources/lx_http.dart';
import 'package:b_player/edge/sources/lx_online_source.dart';
import 'package:b_player/edge/sources/lx_platforms.dart';

/// 真实网络自检：`ONLINE_LIVE=1 flutter test test/lx_live_test.dart`。
/// 普通测试默认跳过，避免 CI/离线环境依赖外部服务。
void main() {
  final enabled = Platform.environment['ONLINE_LIVE'] == '1';

  test('在线曲库真实链路：五平台检索 + 歌词 + 播放地址', () async {
    final client = http.Client();
    addTearDown(client.close);
    final httpLayer = LxHttp(client);
    final source = LxOnlineSource(client: client);

    for (final platform in const [
      KwPlatform(),
      KgPlatform(),
      MgPlatform(),
      TxPlatform(),
      WyPlatform(),
    ]) {
      final result = await platform.search(httpLayer, '晴天', page: 1, limit: 5);
      expect(result.tracks, isNotEmpty, reason: '${platform.label} 检索为空');

      // 单曲可能没有词，前几首里至少要有一首能取到，才算该平台歌词链路可用。
      String? found;
      for (final track in result.tracks) {
        try {
          final lyric = await platform.lyric(httpLayer, track);
          if (lyric.lyric.trim().isNotEmpty) {
            found = '${track.title}/${track.artist} ${lyric.lyric.length}字符';
            break;
          }
        } catch (_) {}
      }
      expect(found, isNotNull, reason: '${platform.label} 前 ${result.tracks.length} 首都没有歌词');
      // ignore: avoid_print
      print('${platform.label}: $found');

      // 播放地址按平台首曲逐个尝试，个别受限曲目失败不影响平台结论。
      Uri? playable;
      for (final track in result.tracks) {
        try {
          playable = await source.audioUri(track);
          break;
        } catch (_) {}
      }
      expect(playable, isNotNull, reason: '${platform.label} 播放地址全部兑换失败');
      final head = await client.head(playable!);
      expect(head.statusCode, anyOf(200, 206), reason: '${platform.label} 播放地址不可访问：${head.statusCode}');
      // ignore: avoid_print
      print('${platform.label} 播放地址: ${playable.host} (HTTP ${head.statusCode})');
    }

    final page = await source.search('晴天', limit: 10);
    expect(page.items, isNotEmpty);
  }, skip: enabled ? null : '设置 ONLINE_LIVE=1 后运行真实网络自检');
}
