import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 节点侧日志：滚动文件 + 脱敏，release 构建同样写盘。
///
/// 为什么需要它：Windows 便携包是 GUI 程序，没有控制台，`debugPrint` 的输出现场
/// 根本无处可看——出问题时只能靠 MQTT 快照猜。这里把日志落到应用支持目录，
/// 店家能把文件导出来复盘。
///
/// 三条硬约束：
/// - **凭据绝不落盘**：MQTT 密码、WebDAV 账号、音源脚本 key 一律不写；URL 统一剥掉
///   query（直链、播放地址、更新检查都靠它），否则一份日志就把密钥泄了。
/// - **日志坏了不能拖垮应用**：写盘失败只记在 [lastError]，不影响播放与队列。
/// - **不无限增长**：按天分文件，保留 7 天，单文件超过 4MB 直接截断重写
///   （近期日志比远古日志有用，就不做多份滚动了）。
class EnodeLog {
  EnodeLog._();

  static const _keepDays = 7;
  static const _maxBytes = 4 * 1024 * 1024;

  static Directory? _dir;
  static IOSink? _sink;
  static String? _day;
  static int _written = 0;
  static Timer? _flushTimer;
  static bool _ready = false;
  static String? _lastError;
  static DebugPrintCallback? _console;

  /// 「正在运行」标记：启动时写、正常退出时删。下次启动看到它还在，
  /// 说明上次是被崩溃或强杀带走的——现场没人值守时，这是唯一能事后知道的线索。
  /// 里面记下版本与启动时刻，崩溃后能直接对上是哪一版出的事。
  static File? _runningMark;

  /// 运行时版本号（`1.4.7+10`）。启动时读一次，日志与运行标记都用它。
  static String _version = 'dev';

  /// 日志目录；未成功启用时为 null。
  static Directory? get directory => _dir;
  static bool get ready => _ready;
  static String? get lastError => _lastError;
  static String get version => _version;

  /// 首次调用创建目录并清理过期文件；重复调用无副作用。
  static Future<void> init({Directory? dir}) async {
    if (_ready) return;
    try {
      final target = dir ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'logs'));
      await target.create(recursive: true);
      _dir = target;
      _ready = true;
      _version = await _readVersion();
      _prune();
      i('log', '日志启用 v=$_version dir=${target.path}');
      await _markRunning();
    } catch (e) {
      _lastError = '$e';
    }
  }

  /// 版本名 + 构建号。读不到就退回 `dev`：日志不能因为拿不到包信息而停摆。
  static Future<String> _readVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isEmpty) return 'dev';
      return info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'dev';
    }
  }

  /// 写下运行标记，并检查上一次是不是没走到正常退出。
  static Future<void> _markRunning() async {
    final dir = _dir;
    if (dir == null) return;
    final mark = File(p.join(dir.path, '.running'));
    _runningMark = mark;
    try {
      if (await mark.exists()) {
        // 第一行版本、第二行启动时刻；老格式只有时刻。
        final lines = (await mark.readAsString()).split('\n').map((l) => l.trim()).toList();
        final prevVersion = lines.length >= 2 ? lines.first : '';
        final prevAt = lines.length >= 2 ? lines.last : lines.first;
        w(
          'app',
          '上次没有正常退出（崩溃或被强杀）：版本=${prevVersion.isEmpty ? '未知' : prevVersion}'
          '${prevAt.isEmpty ? '' : ' 启动于 $prevAt'}',
        );
      }
      await mark.writeAsString('$_version\n${DateTime.now()}', flush: true);
    } catch (_) {
      // 标记写不了不影响日志本身。
    }
  }

  /// 正常退出前调用：删掉运行标记，下次启动就不会报「上次未正常退出」。
  static Future<void> markCleanExit() async {
    final mark = _runningMark;
    if (mark == null) return;
    try {
      if (await mark.exists()) await mark.delete();
    } catch (_) {}
  }

  /// 把全局 `debugPrint` 接到日志上：现有调用点不用改，第三方库的输出也一并落盘。
  /// 必须只装一次，否则会自我递归。
  static void bridgeConsole() {
    if (_console != null) return;
    _console = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      _console!(message, wrapWidth: wrapWidth);
      _write('D', 'dart', message ?? '');
    };
  }

  /// 把 trackKey 这类长 id 截成尾部 8 位：日志里够区分，又不占篇幅。
  static String shortId(String value) =>
      value.length <= 8 ? value : '…${value.substring(value.length - 8)}';

  static void d(String tag, String message) => _write('D', tag, message);
  static void i(String tag, String message) => _write('I', tag, message);

  static void w(String tag, String message, [Object? error]) =>
      _write('W', tag, error == null ? message : '$message err=$error');

  static void e(String tag, String message, [Object? error, StackTrace? stack]) {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write(' err=$error');
    if (stack != null) buffer.write('\n$stack');
    _write('E', tag, buffer.toString());
    // 错误立即刷盘：进程可能马上就没了。
    unawaited(_sink?.flush() ?? Future<void>.value());
  }

  static void _write(String level, String tag, String message) {
    if (!_ready) return;
    final now = DateTime.now();
    final line = '${_ts(now)} $level [$tag] ${sanitize(message)}\n';
    _console?.call(line.trimRight());
    try {
      _openIfNeeded(now);
      final sink = _sink;
      if (sink == null) return;
      sink.write(line);
      _written += line.length;
      if (_written > _maxBytes) {
        // 截断重写：留着今天最新的日志比留一堆更早的更有用。
        _sink = null;
        sink.close();
        File(p.join(_dir!.path, 'enode-${_dayKey(now)}.log')).writeAsStringSync('');
        _written = 0;
        _openIfNeeded(now);
      }
      _scheduleFlush();
    } catch (e) {
      _lastError = '$e';
    }
  }

  static void _openIfNeeded(DateTime now) {
    final day = _dayKey(now);
    if (_sink != null && _day == day) return;
    _sink?.close();
    final file = File(p.join(_dir!.path, 'enode-$day.log'));
    _written = file.existsSync() ? file.lengthSync() : 0;
    _sink = file.openWrite(mode: FileMode.append);
    _day = day;
  }

  static void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 2), () {
      _flushTimer = null;
      unawaited(_sink?.flush() ?? Future<void>.value());
    });
  }

  /// 关闭 sink；退出/测试收尾时调用，确保最后几行落盘。
  static Future<void> close() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final sink = _sink;
    _sink = null;
    _day = null;
    _ready = false;
    try {
      await sink?.flush();
      await sink?.close();
    } catch (_) {}
  }

  static void _prune() {
    final dir = _dir;
    if (dir == null) return;
    final cutoff = DateTime.now().subtract(const Duration(days: _keepDays));
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('enode-') || !name.endsWith('.log')) continue;
        if (entity.statSync().modified.isBefore(cutoff)) entity.deleteSync();
      }
    } catch (e) {
      _lastError = '$e';
    }
  }

  static String _dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';

  static String _ts(DateTime t) =>
      '${_dayKey(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';

  /// 脱敏：URL 的 query 一律抹掉，`user:pass@host` 抹掉账号段，
  /// 常见的敏感键值对抹掉值。宁可日志少点信息，也不能把凭据写进去。
  static String sanitize(String input) {
    var out = input;
    // scheme://user:pass@host → scheme://<redacted>@host
    out = out.replaceAllMapped(
      RegExp(r'([a-zA-Z][a-zA-Z0-9+.\-]*://)[^/\s@]+@'),
      (m) => '${m[1]}<redacted>@',
    );
    // URL 的 query 全部脱敏（直链签名、token 常在这里）
    out = out.replaceAllMapped(
      RegExp(r'(https?://[^\s?#]*)\?[^\s#]*'),
      (m) => '${m[1]}?<redacted>',
    );
    // password=xxx / token: xxx / "apikey":"xxx"
    // Dart 的 RegExp 不支持内联 (?i)，大小写用参数关掉。
    out = out.replaceAllMapped(
      RegExp(
        r'''["']?\b(password|passwd|pwd|token|secret|api_?key|authorization|credential)\b["']?\s*[=:]\s*("[^"]*"|'[^']*'|\S+)''',
        caseSensitive: false,
      ),
      (m) => '${m[1]}=<redacted>',
    );
    return out;
  }
}

/// 用系统文件管理器打开日志目录；失败静默（只是找不到入口，不影响排障其他手段）。
Future<bool> openLogDirectory() async {
  final dir = EnodeLog.directory;
  if (dir == null) return false;
  try {
    if (Platform.isWindows) {
      await Process.start('explorer', [dir.path], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [dir.path], mode: ProcessStartMode.detached);
    } else {
      await Process.start('xdg-open', [dir.path], mode: ProcessStartMode.detached);
    }
    return true;
  } catch (e) {
    EnodeLog.w('log', '打开日志目录失败 $e');
    return false;
  }
}
