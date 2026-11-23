import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/edge/sources/lx_source_entry.dart';

LxSourceEntry _entry(String id, String script) => LxSourceEntry(
      id: id,
      url: 'https://example.test/$id.js',
      script: script,
      meta: LxSourceMeta(name: id, version: '1.0.0', author: 'a'),
      updatedAt: 1,
      hash: LxSourceEntry.hashOf(script),
    );

String _script(String id) =>
    '/*\n * @name $id\n * @version 1.0.0\n * @author a\n */\nvar x = "$id";\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('enode_lx_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('脚本正文落到 scripts 目录，索引不带脚本', () async {
    final store = LxSourceStore(dir);
    await store.save([_entry('lx_a', _script('a')), _entry('lx_b', _script('b'))]);

    final index = File(p.join(dir.path, 'sources.json'));
    expect(await index.exists(), isTrue);
    final text = await index.readAsString();
    expect(text.contains('@name'), isFalse, reason: '脚本正文不该进索引');
    expect(await File(p.join(dir.path, 'scripts', 'lx_a.js')).exists(), isTrue);

    final loaded = await store.load();
    expect([for (final s in loaded) s.id], ['lx_a', 'lx_b']);
    expect(loaded.first.script, _script('a'));
    expect(loaded.last.meta.name, 'lx_b');
  });

  test('更新脚本覆盖同 id 文件，删掉的音源顺带清理脚本', () async {
    final store = LxSourceStore(dir);
    await store.save([_entry('lx_a', _script('a')), _entry('lx_b', _script('b'))]);

    await store.save([_entry('lx_a', _script('a2'))]);

    final loaded = await store.load();
    expect(loaded.single.script, _script('a2'));
    expect(await File(p.join(dir.path, 'scripts', 'lx_b.js')).exists(), isFalse);
    expect(await File(p.join(dir.path, 'scripts', 'lx_a.js')).exists(), isTrue);
  });

  test('脚本文件缺失的条目直接跳过，不影响其他条目', () async {
    final store = LxSourceStore(dir);
    await store.save([_entry('lx_a', _script('a')), _entry('lx_b', _script('b'))]);
    await File(p.join(dir.path, 'scripts', 'lx_a.js')).delete();

    final loaded = await store.load();
    expect([for (final s in loaded) s.id], ['lx_b']);
  });

  test('从旧 prefs 迁移到文件，旧 key 保留', () async {
    final legacy = jsonEncode([_entry('lx_a', _script('a')).toJson()]);
    SharedPreferences.setMockInitialValues({'lx.sources.v2': legacy});

    final loaded = await LxSourceStore(dir).load();
    expect(loaded.single.script, _script('a'));
    expect(await File(p.join(dir.path, 'sources.json')).exists(), isTrue);
    expect(await File(p.join(dir.path, 'scripts', 'lx_a.js')).exists(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('lx.sources.v2'), legacy);

    final again = await LxSourceStore(dir).load();
    expect(again.single.meta.version, '1.0.0');
  });

  test('索引为空列表时不再回头读旧 prefs', () async {
    SharedPreferences.setMockInitialValues({
      'lx.sources.v2': jsonEncode([_entry('lx_a', _script('a')).toJson()]),
    });
    final store = LxSourceStore(dir);
    await store.save(const []);
    expect(await store.load(), isEmpty);
  });
}