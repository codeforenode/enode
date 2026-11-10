# 第三方组件与许可

eNode 以 AGPL-3.0 发布（见 [`LICENSE`](LICENSE)）。下面是随源码仓库或发布二进制分发的第三方组件。
打安装包时请保留本文件，并确认发布目录里的 `LICENSE.txt`（CEF）与 `data/flutter_assets/NOTICES.Z` 一并分发。

## 随 Windows 构建分发的二进制

| 组件 | 版本 | 许可 | 来源 / 说明 |
|---|---|---|---|
| Chromium Embedded Framework (CEF) | 149.0.4 | BSD-3-Clause | <https://github.com/chromiumembedded/cef>。由 `flutter_chromium_webview` 下载，许可全文见发布目录的 `LICENSE.txt`。 |
| libmpv | 0.36.0-403-g652a1dd907 | LGPL-2.1-or-later | 由 `media_kit_libs_windows_audio` 带入的预编译 `libmpv-2.dll`，构建参数含 `-Dgpl=false`。源码：<https://github.com/mpv-player/mpv>，构建：<https://github.com/media-kit/libmpv-win32-audio-build>。 |
| FFmpeg | 随上述 libmpv 构建 | LGPL-2.1-or-later | 随 libmpv 构建链接；该构建关闭了 GPL 组件。 |
| Flutter engine / Dart runtime | 3.44.x | BSD-3-Clause | <https://github.com/flutter/flutter>。 |

LGPL 组件以动态库形式分发；需要替换时，直接替换发布目录下的 `libmpv-2.dll` 即可。

## 仓库内嵌源码

| 组件 | 版本 | 许可 | 说明 |
|---|---|---|---|
| flutter_chromium_webview | 0.5.5（含本地修改） | MIT，Copyright (c) 2026 Lucas Veneno | 位于 `b_player/third_party/flutter_chromium_webview`，许可全文见该目录的 `LICENSE`。本项目对其做了 CEF 合成与透明投放相关修改，原版权声明保留。 |

## 依赖包

- Flutter/Dart 依赖（media_kit、mqtt_client、flutter_js、shared_preferences、file_picker 等）以各自许可发布；
  `flutter build` 会把依赖的许可全文打进发布产物的 `data/flutter_assets/NOTICES.Z`。
- `relay/` 的 Node 依赖由 `npm install` 安装，许可见各包；主依赖 `mqtt` 为 MIT。
- 本仓库不包含音乐、歌词或音源脚本。
