import 'dart:async';

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
  Future<void> open(Uri uri, {bool autoplay = true, Map<String, String>? headers});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume); // 0..1
  Future<void> stop();
  Future<void> dispose();
}

/// media_kit（libmpv）后端；构造前必须已调用 `MediaKit.ensureInitialized()`。
class MediaKitEngine implements AudioEngine {
  MediaKitEngine() : _player = Player();

  final Player _player;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Future<void> open(Uri uri, {bool autoplay = true, Map<String, String>? headers}) =>
      _player.open(
        Media(
          uri.toString(),
          httpHeaders: headers == null || headers.isEmpty ? null : headers,
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
