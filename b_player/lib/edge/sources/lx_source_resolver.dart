import 'package:http/http.dart' as http;

import 'lx_script_runtime.dart';
import '../../l10n/l10n.dart';
import 'lx_source_entry.dart';

/// 一次成功的取链：哪个音源给出的地址。
class LxResolvedUrl {
  const LxResolvedUrl({required this.sourceId, required this.sourceName, required this.uri});

  final String sourceId;
  final String sourceName;
  final Uri uri;
}

/// 单个已导入脚本的运行实例：懒初始化 + 失败冷却。
class LxScriptSource {
  LxScriptSource(this.entry, {http.Client? client}) : _runtime = LxScriptRuntime(client: client);

  static const _retryDelay = Duration(seconds: 60);

  LxSourceEntry entry;
  final LxScriptRuntime _runtime;

  LxInitResult? _init;
  DateTime? _failedAt;
  String? _failure;

  bool get isReady => _init != null;

  Future<LxInitResult> ensureInitialized() async {
    final cached = _init;
    if (cached != null) return cached;

    final failedAt = _failedAt;
    if (failedAt != null && DateTime.now().difference(failedAt) < _retryDelay) {
      throw LxScriptException(_failure ?? l10n.sourceUnavailable);
    }

    try {
      final result = await _runtime.init(
        entry.script,
        name: entry.meta.name,
        version: entry.meta.version,
        author: entry.meta.author,
        description: entry.meta.description,
        homepage: entry.meta.homepage,
      );
      _init = result;
      _failedAt = null;
      _failure = null;
      entry = entry.copyWith(
        platforms: result.sources.keys.toSet(),
        clearError: true,
      );
      return result;
    } catch (e) {
      _failedAt = DateTime.now();
      _failure = e.toString();
      entry = entry.copyWith(lastError: _failure);
      rethrow;
    }
  }

  Future<Uri> musicUrl({
    required String platform,
    required Map<String, Object?> musicInfo,
    required String quality,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final init = await ensureInitialized();
    if (!init.can(platform, 'musicUrl')) {
      throw LxScriptException(l10n.platformResolveUnsupported);
    }
    final url = await _runtime.musicUrl(
      platform: platform,
      musicInfo: musicInfo,
      quality: quality,
      timeout: timeout,
    );
    return Uri.parse(url);
  }

  /// 读取脚本自己上报的更新提示（不影响取链）。
  Future<LxUpdateAlert?> readUpdateAlert({Duration budget = const Duration(seconds: 3)}) =>
      _runtime.readUpdateAlert(budget: budget);

  void dispose() => _runtime.dispose();
}

/// 多音源调度：按导入顺序（即优先级）逐个尝试，失败自动换下一个。
///
/// 对应 any-listen 的 `getExtSource(action, excludeList, source)` 思路，
/// 但调度在 Dart 侧完成，脚本本身不需要知道还有别的音源存在。
class LxSourceResolver {
  LxSourceResolver({http.Client? httpClient}) : _client = httpClient;

  final http.Client? _client;
  final Map<String, LxScriptSource> _sources = {};
  List<LxSourceEntry> _entries = const [];
  List<String> _lastFailures = const [];

  List<LxSourceEntry> get entries => List.unmodifiable(_entries);
  List<String> get lastFailures => List.unmodifiable(_lastFailures);

  /// 换配置时只重建被改动的脚本，未变动的保留已初始化的 JS 上下文。
  void setEntries(Iterable<LxSourceEntry> entries) {
    _entries = List.unmodifiable([...entries]);
    final byId = {for (final entry in _entries) entry.id: entry};
    _sources.removeWhere((id, source) {
      final next = byId[id];
      if (next == null || next.script != source.entry.script) {
        source.dispose();
        return true;
      }
      source.entry = next;
      return false;
    });
  }

  LxSourceEntry? entryById(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// 预热单个音源，供“测试”按钮使用。
  Future<LxInitResult> warmUp(String id) {
    final entry = entryById(id);
    if (entry == null) throw LxScriptException(l10n.sourceNotFound);
    return _sourceFor(entry).ensureInitialized();
  }

  /// 按顺序尝试所有勾选且声明了该平台的音源；全部失败返回 null。
  Future<LxResolvedUrl?> resolve({
    required String platform,
    required Map<String, Object?> musicInfo,
    required String quality,
    Set<String> excluding = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final failures = <String>[];
    for (final entry in _entries) {
      if (!entry.enabled || excluding.contains(entry.id)) continue;
      // 已知不支持该平台就不必浪费一次 JS 初始化。
      if (entry.platforms.isNotEmpty && !entry.platforms.contains(platform)) continue;
      final source = _sourceFor(entry);
      try {
        final uri = await source.musicUrl(
          platform: platform,
          musicInfo: musicInfo,
          quality: quality,
          timeout: timeout,
        );
        _lastFailures = failures;
        return LxResolvedUrl(sourceId: entry.id, sourceName: entry.name, uri: uri);
      } catch (e) {
        failures.add('${entry.name}: $e');
      }
    }
    _lastFailures = failures;
    return null;
  }

  void disposeAll() {
    for (final source in _sources.values) {
      source.dispose();
    }
    _sources.clear();
  }

  LxScriptSource _sourceFor(LxSourceEntry entry) =>
      _sources.putIfAbsent(entry.id, () => LxScriptSource(entry, client: _client));
}
