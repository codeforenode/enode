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

/// Windows 上能打开的盘符根目录（C:\、D:\ …），其他平台返回空表。
///
/// 应用内浏览器只能逐级往上走，走到 `C:\` 时 dirname 等于自身、再没有上级，
/// 没有盘符入口就永远换不到别的盘。这里按字母探一遍，只收「确实能当目录
/// 打开」的盘；空光驱、掉线的映射盘会被自然过滤掉。每次打开对话框重新枚举，
/// 中途插上的 U 盘关掉重开即可看到。
List<String> listWindowsDrives() {
  if (!Platform.isWindows) return const <String>[];
  final drives = <String>[];
  for (var code = 0x41; code <= 0x5A; code++) {
    final root = '${String.fromCharCode(code)}:\\';
    try {
      if (Directory(root).existsSync()) drives.add(root);
    } catch (_) {
      // 盘符登记了但暂时读不到（光驱无盘等），跳过，别让整个选择器卡住。
    }
  }
  return drives;
}

/// 起始目录：优先当前根目录，失效时退回设备常用位置。
String pickerStartPath(String initial) {
  final t = initial.trim();
  if (t.isNotEmpty && Directory(t).existsSync()) return p.normalize(t);
  if (Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'];
    if (home != null && Directory(home).existsSync()) return p.normalize(home);
    final drives = listWindowsDrives();
    if (drives.isNotEmpty) return drives.first;
    return 'C:\\';
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
    this.listDrives = listWindowsDrives,
  });

  final String initialPath;
  final Future<bool> Function()? onOpenSettings;
  final Future<List<String>> Function(String dir) listDirs;
  /// 可注入以便测试；非 Windows 平台返回空表，盘符入口会自动隐藏。
  final List<String> Function() listDrives;

  @override
  State<DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<DirectoryPickerDialog> {
  late String _path;
  late final List<String> _drives;
  List<String> _children = const [];
  bool _drivesView = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = pickerStartPath(widget.initialPath);
    _drives = widget.listDrives();
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
    setState(() {
      _path = p.normalize(path);
      _drivesView = false;
    });
    _load();
  }

  /// 「此电脑」：列出所有盘符。根目录再往上没有父目录了，得有地方可去。
  void _showDrives() {
    if (_drives.isEmpty) return;
    setState(() {
      _drivesView = true;
      _children = const [];
      _loading = false;
      _error = null;
    });
  }

  String? get _parent {
    final parent = p.dirname(_path);
    return parent == _path ? null : parent;
  }

  bool get _hasDrives => _drives.isNotEmpty;

  bool get _canGoUp => !_drivesView && (_parent != null || _hasDrives);

  void _goUp() {
    final parent = _parent;
    if (parent != null) {
      _enter(parent);
    } else {
      _showDrives();
    }
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
                onPressed: _canGoUp ? _goUp : null,
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                color: C.txt,
                tooltip: t.parentFolder,
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Text(_drivesView ? t.thisPc : _path, style: TextStyle(fontSize: 12.5, color: C.dim)),
                ),
              ),
              if (_hasDrives)
                PopupMenuButton<String>(
                  key: const Key('dir-picker-drives'),
                  tooltip: t.switchDrive,
                  icon: Icon(Icons.storage_rounded, size: 18, color: C.txt),
                  onSelected: _enter,
                  itemBuilder: (_) => [
                    for (final drive in _drives)
                      PopupMenuItem<String>(
                        key: Key('dir-picker-drive-${drive[0]}'),
                        value: drive,
                        child: Text(drive, style: TextStyle(fontSize: 13, color: C.txt)),
                      ),
                  ],
                ),
              const SizedBox(width: 4),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 300, child: _body()),
          const SizedBox(height: 8),
          Text(_drivesView ? t.chooseDriveHint : t.chooseFolderHint,
              style: TextStyle(fontSize: 12, color: C.faint)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel, style: TextStyle(color: C.dim))),
        FilledButton(
          onPressed: (_loading || _error != null || _drivesView) ? null : () => Navigator.pop(context, _path),
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
    if (_drivesView) {
      return ListView.separated(
        key: const Key('dir-picker-drive-list'),
        itemCount: _drives.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: C.line),
        itemBuilder: (context, i) => _driveRow(_drives[i]),
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

  Widget _driveRow(String drive) => InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => _enter(drive),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
          child: Row(children: [
            Icon(Icons.storage_rounded, size: 18, color: C.acc),
            const SizedBox(width: 10),
            Expanded(
              child: Text(drive, style: TextStyle(fontSize: 13, color: C.txt), overflow: TextOverflow.ellipsis),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: C.faint),
          ]),
        ),
      );
}
