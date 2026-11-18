import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:b_player/edge/sources/lx_source_entry.dart';
import 'package:b_player/ui/image_path_picker.dart';

const _script = '''/*!
 * @name 本地音源
 * @version 2.0.0
 * @author 本机
 */
send(inited)
''';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('enode_lx_local_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeScript(String name, String content) async {
    final file = File(p.join(temp.path, name));
    await file.writeAsBytes(utf8.encode(content));
    return file;
  }

  test('读取本地 .js：绝对路径作为身份，保留脚本原文与哈希', () async {
    final file = await writeScript('source.js', _script);
    final entry = await readLxSourceFile(file.path);

    expect(entry.local, isTrue);
    expect(entry.url, p.normalize(file.absolute.path));
    expect(entry.id, LxSourceEntry.idFor(entry.url));
    expect(entry.meta.name, '本地音源');
    expect(entry.script, _script);
    expect(entry.hash, LxSourceEntry.hashOf(_script));
  });

  test('同一路径重选视为更新：id 不变，内容变了哈希就变', () async {
    final file = await writeScript('source.js', _script);
    final first = await readLxSourceFile(file.path);

    await writeScript('source.js', '$_script// v2');
    final second = await readLxSourceFile(file.path);

    expect(second.id, first.id);
    expect(second.hash, isNot(first.hash));
    final merged = LxSourceStore.upsert([first], second);
    expect(merged, hasLength(1));
    expect(merged.single.script, contains('v2'));
  });

  test('非 .js、文件不存在、缺少 @name 都给出可读错误', () async {
    final txt = await writeScript('source.txt', _script);
    await expectLater(
        readLxSourceFile(txt.path), throwsA(isA<FormatException>()));

    await expectLater(
      readLxSourceFile(p.join(temp.path, 'missing.js')),
      throwsA(isA<FormatException>()),
    );

    final unnamed = await writeScript('unnamed.js', 'send(inited)');
    await expectLater(
      readLxSourceFile(unnamed.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('local 标记随条目落盘，旧数据默认 false', () async {
    final file = await writeScript('source.js', _script);
    final entry = await readLxSourceFile(file.path);
    final restored =
        LxSourceEntry.fromJson(jsonDecode(jsonEncode(entry.toJson())));
    expect(restored!.local, isTrue);

    final legacy = Map<String, Object?>.from(entry.toJson())..remove('local');
    expect(LxSourceEntry.fromJson(legacy)!.local, isFalse);
  });

  test('选文件浏览器只列出目标扩展名', () async {
    await writeScript('a.js', _script);
    await writeScript('b.txt', 'x');
    await Directory(p.join(temp.path, 'sub')).create();

    final entries = await listFiles(temp.path, const {'.js'});
    expect(entries.files.map(p.basename), ['a.js']);
    expect(entries.dirs.map(p.basename), ['sub']);
  });
}