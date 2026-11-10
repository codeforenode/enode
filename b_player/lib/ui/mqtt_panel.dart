import 'dart:async';

import 'package:flutter/material.dart';

import '../edge/mqtt_paste.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'cards.dart';
import 'form_bits.dart';

/// 广播（MQTT）连接设置：整段粘贴一次，自动识别地址、端口、账号与密码。
class MqttPanel extends StatefulWidget {
  const MqttPanel({super.key, required this.state});
  final AppState state;

  @override
  State<MqttPanel> createState() => _MqttPanelState();
}

class _MqttPanelState extends State<MqttPanel> {
  final _input = TextEditingController();
  String? _error;
  String? _ok;
  bool _busy = false;
  Timer? _okTimer;

  @override
  void dispose() {
    _okTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  /// 只确认「解析并保存」这一步，连接状态交给面板标题实时显示，避免写死的状态过期。
  void _showOk(String text) {
    _okTimer?.cancel();
    setState(() => _ok = text);
    _okTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _ok = null);
    });
  }

  Future<void> _apply() async {
    setState(() {
      _error = null;
      _ok = null;
    });
    try {
      final parsed = parseMqttPaste(_input.text, base: widget.state.edge.config);
      setState(() => _busy = true);
      await widget.state.applyMqttConfig(parsed);
      if (!mounted) return;
      // 密码已经落到本机配置里，输入框不留明文。
      _input.clear();
      _showOk(l10n.mqttApplied(parsed.host, parsed.port));
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = l10n.applyFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() {
      _error = null;
      _ok = null;
      _busy = true;
    });
    try {
      await widget.state.clearMqttConfig();
      if (!mounted) return;
      _input.clear();
      _showOk(l10n.mqttCleared);
    } catch (e) {
      if (mounted) setState(() => _error = l10n.clearFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.state.edge,
        builder: (context, _) {
          final edge = widget.state.edge;
          final config = edge.config;
          final t = AppL10n.of(context);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardHead(t.tabBroadcast, trailing: edge.statusLabel),
            Text(
              config.configured ? t.mqttIntro : t.mqttIntroUnconfigured,
              style: kMini,
            ),
            const SizedBox(height: 10),
            FormInput(
              controller: _input,
              maxLines: 4,
              hint: t.mqttPasteHint,
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton(
                onPressed: _busy ? null : _apply,
                style: FilledButton.styleFrom(backgroundColor: C.acc, foregroundColor: C.onAcc),
                child: Text(_busy ? t.mqttApplying : t.mqttApply),
              ),
              TextButton(
                onPressed: _busy || !config.configured ? null : _reset,
                style: TextButton.styleFrom(foregroundColor: C.dim),
                child: Text(t.mqttClear),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(fontSize: 11.5, color: C.bad)),
            ],
            if (_ok != null) ...[
              const SizedBox(height: 8),
              Text(_ok!, style: TextStyle(fontSize: 11.5, color: C.acc)),
            ],
            if (edge.lastError != null) ...[
              const SizedBox(height: 8),
              Text(edge.lastError!, style: TextStyle(fontSize: 11.5, color: C.bad)),
            ],
            const SizedBox(height: 12),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.mqttActive, style: TextStyle(fontSize: 11.5, color: C.dim, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (!config.configured)
                  _kv(t.brokerAddress, t.mqttNotConfiguredShort)
                else ...[
                  _kv(t.brokerAddress, '${config.host}:${config.port}${config.tls ? ' · TLS' : ''}'),
                  _kv(t.username, config.username.isEmpty ? t.mqttAnonymous : config.username),
                  _kv(t.password, config.password.isEmpty ? t.notSet : t.mqttPasswordMasked(config.password.length)),
                ],
                _kv(t.mqttTopicPrefix, config.topicPrefix),
              ]),
            ),
            const SizedBox(height: 8),
            Text(t.mqttLocalOnly, style: kMini),
          ]);
        },
      );

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 64, child: Text(key, style: TextStyle(fontSize: 11.5, color: C.faint))),
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kNums.copyWith(fontSize: 12, color: C.txt)),
          ),
        ]),
      );
}
