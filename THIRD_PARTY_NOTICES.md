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

## 随发布二进制分发的字体

| 组件 | 版本 | 许可 | 来源 / 说明 |
|---|---|---|---|
| 阿里巴巴普惠体 3.0（Alibaba PuHuiTi 3.0）55 Regular / 85 Bold | 3.01 | 《阿里巴巴普惠体3.0版》法律声明（免费商用普通许可） | 官方字体站 <https://www.alibabafonts.com/>，2026-11-12 下载；许可全文（中/英）见随包的 `AlibabaPuHuiTi-3-LICENSE.txt`。 |

- 随包字体文件（仓库路径 `b_player/assets/fonts/`）：`AlibabaPuHuiTi-3-55-Regular.otf`（SHA-256 `0d0b12d1ea1cbbc0bf152da7a39f2b02a385a6c3ee8b78475e50f1f31379a364`）、`AlibabaPuHuiTi-3-85-Bold.otf`（SHA-256 `f75a885212d5576378b9b02859237309bcdee4ec01839a20dc184dc41e42689b`）。
- 字体文件按官方压缩包原样分发：未裁剪、未转换格式、未改名、未修改字形或字体内置的权利声明。仅作为本软件的界面字体随软件整体提供，不单独定价、出租、转授权，也不用于暗示阿里巴巴对本产品的合作、赞助或背书。
- 简体字库不覆盖完整 Big5/HKSCS 用字；繁体界面与生僻字由系统字体回退。

## 仓库内嵌源码

| 组件 | 版本 | 许可 | 说明 |
|---|---|---|---|
| flutter_chromium_webview | 0.5.5（含本地修改） | MIT，Copyright (c) 2026 Lucas Veneno | 位于 `b_player/third_party/flutter_chromium_webview`，许可全文见该目录的 `LICENSE`。本项目对其做了 CEF 合成与透明投放相关修改，原版权声明保留。 |

## 依赖包

- Flutter/Dart 依赖（media_kit、mqtt_client、flutter_js、shared_preferences、file_picker 等）以各自许可发布；
  `flutter build` 会把依赖的许可全文打进发布产物的 `data/flutter_assets/NOTICES.Z`。
- `relay/` 的 Node 依赖由 `npm install` 安装，许可见各包；主依赖 `mqtt` 为 MIT。
- 本仓库不包含音乐、歌词或音源脚本。
