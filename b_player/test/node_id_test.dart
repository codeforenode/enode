import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/edge/node_id.dart';

/// 节点 ID 是接入方的绑定键，改生成方式时最要紧的是「不能悄悄变」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(NodeIdentity.resetCacheForTest);

  test('首次冷启动生成随机 ID，格式正确且同进程内稳定', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await NodeIdentity.ensure();
    final b = await NodeIdentity.ensure();
    expect(a, matches(RegExp(r'^nd-[0-9a-f]{16}$')));
    expect(b, a);
    expect(NodeIdentity.cached, a);
  });

  test('落盘后重新冷启动仍是同一个 ID', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await NodeIdentity.ensure();

    NodeIdentity.resetCacheForTest();
    final again = await NodeIdentity.ensure();
    expect(again, first);
  });

  test('老版本已经存下的 ID 一律沿用，不重新生成', () async {
    const legacy = 'nd-3f1a9c02b7d84e51';
    SharedPreferences.setMockInitialValues({'edge.node.id': legacy});
    expect(await NodeIdentity.ensure(), legacy);
  });

  test('落盘值格式不对时才重新生成', () async {
    SharedPreferences.setMockInitialValues({'edge.node.id': 'nd-not-a-real-id'});
    final id = await NodeIdentity.ensure();
    expect(id, matches(RegExp(r'^nd-[0-9a-f]{16}$')));
    expect(id, isNot('nd-not-a-real-id'));
  });
}
