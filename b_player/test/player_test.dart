import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/edge/config.dart';
import 'package:b_player/edge/library.dart';
import 'package:b_player/edge/player_engine.dart';
import 'package:b_player/edge/protocol.dart';
import 'package:b_player/l10n/l10n.dart';
import 'package:b_player/log.dart';
import 'package:b_player/state/app_state.dart';

const _mqtt = MqttConfig(enabled: false);

class _FakeSource extends MusicSource {
  _FakeSource(this.tracks, {this.failingKeys = const {}});

  final List<Track> tracks;

  /// 模拟在线音源取链失败。
  final Set<String> failingKeys;

  /// 取链次数，用来验证直链缓存。
  int audioCalls = 0;

  @override
  String get id => 'fake';

  @override
  String get kind => 'memory';

  @override
  String get label => '测试音源';

  @override
  Set<MusicSourceCapability> get capabilities => const {
        MusicSourceCapability.list,
        MusicSourceCapability.audio,
        MusicSourceCapability.lyric,
      };

  @override
  Future<List<String>> listTrackKeys() async => [for (final t in tracks) t.trackKey];

  @override
  Future<List<Track>> fetchTracks(List<String> keys) async => tracks;

  @override
  Future<Uri> audioUri(Track track) async {
    audioCalls++;
    if (failingKeys.contains(track.trackKey)) throw const MusicSourceException('取链失败');
    return Uri.parse('https://cdn.example/${track.trackKey.replaceAll(':', '_')}.mp3');
  }

  @override
  Future<MusicLyric> lyric(Track track) async => const MusicLyric(lyric: '[00:00.00]测试');
}

class _FakeEngine implements AudioEngine {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _error = StreamController<String>.broadcast();

  final List<Uri> opened = [];
  Map<String, String>? lastHeaders;
  bool lastAutoplay = true;
  bool playing = false;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  Duration? lastSeek;
  double volume = 1;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Stream<String> get errorStream => _error.stream;

  @override
  Future<void> open(Uri uri, {bool autoplay = true, Map<String, String>? headers}) async {
    opened.add(uri);
    lastHeaders = headers;
    lastAutoplay = autoplay;
    if (uri.path.contains('bad')) throw StateError('解码失败');
    playing = autoplay;
  }

  @override
  Future<void> play() async {
    playCalls++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
  }

  @override
  Future<void> seek(Duration position) async => lastSeek = position;

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
  }

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _completed.close();
    await _error.close();
  }

  void emitPosition(int ms) => _position.add(Duration(milliseconds: ms));

  void emitDuration(int ms) => _duration.add(Duration(milliseconds: ms));

  void emitCompleted() => _completed.add(true);

  void emitError(String message) => _error.add(message);
}

({AppState state, _FakeEngine engine, _FakeSource source}) _build({
  Set<String> failingKeys = const {},
  Duration watchdog = const Duration(seconds: 8),
}) {
  final tracks = [
    Track(trackKey: 'fake:a', title: '甲', artist: 'A', durationMs: 3000, sourceId: 'fake'),
    Track(trackKey: 'fake:bad', title: '坏', artist: 'B', durationMs: 3000, sourceId: 'fake'),
    Track(trackKey: 'fake:b', title: '乙', artist: 'C', durationMs: 4000, sourceId: 'fake'),
  ];
  final source = _FakeSource(tracks, failingKeys: failingKeys);
  final engine = _FakeEngine();
  final state = AppState(
    mqtt: _mqtt,
    library: Library([source], tracks: tracks),
    engine: engine,
    watchdogPeriod: watchdog,
  );
  return (state: state, engine: engine, source: source);
}

Future<EnqueueResult> _enqueue(AppState state, String key) async {
  return await state.edge.enqueue(EnqueueRequest(trackKey: key, requestId: 'req-$key'));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('入队后解析播放地址、打开引擎并开始播放', () async {
    final h = _build();
    addTearDown(h.state.dispose);

    _enqueue(h.state, 'fake:a');
    await pumpEventQueue();

    expect(h.engine.opened.map((u) => u.toString()),
        ['https://cdn.example/fake_a.mp3']);
    expect(h.engine.lastAutoplay, isTrue);
    expect(h.engine.volume, closeTo(.7, 1e-9));
    expect(h.state.playing, isTrue);
    expect(h.state.playbackError, isNull);
  });

  test('进度与时长以引擎上报为准', () async {
    final h = _build();
    addTearDown(h.state.dispose);
    _enqueue(h.state, 'fake:a');
    await pumpEventQueue();

    h.engine.emitPosition(1250);
    h.engine.emitDuration(3300);
    await pumpEventQueue();

    expect(h.state.nowPlaying!.positionMs, 1250);
    expect(h.state.nowPlaying!.durationMs, 3300);
  });

  test('播放完成自动切下一首，队列空了就停止', () async {
    final h = _build();
    addTearDown(h.state.dispose);
    _enqueue(h.state, 'fake:a');
    _enqueue(h.state, 'fake:b');
    await pumpEventQueue();

    h.engine.emitCompleted();
    await pumpEventQueue();

    expect(h.state.queue.length, 1);
    expect(h.state.nowPlaying!.trackKey, 'fake:b');
    expect(h.engine.opened.length, 2);
    expect(h.engine.opened.last.toString(), contains('fake_b'));
    expect(h.state.playing, isTrue);

    h.engine.emitCompleted();
    await pumpEventQueue();

    expect(h.state.queue, isEmpty);
    expect(h.state.playing, isFalse);
    expect(h.engine.stopCalls, 1);
  });

  test('暂停/继续、音量与 seek 都下发到引擎', () async {
    final h = _build();
    addTearDown(h.state.dispose);
    _enqueue(h.state, 'fake:a');
    await pumpEventQueue();
    h.engine.emitDuration(4000);
    await pumpEventQueue();

    h.state.togglePlay();
    await pumpEventQueue();
    expect(h.state.playing, isFalse);
    expect(h.engine.pauseCalls, 1);

    h.state.togglePlay();
    await pumpEventQueue();
    expect(h.state.playing, isTrue);
    expect(h.engine.playCalls, 1);

    h.state.setVolume(.25);
    await pumpEventQueue();
    expect(h.state.volume, .25);
    expect(h.engine.volume, .25);
    h.state.setVolume(2);
    expect(h.state.volume, 1);

    h.state.seekTo(5000);
    await pumpEventQueue();
    expect(h.state.nowPlaying!.positionMs, 4000);
    expect(h.engine.lastSeek, const Duration(milliseconds: 4000));

    h.state.previous();
    await pumpEventQueue();
    expect(h.engine.lastSeek, Duration.zero);
  });

  test('取链失败的曲目不入队，并把原因带回给 C端', () async {
    final h = _build(failingKeys: {'fake:a'});
    addTearDown(h.state.dispose);

    final rejected = await _enqueue(h.state, 'fake:a');
    await pumpEventQueue();

    expect(rejected.accepted, isFalse);
    expect(rejected.reason, errSourceUnavailable);
    expect(rejected.message, contains('放不了'));
    expect(h.state.queue, isEmpty);
    expect(h.state.nowPlaying, isNull);
    expect(h.engine.opened, isEmpty, reason: '放不了的歌根本不该进队列');

    final accepted = await _enqueue(h.state, 'fake:b');
    await pumpEventQueue();

    expect(accepted.accepted, isTrue);
    expect(h.state.nowPlaying!.trackKey, 'fake:b');
    expect(h.engine.opened.map((u) => u.toString()), ['https://cdn.example/fake_b.mp3']);
    expect(h.state.playbackError, isNull);
  });

  test('入队解析过的直链被复用，不重复取链', () async {
    final h = _build();
    addTearDown(h.state.dispose);

    await _enqueue(h.state, 'fake:a');
    await pumpEventQueue();

    expect(h.source.audioCalls, 1);
    expect(h.engine.opened, hasLength(1));
  });

  test('引擎打开失败时强制重取直链，仍失败才跳过', () async {
    final h = _build();
    addTearDown(h.state.dispose);

    await _enqueue(h.state, 'fake:bad');
    await _enqueue(h.state, 'fake:b');
    await pumpEventQueue();

    expect(h.state.nowPlaying!.trackKey, 'fake:b');
    expect(h.engine.opened, hasLength(3));
    expect(h.engine.opened[0].toString(), contains('fake_bad'));
    expect(h.engine.opened[1].toString(), contains('fake_bad'), reason: '打不开就强制重新取链再试一次');
    expect(h.engine.opened[2].toString(), contains('fake_b'));
    expect(h.source.audioCalls, 3, reason: '坏歌入队 1 次 + 重取 1 次，乙入队 1 次后播放复用缓存');
    expect(h.state.playbackError, l10n.playOpenFailed('坏', 'Bad state: 解码失败'));
  });

  test('打开后一直没有进度：先重取直链重开，第二次仍无进度才跳过', () async {
    final h = _build(watchdog: const Duration(milliseconds: 60));
    addTearDown(h.state.dispose);

    await _enqueue(h.state, 'fake:a');
    await pumpEventQueue();
    expect(h.engine.opened, hasLength(1));
    expect(h.source.audioCalls, 1);

    // 引擎打开成功但从不报进度：这正是直链过期的典型表现。
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await pumpEventQueue();

    expect(h.source.audioCalls, 2, reason: '先按直链过期重取一次');
    expect(h.engine.opened, hasLength(2), reason: '新链要重新交给引擎');
    expect(h.state.queue, hasLength(1), reason: '还有救的时候不能跳歌');
    expect(h.state.playbackError, isNull);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    await pumpEventQueue();

    expect(h.state.queue, isEmpty, reason: '重取后仍无进度，才判定放不了');
    expect(h.state.playbackError, isNotNull);
  });

  test('健康状态里的 caps 跟随真实能力', () async {
    final h = _build();
    addTearDown(h.state.dispose);
    expect(h.state.edge.health()['caps'], contains('search'), reason: '本机有索引就是可播结果');

    final empty = AppState(
      mqtt: _mqtt,
      library: Library(<MusicSource>[], tracks: const []),
      engine: _FakeEngine(),
    );
    addTearDown(empty.dispose);
    final caps = empty.edge.health()['caps'] as List;
    expect(caps, isNot(contains('search')), reason: '搜出来也放不了，就别声明会检索');
    expect(caps, containsAll(<String>['enqueue', 'snapshot', 'events']));
  });

  test('引擎错误会显示在状态里，成功拿到时长后清除', () async {
    final h = _build();
    addTearDown(h.state.dispose);
    _enqueue(h.state, 'fake:a');
    await pumpEventQueue();

    h.engine.emitError('Failed to recognize file format.');
    await pumpEventQueue();
    expect(h.state.playbackError, l10n.audioFormatUnsupported);

    h.engine.emitDuration(3000);
    await pumpEventQueue();
    expect(h.state.playbackError, isNull);
  });

  test('一次播放的关键环节都写进日志，能按 #gen 串起来', () async {
    final dir = await Directory.systemTemp.createTemp('enode_play_log');
    addTearDown(() async {
      await EnodeLog.close();
      await dir.delete(recursive: true);
    });
    await EnodeLog.init(dir: dir);

    final h = _build();
    addTearDown(h.state.dispose);

    await _enqueue(h.state, 'fake:a');
    await pumpEventQueue();
    h.state.togglePlay();
    h.state.skip();
    // 歌词单独走一条链路（library.lyricFor → 上游），也必须有记录。
    await h.state.edge.lyric();
    await pumpEventQueue();
    await EnodeLog.close();

    final files = dir.listSync().whereType<File>().toList();
    final text = await files.single.readAsString();

    expect(text, contains('[queue] 接受《甲》'), reason: '入队要有记录');
    expect(text, contains('[audio]'), reason: '取链过程要有记录');
    expect(text, contains('取链成功'), reason: '取链结果要有记录');
    expect(text, contains('[player] #'), reason: '播放阶段要带 gen 便于串联');
    expect(text, contains('开始加载《甲》'), reason: '切歌开始要有记录');
    expect(text, contains('开播《甲》'), reason: '开播要有记录');
    expect(text, contains('暂停'), reason: '暂停操作要有记录');
    expect(text, contains('手动下一首'), reason: '切歌操作要有记录');
    expect(text, contains('[lyric]'), reason: '取词过程要有记录');
    expect(text, contains('取词成功'), reason: '取词结果要有记录');
  });
}
