import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library.dart';
import 'library_store.dart';
import 'sources/local_directory_source.dart';
import 'sources/lx_online_source.dart';
import 'sources/lx_settings.dart';
import 'sources/lx_source_entry.dart';
import 'sources/lx_source_resolver.dart';
import 'sources/webdav_manager.dart';
import 'sources/webdav_store.dart';

/// 启动装配：读持久化的曲库目录与索引，把本地音源挂进统一曲库。
/// 与 any-listen 的启动流程一致：先用缓存秒开，再后台增量扫描。
class LibraryBootstrap {
  LibraryBootstrap({
    required this.library,
    required this.source,
    required this.online,
    required this.resolver,
    required this.webDav,
  });

  final Library library;
  final LocalDirectorySource source;
  final LxOnlineSource online;
  final LxSourceResolver resolver;
  final WebDavManager webDav;

  static const _rootKey = 'library.root';

  static String defaultRoot() => Platform.isAndroid ? '/storage/emulated/0/Music' : r'D:\Music';

  static Future<LibraryBootstrap> open() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_rootKey)?.trim();
    final root = (saved == null || saved.isEmpty) ? defaultRoot() : saved;
    final support = await getApplicationSupportDirectory();
    final store = LibraryStore(p.join(support.path, 'library'));
    final source = LocalDirectorySource(root: root, store: store);
    // 本地目录是列表型音源（索引进曲库），在线音源是检索型音源（按需查询）。
    final resolver = LxSourceResolver();
    resolver.setEntries(await LxSourceStore().load());
    final online = LxOnlineSource(
      settings: await LxSettings.load(),
      sourceResolver: resolver,
    );
    final library = Library([source, online]);
    // WebDAV 也用缓存索引秒开；启动不主动连远端，等用户点同步。
    final webDav = WebDavManager(
      registry: library.registry,
      store: WebDavIndexStore(p.join(support.path, 'webdav')),
    );
    await webDav.load();
    await library.reload();
    return LibraryBootstrap(
      library: library,
      source: source,
      online: online,
      resolver: resolver,
      webDav: webDav,
    );
  }

  static Future<void> saveRoot(String root) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rootKey, root);
  }
}
