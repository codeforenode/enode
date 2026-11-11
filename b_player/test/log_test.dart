import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/log.dart';

/// 日志会离开本机（店家发给开发者），脱敏规则是安全边界，必须被测住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('脱敏', () {
    test('URL 的 query 整个抹掉（直链签名、token 常在这里）', () {
      final out = EnodeLog.sanitize('播放 https://cdn.example.com/a.mp3?sign=abc123&token=xyz789');
      expect(out, '播放 https://cdn.example.com/a.mp3?<redacted>');
      expect(out, isNot(contains('abc123')));
      expect(out, isNot(contains('xyz789')));
    });

    test('URL 里的账号密码段抹掉', () {
      final out = EnodeLog.sanitize('connect mqtt://alice:s3cret@broker.example.com:1883');
      expect(out, 'connect mqtt://<redacted>@broker.example.com:1883');
      expect(out, isNot(contains('s3cret')));
    });

    test('常见敏感键的值抹掉，键名保留便于排障', () {
      final out = EnodeLog.sanitize('password=123456 token: abc.def "apiKey":"sk-xxx"');
      expect(out, isNot(contains('123456')));
      expect(out, isNot(contains('abc.def')));
      expect(out, isNot(contains('sk-xxx')));
      expect(out, contains('password=<redacted>'));
      expect(out, contains('token=<redacted>'));
    });

    test('普通文本不被误伤', () {
      const line = '开播《晴天》 https://cdn.example.com 队列 3 首';
      expect(EnodeLog.sanitize(line), line);
    });
  });

  test('日志落盘：带级别与 tag，且内容已脱敏', () async {
    final dir = await Directory.systemTemp.createTemp('enode_log_test');
    addTearDown(() async {
      await dir.delete(recursive: true);
    });

    await EnodeLog.init(dir: dir);
    EnodeLog.i('test', 'hello password=abc');
    EnodeLog.w('test', 'warn 一条', StateError('boom'));
    await EnodeLog.close();

    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.log')).toList();
    expect(files, hasLength(1));

    final text = await files.single.readAsString();
    expect(text, contains('I [test] hello'));
    expect(text, contains('W [test]'));
    expect(text, contains('boom'));
    expect(text, isNot(contains('password=abc')));
  });

  test('上次没正常退出，下次启动要自己说出来', () async {
    final dir = await Directory.systemTemp.createTemp('enode_log_mark');
    addTearDown(() async {
      await EnodeLog.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    String logText() {
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.log'));
      return files.isEmpty ? '' : files.map((f) => f.readAsStringSync()).join();
    }

    // 第一次启动后「崩溃」：只 close，不调 markCleanExit。
    await EnodeLog.init(dir: dir);
    expect(File('${dir.path}/.running').existsSync(), isTrue, reason: '启动就该留下运行标记');
    await EnodeLog.close();

    // 第二次启动应当认出上次没走完（close 会 flush，之后才能读）。
    await EnodeLog.init(dir: dir);
    await EnodeLog.close();
    expect(logText(), contains('上次没有正常退出'));
    expect(File('${dir.path}/.running').existsSync(), isTrue, reason: '这次又写下了新标记');

    // 正常退出后标记该被撤掉。
    await EnodeLog.markCleanExit();
    expect(File('${dir.path}/.running').existsSync(), isFalse);

    // 再启动一次，不该重复报警。
    await EnodeLog.init(dir: dir);
    await EnodeLog.markCleanExit();
    await EnodeLog.close();
    expect('上次没有正常退出'.allMatches(logText()).length, 1, reason: '只有那一次崩溃该被记下');
  });
}
