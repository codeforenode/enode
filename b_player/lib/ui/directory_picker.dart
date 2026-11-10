import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme.dart';
import '../l10n/l10n.dart';

/// 列出可读子目录（跳过隐藏目录），按名称排序。
Future<List<String>> listSubdirectories(String dir) async {
  final out = <String>[];
  await for (final entity in Directory(dir).list(followLinks: false)) {
    if (entity is! Directory) continue;
    final name = p.basename(entity.path);
    if (name.isEmpty || name.startsWith('.')) continue;
    out.add(p.normalize(entity.path));
  }
  out.sort((a, b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));
  return out;
}

/// 起始目录：优先当前根目录，失效时退回设备常用位置。
String pickerStartPath(String initial) {
  final t = initial.trim();
  if (t.isNotEmpty && Directory(t).existsSync()) return p.normalize(t);
  if (Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'];
    if (home != null && Directory(home).existsSync()) return p.normalize(home);
    return r'D:\';
  }
  return '/storage/emulated/0';
}

Future<String?> showDirectoryPicker(
  BuildContext context, {
  required String initialPath,
  Future<bool> Function()? onOpenSettings,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => DirectoryPickerDialog(initialPath: initialPath, onOpenSettings: onOpenSettings),
    );

/// 应用内目录浏览器：曲库按真实路径扫描，SAF 返回的 content:// 无法直接读取同名歌词。
class DirectoryPickerDialog extends StatefulWidget {
  const DirectoryPickerDialog({
    super.key,
    required this.initialPath,
    this.onOpenSettings,
    this.listDirs = listSubdirectories,
  });

  final String initialPath;
  final Future<bool> Function()? onOpenSettings;
  final Future<List<String>> Function(String dir) listDirs;

  @override
  State<DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<DirectoryPickerDialog> {
  late String _path;
  List<String> _children = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = pickerStartPath(widget.initialPath);
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final dirs = await widget.listDirs(_path);
      if (!mounted) return;
      setState(() {
        _children = dirs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _children = const [];
        _loading = false;
        _error = l10n.dirUnreadable;
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

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return AlertDialog(
      backgroundColor: C.panel,
      title: Text(t.chooseLibraryFolder, style: kCardTitle),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            decoration: BoxDecoration(
              color: C.panel2,
              border: Border.all(color: C.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              IconButton(
                key: const Key('dir-picker-up'),
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
          SizedBox(height: 300, child: _body()),
          const SizedBox(height: 8),
          Text(t.chooseFolderHint, style: TextStyle(fontSize: 12, color: C.faint)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel, style: TextStyle(color: C.dim))),
        FilledButton(
          onPressed: (_loading || _error != null) ? null : () => Navigator.pop(context, _path),
          style: FilledButton.styleFrom(backgroundColor: C.acc, foregroundColor: C.onAcc),
          child: Text(t.chooseThisFolder),
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
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline_rounded, size: 22, color: C.warn),
          const SizedBox(height: 8),
          Text(error, style: TextStyle(fontSize: 12.5, color: C.dim), textAlign: TextAlign.center),
          if (widget.onOpenSettings != null)
            TextButton(
              onPressed: () async {
                await widget.onOpenSettings!();
                await _load();
              },
              child: Text(t.grantAccess, style: TextStyle(color: C.acc)),
            ),
        ]),
      );
    }
    if (_children.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_off_outlined, size: 22, color: C.faint),
          const SizedBox(height: 8),
          Text(t.noSubfolders, style: TextStyle(fontSize: 12.5, color: C.faint)),
        ]),
      );
    }
    return ListView.separated(
      key: const Key('dir-picker-list'),
      itemCount: _children.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: C.line),
      itemBuilder: (context, i) {
        final path = _children[i];
        return InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: () => _enter(path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
            child: Row(children: [
              Icon(Icons.folder_rounded, size: 18, color: C.acc),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.basename(path),
                    style: TextStyle(fontSize: 13, color: C.txt), overflow: TextOverflow.ellipsis),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: C.faint),
            ]),
          ),
        );
      },
    );
  }
}
