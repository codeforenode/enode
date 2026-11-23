import 'dart:async';
import 'dart:convert';

import 'package:media_kit/media_kit.dart';

/// 播放后端抽象：状态层只依赖这里，测试注入假引擎，
/// 正式运行由 libmpv/ffmpeg 承担解码，APE/FLAC/OGG/Opus/M4A/MKV 等都能播。
abstract class AudioEngine {
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get completedStream;
  Stream<String> get errorStream;

  /// [uri] 可能是本地 `file:`，也可能是在线音源/WebDAV 取到的 http(s) 地址。
  /// [headers] 用于需要认证的远程音源（如 WebDAV Basic），凭据不拼进 URL。
  /// [start] 交给后端在加载媒体时生效；不要用 open 之后立刻 seek 代替——
  /// libmpv 还没加载完文件时 seek 会被丢掉，续播就会从 0 开始。
  Future<void> open(
    Uri uri, {
    bool autoplay = true,
    Map<String, String>? headers,
    Duration? start,
  });
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume); // 0..1
  Future<void> stop();
  Future<void> dispose();
}

class AudioOutputDevice {
  const AudioOutputDevice(this.id, this.name);

  static const system = AudioOutputDevice('auto', '');
  final String id;
  final String name;
}

/// 可选能力，旧播放后端及只测试播放的假引擎无需实现设备管理。
abstract interface class AudioOutputEngine {
  Stream<List<AudioOutputDevice>> get audioDevicesStream;
  Future<List<AudioOutputDevice>> getAudioDevices();
  Future<void> setAudioDevice(AudioOutputDevice device);
}

/// media_kit（libmpv）后端；构造前必须已调用 `MediaKit.ensureInitialized()`。
class MediaKitEngine implements AudioEngine, AudioOutputEngine {
  MediaKitEngine() : _player = Player();

  final Player _player;

  @override
  Stream<List<AudioOutputDevice>> get audioDevicesStream =>
      _player.stream.audioDevices.map((devices) => [
            for (final device in devices)
              AudioOutputDevice(device.name, device.description),
          ]);

  @override
  Future<List<AudioOutputDevice>> getAudioDevices() async {
    // state.audioDevices 初始只有 auto 占位项，不能据此判定保存的设备已丢失。
    final native = _player.platform as NativePlayer;
    final value = await native.getProperty('audio-device-list');
    final devices = jsonDecode(value) as List<dynamic>;
    return [
      for (final device in devices)
        AudioOutputDevice(device['name'] as String, device['description'] as String),
    ];
  }

  @override
  Future<void> setAudioDevice(AudioOutputDevice device) async {
    await _player.setAudioDevice(AudioDevice(device.id, device.name));
    // 1.2.6 的 setter 不把所有 mpv 属性错误作为异常抛出，读回确认后再保存偏好。
    final selected = await (_player.platform as NativePlayer).getProperty('audio-device');
    if (selected != device.id) throw StateError('音频输出设备设置未生效');
  }

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Future<void> open(
    Uri uri, {
    bool autoplay = true,
    Map<String, String>? headers,
    Duration? start,
  }) =>
      _player.open(
        Media(
          uri.toString(),
          httpHeaders: headers == null || headers.isEmpty ? null : headers,
          start: start,
        ),
        play: autoplay,
      );

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0) * 100.0);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
