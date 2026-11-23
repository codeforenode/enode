import 'dart:convert';
import 'dart:io';

/// 应用内容的原子 JSON 文件。
///
/// 先写 `.tmp` 再 rename 覆盖目标（Windows 上 Dart 的 rename 会替换已有文件），
/// 中途被杀不会留下半个 JSON；主文件读不出来时回退上一次的 `.bak`。
/// 适合“体积随曲库/列表增长、写坏了代价高”的数据；不适合 prefs 那种整包小配置。
class AtomicJsonFile {
  AtomicJsonFile(this.file);

  final File file;

  File get _tmp => File('${file.path}.tmp');
  File get _backup => File('${file.path}.bak');

  /// 主文件优先；解析失败、为空或不存在时读备份。两边都不可用返回 null。
  Future<Object?> read() async {
    for (final candidate in [file, _backup]) {
      try {
        if (!await candidate.exists()) continue;
        final text = await candidate.readAsString();
        if (text.trim().isEmpty) continue;
        return jsonDecode(text);
      } catch (_) {
        // 半截/损坏的候选文件不能拖垮启动，继续看备份。
      }
    }
    return null;
  }

  Future<void> write(Object? data) => writeText(jsonEncode(data));

  /// 调用方已经编码好内容（例如播放位置这种高频小文件）时直接写文本。
  Future<void> writeText(String text) async {
    await file.parent.create(recursive: true);
    await _tmp.writeAsString(text, flush: true);
    // 旧内容留一份 .bak：rename 覆盖目标失败时还有上一次可读的快照。
    if (await file.exists()) {
      await file.rename(_backup.path);
    }
    await _tmp.rename(file.path);
  }

  Future<void> delete() async {
    for (final candidate in [file, _backup, _tmp]) {
      try {
        if (await candidate.exists()) await candidate.delete();
      } catch (_) {}
    }
  }
}