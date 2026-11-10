import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/edge/config.dart';
import 'package:b_player/edge/mqtt_paste.dart';

const _base = MqttConfig(
  host: 'old.example.com',
  port: 1883,
  username: 'old',
  password: 'old',
  topicPrefix: 'bp/v1',
  clientId: 'cid-1',
  enabled: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('粘贴识别', () {
    test('mqtt:// 整串：账号密码地址端口一次认清', () {
      final c = parseMqttPaste('mqtt://venue:p%40ss@broker.example.com:1883', base: _base);
      expect(c.host, 'broker.example.com');
      expect(c.port, 1883);
      expect(c.tls, isFalse);
      expect(c.username, 'venue');
      expect(c.password, 'p@ss');
      // 连接信息里没有的字段沿用当前值。
      expect(c.topicPrefix, 'bp/v1');
      expect(c.clientId, 'cid-1');
      expect(c.enabled, isTrue);
    });

    test('mqtts:// 默认 8883 并开 TLS', () {
      final c = parseMqttPaste('mqtts://user:secret@host.example.com', base: _base);
      expect(c.port, 8883);
      expect(c.tls, isTrue);
    });

    test('地址:端口 也认', () {
      final c = parseMqttPaste('192.168.1.10:1884', base: _base);
      expect(c.host, '192.168.1.10');
      expect(c.port, 1884);
      expect(c.tls, isFalse);
      expect(c.username, isEmpty);
      expect(c.password, isEmpty);
    });

    test('省略协议头：账号:密码@地址:端口', () {
      final c = parseMqttPaste('venue:secret@broker.example.com:1883', base: _base);
      expect(c.host, 'broker.example.com');
      expect(c.username, 'venue');
      expect(c.password, 'secret');
    });

    test('多行中文键值（全角冒号）', () {
      final c = parseMqttPaste(
        'Broker：192.168.1.10\n端口: 1884\n用户名: venue\n密码: p@ss:1',
        base: _base,
      );
      expect(c.host, '192.168.1.10');
      expect(c.port, 1884);
      expect(c.username, 'venue');
      expect(c.password, 'p@ss:1');
    });

    test('多行键值里的加密标记生效', () {
      final c = parseMqttPaste(
        'Broker: broker.example.com\n端口: 8883\n账号: venue\n密码: secret\n加密: 是',
        base: _base,
      );
      expect(c.host, 'broker.example.com');
      expect(c.port, 8883);
      expect(c.tls, isTrue);
      expect(c.username, 'venue');
      expect(c.password, 'secret');
    });

    test('加密且没写端口时按 8883', () {
      final c = parseMqttPaste('Broker: broker.example.com\ntls: true', base: _base);
      expect(c.tls, isTrue);
      expect(c.port, 8883);
    });

    test('加密: 否 保持明文与 1883', () {
      final c = parseMqttPaste('Broker: broker.example.com\n加密: 否', base: _base);
      expect(c.tls, isFalse);
      expect(c.port, 1883);
    });

    test('多行裸值：地址/端口/账号/密码', () {
      final c = parseMqttPaste('broker.example.com\n1886\nvenue\nsecret pass', base: _base);
      expect(c.host, 'broker.example.com');
      expect(c.port, 1886);
      expect(c.username, 'venue');
      expect(c.password, 'secret pass');
    });

    test('JSON', () {
      final c = parseMqttPaste(
        '{"host":"h.example.com","port":1885,"username":"u","password":"p","tls":true}',
        base: _base,
      );
      expect(c.host, 'h.example.com');
      expect(c.port, 1885);
      expect(c.tls, isTrue);
      expect(c.username, 'u');
      expect(c.password, 'p');
    });

    test('空串和看不懂的内容给出可读错误', () {
      expect(() => parseMqttPaste('   ', base: _base), throwsA(isA<FormatException>()));
      expect(() => parseMqttPaste('完全不是连接信息', base: _base),
          throwsA(isA<FormatException>()));
    });

    test('ws/wss 明确拒绝，不装作能用', () {
      expect(
        () => parseMqttPaste('ws://broker.example.com:8083/mqtt', base: _base),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('参数落盘', () {
    test('多行中文标签：密码里的 # / ? } [ 原样保留', () {
      final c = parseMqttPaste('Broker: h.example.com\n端口: 1883\n账号: u\n密码: #a/b?c}[', base: _base);
      expect(c.host, 'h.example.com');
      expect(c.port, 1883);
      expect(c.username, 'u');
      expect(c.password, '#a/b?c}[');
    });

    test('默认配置不含任何内置凭据', () {
      const c = MqttConfig();
      expect(c.configured, isFalse);
      expect(c.host, isEmpty);
      expect(c.username, isEmpty);
      expect(c.password, isEmpty);
    });

    test('保存后能原样读回，清除后回到未配置', () async {
      SharedPreferences.setMockInitialValues({});
      const saved = MqttConfig(
        host: 'saved.example.com',
        port: 8883,
        tls: true,
        username: 'venue',
        password: "p#ss'1",
        topicPrefix: 'bp/v1',
        clientId: 'cid-2',
      );
      await MqttConfigStore.save(saved);
      final loaded = await MqttConfigStore.load();
      expect(loaded, isNotNull);
      expect(loaded!.host, 'saved.example.com');
      expect(loaded.port, 8883);
      expect(loaded.tls, isTrue);
      expect(loaded.username, 'venue');
      expect(loaded.password, "p#ss'1");

      await MqttConfigStore.clear();
      expect(await MqttConfigStore.load(), isNull);
    });

    test('坏配置不生效', () async {
      SharedPreferences.setMockInitialValues({'mqtt.config.v1': '{not json'});
      expect(await MqttConfigStore.load(), isNull);
    });
  });
}
