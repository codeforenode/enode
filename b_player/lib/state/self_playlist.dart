import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../edge/atomic_json.dart';

enum PlaylistMode {
  sequential,
  shuffle;

  static PlaylistMode fromCode(String? code) =>
      values.firstWhere((m) => m.name == code, orElse: () => sequential);
}

/// 一天内的播放区间，按「当天 0 点起的分钟数」保存。
class PlaylistWindow {
  const PlaylistWindow(this.startMinutes, this.endMinutes);

  final int startMinutes;
  final int endMinutes;

  bool get overnight => startMinutes > endMinutes;
  bool get allDay => startMinutes == endMinutes;

  PlaylistWindow copyWith({int? startMinutes, int? endMinutes}) => PlaylistWindow(
        startMinutes ?? this.startMinutes,
        endMinutes ?? this.endMinutes,
      );

  Map<String, Object?> toJson() => {'start': startMinutes, 'end': endMinutes};

  static PlaylistWindow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final start = raw['start'];
    final end = raw['end'];
    if (start is! num || end is! num) return null;
    return PlaylistWindow(
      start.toInt().clamp(0, 1439),
      end.toInt().clamp(0, 1439),
    );
  }
}

/// 每份列表自己的时段：支持跨午夜（22:00–02:00 算前一天生效）。
class PlaylistSchedule {
  PlaylistSchedule({
    this.enabled = false,
    Set<int>? days,
    List<PlaylistWindow>? windows,
  })  : days = {...?days},
        windows = [...?windows];

  factory PlaylistSchedule.defaults() => PlaylistSchedule(
        days: {1, 2, 3, 4, 5, 6, 7},
        windows: [const PlaylistWindow(9 * 60, 22 * 60)],
      );

  bool enabled;

  /// ISO 星期：周一 = 1 … 周日 = 7。
  final Set<int> days;
  final List<PlaylistWindow> windows;

  bool get canRun => days.isNotEmpty && windows.isNotEmpty;

  bool isActiveAt(DateTime now) {
    if (!enabled || !canRun) return false;
    final today = now.weekday;
    final yesterday = today == 1 ? 7 : today - 1;
    final minute = now.hour * 60 + now.minute;
    for (final w in windows) {
      if (w.allDay) {
        if (days.contains(today)) return true;
      } else if (!w.overnight) {
        if (days.contains(today) && minute >= w.startMinutes && minute < w.endMinutes) {
          return true;
        }
      } else {
        if (days.contains(today) && minute >= w.startMinutes) return true;
        if (days.contains(yesterday) && minute < w.endMinutes) return true;
      }
    }
    return false;
  }

  PlaylistSchedule copy() => PlaylistSchedule(
        enabled: enabled,
        days: days,
        windows: [for (final w in windows) w.copyWith()],
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'days': (days.toList()..sort()),
        'windows': [for (final w in windows) w.toJson()],
      };

  static PlaylistSchedule fromJson(Object? raw) {
    if (raw is! Map) return PlaylistSchedule();
    final days = <int>{};
    final rawDays = raw['days'];
    if (rawDays is List) {
      for (final d in rawDays) {
        if (d is num) {
          final day = d.toInt();
          if (day >= 1 && day <= 7) days.add(day);
        }
      }
    }
    final windows = <PlaylistWindow>[];
    final rawWindows = raw['windows'];
    if (rawWindows is List) {
      for (final w in rawWindows) {
        final window = PlaylistWindow.fromJson(w);
        if (window != null) windows.add(window);
      }
    }
    return PlaylistSchedule(
      enabled: raw['enabled'] == true,
      days: days,
      windows: windows,
    );
  }
}

/// 列表里的一条歌单项。在线曲目只存指纹与展示信息，播放时再映射回 [Library]。
class PlaylistEntry {
  const PlaylistEntry({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.durationMs,
    required this.sourceId,
  });

  final String trackKey;
  final String title;
  final String artist;
  final int durationMs;
  final String sourceId;

  PlaylistEntry copyWith({
    String? trackKey,
    String? title,
    String? artist,
    int? durationMs,
    String? sourceId,
  }) =>
      PlaylistEntry(
        trackKey: trackKey ?? this.trackKey,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        durationMs: durationMs ?? this.durationMs,
        sourceId: sourceId ?? this.sourceId,
      );

  Map<String, Object?> toJson() => {
        'key': trackKey,
        'title': title,
        'artist': artist,
        'durationMs': durationMs,
        'source': sourceId,
      };

  static PlaylistEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    if (key is! String || key.isEmpty) return null;
    return PlaylistEntry(
      trackKey: key,
      title: raw['title'] is String ? raw['title'] as String : '',
      artist: raw['artist'] is String ? raw['artist'] as String : '',
      durationMs: raw['durationMs'] is num ? (raw['durationMs'] as num).toInt() : 0,
      sourceId: raw['source'] is String ? raw['source'] as String : 'local',
    );
  }
}

/// 一份自建列表：顺序/随机、自己的定时段和续播位置。
///
/// [index] 与 [positionMs] 是「上次停在哪儿」，点歌插播和暂停都会更新它；
/// [lastPlayedAtMs] 用来判断时段重新开始时该续播还是从头开始。
class SelfPlaylist {
  SelfPlaylist({
    required this.id,
    required this.name,
    this.mode = PlaylistMode.sequential,
    PlaylistSchedule? schedule,
    List<PlaylistEntry>? tracks,
    this.index = 0,
    this.positionMs = 0,
    this.lastPlayedAtMs = 0,
  })  : schedule = schedule ?? PlaylistSchedule(),
        tracks = [...?tracks];

  final String id;
  String name;
  PlaylistMode mode;
  PlaylistSchedule schedule;
  final List<PlaylistEntry> tracks;
  int index;
  int positionMs;
  int lastPlayedAtMs;

  List<int> _shuffleBag = [];
  static final Random _random = Random();

  PlaylistEntry? get current =>
      index >= 0 && index < tracks.length ? tracks[index] : null;

  bool contains(String trackKey) => tracks.any((t) => t.trackKey == trackKey);

  void normalize() {
    if (tracks.isEmpty) {
      index = 0;
      positionMs = 0;
      _shuffleBag = [];
      return;
    }
    if (index < 0 || index >= tracks.length) index = 0;
    if (positionMs < 0) positionMs = 0;
    _shuffleBag.removeWhere((i) => i < 0 || i >= tracks.length);
  }

  bool addTrack(PlaylistEntry entry) {
    if (contains(entry.trackKey)) return false;
    tracks.add(entry);
    if (tracks.length == 1) {
      index = 0;
      positionMs = 0;
    }
    _shuffleBag = [];
    return true;
  }

  void removeTrackAt(int i) {
    if (i < 0 || i >= tracks.length) return;
    final wasCurrent = i == index;
    tracks.removeAt(i);
    _shuffleBag = [];
    if (tracks.isEmpty) {
      index = 0;
      positionMs = 0;
    } else if (wasCurrent) {
      if (index >= tracks.length) index = 0;
      positionMs = 0;
    } else if (i < index) {
      index--;
    }
  }

  /// `to` 与 ReorderableList.onReorderItem 一致：已经按移除后的列表修正过。
  void moveTrack(int from, int to) {
    if (from < 0 || from >= tracks.length || from == to) return;
    final item = tracks.removeAt(from);
    final target = to.clamp(0, tracks.length);
    tracks.insert(target, item);
    if (index == from) {
      index = target;
    } else if (from < index && target >= index) {
      index--;
    } else if (from > index && target <= index) {
      index++;
    }
    _shuffleBag = [];
  }

  void setMode(PlaylistMode next) {
    if (mode == next) return;
    mode = next;
    _shuffleBag = [];
  }

  /// 下一首的下标；随机模式一轮内不重复，只避开当前曲目。
  int nextIndex() {
    if (tracks.isEmpty) return -1;
    if (tracks.length == 1) return 0;
    if (mode == PlaylistMode.sequential) return (index + 1) % tracks.length;

    while (_shuffleBag.isNotEmpty) {
      final i = _shuffleBag.removeLast();
      if (i != index && i >= 0 && i < tracks.length) return i;
    }
    _shuffleBag = [
      for (var i = 0; i < tracks.length; i++)
        if (i != index) i,
    ]..shuffle(_random);
    return _shuffleBag.isNotEmpty ? _shuffleBag.removeLast() : index;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'mode': mode.name,
        'schedule': schedule.toJson(),
        'index': index,
        'positionMs': positionMs,
        'lastPlayedAtMs': lastPlayedAtMs,
        'tracks': [for (final t in tracks) t.toJson()],
      };

  /// 结构快照：不带播放进度。进度高频变化，单独放 `playlist_state.json`，
  /// 避免每 10 秒把整份列表重新写一遍。
  Map<String, Object?> toStructureJson() => {
        'id': id,
        'name': name,
        'mode': mode.name,
        'schedule': schedule.toJson(),
        'tracks': [for (final t in tracks) t.toJson()],
      };

  Map<String, Object?> toStateJson() => {
        'id': id,
        'index': index,
        'positionMs': positionMs,
        'lastPlayedAtMs': lastPlayedAtMs,
      };

  static SelfPlaylist? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final tracks = <PlaylistEntry>[];
    final rawTracks = raw['tracks'];
    if (rawTracks is List) {
      for (final t in rawTracks) {
        final entry = PlaylistEntry.fromJson(t);
        if (entry != null) tracks.add(entry);
      }
    }
    final playlist = SelfPlaylist(
      id: id,
      name: raw['name'] is String ? raw['name'] as String : '',
      mode: PlaylistMode.fromCode(raw['mode'] is String ? raw['mode'] as String : null),
      schedule: PlaylistSchedule.fromJson(raw['schedule']),
      tracks: tracks,
      index: raw['index'] is num ? (raw['index'] as num).toInt() : 0,
      positionMs: raw['positionMs'] is num ? (raw['positionMs'] as num).toInt() : 0,
      lastPlayedAtMs:
          raw['lastPlayedAtMs'] is num ? (raw['lastPlayedAtMs'] as num).toInt() : 0,
    );
    if (playlist.name.trim().isEmpty) playlist.name = id;
    playlist.normalize();
    return playlist;
  }
}

class PlaylistSnapshot {
  const PlaylistSnapshot({this.lists = const [], this.activeId});

  final List<SelfPlaylist> lists;
  final String? activeId;

  Map<String, Object?> toJson() => {
        'active': activeId,
        'lists': [for (final p in lists) p.toJson()],
      };

  /// 与 [toJson] 相同但去掉进度字段；文件名级别的结构快照只在这里写。
  Map<String, Object?> toStructureJson() => {
        'v': 2,
        'active': activeId,
        'lists': [for (final p in lists) p.toStructureJson()],
      };

  Map<String, Object?> toStateJson() => {
        'v': 1,
        'active': activeId,
        'lists': [for (final p in lists) p.toStateJson()],
      };

  static PlaylistSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lists = <SelfPlaylist>[];
    final rawLists = raw['lists'];
    if (rawLists is List) {
      for (final r in rawLists) {
        final p = SelfPlaylist.fromJson(r);
        if (p != null) lists.add(p);
      }
    }
    final active = raw['active'];
    return PlaylistSnapshot(
      lists: lists,
      activeId: active is String ? active : null,
    );
  }

  /// 结构 + 状态两份文件合回一个快照；状态按列表 id 对齐。
  static PlaylistSnapshot? fromFiles(Object? structure, Object? state) {
    if (structure is! Map) return null;
    final lists = <SelfPlaylist>[];
    final rawLists = structure['lists'];
    if (rawLists is List) {
      for (final r in rawLists) {
        final p = SelfPlaylist.fromJson(r);
        if (p != null) lists.add(p);
      }
    }
    String? active = structure['active'] is String ? structure['active'] as String : null;
    if (state is Map) {
      if (state['active'] is String) active = state['active'] as String;
      final byId = <String, Map>{};
      final rawStates = state['lists'];
      if (rawStates is List) {
        for (final item in rawStates) {
          if (item is Map && item['id'] is String) {
            byId[item['id'] as String] = item;
          }
        }
      }
      for (final playlist in lists) {
        final saved = byId[playlist.id];
        if (saved == null) continue;
        if (saved['index'] is num) playlist.index = (saved['index'] as num).toInt();
        if (saved['positionMs'] is num) {
          playlist.positionMs = (saved['positionMs'] as num).toInt();
        }
        if (saved['lastPlayedAtMs'] is num) {
          playlist.lastPlayedAtMs = (saved['lastPlayedAtMs'] as num).toInt();
        }
        playlist.normalize();
      }
    }
    return PlaylistSnapshot(lists: lists, activeId: active);
  }
}

/// 自建列表落盘：结构写 `data/playlists.json`，进度写 `data/playlist_state.json`。
///
/// 旧版本把整份列表（含播放位置）放在 prefs 的 `playlists.v1` 里，播放时每 10 秒
/// 重写整个 prefs 文件。现在进度单独落盘，结构只在增删/排序/改设置时写。
class PlaylistStore {
  PlaylistStore([this._directory]);

  /// 显式目录用于测试；正式运行放到应用支持目录的 `data/` 下。
  final Directory? _directory;

  static const _legacyKey = 'playlists.v1';
  static const _directoryName = 'data';

  Future<Directory> _dir() async {
    final explicit = _directory;
    if (explicit != null) return explicit;
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, _directoryName));
  }

  File _structureFile(Directory dir) => File(p.join(dir.path, 'playlists.json'));

  File _stateFile(Directory dir) => File(p.join(dir.path, 'playlist_state.json'));

  Future<PlaylistSnapshot?> load() async {
    Directory dir;
    try {
      dir = await _dir();
    } catch (_) {
      // 无 path_provider 的测试/预览环境：只读旧 prefs，不迁移。
      return _loadLegacy();
    }
    final structure = await AtomicJsonFile(_structureFile(dir)).read();
    if (structure is Map) {
      final state = await AtomicJsonFile(_stateFile(dir)).read();
      final snapshot = PlaylistSnapshot.fromFiles(structure, state);
      if (snapshot != null) return snapshot;
    }
    final legacy = await _loadLegacy();
    if (legacy != null) {
      // 先写新文件，旧 key 保留一版做回滚兜底；播放过程不再写 prefs。
      try {
        await writeStructure(_encodeStructure(legacy));
        await writeState(_encodeState(legacy));
      } catch (_) {}
    }
    return legacy;
  }

  Future<PlaylistSnapshot?> _loadLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyKey);
      if (raw == null || raw.trim().isEmpty) return null;
      return PlaylistSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeStructure(String encoded) async {
    try {
      await AtomicJsonFile(_structureFile(await _dir())).writeText(encoded);
    } catch (_) {
      // 落盘失败不能拖垮播放；下一次结构变更会再试。
    }
  }

  Future<void> writeState(String encoded) async {
    try {
      await AtomicJsonFile(_stateFile(await _dir())).writeText(encoded);
    } catch (_) {
      // 同上。
    }
  }

  /// 兼容旧调用：把一整份快照拆成结构 + 状态两份文件。
  Future<void> save(String encoded) async {
    final snapshot = PlaylistSnapshot.fromJson(jsonDecode(encoded));
    if (snapshot == null) return;
    await writeStructure(_encodeStructure(snapshot));
    await writeState(_encodeState(snapshot));
  }

  static String encode(PlaylistSnapshot snapshot) =>
      jsonEncode(snapshot.toJson());

  static String encodeStructure(PlaylistSnapshot snapshot) =>
      jsonEncode(snapshot.toStructureJson());

  static String encodeState(PlaylistSnapshot snapshot) =>
      jsonEncode(snapshot.toStateJson());

  static String _encodeStructure(PlaylistSnapshot snapshot) =>
      encodeStructure(snapshot);

  static String _encodeState(PlaylistSnapshot snapshot) =>
      encodeState(snapshot);
}
