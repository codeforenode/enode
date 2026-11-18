import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme.dart';
import '../l10n/l10n.dart';
import 'directory_picker.dart';

const _imageExts = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'};
const _videoExts = {'.mp4', '.webm', '.mov', '.mkv', '.avi', '.m4v', '.ogv'};
const _scriptExts = {'.js'};
const _certExts = {'.pem', '.crt', '.cer'};

/// 起始目录：已选过文件就从它所在目录继续，否则退回用户目录。
String mediaPickerStart(String path) {
  final t = path.trim();
  if (t.isNotEmpty) {
    final dir = p.dirname(t);
    if (Directory(dir).existsSync()) return p.normalize(dir);
  }
  return pickerStartPath('');
}

Future<String?> showMediaPathPicker(
  BuildContext context, {
  required String initialPath,
  required bool video,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => PathPickerDialog(
        initialPath: initialPath,
        extensions: video ? _videoExts : _imageExts,
        title: video ? l10n.screenPickVideo : l10n.screenPickImage,
        emptyText: video ? l10n.screenNoVideos : l10n.noImages,
        note: l10n.imagePathNote,
        pathHint: l10n.pastePathHint,
        fileIcon: video ? Icons.movie_outlined : Icons.image_outlined,
      ),
    );

/// 音源脚本：只列 .js，也允许直接粘路径（Android 上不一定能逐级翻到目标目录）。
Future<String?> showScriptPathPicker(
  BuildContext context, {
  required String initialPath,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => PathPickerDialog(
        initialPath: initialPath,
        extensions: _scriptExts,
        title: l10n.pickScriptFile,
        emptyText: l10n.noScriptFiles,
        note: l10n.scriptPathNote,
        pathHint: l10n.scriptPathHint,
        fileIcon: Icons.code_rounded,
      ),
    );

/// Broker 的 CA 证书：内容必须是 PEM 文本。
Future<String?> showCertificatePathPicker(
  BuildContext context, {
  required String initialPath,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => PathPickerDialog(
        initialPath: initialPath,
        extensions: _certExts,
        title: l10n.pickCertFile,
        emptyText: l10n.noCertFiles,
        note: l10n.certPathNote,
        pathHint: l10n.certPathHint,
        fileIcon: Icons.verified_user_outlined,
      ),
    );

/// 仓库里没有系统文件选择插件（曲库目录同样是手写的浏览器），
/// 所以这里继续沿用「自己列目录」的做法，只把目标类型列成可点，并允许直接粘路径。
class PathPickerDialog extends StatefulWidget {
  const PathPickerDialog({
    super.key,
    required this.initialPath,
    required this.extensions,
    required this.title,
    required this.emptyText,
    required this.note,
    required this.pathHint,
    required this.fileIcon,
    this.listEntries,
  });

  final String initialPath;
  final Set<String> extensions;
  final String title;
  final String emptyText;
  final String note;
  final String pathHint;
  final IconData fileIcon;
  final Future<({List<String> dirs, List<String> files})> Function(String dir, Set<String> extensions)?
      listEntries;

  @override
  State<PathPickerDialog> createState() => _PathPickerDialogState();
}

/// 列出某目录下的子目录和目标文件（跳过隐藏项）。
Future<({List<String> dirs, List<String> files})> listFiles(
  String dir,
  Set<String> extensions,
) async {
  final dirs = <String>[];
  final files = <String>[];
  await for (final entity in Directory(dir).list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name.isEmpty || name.startsWith('.')) continue;
    if (entity is Directory) {
      dirs.add(p.normalize(entity.path));
    } else if (entity is File &&
        extensions.contains(p.extension(name).toLowerCase())) {
      files.add(p.normalize(entity.path));
    }
  }
  int byName(String a, String b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase());
  dirs.sort(byName);
  files.sort(byName);
  return (dirs: dirs, files: files);
}

class _PathPickerDialogState extends State<PathPickerDialog> {
  late String _path;
  late final TextEditingController _manual;
  ({List<String> dirs, List<String> files}) _entries = (dirs: const [], files: const []);
  bool _loading = true;
  String? _error;

  Future<({List<String> dirs, List<String> files})> _list(String dir) =>
      widget.listEntries?.call(dir, widget.extensions) ?? listFiles(dir, widget.extensions);

  @override
  void initState() {
    super.initState();
    _path = mediaPickerStart(widget.initialPath);
    _manual = TextEditingController(text: widget.initialPath);
    _load();
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final entries = await _list(_path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries = (dirs: const [], files: const []);
        _loading = false;
        _error = l10n.imageDirUnreadable;
      });
    }
  }

  void _enter(String path) {
    setState(() => _path = p.normalize(path));
    _load();
  }

  String? get _parent {
    final parent = p.dirname(_path);
    return parent == _path ? null : parent;
  }

  void _pick(String file) => Navigator.pop(context, p.normalize(file));

  bool get _valid =>
      widget.extensions.contains(p.extension(_manual.text.trim()).toLowerCase());

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final manual = _manual.text.trim();
    return AlertDialog(
      backgroundColor: C.panel,
      title: Text(widget.title, style: kCardTitle),
      content: SizedBox(
        width: 500,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            decoration: BoxDecoration(
              color: C.panel2,
              border: Border.all(color: C.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              IconButton(
                onPressed: _parent == null ? null : () => _enter(_parent!),
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                color: C.txt,
                tooltip: t.parentFolder,
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Text(_path, style: TextStyle(fontSize: 12.5, color: C.dim)),
                ),
              ),
              const SizedBox(width: 4),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 280, child: _body()),
          const SizedBox(height: 10),
          TextField(
            controller: _manual,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: 12.5, color: C.txt),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: C.panel2,
              hintText: widget.pathHint,
              hintStyle: TextStyle(fontSize: 12, color: C.faint),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: C.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: C.acc),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.note,
            style: TextStyle(fontSize: 11.5, color: _valid ? C.acc : C.faint),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel, style: TextStyle(color: C.dim))),
        FilledButton(
          onPressed: _valid ? () => Navigator.pop(context, p.normalize(manual)) : null,
          style: FilledButton.styleFrom(backgroundColor: C.acc, foregroundColor: C.onAcc),
          child: Text(t.useThisPath),
        ),
      ],
    );
  }

  Widget _body() {
    final t = AppL10n.of(context);
    if (_loading) {
      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final error = _error;
    if (error != null) {
      return Center(child: Text(t.imageDirError(error), style: TextStyle(fontSize: 12.5, color: C.warn)));
    }
    final items = [
      for (final d in _entries.dirs) (d, true),
      for (final f in _entries.files) (f, false),
    ];
    if (items.isEmpty) {
      return Center(
        child: Text(widget.emptyText, style: TextStyle(fontSize: 12.5, color: C.faint)),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: C.line),
      itemBuilder: (context, i) {
        final (path, isDir) = items[i];
        return InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: isDir ? () => _enter(path) : () => _pick(path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
            child: Row(children: [
              Icon(
                isDir ? Icons.folder_rounded : widget.fileIcon,
                size: 18,
                color: isDir ? C.acc : C.dim,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.basename(path),
                    style: TextStyle(fontSize: 13, color: C.txt), overflow: TextOverflow.ellipsis),
              ),
              if (isDir) Icon(Icons.chevron_right_rounded, size: 18, color: C.faint),
            ]),
          ),
        );
      },
    );
  }
}
