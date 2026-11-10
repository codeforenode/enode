import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:b_player/ui/directory_picker.dart';

import 'l10n_harness.dart';

void main() {
  setUp(useTraditionalChinese);

  test('列出子目录：过滤隐藏目录与文件，按名称排序', () async {
    final tmp = await Directory.systemTemp.createTemp('dirpicker');
    addTearDown(() => tmp.delete(recursive: true));
    await Directory(p.join(tmp.path, 'b')).create();
    await Directory(p.join(tmp.path, 'A')).create();
    await Directory(p.join(tmp.path, '.hidden')).create();
    await File(p.join(tmp.path, 'song.mp3')).writeAsString('x');

    final dirs = await listSubdirectories(tmp.path);
    expect(dirs.map(p.basename).toList(), ['A', 'b']);
  });

  testWidgets('目录选择器：可进入子目录、返回上一级并取回路径', (tester) async {
    // testWidgets 运行在 fake-async 里，真实异步 IO 永远不会完成，这里必须用同步 API。
    final tmp = Directory.systemTemp.createTempSync('dirpicker');
    addTearDown(() => tmp.deleteSync(recursive: true));

    String? picked;
    Future<List<String>> lister(String dir) async {
      if (p.equals(dir, tmp.path)) {
        return [p.join(tmp.path, 'Album A'), p.join(tmp.path, 'jazz')];
      }
      return const [];
    }

    await tester.pumpWidget(localizedApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showDialog<String>(
                context: context,
                builder: (_) => DirectoryPickerDialog(initialPath: tmp.path, listDirs: lister),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.chooseLibraryFolder), findsOneWidget);
    expect(find.text('Album A'), findsOneWidget);
    expect(find.text('jazz'), findsOneWidget);

    await tester.tap(find.text('Album A'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.noSubfolders), findsOneWidget);
    expect(find.text(p.join(tmp.path, 'Album A')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dir-picker-up')));
    await tester.pumpAndSettle();
    expect(find.text('jazz'), findsOneWidget);

    await tester.tap(find.text(l10n.chooseThisFolder));
    await tester.pumpAndSettle();
    expect(picked, p.normalize(tmp.path));
  });
}
