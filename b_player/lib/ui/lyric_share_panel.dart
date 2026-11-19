import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'cards.dart';
import 'form_bits.dart';

/// 「广播」页里的局域网歌词页开关：开启后在手机浏览器打开地址即可看当前歌词。
///
/// 只暴露正在播放的一首，曲库不出本机；地址里的令牌等同于密码，可随时重置。
class LyricSharePanel extends StatefulWidget {
  const LyricSharePanel({super.key, required this.state});
  final AppState state;

  @override
  State<LyricSharePanel> createState() => _LyricSharePanelState();
}

class _LyricSharePanelState extends State<LyricSharePanel> {
  late final TextEditingController _port =
      TextEditingController(text: '${widget.state.lyricShare.port}');

  /// 用户动过端口输入框后，异步加载完成的设置不再回写，避免打断输入。
  bool _portTouched = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  int? _parsedPort() {
    final port = int.tryParse(_port.text.trim());
    return port != null && port >= 1024 && port <= 65535 ? port : null;
  }

  Future<void> _toggle(bool on) async {
    final t = AppL10n.of(context);
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final settings = widget.state.lyricShare;
      if (!on) {
        await widget.state.applyLyricShare(settings.copyWith(enabled: false));
        return;
      }
      final port = _parsedPort();
      if (port == null) {
        setState(() => _error = t.lyricSharePortInvalid);
        return;
      }
      await widget.state.applyLyricShare(settings.copyWith(enabled: true, port: port));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 改端口：停用状态下只保存，启用状态下立即换端口重启。
  Future<void> _applyPort() async {
    final t = AppL10n.of(context);
    final port = _parsedPort();
    setState(() {
      _error = null;
      if (port == null) _error = t.lyricSharePortInvalid;
    });
    if (port == null) return;
    setState(() => _busy = true);
    try {
      await widget.state.applyLyricShare(widget.state.lyricShare.copyWith(port: port));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final t = AppL10n.of(context);
          final settings = widget.state.lyricShare;
          final running = widget.state.lyricShareRunning;
          final urls = widget.state.lyricShareUrls;
          final error = _error ??
              (settings.enabled && !running ? widget.state.lyricShareError : null);
          // 设置是异步读的；用户没动过输入框就跟着最新值走。
          if (!_portTouched) _port.text = '${settings.port}';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 22),
              CardHead(
                t.lyricShareTitle,
                trailing: running ? t.lyricShareOn : t.lyricShareOff,
              ),
              Text(t.lyricShareIntro, style: kMini),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Choice(
                    fill: C.panel,
                    label: t.lyricShareEnable,
                    on: settings.enabled,
                    onTap: _busy ? () {} : () => _toggle(true),
                  ),
                  Choice(
                    fill: C.panel,
                    label: t.lyricShareDisable,
                    on: !settings.enabled,
                    onTap: _busy ? () {} : () => _toggle(false),
                  ),
                  SizedBox(
                    width: 96,
                    child: FormInput(
                      controller: _port,
                      hint: t.lyricSharePort,
                      onChanged: (_) => _portTouched = true,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _applyPort,
                    style: TextButton.styleFrom(foregroundColor: C.dim),
                    child: Text(t.lyricShareApply),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (urls.isEmpty)
                      Text(t.lyricShareEmpty, style: kMini)
                    else
                      for (final url in urls)
                        Row(children: [
                          Expanded(
                            child: SelectableText(
                              url,
                              style: TextStyle(fontSize: 12, color: C.txt, height: 1.6),
                            ),
                          ),
                          TextButton(
                            onPressed: () => copyToClipboard(context, url, t.lyricShareCopied),
                            style: TextButton.styleFrom(foregroundColor: C.dim),
                            child: Text(t.lyricShareCopy),
                          ),
                        ]),
                    if (urls.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(t.lyricShareOpenHint, style: kMini),
                    ],
                  ],
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  settings.enabled && !running && _error == null
                      ? t.lyricShareUnavailable(error)
                      : error,
                  style: TextStyle(fontSize: 11.5, color: C.bad),
                ),
              ],
              const SizedBox(height: 8),
              Text(t.lyricShareHint, style: kMini),
              const SizedBox(height: 4),
              Text(t.lyricShareSecurity, style: kMini),
            ],
          );
        },
      );
}
