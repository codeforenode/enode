import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'package:b_player/edge/config.dart';
import 'package:b_player/edge/edge_node.dart';
import 'package:b_player/edge/library.dart';
import 'package:b_player/edge/protocol.dart';

/// 需要真实 broker：`EDGE_BROKER=1 flutter test test/edge_integration_test.dart`。
/// 主要用于联调前自检，不进入普通测试默认执行。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = Platform.environment['EDGE_BROKER'] == '1';
  const host = '127.0.0.1';
  const port = 1883;

  test('边缘节点：健康保留 + 检索/入队 RPC 闭环', () async {
    final lib = Library.demo(200);
    final added = <String>[];
    final events = <Map<String, Object?>>[];
    late final EdgeNode node;
    node = EdgeNode(
      search: (q, offset, limit) async => lib.search(q, offset: offset, limit: limit),
      enqueue: (req) {
        added.add(req.seat ?? '');
        node.notifyQueueChanged();
        return const EnqueueResult.accepted(1);
      },
      snapshot: () => {'player': null, 'queue': const []},
      health: () => {'queueDepth': 0, 'playing': true, 'library': {'count': 200}},
      lyric: () async => {
        'trackKey': 'local:00000',
        'format': 'lrc',
        'offsetMs': 0,
        'text': '[00:00.00]测试歌词 - 测试歌手\n[00:08.00]第二行',
      },
      config: const MqttConfig(host: host, port: port),
    );
    addTearDown(node.dispose);

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!node.connected && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(node.connected, isTrue, reason: node.lastError ?? '未连接');
    final nodeId = node.nodeId;
    expect(validNodeId(nodeId), isTrue);

    final probe = MqttServerClient.withPort(host, 'itest-probe-${DateTime.now().microsecondsSinceEpoch}', port);
    probe.logging(on: false);
    probe.setProtocolV311();
    // ignore: avoid_print
    print('probe clientId=${probe.clientIdentifier}');
    await probe.connect();
    addTearDown(() => probe.disconnect());

    final responses = <String, Completer<Map<String, Object?>>>{};
    final eventsDone = Completer<Map<String, Object?>>();
    probe.updates?.listen((list) {
      for (final m in list) {
        final p = m.payload;
        if (p is! MqttPublishMessage) continue;
        final text = MqttPublishPayload.bytesToStringAsString(p.payload.message);
        if (m.topic.endsWith('/events')) {
          final parsed = jsonDecode(text);
          if (parsed is Map) events.add(parsed.cast<String, Object?>());
          if (jsonEncode(parsed).contains('"queue.update"') && !eventsDone.isCompleted) {
            eventsDone.complete(parsed.cast<String, Object?>());
          }
          continue;
        }
        if (m.topic.contains('/rpc/')) {
          final nonce = m.topic.substring(m.topic.lastIndexOf('/') + 1);
          final c = responses[nonce];
          if (c != null && !c.isCompleted && jsonDecode(text) is Map) {
            c.complete((jsonDecode(text) as Map).cast<String, Object?>());
          }
        }
      }
    });

    final searchTopic = searchRespTopic(defaultTopicPrefix, nodeId, '+');
    final enqueueTopic = enqueueRespTopic(defaultTopicPrefix, nodeId, '+');
    probe.subscribe(searchTopic, MqttQos.atLeastOnce);
    probe.subscribe(enqueueTopic, MqttQos.atLeastOnce);
    probe.subscribe(eventsTopic(defaultTopicPrefix, nodeId), MqttQos.atLeastOnce);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    Future<Map<String, Object?>> call(String type, String reqTopic, Map<String, Object?> payload) {
      final nonce = 'n${DateTime.now().microsecondsSinceEpoch}';
      final c = Completer<Map<String, Object?>>();
      responses[nonce] = c;
      final body = EdgeEnvelope(type: type, node: nodeId, ts: _now(), nonce: nonce, payload: payload);
      final builder = MqttClientPayloadBuilder()..addUTF8String(jsonEncode(body.toJson()));
      probe.publishMessage(reqTopic, MqttQos.atLeastOnce, builder.payload!);
      return c.future.timeout(const Duration(seconds: 6));
    }

    final searchResp = await call(
      tSearchReq,
      node.searchReqTopicName,
      {'q': '晴天', 'offset': 0, 'limit': 3},
    );
    final searchPayload = (searchResp['payload'] as Map).cast<String, Object?>();
    expect(searchPayload['ok'], isTrue);
    final items = (searchPayload['items'] as List).cast<Map>();
    expect(items, isNotEmpty);
    expect(items.length, lessThanOrEqualTo(3));
    expect(searchPayload['total'], isA<int>());

    final hit = items.first.cast<String, Object?>();
    final enqueueResp = await call(
      tEnqueueReq,
      node.enqueueReqTopicName,
      {
        'trackKey': hit['trackKey'],
        'requestId': 'req-${DateTime.now().millisecondsSinceEpoch}',
        'guest': {'seat': '9 号桌', 'tag': 'itest'},
      },
    );
    final enqueuePayload = (enqueueResp['payload'] as Map).cast<String, Object?>();
    expect(enqueuePayload['ok'], isTrue);
    expect(enqueuePayload['result'], 'accepted');
    expect(added, ['9 号桌']);

    final update = await eventsDone.future.timeout(const Duration(seconds: 6));
    expect(update['type'], eQueueUpdate);

    final fresh = MqttServerClient.withPort(host, 'itest-retained-${DateTime.now().microsecondsSinceEpoch}', port);
    fresh.logging(on: false);
    fresh.setProtocolV311();
    await fresh.connect();
    addTearDown(() => fresh.disconnect());
    final health = Completer<Map<String, Object?>>();
    final offline = Completer<Map<String, Object?>>();
    final lyricMsg = Completer<Map<String, Object?>>();
    fresh.updates?.listen((list) {
      for (final m in list) {
        final p = m.payload;
        if (p is! MqttPublishMessage) continue;
        final text = MqttPublishPayload.bytesToStringAsString(p.payload.message);
        final parsed = jsonDecode(text);
        if (parsed is! Map) continue;
        if (m.topic == healthTopic(defaultTopicPrefix, nodeId)) {
          final body = parsed.cast<String, Object?>();
          if (body['state'] == stateOffline) {
            if (!offline.isCompleted) offline.complete(body);
          } else if (!health.isCompleted) {
            health.complete(body);
          }
        }
        if (m.topic == lyricTopic(defaultTopicPrefix, nodeId) && !lyricMsg.isCompleted) {
          lyricMsg.complete(parsed.cast<String, Object?>());
        }
      }
    });
    fresh.subscribe(healthTopic(defaultTopicPrefix, nodeId), MqttQos.atLeastOnce);
    fresh.subscribe(lyricTopic(defaultTopicPrefix, nodeId), MqttQos.atLeastOnce);
    final healthMsg = await health.future.timeout(const Duration(seconds: 6));
    expect(healthMsg['state'], stateOnline);
    expect(healthMsg['caps'], contains('search'));
    expect(healthMsg['node'], nodeId);

    final lyric = await lyricMsg.future.timeout(const Duration(seconds: 6));
    expect(lyric['node'], nodeId);
    expect(lyric['trackKey'], 'local:00000');
    expect(lyric['format'], 'lrc');
    expect(lyric['text'], contains('测试歌词'));
    expect((lyric['rev'] as String).length, 8);

    // 正常退出前补发的离线状态必须覆盖 retained health，中继立即能判定掉线。
    await node.publishOffline();
    final gone = await offline.future.timeout(const Duration(seconds: 6));
    expect(gone['state'], stateOffline);
    expect(gone['node'], nodeId);
  }, skip: enabled ? null : '设置 EDGE_BROKER=1 并启动本地 broker 后运行');
}

int _now() => DateTime.now().millisecondsSinceEpoch;
