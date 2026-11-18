import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../edge/player_engine.dart';
import '../l10n/l10n.dart';

enum AudioOutputNotice { unavailable, selectionFailed, fallbackFailed, loadFailed, saveFailed }

/// 设备操作只改输出属性，不打开、停止或重排歌曲。所有写入按请求顺序执行。
class AudioOutputController extends ChangeNotifier {
  AudioOutputController(this.engine) {
    _subscription = engine.audioDevicesStream.listen(_devicesChanged, onError: (Object _) {
      if (_disposed) return;
      notice = AudioOutputNotice.loadFailed;
      notifyListeners();
    });
    final request = _request;
    ready = _enqueue(() => _restore(request));
  }

  static const preferenceKey = 'player.audioOutput';
  final AudioOutputEngine engine;
  late final Future<void> ready;
  late final StreamSubscription<List<AudioOutputDevice>> _subscription;
  Future<void> _tail = Future<void>.value();
  SharedPreferences? _preferences;
  bool _disposed = false;
  bool _loaded = false;
  int _pending = 0;
  int _request = 0;
  int _deviceRevision = 0;
  List<AudioOutputDevice> devices = const [AudioOutputDevice.system];
  AudioOutputDevice selected = AudioOutputDevice.system;
  AudioOutputNotice? notice;
  String noticeDeviceName = '';

  bool get busy => _pending > 0;
  bool get loaded => _loaded;
  bool get blocksPlaybackRecovery => busy || notice == AudioOutputNotice.fallbackFailed;
  Future<void> get settled => _tail;

  String? get message => switch (notice) {
        AudioOutputNotice.unavailable => l10n.audioOutputUnavailable(noticeDeviceName),
        AudioOutputNotice.selectionFailed => l10n.audioOutputSelectionFailed(noticeDeviceName),
        AudioOutputNotice.fallbackFailed => l10n.audioOutputFallbackFailed,
        AudioOutputNotice.loadFailed => l10n.audioOutputLoadFailed,
        AudioOutputNotice.saveFailed => l10n.audioOutputSaveFailed,
        null => null,
      };

  List<AudioOutputDevice> _normalize(List<AudioOutputDevice> value) => [
        AudioOutputDevice.system,
        ...{for (final d in value) if (d.id != 'auto' && d.id.isNotEmpty) d.id: d}.values,
      ];

  AudioOutputDevice? _find(String id) {
    for (final device in devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    if (_disposed) return Future<void>.value();
    _pending++;
    notifyListeners();
    _tail = _tail.then((_) async {
      try {
        if (!_disposed) await operation();
      } finally {
        _pending--;
        if (!_disposed) notifyListeners();
      }
    });
    return _tail;
  }

  Future<void> _restore(int request) async {
    try {
      _preferences = await SharedPreferences.getInstance();
      final raw = _preferences!.getString(preferenceKey);
      var saved = AudioOutputDevice.system;
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        saved = AudioOutputDevice(json['id'] as String, json['name'] as String);
      }
      final revision = _deviceRevision;
      final snapshot = await engine.getAudioDevices();
      if (_disposed) return;
      if (revision == _deviceRevision) devices = _normalize(snapshot);
      _loaded = true;
      if (request != _request) return;
      await _apply(saved, request);
    } catch (_) {
      if (!_disposed && request == _request) notice = AudioOutputNotice.loadFailed;
    }
  }

  void _devicesChanged(List<AudioOutputDevice> value) {
    if (_disposed) return;
    _deviceRevision++;
    devices = _normalize(value);
    notifyListeners();
    if (!_loaded) return;
    unawaited(_enqueue(() async {
      if (_find(selected.id) == null) {
        await _fallback(selected.name, _request);
      }
    }));
  }

  Future<void> refresh() => _enqueue(() async {
        final revision = _deviceRevision;
        try {
          final snapshot = await engine.getAudioDevices();
          if (_disposed) return;
          if (revision == _deviceRevision) devices = _normalize(snapshot);
          _loaded = true;
          if (_find(selected.id) == null) await _fallback(selected.name, _request);
          if (notice == AudioOutputNotice.loadFailed) notice = null;
        } catch (_) {
          if (!_disposed) notice = AudioOutputNotice.loadFailed;
        }
      });

  Future<void> select(AudioOutputDevice device) {
    final request = ++_request;
    return _enqueue(() => _apply(device, request));
  }

  Future<void> _apply(AudioOutputDevice device, int request) async {
    if (_disposed || request != _request) return;
    final available = _find(device.id);
    if (available == null) {
      await _fallback(device.name, request);
      return;
    }
    try {
      await engine.setAudioDevice(available);
      if (_disposed || request != _request) return;
      if (_find(available.id) == null) {
        await _fallback(available.name, request);
        return;
      }
      selected = available;
      notice = null;
      await _save();
    } catch (_) {
      if (_disposed || request != _request) return;
      // setter 可能已部分生效；明确设回默认，避免界面与实际路由不一致。
      await _fallback(available.name, request, selectionFailed: true);
    }
  }

  Future<void> _fallback(String name, int request, {bool selectionFailed = false}) async {
    try {
      await engine.setAudioDevice(AudioOutputDevice.system);
      if (_disposed || request != _request) return;
      selected = AudioOutputDevice.system;
      noticeDeviceName = name;
      notice = selectionFailed ? AudioOutputNotice.selectionFailed : AudioOutputNotice.unavailable;
      await _save();
    } catch (_) {
      if (!_disposed && request == _request) notice = AudioOutputNotice.fallbackFailed;
    }
  }

  Future<void> _save() async {
    try {
      final preferences = _preferences ??= await SharedPreferences.getInstance();
      if (_disposed) return;
      final saved = await preferences.setString(preferenceKey,
          jsonEncode({'id': selected.id, 'name': selected.name}));
      if (!saved && !_disposed) notice = AudioOutputNotice.saveFailed;
    } catch (_) {
      if (!_disposed) notice = AudioOutputNotice.saveFailed;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
