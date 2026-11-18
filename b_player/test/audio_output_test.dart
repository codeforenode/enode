import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/edge/player_engine.dart';
import 'package:b_player/state/audio_output.dart';

const speakers = AudioOutputDevice('wasapi/speakers', '扬声器');
const headphones = AudioOutputDevice('wasapi/headphones', '耳机');

class FakeOutputs implements AudioOutputEngine {
  final changes = StreamController<List<AudioOutputDevice>>.broadcast(sync: true);
  List<AudioOutputDevice> devices = [speakers, headphones];
  final calls = <String>[];
  final failures = <String>{};
  Completer<List<AudioOutputDevice>>? scan;
  Completer<void>? switching;
  Completer<void>? entered;
  int active = 0;
  int maxActive = 0;

  @override
  Stream<List<AudioOutputDevice>> get audioDevicesStream => changes.stream;

  @override
  Future<List<AudioOutputDevice>> getAudioDevices() async => scan == null ? devices : await scan!.future;

  @override
  Future<void> setAudioDevice(AudioOutputDevice device) async {
    active++;
    if (active > maxActive) maxActive = active;
    calls.add(device.id);
    final wait = switching;
    switching = null;
    entered?.complete();
    entered = null;
    try {
      await wait?.future;
      if (failures.contains(device.id)) throw StateError('设备不可用');
    } finally {
      active--;
    }
  }

  void emit(List<AudioOutputDevice> value) {
    devices = value;
    changes.add(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  AudioOutputController create(FakeOutputs engine) {
    final controller = AudioOutputController(engine);
    addTearDown(() async {
      controller.dispose();
      await controller.settled;
      await engine.changes.close();
    });
    return controller;
  }

  Future<Map<String, dynamic>> saved() async {
    final p = await SharedPreferences.getInstance();
    return jsonDecode(p.getString(AudioOutputController.preferenceKey)!) as Map<String, dynamic>;
  }

  test('保存设备 ID 和可读名，重启按 ID 恢复并更新设备名称', () async {
    final first = create(FakeOutputs());
    await first.ready;
    await first.select(speakers);
    expect(await saved(), {'id': speakers.id, 'name': speakers.name});
    final engine = FakeOutputs()..devices = [AudioOutputDevice(speakers.id, '新扬声器名称')];
    final restored = create(engine);
    await restored.ready;
    expect(engine.calls, [speakers.id]);
    expect(restored.selected.name, '新扬声器名称');
    expect(restored.notice, isNull);
    expect((await saved())['name'], '新扬声器名称');
  });

  test('启动时保存设备不存在，回退默认并保留可读提示', () async {
    SharedPreferences.setMockInitialValues({
      AudioOutputController.preferenceKey: jsonEncode({'id': speakers.id, 'name': speakers.name}),
    });
    final engine = FakeOutputs()..devices = [];
    final output = create(engine);
    await output.ready;
    expect(engine.calls, ['auto']);
    expect(output.selected.id, 'auto');
    expect(output.notice, AudioOutputNotice.unavailable);
    expect(output.message, contains(speakers.name));
    expect((await saved())['id'], 'auto');
  });

  test('热拔出当前设备仅回退一次，重新插入不抢回输出', () async {
    final engine = FakeOutputs();
    final output = create(engine);
    await output.ready;
    await output.select(speakers);
    engine.calls.clear();
    engine.emit([headphones]);
    engine.emit([headphones]);
    await output.settled;
    expect(engine.calls, ['auto']);
    expect(output.notice, AudioOutputNotice.unavailable);
    engine.emit([speakers, headphones]);
    await output.settled;
    expect(engine.calls, ['auto']);
    expect(output.selected.id, 'auto');
  });

  test('选择失败明确回退默认，默认也失败时不谎报成功或覆盖偏好', () async {
    final engine = FakeOutputs();
    final output = create(engine);
    await output.ready;
    await output.select(speakers);
    engine.failures.add(headphones.id);
    await output.select(headphones);
    expect(output.selected.id, 'auto');
    expect(output.notice, AudioOutputNotice.selectionFailed);
    await output.select(speakers);
    engine.failures.add('auto');
    await output.select(headphones);
    expect(output.notice, AudioOutputNotice.fallbackFailed);
    expect(output.blocksPlaybackRecovery, isTrue);
    expect((await saved())['id'], speakers.id);
    engine.failures.clear();
    await output.select(AudioOutputDevice.system);
    expect(output.notice, isNull);
  });

  test('恢复等待设备枚举时，用户选择优先且真实列表不会被旧快照覆盖', () async {
    SharedPreferences.setMockInitialValues({
      AudioOutputController.preferenceKey: jsonEncode({'id': speakers.id, 'name': speakers.name}),
    });
    final scan = Completer<List<AudioOutputDevice>>();
    final engine = FakeOutputs()..scan = scan;
    final output = create(engine);
    await Future<void>.delayed(Duration.zero);
    final choice = output.select(headphones);
    engine.emit([headphones]);
    scan.complete([speakers]);
    await choice;
    expect(engine.calls, [headphones.id]);
    expect(output.selected.id, headphones.id);
    expect(output.devices.map((d) => d.id), ['auto', headphones.id]);
    expect((await saved())['id'], headphones.id);
  });

  test('正在恢复原生设备时的新选择最后生效，原生调用不并发', () async {
    SharedPreferences.setMockInitialValues({
      AudioOutputController.preferenceKey: jsonEncode({'id': speakers.id, 'name': speakers.name}),
    });
    final wait = Completer<void>();
    final entered = Completer<void>();
    final engine = FakeOutputs()..switching = wait..entered = entered;
    final output = create(engine);
    await entered.future;
    final choice = output.select(headphones);
    wait.complete();
    await choice;
    expect(engine.calls, [speakers.id, headphones.id]);
    expect(engine.maxActive, 1);
    expect(output.selected.id, headphones.id);
    expect((await saved())['id'], headphones.id);
  });

  test('选择过程中设备消失，完成后检查最新列表并回退', () async {
    final engine = FakeOutputs();
    final output = create(engine);
    await output.ready;
    final wait = Completer<void>();
    final entered = Completer<void>();
    engine.switching = wait;
    engine.entered = entered;
    final choice = output.select(speakers);
    await entered.future;
    engine.emit([headphones]);
    wait.complete();
    await choice;
    await output.settled;
    expect(engine.calls, ['auto', speakers.id, 'auto']);
    expect(output.notice, AudioOutputNotice.unavailable);
    expect((await saved())['id'], 'auto');
  });

  test('销毁后未完成的扫描不再调用引擎或保存', () async {
    final scan = Completer<List<AudioOutputDevice>>();
    final engine = FakeOutputs()..scan = scan;
    final output = AudioOutputController(engine);
    await Future<void>.delayed(Duration.zero);
    output.dispose();
    scan.complete([speakers]);
    await output.ready;
    expect(engine.calls, isEmpty);
    final p = await SharedPreferences.getInstance();
    expect(p.containsKey(AudioOutputController.preferenceKey), isFalse);
    await engine.changes.close();
  });
}
