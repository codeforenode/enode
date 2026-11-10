import 'dart:async';

import 'package:flutter/foundation.dart';

import '../desktop/cast_windows.dart';
import '../edge/config.dart';
import '../edge/edge_node.dart';
import '../edge/featured.dart';
import '../edge/library.dart';
import '../edge/library_bootstrap.dart';
import '../edge/library_permissions.dart';
import '../edge/library_scanner.dart';
import '../edge/player_engine.dart';
import '../edge/protocol.dart';
import '../edge/sources/local_directory_source.dart';
import '../edge/sources/lx_online_source.dart';
import '../edge/sources/lx_settings.dart';
import '../edge/sources/lx_script_runtime.dart';
import '../edge/sources/lx_source_entry.dart';
import '../edge/sources/lx_source_resolver.dart';
import '../edge/sources/webdav_client.dart';
import '../edge/sources/webdav_config.dart';
import '../edge/sources/webdav_manager.dart';
import '../edge/sources/webdav_source.dart';
import '../l10n/l10n.dart';
import 'cast_settings.dart';
import 'lrc.dart';

class QueueItem {
  QueueItem({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.seat,
    this.positionMs = 0,
  });

  final String trackKey;
  final String title;
  final String artist;

  /// 扫描/元数据给出的时长；引擎打开成功后会用实际时长覆盖。
  int durationMs;

  /// 接入方传入的原始桌号字符串，B端 不做格式解释；null 表示本机添加。
  final String? seat;
  int positionMs;

  String get seatLabel => seat ?? l10n.seatLocal;
}

/// B端 的本地状态：曲库、权威队列、播放进度。
/// 对外只通过 [edge]（MQTT）暴露健康状态与检索/入队 RPC，曲库内容不出本机。
class AppState extends ChangeNotifier {
  AppState({
    MqttConfig? mqtt,
    Library? library,
    this.localSource,
    this.onlineSource,
    this.webDav,
    this.engine,
    this.watchdogPeriod = const Duration(seconds: 8),
  })  : demoMode = library == null,
        library = library ?? Library.demo() {
    queue = demoMode ? _demoQueue(this.library) : <QueueItem>[];
    playing = demoMode;
    // 出厂歌单要读 asset 并检索上游，属于副作用，交给入口显式触发
    // （测试构造 AppState 时不该联网，也不该依赖 binding）。
    featured = FeaturedService(library: this.library);
    edge = EdgeNode(
      search: (q, offset, limit) => this.library.searchAsync(q, offset: offset, limit: limit),
      enqueue: _handleEnqueue,
      snapshot: _snapshot,
      health: _health,
      lyric: _lyric,
      featured: featured.payload,
      config: mqtt,
    );
    if (engine == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _advance());
    } else {
      _bindEngine(engine!);
      if (queue.isNotEmpty) unawaited(_loadCurrent());
    }
    if (webDav != null) {
      _webDavRevision = webDav!.revision;
      webDav!.addListener(_onWebDavChanged);
    }
    unawaited(_warmArt(nowPlaying?.trackKey));
    if (localSource != null) unawaited(scanLibrary());
  }

  final bool demoMode;
  final Library library;

  /// 正式运行时唯一的数据来源；测试/演示模式为 null。
  final LocalDirectorySource? localSource;

  /// 在线曲库音源；演示模式为 null，隐藏配置入口据此判断是否可用。
  final LxOnlineSource? onlineSource;

  /// WebDAV 音源管理；演示/测试模式为 null。
  final WebDavManager? webDav;

  /// 真实播放后端；为 null 时退回演示用的每秒模拟推进（测试/无原生插件环境）。
  final AudioEngine? engine;

  Timer? _tick;
  Timer? _watchdog;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;
  late final EdgeNode edge;
  late final FeaturedService featured;
  late final List<QueueItem> queue;

  /// 入队取链的时间预算：中继等节点应答上限是 9s，这里留出余量。
  static const _enqueueResolveBudget = Duration(seconds: 6);

  /// 兜底映射的预算：映射和取链共用那 9s，给取链留大头。
  static const _remapBudget = Duration(seconds: 3);

  /// 打开后多久没有进度就判定打不开；正常 8 秒，测试可注入更短的值。
  final Duration watchdogPeriod;

  bool playing = true;

  /// 0..1；引擎存在时同步到后端。
  double volume = .7;

  bool _scanning = false;
  int _scanned = 0;
  int _scanTotal = 0;
  String? _scanError;
  StoragePermissionState? _permission;
  bool _disposed = false;
  int _lastHealthPublishMs = 0;
  int _webDavRevision = 0;

  int _lyricGeneration = 0;
  bool _lyricAvailable = false;
  List<LyricLine> _lyricLines = const [];
  Uri? _cover;

  int _playGen = 0;
  bool _loading = false;
  String? _playbackError;

  /// 最近一次取链/解码失败的原因；成功拿到时长后清空。
  String? get playbackError => _playbackError;

  int get libraryCount => library.tracks.length;
  int get localTrackCount =>
      localSource?.trackCount ?? (demoMode ? library.tracks.length : library.tracks.where((t) => t.isLocal).length);
  int get webDavTrackCount => webDav?.trackCount ?? 0;
  List<WebDavSource> get webDavSources => webDav?.sources ?? const <WebDavSource>[];
  bool webDavSyncing(String id) => webDav?.isSyncing(id) ?? false;
  ({int tracks, int folders})? webDavProgress(String id) => webDav?.progressOf(id);
  bool get scanning => _scanning;
  int get scanned => _scanned;
  int get scanTotal => _scanTotal;
  int get brokenCount => localSource?.brokenCount ?? 0;
  DateTime? get lastScan => localSource?.lastScanAt;
  String get scanDir => localSource?.root ?? '';
  String? get scanError => _scanError;
  StoragePermissionState? get permission => _permission;

  QueueItem? get nowPlaying => queue.isEmpty ? null : queue.first;

  /// 当前曲目的歌词行；切歌时由 [_warmArt] 重新解析。
  List<LyricLine> get lyricLines => _lyricLines;
  bool get lyricAvailable => _lyricAvailable;

  /// 当前曲目对应的歌词行下标，第一句之前为 -1。
  int get lyricIndex => lyricIndexAt(_lyricLines, nowPlaying?.positionMs ?? 0);

  /// 当前曲目的封面；本地目录取同目录图片，在线曲目取平台返回的地址。
  Uri? get coverUri => _cover;

  /// 播放卡上的来源标签：在线给出音源脚本与音质，本地/WebDAV 只给来源名。
  List<String> sourceTags(String trackKey) {
    final track = library.byKey(trackKey);
    if (track == null) return const [];
    final source = library.registry.byId(track.sourceId);
    if (source?.kind == 'webdav') return [source!.label];
    if (track.isLocal) return [l10n.localTag];
    final tags = <String>[
      library.sourceLabelFor(trackKey),
      if (onlineSource != null) onlineSource!.quality,
    ];
    return tags.where((t) => t.trim().isNotEmpty).toList(growable: false);
  }

  static List<QueueItem> _demoQueue(Library lib) {
    QueueItem at(String title, {String? seat, int positionMs = 0}) {
      final t = lib.tracks.firstWhere((t) => t.title == title);
      return QueueItem(
        trackKey: t.trackKey,
        title: t.title,
        artist: t.artist,
        durationMs: t.durationMs,
        seat: seat,
        positionMs: positionMs,
      );
    }

    return [
      at('搁浅之外', seat: '12 号桌', positionMs: 83000),
      at('稻香之外', seat: '7 号桌'),
      at('晴天之外'),
      at('晴天之外', seat: '12 号桌'),
    ];
  }

  // ---------------- 曲库 ----------------

  Future<void> scanLibrary({bool requestPermission = true}) async {
    final source = localSource;
    if (source == null || _scanning) return;
    _scanning = true;
    _scanError = null;
    _scanned = 0;
    _scanTotal = 0;
    notifyListeners();

    if (requestPermission) {
      _permission = await LibraryPermissions.request();
    } else {
      _permission ??= await LibraryPermissions.check();
    }
    if (!(_permission?.canReadLibrary ?? true)) {
      _scanning = false;
      _scanError = _permission!.summary;
      notifyListeners();
      return;
    }

    ScanResult result;
    try {
      result = await source.scan(onProgress: (done, total) {
        _scanned = done;
        _scanTotal = total;
        notifyListeners();
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastHealthPublishMs > 1000) {
          _lastHealthPublishMs = now;
          edge.publishHealth();
        }
      });
    } catch (e) {
      _scanning = false;
      _scanError = l10n.scanFailed('$e');
      notifyListeners();
      return;
    }

    _scanning = false;
    _scanTotal = result.tracks.length;
    _scanned = result.tracks.length;
    if (result.error != null) _scanError = result.error;
    if (!result.canceled) {
      // 本地扫描只替换本地音源；统一曲库要重新汇总，别把 WebDAV 曲目冲掉。
      await library.reload();
      edge.publishHealth();
    }
    notifyListeners();
  }

  Future<void> setLibraryRoot(String value) async {
    final source = localSource;
    final next = value.trim();
    if (source == null || next.isEmpty) return;
    await source.setRoot(next);
    await LibraryBootstrap.saveRoot(source.root);
    await library.reload();
    _scanError = null;
    _scanned = 0;
    _scanTotal = 0;
    notifyListeners();
    await scanLibrary(requestPermission: false);
  }

  Future<void> requestLibraryPermission() async {
    if (localSource == null) return;
    _permission = await LibraryPermissions.request();
    notifyListeners();
    if (_permission?.canReadLibrary == true) {
      await scanLibrary(requestPermission: false);
    }
  }

  Future<bool> openStorageSettings() => LibraryPermissions.openSystemSettings();

  // ---------------- 在线曲库配置 ----------------

  LxSettings? get onlineSettings {
    final source = onlineSource;
    if (source == null) return null;
    return LxSettings(
      quality: source.quality,
      enabledPlatforms: {...source.enabledPlatformIds},
    );
  }

  /// 保存后立即换源并清缓存，不重启即可生效。
  Future<void> saveOnlineSettings(LxSettings settings) async {
    final source = onlineSource;
    if (source == null) return;
    source.applySettings(settings);
    // 直链是按音质取的，换音质后旧地址全部作废。
    library.clearAudioCache();
    await settings.save();
    notifyListeners();
  }

  // ---------------- 歌词投放（Windows） ----------------

  CastSettings _cast = CastSettings.defaults;
  List<CastMonitor> _castMonitors = const [];
  CastWindows? _castWindows;

  CastSettings get cast => _cast;
  List<CastMonitor> get castMonitors => _castMonitors;

  /// 真开起来的投放窗数量：设置里勾了但没起来时，这里和屏数是两回事。
  int get castWindowCount => _castWindows?.windowCount ?? 0;

  /// 开窗 / 掉窗的可读原因，设置页原样显示（拒绝要带回理由）。
  String? get castWindowsError => _castWindows?.lastError;

  /// 把设置和播放进度接到真实投放窗上。只在 Windows 主 isolate 调，测试不接就不会碰插件。
  void bindCastWindows() {
    if (_disposed || _castWindows != null) return;
    _castWindows = CastWindows(this);
  }

  /// 退出进程前先把投放窗收干净，否则子引擎的窗口会黑在屏幕上。
  Future<void> closeCastWindows() => _castWindows?.closeAll() ?? Future.value();

  /// 读设置 + 扫一次屏。非 Windows 或无插件环境扫到空列表，投放入口随之关闭。
  Future<void> loadCast() async {
    final monitors = await scanCastMonitors();
    final settings = await CastSettings.load();
    applyCastScan(monitors, aligned: settings);
  }

  /// 重新扫描显示器；拔插屏后调用，已存的每屏配置按 id 保留。
  Future<void> rescanCastMonitors() async {
    applyCastScan(await scanCastMonitors());
    await _cast.save();
  }

  /// 把一次扫描结果并进设置。抽出来是为了能在测试里喂假屏列表（CI 上没有屏可扫）。
  void applyCastScan(List<CastMonitor> monitors, {CastSettings? aligned}) {
    _castMonitors = monitors;
    _cast = (aligned ?? _cast).alignedTo(monitors);
    notifyListeners();
  }

  /// 投放屏右键「关闭本屏投放」。
  Future<void> closeCastScreen(String monitorId) async {
    final next = _cast.withoutScreen(monitorId);
    if (next == _cast) return;
    await saveCast(next);
  }

  /// 投放屏右键「关闭全部投放」；素材与布局保留，重新勾选屏幕即恢复。
  Future<void> closeCasting() async {
    if (!_cast.enabled) return;
    await saveCast(_cast.withCastingOff());
  }

  Future<void> saveCast(CastSettings next) async {
    final prev = _cast;
    _cast = next;
    notifyListeners();
    await next.save();
    // 偏移是发布给 C端 的歌词元数据，改了要重发一次 retained 消息。
    if (prev.style.offsetMs != next.style.offsetMs) edge.publishLyric();
  }

  // ---------------- 广播（MQTT） ----------------

  /// 「广播」页应用新参数：先落盘再重连，重启后仍生效。
  Future<void> applyMqttConfig(MqttConfig config) async {
    await MqttConfigStore.save(config);
    await edge.applyConfig(config);
  }

  /// 清掉本机保存的参数，回到未配置状态并断开。
  Future<void> clearMqttConfig() async {
    await MqttConfigStore.clear();
    await edge.applyConfig(const MqttConfig());
  }

  // ---------------- 多音源 ----------------

  List<LxSourceEntry> get onlineSources =>
      onlineSource?.resolver?.entries ?? const <LxSourceEntry>[];

  /// 列表顺序即取链优先级；勾选状态一并保存。
  Future<void> saveOnlineSources(List<LxSourceEntry> sources) async {
    final source = onlineSource;
    if (source == null) return;
    source.applySources(sources);
    library.clearAudioCache();
    await LxSourceStore().save(sources);
    notifyListeners();
    // 导入/停用脚本会改变 caps 里有没有 search，立刻重发一次健康状态。
    edge.publishHealth();
  }

  /// 用独立上下文试跑一个音源，不动当前正在用的实例。
  /// 返回结构化结果：消息只用于展示，调用方不再靠文案前缀判断成败。
  Future<({bool ok, String message, LxUpdateAlert? alert})> testOnlineSource(
    LxSourceEntry entry,
  ) async {
    final probe = LxScriptSource(entry);
    final started = DateTime.now();
    try {
      final init = await probe.ensureInitialized();
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final canResolve =
          init.sources.values.any((capability) => capability.supports('musicUrl'));
      final ready = l10n.probeReady(elapsed);
      final alert = await probe.readUpdateAlert();
      return (
        ok: true,
        message: canResolve ? ready : '$ready${l10n.probeNoResolve}',
        alert: alert,
      );
    } catch (e) {
      return (ok: false, message: l10n.probeFailed('$e'), alert: null);
    } finally {
      probe.dispose();
    }
  }

  /// 重拉同一地址，用脚本哈希判断是否有新版。
  ///
  /// 只下载不替换；同时顺带读一次本地脚本自己上报的 `updateAlert`。
  /// 是否执行新脚本由用户在界面上确认。
  Future<({LxSourceEntry? update, LxUpdateAlert? alert, String? error})>
      checkOnlineSourceUpdate(LxSourceEntry entry) async {
    LxScriptSource? probe;
    try {
      final latest = await fetchLxSource(entry.url);
      final localHash =
          entry.hash.isNotEmpty ? entry.hash : LxSourceEntry.hashOf(entry.script);
      LxUpdateAlert? alert;
      try {
        probe = LxScriptSource(entry);
        await probe.ensureInitialized();
        alert = await probe.readUpdateAlert();
      } catch (_) {
        // 更新提示是附带信息，脚本跑不起来时仍要报告版本差异。
      }
      return (
        update: latest.hash == localHash ? null : latest,
        alert: alert,
        error: null,
      );
    } catch (e) {
      return (update: null, alert: null, error: '$e');
    } finally {
      probe?.dispose();
    }
  }

  /// 隐藏配置页里的连通性探针：检索 + 取链各测一次，不混入本机结果。
  Future<String> probeOnlineSearch([String keyword = '晴天']) async {
    final source = onlineSource;
    if (source == null) return l10n.probeNoOnlineSource;
    final started = DateTime.now();
    try {
      final page = await source.search(keyword.trim(), limit: 10);
      final searchMs = DateTime.now().difference(started).inMilliseconds;
      if (page.items.isEmpty) return l10n.probeZero(searchMs);
      final resolveStarted = DateTime.now();
      try {
        final uri = await source.audioUri(page.items.first);
        final resolveMs = DateTime.now().difference(resolveStarted).inMilliseconds;
        return l10n.probeTracks(page.items.length, searchMs, resolveMs, uri.host);
      } catch (e) {
        return l10n.probeResolveFailed(page.items.length, searchMs, '$e');
      }
    } catch (e) {
      return l10n.probeFailed('$e');
    }
  }

  // ---------------- WebDAV 音源 ----------------

  /// 同步/增删只在索引真正变化时重建统一曲库；进度通知只刷 UI。
  void _onWebDavChanged() {
    if (_disposed) return;
    final manager = webDav;
    if (manager != null && manager.revision != _webDavRevision) {
      _webDavRevision = manager.revision;
      unawaited(_reloadLibrary());
    }
    notifyListeners();
  }

  Future<void> _reloadLibrary() async {
    final before = library.tracks.length;
    await library.reload();
    if (_disposed) return;
    notifyListeners();
    if (library.tracks.length != before) edge.publishHealth();
  }

  Future<WebDavSource> saveWebDav(WebDavServer server, {String? previousId}) async {
    final manager = webDav;
    if (manager == null) throw WebDavException(l10n.sourceUnavailable);
    return manager.save(server, previousId: previousId);
  }

  Future<void> removeWebDav(String id) async {
    await webDav?.remove(id);
  }

  Future<WebDavSyncResult> syncWebDav(String id) async {
    final manager = webDav;
    if (manager == null) throw WebDavException(l10n.sourceUnavailable);
    return manager.sync(id);
  }

  Future<int> testWebDav(WebDavServer server) async {
    final manager = webDav;
    if (manager == null) throw WebDavException(l10n.sourceUnavailable);
    return manager.test(server);
  }

  // ---------------- 播放/队列 ----------------

  /// 无引擎时的模拟推进：只在测试/演示模式使用。
  void _advance() {
    final head = nowPlaying;
    if (head == null || !playing) return;
    head.positionMs += 1000;
    var changedTrack = false;
    if (head.positionMs >= head.durationMs) {
      queue.removeAt(0);
      changedTrack = true;
      if (queue.isEmpty) playing = false;
      unawaited(_warmArt(nowPlaying?.trackKey));
    }
    notifyListeners();
    if (changedTrack) edge.notifyTrackChanged();
  }

  void _bindEngine(AudioEngine e) {
    _positionSub = e.positionStream.listen(_onEnginePosition);
    _durationSub = e.durationStream.listen(_onEngineDuration);
    _completedSub = e.completedStream.listen((done) {
      if (done) _onEngineCompleted();
    });
    _errorSub = e.errorStream.listen(_onEngineError);
  }

  static const _positionStepMs = 250;

  void _onEnginePosition(Duration position) {
    final head = nowPlaying;
    if (_disposed || head == null || _loading) return;
    final ms = position.inMilliseconds;
    if (ms < 0 || (ms - head.positionMs).abs() < _positionStepMs) return;
    head.positionMs = ms;
    if (ms > 0) _cancelWatchdog();
    notifyListeners();
  }

  void _onEngineDuration(Duration duration) {
    final head = nowPlaying;
    if (_disposed || head == null || _loading) return;
    final ms = duration.inMilliseconds;
    if (ms <= 0) return;
    _cancelWatchdog();
    final changed = head.durationMs != ms || _playbackError != null;
    head.durationMs = ms;
    _playbackError = null;
    if (changed) notifyListeners();
  }

  void _onEngineCompleted() {
    if (_disposed || _loading || queue.isEmpty) return;
    _advanceHead();
  }

  void _onEngineError(String message) {
    if (_disposed) return;
    final text = message.trim();
    if (text.isEmpty) return;
    _playbackError = _readablePlaybackError(text);
    notifyListeners();
  }

  /// libmpv 的报错是英文，操作员只需要知道“这歌放不了”。
  static String _readablePlaybackError(String text) {
    if (text.contains('Failed to recognize file format')) return l10n.audioFormatUnsupported;
    if (text.contains('Failed to open')) return l10n.audioOpenFailed;
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  /// 解析队首播放地址并交给引擎；队首没变时旧任务的结果直接丢弃。
  Future<void> _loadCurrent() async {
    final e = engine;
    if (e == null) return;
    final gen = ++_playGen;
    _cancelWatchdog();
    final head = nowPlaying;
    if (head == null) {
      _loading = false;
      await e.stop();
      return;
    }

    _loading = true;
    head.positionMs = 0;
    notifyListeners();

    AudioRef? resolved;
    try {
      resolved = await library.audioFor(head.trackKey);
    } catch (_) {
      resolved = null;
    }
    if (_disposed || gen != _playGen) return;
    if (resolved == null) {
      _loading = false;
      _failAndSkip(l10n.skipResolveFailed(head.title), gen);
      return;
    }

    var current = resolved;
    Object? openError;
    for (var attempt = 0;; attempt++) {
      try {
        await e.open(current.uri, autoplay: playing, headers: current.headers);
        openError = null;
        break;
      } catch (err) {
        openError = err;
        // 在线直链有时效，第一次打不开就强制重新取链再试一次；本地文件没有这一步。
        final network = current.uri.isScheme('http') || current.uri.isScheme('https');
        if (attempt > 0 || !network) break;
        library.invalidateAudio(head.trackKey);
        final refetched = await library.audioFor(head.trackKey, refresh: true);
        if (refetched == null) break;
        current = refetched;
      }
    }
    if (_disposed || gen != _playGen) return;
    if (openError != null) {
      _loading = false;
      _failAndSkip(l10n.playOpenFailed(head.title, '$openError'), gen);
      return;
    }

    _loading = false;
    try {
      await e.setVolume(volume);
    } catch (_) {}
    // libmpv 遇到损坏/不支持的格式通常不会让 open 抛错，只发 error。
    // 8 秒内既没有时长也没有进度就当作打不开，跳过以免队列卡死。
    _armWatchdog(head, gen);
    notifyListeners();
  }

  /// 8 秒没有进度就判定这首打不开。
  ///
  /// 直链过期最常见的表现是「open 不报错、但永远读不出内容」，所以先按过期处理一次
  /// （重取链 + 重开），只有第二次仍然没有进度才跳过——否则会把本来能救回来的歌直接跳掉。
  /// 救援只做一次，真正的坏文件不会反复卡 8 秒。
  void _armWatchdog(QueueItem head, int gen, {bool allowRecover = true}) {
    _cancelWatchdog();
    _watchdog = Timer(watchdogPeriod, () async {
      if (_disposed || gen != _playGen) return;
      final np = nowPlaying;
      if (np == null || np.positionMs > 0) return;
      if (allowRecover && await _recoverStaleLink(head, gen)) {
        _armWatchdog(head, gen, allowRecover: false);
        return;
      }
      if (_disposed || gen != _playGen) return;
      _failAndSkip(l10n.skipUnplayable(np.title), gen);
    });
  }

  /// 丢掉可能过期的直链、重新取一次并重开播放。返回新链是否已交给引擎。
  Future<bool> _recoverStaleLink(QueueItem head, int gen) async {
    final e = engine;
    if (e == null) return false;
    library.invalidateAudio(head.trackKey);
    AudioRef? refetched;
    try {
      refetched = await library.audioFor(head.trackKey, refresh: true);
    } catch (_) {
      refetched = null;
    }
    if (refetched == null || _disposed || gen != _playGen) return false;
    try {
      await e.open(refetched.uri, autoplay: playing, headers: refetched.headers);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _cancelWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  void _failAndSkip(String message, int gen) {
    if (_disposed || gen != _playGen) return;
    _playbackError = message;
    _advanceHead();
  }

  /// 队首出队，后面顶上；空队列则停止播放。
  void _advanceHead() {
    if (queue.isEmpty) return;
    queue.removeAt(0);
    final head = nowPlaying;
    if (head == null) {
      playing = false;
      _cancelWatchdog();
      unawaited(engine?.stop());
    } else if (engine != null) {
      unawaited(_loadCurrent());
    }
    unawaited(_warmArt(head?.trackKey));
    notifyListeners();
    edge.notifyTrackChanged();
  }

  void togglePlay() {
    if (engine != null && nowPlaying == null) return;
    playing = !playing;
    if (engine != null) {
      unawaited(playing ? engine!.play() : engine!.pause());
    }
    notifyListeners();
    edge.notifyPlayback();
  }

  /// 「下一首」：移出队首让后面顶上。
  void skip() {
    if (queue.isEmpty) return;
    _advanceHead();
  }

  /// 「上一首」：没有历史队列，回到当前曲目开头。
  void previous() {
    if (nowPlaying == null) return;
    seekTo(0);
  }

  void seekTo(int positionMs) {
    final head = nowPlaying;
    if (head == null) return;
    final upper = head.durationMs > 0 ? head.durationMs : (1 << 31);
    final ms = positionMs.clamp(0, upper);
    head.positionMs = ms;
    notifyListeners();
    unawaited(engine?.seek(Duration(milliseconds: ms)));
    if (engine != null) edge.notifyPlayback();
  }

  void setVolume(double value) {
    volume = value.clamp(0.0, 1.0);
    notifyListeners();
    unawaited(engine?.setVolume(volume));
  }

  void removeAt(int i) {
    if (i < 0 || i >= queue.length) return;
    queue.removeAt(i);
    final headChanged = i == 0;
    if (headChanged) {
      final head = nowPlaying;
      if (head == null) {
        playing = false;
        _cancelWatchdog();
        unawaited(engine?.stop());
      } else if (engine != null) {
        unawaited(_loadCurrent());
      }
      unawaited(_warmArt(head?.trackKey));
    }
    notifyListeners();
    if (headChanged) {
      edge.notifyTrackChanged();
    } else {
      edge.notifyQueueChanged();
    }
  }

  /// `to` 是 ReorderableList 的 onReorderItem 语义：已按移除后的列表修正过的落点。
  void move(int from, int to) {
    if (from < 0 || from >= queue.length || from == to) return;
    final item = queue.removeAt(from);
    if (to < 0 || to > queue.length) {
      queue.insert(from, item);
      return;
    }
    queue.insert(to, item);
    final headChanged = from == 0 || to == 0;
    if (headChanged) {
      unawaited(_warmArt(nowPlaying?.trackKey));
      if (engine != null) unawaited(_loadCurrent());
    }
    notifyListeners();
    if (headChanged) {
      edge.notifyTrackChanged();
    } else {
      edge.notifyQueueChanged();
    }
  }

  /// 入队前先解析一次播放地址：解析不出来的曲目不接受，
  /// 否则顾客只会看到自己点的歌在队列里闪一下就没了（错误只有 B端 屏幕能看见）。
  Future<EnqueueResult> _handleEnqueue(EnqueueRequest req) async {
    var track = library.byKey(req.trackKey);
    // 节点重启、换机，或页面开了很久之后，本机可能已经不认识这个 trackKey（在线曲目
    // 只缓存在内存里）。用请求里的歌名/歌手在本机重新映射一次（协议 §10.3），
    // 映射不到才算真的没有。
    if (track == null) {
      track = await _remapTrack(req);
      if (track == null) return const EnqueueResult.rejected(errTrackNotFound);
    }
    if (queue.length >= 200) {
      return const EnqueueResult.rejected(errQueueFull, '前面排队的人太多了，稍后再点');
    }
    try {
      final uri = await library.audioUriFor(track.trackKey).timeout(_enqueueResolveBudget);
      if (uri == null) {
        return const EnqueueResult.rejected(errSourceUnavailable, '这首歌本店暂时放不了，换一首试试');
      }
    } on TimeoutException {
      return const EnqueueResult.rejected(errSourceUnavailable, '取链超时，稍后再点一次试试');
    }
    final wasEmpty = queue.isEmpty;
    queue.add(QueueItem(
      trackKey: track.trackKey,
      title: track.title,
      artist: track.artist,
      durationMs: track.durationMs,
      seat: req.seat,
    ));
    if (wasEmpty) {
      playing = true;
      unawaited(_warmArt(track.trackKey));
      if (engine != null) unawaited(_loadCurrent());
    }
    notifyListeners();
    edge.notifyQueueChanged();
    // 空闲时入队会直接开播，此时曲目已切换，必须重发歌词主题。
    if (wasEmpty) edge.publishLyric();
    return EnqueueResult.accepted(queue.length);
  }

  /// 把已经失效的 trackKey 映射成本机曲库里真实存在的一条。
  ///
  /// 在线曲目 `lx:` 的 trackKey 由 `platform:songId` 决定；但取链依赖本机的在线曲目
  /// 元数据缓存（只在内存里），节点重启后就散了。这里补一次检索并 remember，
  /// 之后 `audioFor` 才能解析出播放地址。
  Future<Track?> _remapTrack(EnqueueRequest req) async {
    final hint = req.hint;
    if (hint == null) return null;
    final queries = <String>[
      hint.title,
      if (hint.artist.isNotEmpty) '${hint.title} ${hint.artist}',
    ];
    for (final query in queries) {
      try {
        final page = await library.searchAsync(query, limit: 12, timeout: _remapBudget);
        final hit = matchCandidate(
          page.items,
          trackKey: req.trackKey,
          title: hint.title,
          artist: hint.artist,
          durationMs: hint.durationMs,
        );
        if (hit != null) {
          library.remember([hit]);
          return hit;
        }
      } catch (_) {
        // 在线音源不可用就算了：映射不到就老实回 TRACK_NOT_FOUND。
      }
    }
    return null;
  }

  Map<String, Object?> _snapshot() {
    Map<String, Object?> item(QueueItem q) => {
          'trackKey': q.trackKey,
          'title': q.title,
          'artist': q.artist,
          'durationMs': q.durationMs,
          if (q.seat != null) 'guest': {'seat': q.seat},
        };
    final np = nowPlaying;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return {
      'player': np == null
          ? null
          : {
              ...item(np),
              'positionMs': np.positionMs,
              'sampledAtMs': nowMs,
              'rate': playing ? 1 : 0,
              'lyricAvailable': _lyricAvailable,
              'audioLatencyMs': 0,
            },
      'queue': [for (var i = 1; i < queue.length; i++) item(queue[i])],
    };
  }

  /// 切歌时预热播放卡素材：歌词解析成带时间的行，同时取封面地址。
  Future<void> _warmArt(String? trackKey) async {
    final generation = ++_lyricGeneration;
    final hadLyric = _lyricAvailable;
    _lyricAvailable = false;
    _lyricLines = const [];
    _cover = null;
    if (trackKey == null) {
      notifyListeners();
      if (hadLyric) edge.notifyQueueChanged();
      return;
    }
    unawaited(_warmCover(trackKey, generation));
    final lyric = await library.lyricFor(trackKey);
    if (_disposed || generation != _lyricGeneration) return;
    final text = lyric?.lyric ?? '';
    _lyricAvailable = text.trim().isNotEmpty;
    _lyricLines = _lyricAvailable ? parseLyric(text, format: lyric?.format ?? 'lrc') : const [];
    notifyListeners();
    // 入队时快照已先发出（那时歌词还没解析完），可用性变了要重发 retained。
    if (_lyricAvailable != hadLyric) edge.notifyQueueChanged();
  }

  Future<void> _warmCover(String trackKey, int generation) async {
    Uri? uri;
    try {
      uri = await library.picUriFor(trackKey);
    } catch (_) {
      uri = null;
    }
    if (_disposed || generation != _lyricGeneration) return;
    _cover = uri;
    notifyListeners();
  }

  /// 歌词体；位置/暂停仍由队列快照里的 player 字段表达。
  Future<Map<String, Object?>?> _lyric() async {
    final np = nowPlaying;
    if (np == null) return null;
    final lyric = await library.lyricFor(np.trackKey);
    final raw = lyric?.lyric ?? '';
    if (raw.trim().isEmpty) return null;
    // 对外协议只发标准 LRC：逐字格式在本地解析后压回行级文本。
    final text = toLrcText(parseLyric(raw, format: lyric?.format ?? 'lrc'));
    if (text.trim().isEmpty) return null;
    // 偏移取投放设置里那一份：墙上字幕和手机端的词要按同一个量挪。
    return {'trackKey': np.trackKey, 'format': 'lrc', 'offsetMs': _cast.style.offsetMs, 'text': text};
  }

  Map<String, Object?> _health() => {
        'queueDepth': queue.length,
        'playing': playing,
        // 没有可播结果时不声明 search，避免 C端 搜出一支点不响的歌。
        'caps': [
          if (library.canSearch) 'search',
          // 歌单曲目同样要能取链，跟着 search 一起开关。
          if (library.canSearch) capFeatured,
          'enqueue',
          'snapshot',
          'events',
        ],
        'library': {
          'count': library.tracks.length,
          'scanning': scanning,
          'scanned': scanned,
          'broken': brokenCount,
          'lyricAvailable': _lyricAvailable,
        },
      };

  @override
  void dispose() {
    _disposed = true;
    webDav?.removeListener(_onWebDavChanged);
    webDav?.dispose();
    _castWindows?.dispose();
    _tick?.cancel();
    _cancelWatchdog();
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_completedSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(engine?.dispose());
    edge.dispose();
    super.dispose();
  }
}

String fmtMs(int ms) {
  final s = (ms / 1000).floor().clamp(0, 1 << 31);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
