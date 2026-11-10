import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';
import '../music_source.dart';
import 'webdav_client.dart';
import 'webdav_config.dart';
import 'webdav_source.dart';
import 'webdav_store.dart';

/// WebDAV 音源的增删改与同步编排；UI 监听它拿列表和同步进度。
///
/// 曲库汇总是 [revision] 驱动的：只有索引真正变了才 +1，
/// 进度通知不会让上层反复重建曲库。
class WebDavManager extends ChangeNotifier {
  WebDavManager({
    required this.registry,
    required this.store,
    this.clientFactory,
  });

  final MusicSourceRegistry registry;
  final WebDavIndexStore store;

  /// 测试注入假客户端；正式运行按服务器配置建。
  final WebDavClient Function(WebDavServer server)? clientFactory;

  final List<WebDavServer> _servers = [];
  final List<WebDavSource> _sources = [];
  final Set<String> _syncing = {};
  final Map<String, ({int tracks, int folders})> _progress = {};
  int _revision = 0;

  int get revision => _revision;
  List<WebDavSource> get sources => List.unmodifiable(_sources);
  List<WebDavServer> get servers => List.unmodifiable(_servers);
  int get trackCount => _sources.fold(0, (sum, source) => sum + source.trackCount);
  bool isSyncing(String id) => _syncing.contains(id);
  ({int tracks, int folders})? progressOf(String id) => _progress[id];
  WebDavSource? byId(String id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  Future<void> load() async {
    final configs = await WebDavServerStore().load();
    for (final config in configs) {
      if (byId(config.id) != null) continue;
      final source = _createSource(config);
      await source.load();
      _servers.add(config);
      _sources.add(source);
      registry.add(source);
    }
    if (_sources.isNotEmpty) _revision++;
  }

  WebDavSource _createSource(WebDavServer server) =>
      WebDavSource(server: server, store: store, client: clientFactory?.call(server));

  /// 新增或编辑。地址变了 id 就变，旧索引与缓存一起清掉。
  Future<WebDavSource> save(WebDavServer server, {String? previousId}) async {
    if (previousId != null && previousId != server.id) {
      await _drop(previousId);
    }
    final source = _createSource(server);
    await source.load();
    final index = _sources.indexWhere((s) => s.id == server.id);
    if (index >= 0) {
      _sources[index].dispose();
      _sources[index] = source;
      final configIndex = _servers.indexWhere((s) => s.id == server.id);
      if (configIndex >= 0) _servers[configIndex] = server;
    } else {
      _sources.add(source);
      _servers.add(server);
    }
    registry.add(source);
    await _persist();
    _revision++;
    notifyListeners();
    return source;
  }

  Future<void> remove(String id) async {
    await _drop(id);
    await _persist();
    _revision++;
    notifyListeners();
  }

  Future<void> _drop(String id) async {
    final index = _sources.indexWhere((s) => s.id == id);
    if (index >= 0) {
      _sources.removeAt(index).dispose();
    }
    _servers.removeWhere((s) => s.id == id);
    registry.remove(id);
    await store.clear(id);
  }

  Future<void> _persist() => WebDavServerStore().save(_servers);

  Future<WebDavSyncResult> sync(String id) async {
    final source = byId(id);
    if (source == null) throw WebDavException(l10n.sourceNotFound);
    if (_syncing.contains(id)) throw WebDavException(l10n.webdavSyncing);
    _syncing.add(id);
    _progress.remove(id);
    notifyListeners();
    try {
      final result = await source.sync(onProgress: (tracks, folders) {
        _progress[id] = (tracks: tracks, folders: folders);
        notifyListeners();
      });
      _revision++;
      return result;
    } finally {
      _syncing.remove(id);
      _progress.remove(id);
      notifyListeners();
    }
  }

  /// 保存前试连：PROPFIND 根目录，能列出条目就算通。
  Future<int> test(WebDavServer server) async {
    final client = clientFactory?.call(server) ?? WebDavClient(server: server);
    try {
      return await client.probe();
    } finally {
      client.dispose();
    }
  }

  @override
  void dispose() {
    for (final source in _sources) {
      source.dispose();
    }
    _sources.clear();
    super.dispose();
  }
}
