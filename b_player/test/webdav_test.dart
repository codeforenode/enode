import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/edge/config.dart';
import 'package:b_player/edge/library.dart';
import 'package:b_player/edge/sources/webdav_client.dart';
import 'package:b_player/edge/sources/webdav_config.dart';
import 'package:b_player/edge/sources/webdav_manager.dart';
import 'package:b_player/edge/sources/webdav_source.dart';
import 'package:b_player/edge/sources/webdav_store.dart';
import 'package:b_player/state/app_settings.dart';
import 'package:b_player/state/app_state.dart';
import 'package:b_player/theme.dart';
import 'package:b_player/ui/shell.dart';

import 'l10n_harness.dart';

const _base = 'http://nas.local:5005/dav';

void main() {
  final server = WebDavServer(
    id: WebDavServer.idFor(_base),
    name: 'NAS',
    url: _base,
    username: 'user',
    password: 'pass',
  );

  late Directory temp;
  late List<String> visited;
  late Map<String, int> gets;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('enode_webdav_');
    visited = [];
    gets = {};
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  MockClient mockClient() => MockClient((request) async {
        if (request.method == 'PROPFIND') {
          visited.add(request.url.path);
          final body = _tree[request.url.path];
          return body == null ? http.Response('', 404) : http.Response(body, 207);
        }
        gets.update(request.url.path, (v) => v + 1, ifAbsent: () => 1);
        switch (request.url.path) {
          case '/dav/Artist%20-%20Song.lrc':
            return http.Response.bytes(utf8.encode('[00:01.00]hello lyric'), 200);
          case '/dav/cover.jpg':
            return http.Response.bytes([1, 2, 3, 4], 200);
          default:
            return http.Response('', 404);
        }
      });

  test('递归扫描：解析文件名、跳过系统目录、带认证头与歌词/封面', () async {
    final store = WebDavIndexStore(temp.path);
    final source = WebDavSource(
      server: server,
      store: store,
      client: WebDavClient(server: server, client: mockClient()),
    );
    final progress = <(int, int)>[];
    final result = await source.sync(onProgress: (tracks, folders) => progress.add((tracks, folders)));

    expect(result.tracks.length, 2);
    expect(result.folders, 2);
    expect(result.failedFolders, 0);
    expect(result.error, isNull);
    expect(progress.last, (2, 2));
    expect(visited, containsAll(['/dav/', '/dav/Album/']));
    expect(visited, isNot(contains('/dav/@eaDir/')), reason: '系统目录不递归');
    expect(visited, isNot(contains('/dav/_hidden/')), reason: '隐藏目录不递归');

    final song = result.tracks.firstWhere((t) => t.title == 'Song');
    expect(song.artist, 'Artist');
    expect(song.relPath, 'Artist - Song.flac');
    expect(song.sourceId, server.id);
    expect(song.trackKey, Track.keyFor('Artist - Song.flac', sourceId: server.id));
    expect(song.durationMs, 0, reason: '远程扫描不读标签，时长留给引擎');
    expect(song.absPath, '$_base/Artist%20-%20Song.flac');
    expect(song.lyricRel, endsWith('Artist%20-%20Song.lrc'));
    expect(song.extra['davCover'], endsWith('/dav/cover.jpg'));

    final instrumental = result.tracks.firstWhere((t) => t.relPath == 'Album/02_Instrumental.mp3');
    expect(instrumental.title, 'Instrumental');
    expect(instrumental.artist, l10n.unknownArtist);
    expect(instrumental.extra['davCover'], endsWith('/dav/Album/folder.png'));

    expect(await source.audioUri(song), Uri.parse(song.absPath));
    final headers = await source.audioHeaders(song);
    expect(headers['Authorization'], 'Basic ${base64Encode(utf8.encode('user:pass'))}');

    final lyric = await source.lyric(song);
    expect(lyric.lyric, contains('hello lyric'));

    final pic = await source.picUri(song);
    expect(pic, isNotNull);
    expect(pic!.isScheme('file'), isTrue);
    expect(await File(pic.toFilePath()).readAsBytes(), [1, 2, 3, 4]);
    await source.picUri(song);
    expect(gets['/dav/cover.jpg'], 1, reason: '封面落盘后不重复下载');

    final page = await source.search('song');
    expect(page.items.map((t) => t.title), ['Song']);

    // 重新打开只读索引，不再联网
    final offline = WebDavClient(
      server: server,
      client: MockClient((_) async => fail('索引命中时不应发起网络请求')),
    );
    final reopened = WebDavSource(server: server, store: store, client: offline);
    await reopened.load();
    expect(reopened.trackCount, 2);
    expect(reopened.lastSyncAt, isNotNull);
    final restored = await reopened.fetchTracks([song.trackKey]);
    expect(restored.single.absPath, song.absPath);
    expect(restored.single.lyricRel, song.lyricRel);

    source.dispose();
    reopened.dispose();
  });

  test('管理器：读持久化配置、同步进统一曲库、删除时清索引', () async {
    SharedPreferences.setMockInitialValues({
      'webdav.servers.v1': jsonEncode([server.toJson()]),
    });
    final library = Library(const []);
    final manager = WebDavManager(
      registry: library.registry,
      store: WebDavIndexStore(temp.path),
      clientFactory: (_) => WebDavClient(server: server, client: mockClient()),
    );
    addTearDown(manager.dispose);

    await manager.load();
    expect(manager.sources.length, 1);
    final source = manager.sources.single;
    expect(source.id, server.id);
    expect(source.server.displayName, 'NAS');
    expect(library.registry.byId(server.id), isNotNull);

    final progress = <(int, int)>[];
    manager.addListener(() {
      final p = manager.progressOf(source.id);
      if (p != null) progress.add((p.tracks, p.folders));
    });
    final revisionBefore = manager.revision;
    final result = await manager.sync(source.id);
    expect(result.tracks.length, 2);
    expect(manager.trackCount, 2);
    expect(manager.revision, greaterThan(revisionBefore));
    expect(progress, isNotEmpty, reason: '同步过程中要能拿到发现进度');
    expect(manager.isSyncing(source.id), isFalse);
    expect(manager.progressOf(source.id), isNull);

    await library.reload();
    expect(library.tracks.length, 2);
    final song = library.tracks.firstWhere((t) => t.title == 'Song');
    final ref = await library.audioFor(song.trackKey);
    expect(ref, isNotNull);
    expect(ref!.uri.toString(), song.absPath);
    expect(ref.headers['Authorization'], startsWith('Basic '));

    await manager.remove(source.id);
    expect(manager.sources, isEmpty);
    expect(library.registry.byId(source.id), isNull);
    await library.reload();
    expect(library.tracks, isEmpty);
    expect(await WebDavIndexStore(temp.path).read(source.id, server.url), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('webdav.servers.v1')!) as List, isEmpty);
  });

  test('地址规范化与校验', () {
    expect(WebDavServer.normalizeUrl('  https://nas.local/dav///  '), 'https://nas.local/dav');
    expect(WebDavServer.validUrl('https://nas.local/dav'), isTrue);
    expect(WebDavServer.validUrl('http://192.168.1.9:5005'), isTrue);
    expect(WebDavServer.validUrl('nas.local/dav'), isFalse);
    expect(WebDavServer.validUrl('ftp://nas.local'), isFalse);
    expect(WebDavServer.idFor('https://nas.local/dav'), startsWith('dav_'));
    expect(WebDavServer.idFor(' https://nas.local/dav '), WebDavServer.idFor('https://nas.local/dav'));
  });

  testWidgets('音源面板：WebDAV 行、添加弹窗校验与删除确认', (tester) async {
    useTraditionalChinese();
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'webdav.servers.v1': jsonEncode([server.toJson()]),
    });
    final library = Library(const []);
    final manager = WebDavManager(
      registry: library.registry,
      store: WebDavIndexStore(temp.path),
      clientFactory: (_) => WebDavClient(server: server, client: mockClient()),
    );
    // testWidgets 跑在 FakeAsync 里，真实的文件/偏好读写要用 runAsync。
    await tester.runAsync(() async {
      await manager.load();
      await manager.sync(server.id);
      await library.reload();
    });
    expect(manager.trackCount, 2);

    final settings = AppSettings();
    final state = AppState(mqtt: const MqttConfig(enabled: false), library: library, webDav: manager);
    C.use(Brightness.dark);
    await tester.pumpWidget(localizedApp(
      theme: buildTheme(Brightness.dark),
      home: Shell(state: state, settings: settings),
    ));
    await tester.pump();

    expect(find.text('NAS'), findsOneWidget);
    expect(find.text('nas.local:5005/dav · ${l10n.webdavCount(2)}'), findsOneWidget);
    expect(find.text(l10n.sourcesSummary(0, 2)), findsOneWidget);
    expect(find.byKey(Key('webdav-sync-${server.id}')), findsOneWidget);

    // 新增：地址不合法时停在弹窗里给原因
    await tester.tap(find.byKey(const Key('webdav-add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.webdavAddTitle), findsOneWidget);
    await tester.enterText(find.byKey(const Key('webdav-name')), 'Home');
    await tester.enterText(find.byKey(const Key('webdav-url')), 'nas.local/music');
    await tester.tap(find.byKey(const Key('webdav-save')));
    await tester.pump();
    expect(find.text(l10n.webdavInvalidUrl), findsOneWidget);

    await tester.tap(find.text(l10n.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.webdavAddTitle), findsNothing);
    expect(find.text('NAS'), findsOneWidget);

    // 删除要二次确认；取消后音源仍在
    await tester.tap(find.byKey(Key('webdav-delete-${server.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.webdavDeleteConfirm('NAS')), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('NAS'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
    settings.dispose();
  });
}

// ---------------- WebDAV 假响应 ----------------

final _tree = <String, String>{
  '/dav/': _multistatus([
    _item('/dav/', dir: true),
    _item('/dav/Album/', dir: true),
    _item('/dav/@eaDir/', dir: true, display: '@eaDir'),
    _item('/dav/_hidden/', dir: true, display: '.hidden'),
    _item('/dav/Artist%20-%20Song.flac', size: 1234),
    _item('/dav/Artist%20-%20Song.lrc', size: 90),
    _item('/dav/cover.jpg', size: 200),
  ]),
  '/dav/Album/': _multistatus([
    _item('/dav/Album/', dir: true),
    _item('/dav/Album/02_Instrumental.mp3', size: 999, modified: 'Thu, 01 Jan 2026 00:00:00 GMT'),
    _item('/dav/Album/folder.png', size: 300),
  ]),
};

String _multistatus(List<String> responses) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<d:multistatus xmlns:d="DAV:">${responses.join()}</d:multistatus>';

String _item(
  String href, {
  bool dir = false,
  int size = 0,
  String modified = 'Wed, 05 Nov 2026 10:00:00 GMT',
  String? display,
}) =>
    '<d:response>'
    '<d:href>$href</d:href>'
    '<d:propstat><d:prop>'
    '${display == null ? '' : '<d:displayname>$display</d:displayname>'}'
    '<d:resourcetype>${dir ? '<d:collection/>' : ''}</d:resourcetype>'
    '${dir ? '' : '<d:getcontentlength>$size</d:getcontentlength>'}'
    '<d:getlastmodified>$modified</d:getlastmodified>'
    '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
    '</d:response>';
