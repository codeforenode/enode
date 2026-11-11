import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:b_player/edge/library_store.dart';
import 'package:b_player/edge/music_info.dart';
import 'package:b_player/edge/sources/local_directory_source.dart';
import 'package:b_player/log.dart';

/// 曲库扫描是现场最常见的故障来源（目录填错、盘没挂、没权限），
/// 它的每一条失败路径都必须留下痕迹，否则店家只能说「曲库是空的」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory logDir;

  setUp(() async {
    logDir = await Directory.systemTemp.createTemp('enode_library_log');
    await EnodeLog.init(dir: logDir);
  });

  tearDown(() async {
    await EnodeLog.close();
    if (await logDir.exists()) await logDir.delete(recursive: true);
  });

  Future<String> readLog() async {
    await EnodeLog.close();
    final files = logDir.listSync().whereType<File>().where((f) => f.path.endsWith('.log'));
    if (files.isEmpty) return '';
    return files.map((f) => f.readAsStringSync()).join();
  }

  Track track(String rel, String title) => Track(
        trackKey: 'local:$rel',
        title: title,
        artist: '测试歌手',
        durationMs: 200000,
        sourceId: 'local',
        relPath: rel,
      );

  test('恢复缓存索引会记下条数与目录', () async {
    final support = await Directory.systemTemp.createTemp('enode_library_store');
    addTearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });
    final root = Directory(p.join(support.path, 'Music'));
    await root.create(recursive: true);
    final store = LibraryStore(p.join(support.path, 'store'));
    await store.write(LibraryIndex(
      root: p.normalize(root.path),
      tracks: [track('a.mp3', '甲'), track('b.mp3', '乙')],
      broken: 0,
      scannedAtMs: 1762000000000,
      tookMs: 1200,
    ));

    final source = LocalDirectorySource(root: root.path, store: store);
    await source.load();

    final text = await readLog();
    expect(text, contains('恢复缓存索引 2 首'));
    expect(text, contains('dir=${p.normalize(root.path)}'));
    expect(source.trackCount, 2);
  });

  test('缓存索引属于旧目录时明确记一笔', () async {
    final support = await Directory.systemTemp.createTemp('enode_library_store');
    addTearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });
    final store = LibraryStore(p.join(support.path, 'store'));
    await store.write(LibraryIndex(
      root: p.normalize(p.join(support.path, 'OldMusic')),
      tracks: [track('a.mp3', '甲')],
      broken: 0,
      scannedAtMs: 1762000000000,
      tookMs: 1000,
    ));

    final source = LocalDirectorySource(root: p.join(support.path, 'NewMusic'), store: store);
    await source.load();

    final text = await readLog();
    expect(text, contains('缓存索引属于旧目录'));
    expect(source.trackCount, 0);
  });

  test('目录不存在时扫描结果带错误，日志写明目录', () async {
    final support = await Directory.systemTemp.createTemp('enode_library_store');
    addTearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });
    final missing = p.join(support.path, 'NotHere');
    final source = LocalDirectorySource(root: missing, store: LibraryStore(p.join(support.path, 'store')));

    final result = await source.scan();
    expect(result.error, isNotNull);

    final text = await readLog();
    expect(text, contains('扫描出错'));
    expect(text, contains('dir=${p.normalize(missing)}'));
  });

  test('目录能读但一首都没有，提示确认目录', () async {
    final support = await Directory.systemTemp.createTemp('enode_library_store');
    addTearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });
    final empty = Directory(p.join(support.path, 'Empty'));
    await empty.create(recursive: true);
    final source = LocalDirectorySource(root: empty.path, store: LibraryStore(p.join(support.path, 'store')));

    final result = await source.scan();
    expect(result.error, isNull);
    expect(result.tracks, isEmpty);

    final text = await readLog();
    expect(text, contains('扫描结果为空'));
  });
}
