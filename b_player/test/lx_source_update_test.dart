import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:b_player/edge/sources/lx_source_entry.dart';

const _script = '''/*!
 * @name 测试音源
 * @version 1.0.0
 * @author 测试作者
 */
send(inited)
''';

LxSourceEntry _entry({
  String url = 'https://example.com/source.js',
  String script = _script,
  bool enabled = true,
  String version = '1.0.0',
}) {
  final meta = LxSourceMeta.parse(script);
  return LxSourceEntry(
    id: LxSourceEntry.idFor(url),
    url: url,
    script: script,
    meta: version == meta.version
        ? meta
        : LxSourceMeta(
            name: meta.name,
            version: version,
            author: meta.author,
            description: meta.description,
            homepage: meta.homepage,
          ),
    enabled: enabled,
    hash: LxSourceEntry.hashOf(script),
  );
}

void main() {
  test('脚本哈希：同内容稳定、内容变了就变', () {
    expect(LxSourceEntry.hashOf(_script), LxSourceEntry.hashOf(_script));
    expect(LxSourceEntry.hashOf(_script), hasLength(64));
    expect(LxSourceEntry.hashOf(_script), isNot(LxSourceEntry.hashOf('$_script ')));
  });

  test('持久化：hash 随条目保存，旧数据缺字段时为空', () {
    final entry = _entry();
    final restored = LxSourceEntry.fromJson(
      jsonDecode(jsonEncode(entry.toJson())),
    );
    expect(restored, isNotNull);
    expect(restored!.hash, entry.hash);

    final legacy = Map<String, Object?>.from(entry.toJson())..remove('hash');
    expect(LxSourceEntry.fromJson(legacy)!.hash, isEmpty);
  });

  test('同地址再导入视为更新：保留 id、勾选与顺序，只换脚本', () {
    final first = _entry(url: 'https://example.com/a.js', enabled: false);
    final other = _entry(url: 'https://example.com/b.js');
    final updated = _entry(
      url: 'https://example.com/a.js',
      script: '$_script// v2',
      version: '2.0.0',
    );

    final next = LxSourceStore.upsert([other, first], updated);
    expect(next, hasLength(2));
    expect(next[1].id, first.id);
    expect(next[1].enabled, isFalse);
    expect(next[1].script, contains('v2'));
    expect(next[1].hash, isNot(first.hash));
    expect(next[1].versionLabel, 'v2.0.0');
  });

  test('不同地址按导入顺序追加', () {
    final first = _entry(url: 'https://example.com/a.js');
    final second = _entry(url: 'https://example.com/b.js');
    final next = LxSourceStore.upsert([first], second);
    expect(next.map((entry) => entry.url), [first.url, second.url]);
  });

  test('fetchLxSource：下载后计算哈希并解析元信息', () async {
    final client = MockClient((request) async {
      expect(request.headers['User-Agent'], 'lx-music-request/2.11.0');
      return http.Response.bytes(utf8.encode(_script), 200);
    });

    final entry = await fetchLxSource(
      'https://example.com/source.js',
      client: client,
    );
    expect(entry.hash, LxSourceEntry.hashOf(_script));
    expect(entry.meta.name, '测试音源');
    expect(entry.meta.version, '1.0.0');
  });

  test('版本展示不叠加 v 前缀', () {
    expect(_entry().versionLabel, 'v1.0.0');
    expect(_entry(version: 'v8.9.3').versionLabel, 'v8.9.3');
    expect(_entry(version: '').versionLabel, isEmpty);
  });
}
