# eNode 自助点歌系统

酒吧/量贩场景的自助点歌：顾客用手机 H5 搜歌点歌，包房的播放主机（边缘节点）负责曲库、队列与出声。
自用与研究为主，音源自备，服务端刻意做薄——所有业务判断都留在 B端。

![拓扑](docs/system-topology.png)

```
顾客手机 H5 (guest/)  ──HTTP──  极薄中继 (relay/)  ──MQTT──  EMQX broker  ──MQTT──  B端 eNode × N（每场所一台）
                                  只转发，不存业务                              本地 + WebDAV + 在线音源 + 权威队列 + 播放
```

## 目录

| 目录 | 是什么 | 技术栈 |
|---|---|---|
| [`b_player/`](b_player) | **B端 eNode**：边缘节点 App（Windows / Android / iOS）。本地目录与 WebDAV 曲库扫描、在线音源脚本、MQTT 节点、权威队列、libmpv 播放、一屏演出 UI | Flutter 3.44 / Dart，`media_kit`、`mqtt_client`、`flutter_js` |
| [`relay/`](relay) | **极薄中继**：把 H5 的 HTTP 请求翻译成 MQTT RPC，顺带静态托管 C端页面。只做限流、快照缓存和节点路由 | Node 18+，唯一依赖 `mqtt` |
| [`guest/`](guest) | **C端 H5**：搜歌、点歌、看队列与当前播放，纯静态无构建 | 原生 HTML/CSS/JS |
| [`docs/`](docs) | [B端 对接协议 v1（MQTT）](docs/edge-integration-protocol.md)、拓扑图 | — |

## 协议要点（改代码前先读 [docs/edge-integration-protocol.md](docs/edge-integration-protocol.md)）

- **两类请求分流**：`search` 是无状态只读，可以跨节点、可以扇出聚合；`enqueue` 与队列/歌词/播放状态
  是**有状态**的，必须绑定该场所的权威节点，不允许按负载漂移。
- **对外只开 search / enqueue**。B端 只订阅这两个请求主题，播放控制（暂停/切歌/音量）永远不开放给云和 C端。
- **节点 ID 稳定**：`nodeId` 由设备派生、跨重启不变，场所绑定表按它写。
- 状态靠 `health`（10s 心跳；正常退出补发离线，异常断链由遗嘱兜底）与 retained 的 `queue` / `lyric` 快照，C端 读缓存不追实时。

## 快速开始

### B端 eNode

```bash
cd b_player
flutter pub get
flutter run -d windows          # 或 -d <android device id>
flutter test                    # 用例：协议对接、WebDAV 扫描、在线音源、播放引擎、LRC、曲库目录、一屏 UI
ONLINE_LIVE=1 flutter test test/lx_live_test.dart   # 可选：五平台真实网络自检（默认跳过）
```

出包：

```powershell
# Windows：便携 zip + 安装包（需 VS C++ 工具链与 Inno Setup，缺工具链先跑 install_windows_toolchain.ps1）
powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1 -Installer
#   -> dist\eNode-<ver>-win-x64.zip / eNode-<ver>-win-x64-setup.exe
flutter build apk --release     # -> build/app/outputs/flutter-apk/app-release.apk
```

曲库目录默认 `D:\Music`（桌面）或 `/storage/emulated/0/Music`（Android），在底部「音源」区点
「更改文件夹」改，索引落进应用支持目录，断网也能秒开列表。

**WebDAV 音源**：同一块「音源」区右上角「新增」填地址与账号密码，保存后递归 PROPFIND 把远端音频
扫进统一曲库（跳过 `@eaDir`、回收站和点目录），检索/入队/歌词/封面与本地曲目走同一条链路。
账号密码只存本机 SharedPreferences，不拼进 URL、不打日志；播放请求头由音源单独提供。
宽屏时音源区固定在窗口底部 190px，窄屏（<900）收成一行「音源」条，点「管理」进整页管理。

设置弹层的「音源」段默认隐藏，连点关于页版本号 5 次解锁，用于填在线音源与勾选平台。

### Windows 桌面行为

- 标题栏的叉只是**收进托盘**，播放与点歌服务继续跑。托盘图标左键（双击也走这条）把窗口叫回来，
  右键菜单是「打开 eNode / 开机启动 / 退出」；退出先弹确认框，确认后才停心跳、断 MQTT、销毁托盘再结束进程。
- **开机启动**写当前用户的 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`（值名 `eNode`，路径带引号，
  因为安装目录 `C:\Program Files\eNode` 有空格），不需要管理员权限；再点一次即取消。
- **单实例**：首个进程占住 `127.0.0.1:47621`，后续进程只负责把已有窗口叫起来然后自己退出——曲库索引与 MQTT
  只归一个进程持有。端口被无关程序占用时照常启动，不至于起不来。
- **版本号只有一个来源**：`pubspec.yaml` 的 `version`。构建时写进 exe 文件属性，运行时用 `package_info_plus`
  读回界面，所以标题栏的 v1.4.0 和文件属性的 1.4.0+3 不会各说各话。
- **屏幕管理**（仅 Windows）：设置 → 屏幕管理里勾选目标屏，为每块屏摆素材（歌词、图片、影片、文字、网页），
  支持多图层、逐屏位置/透明度/层级/静音；同一素材可共用多屏，样式共享而位置与声音各自独立。
  画面在 CEF 网页里合成：一块 canvas 承载所有屏的构图，每个目标屏一扇置顶 + 鼠标穿透的 presenter 窗；
  歌词与时钟锚点只有一份，各窗按本地墙钟推进、主进程每秒纠偏一次，所以多屏同拍而不靠逐帧对齐。
  建窗是串行的（并发改窗口样式会整进程段错误）；CEF/画布起不来时退回「一屏一引擎一窗」，再不行由 Flutter 自绘兜底。

### 中继 + C端

```bash
cd relay
npm install
# MQTT 参数从环境变量读，缺少 MQTT_HOST 会直接拒绝启动
MQTT_HOST=broker.example.com MQTT_PORT=1883 \
MQTT_USERNAME=<账号> MQTT_PASSWORD='<密码>' \
npm start                       # 默认 0.0.0.0:8080，PORT 可改；同时静态托管 ../guest
```

Windows PowerShell 下分成几行写：`$env:MQTT_HOST='…'`、`$env:MQTT_PASSWORD='…'`，再 `npm start`。

顾客访问 `http://<中继地址>:8080/?seat=A12`（`seat` 可省，页面内也能填桌号）。
接口只有三个：`GET /api/state`、`GET /api/search?q=`、`POST /api/enqueue`。

## 部署参数

**仓库不内置任何 broker 凭据**，连接信息在部署时提供：

- **B端**：设置 →「广播」，把服务端给的连接信息整段粘进来（`mqtt://账号:密码@地址:端口`，或多行
  `Broker / 端口 / 账号 / 密码`），点「识别并应用」保存到本机并立即重连；「清除本机配置」断开并回到
  未配置。没配置时 B端 不连 MQTT，状态显示「MQTT 未配置」。
- **中继**：启动前用环境变量提供，缺 `MQTT_HOST` 直接退出：
  `MQTT_HOST`、`MQTT_PORT`（默认 1883）、`MQTT_USERNAME`、`MQTT_PASSWORD`、
  `MQTT_TLS`（`1` 开启）、`MQTT_TOPIC_PREFIX`（默认 `node`，要和 B端 一致）。
  读取逻辑见 [`relay/config.js`](relay/config.js)。
- 限流、RPC 超时、快照 TTL：[`relay/config.js`](relay/config.js)
- 在线音源地址与密钥：运行时导入，落 B端 本地存储，不入库、不打日志

> 仓库不内置任何 broker 凭据；换环境或怀疑泄露时，先在 broker 侧轮换密码。
> 日志与提交信息不得打印凭据值。

## 现状与已知边界

- **多场所路由尚未落地**：`relay` 现在把请求发给「health 最新的在线节点」（`selectNode`），
  等价于一中继一场所。协议 §10 已经写清 `venue → nodeId` 绑定表和 `NODE_NOT_BOUND` 的处置，代码照那份文档改。
- **v1 不做应用层签名与防重放**：只校验「能连上 broker + 只能收发本节点主题」，建议用 EMQX 主题级 ACL 兜住。
- **队列不跨节点迁移**：节点离线期间 `enqueue` 直接返回不可用，不做排队补发。
- 播放依赖在线音源实时解析，源站点变更会表现为「跳过」而非报错；B端 有坏文件自动跳过与失败降级。

## 品牌与图标

[`b_player/brand/make_icons.py`](b_player/brand/make_icons.py) 从同一份矢量绘制生成 Android/iOS/Windows/Web
全部图标与 `enode-logo-1024.png`；改 Logo 只改这一个脚本然后重跑。Windows 托盘用的是同一份图形缩到 16px 的
`b_player/assets/icons/enode.ico`（已登记进 pubspec 的 assets），和桌面 exe 图标同源。
全平台显示名都是 **eNode**，Android 包名与 iOS Bundle ID 分别是 `com.enode.b_player` / `com.enode.bPlayer`。

## 第三方约束

架构参考了 any-listen（AGPL-3.0）的层次划分与启动流程，未复制其代码；在线音源沿用开源播放器的
音源脚本协议（仅取 `musicUrl`），检索与歌词由 B端 自己按平台接口实现。
随包分发的 CEF、libmpv/FFmpeg、Flutter 与内嵌的 flutter_chromium_webview 的许可与来源见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可证

[AGPL-3.0](LICENSE)，Copyright (C) 2026 eNode contributors。

可以商用；但分发修改版，或把修改版作为网络服务提供给用户时，必须以 AGPL-3.0 开放对应源码。
作为 eNode 在线服务的使用者，源码地址就是本仓库。

安装包内的 `LICENSE` 与 `THIRD_PARTY_NOTICES.md` 也会随 App 资产打包，可在「设置 → 关于 →
查看许可与第三方组件」离线查看；C端页脚展示 AGPL 标识与源码入口
（<https://github.com/codeforenode/enode>）。

> iOS 目标未随仓库提供签名与上架配置；AGPL 与 App Store 的分发条款存在冲突，上架前请自行评估。

## 免责声明

本仓库不包含音乐、歌词或音源脚本，也不提供任何内容源。在线检索与播放依赖使用者自行导入的第三方脚本
和平台接口；请自行确认版权、平台条款与当地法律。项目与各音乐平台无关联。
