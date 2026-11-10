# B端 边缘节点对接协议 v1（MQTT）

对接对象：调度服务器 / 其他接入方。
服务方：B端（Flutter 播放器）作为**边缘计算节点**——曲库检索、队列权威、播放状态都在 B端；
服务器只通过 MQTT 请求与订阅，不保存曲库数据。
本协议没有「场所」概念：每个 B端 就是一个独立节点，队列与检索都归属节点自身。
**B端 对外只提供 MQTT 接口**：曲目、歌词、播放状态、检索与入队全部走 MQTT 主题，不提供 HTTP 接口。

## 0. 设计边界（先读）

| 事项 | 约定 |
|---|---|
| 曲库数据 | **B端 不公布任何曲库内容/索引**。搜索必须在 B端 上执行，结果只回给当次请求方 |
| 队列 | 每个节点的队列只属于该节点，B端 是唯一权威；服务器看到的只是保留快照 |
| 二维码 / 桌号 | 由接入方自己管理。B端 只接收并展示 `guest` 里的桌号字符串，不生成、不校验桌码 |
| 控制权限 | 仅开放 `search` 与 `enqueue` 两种请求；**不提供暂停/切歌/音量等播放控制接口** |
| 身份 | `nodeId` 由 B端 自动生成（设备标识哈希），**不由接入方分配、不可填写**；跨重装/升级不变，主题与全部消息都带 `nodeId` |

### 0.1 节点 ID

- 格式：`nd-` + 16 位十六进制，例如 `nd-3f1a9c02b7d84e51`。
- 生成：B端 读取设备稳定标识（Android ID / iOS IDFV / Windows MachineGuid / Linux machine-id），
  经 SHA-256 截断得到；消息里不会出现原始硬件标识。
- 稳定性：重装、升级、清空应用数据后重新计算仍是同一个 ID；恢复出厂设置或换机才会变化。
- 服务器不得要求使用者填写节点 ID；节点上线后通过 retained `health` 自动发现。
- 平台差异：Android 的设备标识与签名证书绑定，同一台设备上的调试包与正式包会被视为不同应用，
  节点 ID 可能不同（正式部署固定使用同一签名即可）；iOS 的 IDFV 在本厂商应用全部卸载后可能重置。

## 1. 传输与主题

- MQTT 3.1.1 或 5.0，JSON UTF-8。
- 主题前缀 `{prefix}` 默认 `node`，B端 可自定义；`{nodeId}` 由 B端 生成，格式见 0.1。
  默认主题形如 `node/nd-3f1a9c02b7d84e51/health`，不包含任何厂商/品牌字样。
- 保留消息（retained）只用于 `health`、`queue` 与 `lyric`；RPC 应答不保留。

| 主题 | 方向 | QoS | Retained | 说明 |
|---|---|---|---|---|
| `{prefix}/{nodeId}/health` | B端 → 所有 | 1 | 是 | 健康状态，10s 周期 + 变化即发；正常退出补发 `state:"offline"`，异常断链由遗嘱兜底 |
| `{prefix}/{nodeId}/queue` | B端 → 所有 | 1 | 是 | 队列全量快照 + 当前曲目，带 `seq` |
| `{prefix}/{nodeId}/lyric` | B端 → 所有 | 1 | 是 | 当前曲目的歌词全文，切歌即更新；无曲目时为空歌词 |
| `{prefix}/{nodeId}/events` | B端 → 所有 | 1 | 否 | 增量事件，`seq` 单调递增 |
| `{prefix}/{nodeId}/rpc/search.req` | 服务器 → B端 | 1 | 否 | 检索请求 |
| `{prefix}/{nodeId}/rpc/search.resp/{nonce}` | B端 → 服务器 | 1 | 否 | 检索应答 |
| `{prefix}/{nodeId}/rpc/enqueue.req` | 服务器 → B端 | 1 | 否 | 入队请求 |
| `{prefix}/{nodeId}/rpc/enqueue.resp/{nonce}` | B端 → 服务器 | 1 | 否 | 入队应答 |

服务器发现节点：订阅 `{prefix}/+/health`，retained 消息立即给出全部在线节点；
节点掉线由 `state:"offline"` 的 retained `health` 通知（正常退出由 B端 主动补发，异常断链由遗嘱发布），无需额外的在线主题。

## 2. 通用信封

RPC 与事件共用同一信封，`v` 为协议版本：

```json
{
  "v": 1,
  "type": "search.req",
  "node": "nd-3f1a9c02b7d84e51",
  "ts": 1762104000123,
  "nonce": "5c1d9e2a",
  "payload": {}
}
```

- `ts`：发送方毫秒时钟；入队请求超过 30s 视为过期。
- `nonce`：请求方**每次发送**生成，唯一且不复用；应答主题后缀必须与之一致。
  它只用于应答配对，不承担幂等；入队幂等由 `requestId` 负责（见 §11.2）。
- **未知字段必须忽略；未知 `type`/事件必须跳过且不断链。**
- 路由与请求执行策略见 §10、§11，接入方必须按这两节实现。

## 3. 健康状态（服务器的路由依据）

`{prefix}/{nodeId}/health`，retained，10s 一次：

```json
{
  "v": 1,
  "state": "online",
  "ts": 1762104000123,
  "node": "nd-3f1a9c02b7d84e51",
  "uptimeMs": 86400000,
  "queueDepth": 4,
  "playing": true,
  "library": { "count": 5000, "scanning": true, "scanned": 1240, "broken": 2 },
  "load": { "searchServed": 128, "searchAvgMs": 7, "enqueueServed": 31 },
  "caps": ["search", "enqueue", "snapshot", "events"],
  "app": { "name": "b-player", "version": "0.1.0" }
}
```

| 字段 | 用途 |
|---|---|
| `state` | `online` / `degraded` / `offline`。`degraded` 表示可响应但不宜优先（如曲库扫描中、负载高）；`offline` 由遗嘱消息发出 |
| `queueDepth` | 队列长度；服务器可据此做负载/排队策略 |
| `library.count` / `scanning` / `scanned` / `broken` | 曲库就绪度，仅在 B端 本地产生，不含任何曲目内容 |
| `load.*` | 本进程自启动以来的计数与平均耗时 |
| `caps` | 能力声明；服务器不得假设未声明能力存在。**动态**：`search` 只在节点能给出「点了就能播」的结果时才声明（本机有索引，或在线音源已可取链）。音源脚本被清空后节点会撤下 `search` 并重发 health，接入方应据此关闭搜索入口而不是让顾客搜出一支点不响的歌 |

**注意**：健康消息里没有、也不允许出现任何曲名/歌手/`trackKey`。服务器若需要搜索，
只能发 RPC 给节点，由节点在自己的曲库里算。

服务器路由按**请求类型**分流（见 §10）：
- `search.req` 是无状态只读，可发给任意在线节点，也可跨节点扇出聚合；
- `enqueue.req` 与队列/歌词/状态读取有状态，必须发往场所绑定的节点，不能按负载漂移。
节点之间曲库可能不同源：跨节点检索结果只有在曲库同源时才能直接入队（§10.3）。
健康消息按**本地接收时间**超过 35s 即视为过期、不参与路由；`degraded` 默认不参与入队路由。

## 4. 队列快照与事件

### 4.1 `queue`（retained）

```json
{
  "v": 1,
  "seq": 1842,
  "node": "nd-3f1a9c02b7d84e51",
  "ts": 1762104000123,
  "player": {
    "trackKey": "local:00042",
    "title": "搁浅之外",
    "artist": "五月天",
    "durationMs": 251000,
    "positionMs": 83000,
    "sampledAtMs": 1762104000090,
    "rate": 1,
    "lyricAvailable": true,
    "audioLatencyMs": 0,
    "guest": { "seat": "12" }
  },
  "queue": [
    { "trackKey": "local:00043", "title": "稻香之外", "artist": "邓紫棋", "durationMs": 175000, "guest": { "seat": "7" } }
  ]
}
```

- `seq` 单调递增；新订阅者先拿 retained 快照，再用 `events` 追增量。
- `sampledAtMs` 是 `positionMs` 的采样时刻（B端 时钟），用于远端插值。
- `rate`：`1` 播放 / `0` 暂停；不要用「事件停止」判断暂停。
- `guest.seat` 为接入方传入的原始字符串，B端 不解释其格式。
- `lyricAvailable`：当前曲目是否有可下发歌词；为 `false` 时 `lyric` 主题是空歌词。
- `audioLatencyMs`：B端 播放链路的输出延迟估计，远端渲染歌词时用 `positionMs - audioLatencyMs` 对齐；当前实现为 `0`。

### 4.2 `events`

```json
{ "v": 1, "seq": 1843, "type": "queue.update", "at": 1762104001090, "data": { "queue": [] } }
```

| 类型 | `data` | 触发 |
|---|---|---|
| `queue.update` | `{ "queue": [...] }` | 入队、删除、排序 |
| `player.track` | `{ "trackKey", "title", "artist", "durationMs", "guest" }` | 切歌 |
| `player.state` | `{ "rate": 1 }` | 播放/暂停 |
| `player.tick` | `{ "positionMs", "sampledAtMs", "rate" }` | 默认 5s 心跳 |

`seq` 不连续时，订阅方必须重新读取 retained `queue`，**不依赖补发**。

### 4.3 `lyric`（retained）

曲目与歌词只经 MQTT 下发，B端 **不提供 HTTP 接口**。`lyric` 主题用 retained 消息保存当前曲目的歌词全文，
连接建立与每次切歌时整体重发；位置与暂停不在这里表达，以 `queue` 快照的 `player.positionMs/sampledAtMs/rate` 为准。

```json
{
  "v": 1,
  "node": "nd-3f1a9c02b7d84e51",
  "ts": 1762104000123,
  "trackKey": "local:00042",
  "format": "lrc",
  "offsetMs": 0,
  "rev": "9f3c81ab",
  "text": "[ti:搁浅之外]\n[ar:五月天]\n[00:00.00]搁浅之外 - 五月天\n[00:08.00]歌词第一行\n"
}
```

| 字段 | 说明 |
|---|---|
| `trackKey` | 歌词所属曲目；必须与 `queue.player.trackKey` 一致才渲染 |
| `format` | 固定 `lrc`（后续可扩展，未知格式必须忽略） |
| `offsetMs` | 全局歌词偏移，正值表示歌词整体延后 |
| `rev` | `text` 的 SHA-256 前 8 位；订阅方可据此跳过重复解析 |
| `text` | LRC 全文，UTF-8 编码；`"text":""` 表示当前曲目无歌词或队列为空 |

- **无曲目**：`trackKey`、`rev` 为 `null`/空串，`text` 为空串，`queue.player` 也为 `null`。
- **切歌**：同一时刻先更新 retained `queue`，再更新 retained `lyric`；订阅方以 `trackKey` 对齐，不依赖到达顺序。
- 歌词体积远小于曲库，可直接走 retained；单条建议 ≤ 64KB，超长歌词由 B端 截断。
- 曲库内容仍不出本机：只下发**当前曲目**的歌词，不下发歌词列表或索引。

## 5. 检索 RPC

请求 `{prefix}/{nodeId}/rpc/search.req`：

```json
{ "v": 1, "type": "search.req", "node": "nd-3f1a9c02b7d84e51", "ts": 1762104000123, "nonce": "5c1d9e2a",
  "payload": { "q": "晴天", "offset": 0, "limit": 20 } }
```

- `q`：1–64 字符，按标题/歌手做包含匹配（大小写、全半角归一化；拼音检索属后续能力）。
- `offset`：0–1000；`limit`：1–50，默认 20。
- 单包建议 ≤ 256KB；结果必须分页，**禁止一次回全库**。
- 发请求前先读 `health.caps`：节点没声明 `search` 就别发 `search.req`。节点侧同样门控——
  在线音源取不出播放地址时不返回在线结果，只返回本机命中，保证「搜出来的都能播」。

应答 `{prefix}/{nodeId}/rpc/search.resp/{nonce}`：

```json
{ "v": 1, "type": "search.resp", "node": "nd-3f1a9c02b7d84e51", "ts": 1762104000180, "nonce": "5c1d9e2a",
  "payload": {
    "ok": true, "total": 37, "offset": 0, "limit": 20, "tookMs": 6,
    "items": [
      { "trackKey": "local:00001", "title": "晴天", "artist": "朴树", "durationMs": 250000 }
    ]
  } }
```

**`trackKey` 只在产生它的曲库内有效**：跨节点复用仅当目标节点拥有同源同版本的曲库。
入队必须发给场所绑定节点，规则见 §10.3。若接入方**跨节点聚合检索**，必须逐条标注来源节点
（`originNode`），聚合与去重规则见 §10.2；聚合结果不能替代入队节点。

## 6. 入队 RPC

请求 `{prefix}/{nodeId}/rpc/enqueue.req`：

```json
{ "v": 1, "type": "enqueue.req", "node": "nd-3f1a9c02b7d84e51", "ts": 1762104000123, "nonce": "9a7f33c1",
  "payload": {
    "trackKey": "local:00001",
    "requestId": "t-20261103-0001",
    "guest": { "seat": "12", "tag": "guest-7f3a" }
  } }
```

- `requestId`：接入方生成，用于幂等；同一 `requestId` 10 分钟内只处理一次，重复请求返回第一次的结果
  （拒绝结果同样缓存）。只有已处理的请求才入缓存；`STALE_REQUEST`/`RATE_LIMITED`/`BAD_REQUEST`
  不消耗 `requestId`，修正后可立即重试。重试规则见 §11.2、§11.3。
- `guest.tag`：可选，用于限流归属；`guest.seat`：原样展示到队列。
- **入队目标节点**：必须是场所绑定节点，且 `trackKey` 在该节点有效。检索结果的来源节点不能替代入队节点；
  跨节点检索结果何时可直接入队见 §10.3。
- 是否接受由 B端 决定（容量、限流、曲目存在性）。
- **入队前置校验**：B端 接受前先解析一次播放地址，解析不出来就直接拒绝（`SOURCE_UNAVAILABLE`），
  不会先把歌收进队列再在播放时消失。在线直链按 10 分钟缓存，命中缓存的请求不产生外部 IO；
  因此该请求可能是异步的，见 §11.1。

应答 `{prefix}/{nodeId}/rpc/enqueue.resp/{nonce}`：

```json
{ "v": 1, "type": "enqueue.resp", "node": "nd-3f1a9c02b7d84e51", "ts": 1762104000130, "nonce": "9a7f33c1",
  "payload": { "ok": true, "result": "accepted", "queuePosition": 5,
               "trackKey": "local:00001", "requestId": "t-20261103-0001" } }
```

拒绝时：

```json
{ "payload": { "ok": false, "result": "rejected", "reason": "SOURCE_UNAVAILABLE",
               "message": "这首歌本店暂时放不了，换一首试试",
               "requestId": "t-20261103-0001" } }
```

- `reason` 是 §7 的错误码；`message` 是可直接展示给顾客的一句话（可选，接入方优先用它，缺失时再按码兜底）。
- 被前置校验拒绝的请求**没有进队列**，同一 `requestId` 的重试会返回同一个拒绝结果。

## 7. 错误码（稳定契约）

| 码 | 含义 |
|---|---|
| `BAD_REQUEST` | 字段缺失/越界/版本不支持 |
| `RATE_LIMITED` | 超过限流（入队默认 6 次/分钟/`guest.tag`） |
| `QUEUE_FULL` | 队列达到上限（默认 200） |
| `TRACK_NOT_FOUND` | `trackKey` 在本节点不存在或已失效 |
| `SOURCE_UNAVAILABLE` | 入队前解析不出播放地址：未导入音源脚本、直链全部失效或取链超时。拒绝入队并附顾客可读的 `message`；换一首或让店家修好音源后**换新 `requestId`** 再点（旧 `requestId` 命中拒绝缓存） |
| `STALE_REQUEST` | `ts` 超过 30s |
| `INTERNAL` | B端 内部错误（检索超时也归此类）。入队重试须带同一 `requestId`；检索没有 `requestId`，重试换新 `nonce` |

各码的重试与处置见 §11.3。

## 8. 鉴权与部署

- **连接级**：仓库不内置 broker 地址与凭据。B端 在 设置 →「广播」整段粘贴连接信息（保存在本机，
  未配置时不发起连接）；中继从 `MQTT_HOST` 等环境变量读取（见 `relay/config.js`）。
- **主题级 ACL**（推荐）：

| 角色 | 可发布 | 可订阅 |
|---|---|---|
| B端（每节点一套凭据） | `{prefix}/{nodeId}/health`、`/queue`、`/lyric`、`/events`、`/rpc/search.resp/+`、`/rpc/enqueue.resp/+` | `{prefix}/{nodeId}/rpc/search.req`、`/rpc/enqueue.req` |
| 服务器 | `{prefix}/+/rpc/search.req`、`/rpc/enqueue.req` | `{prefix}/+/health`、`/queue`、`/lyric`、`/events`、`/rpc/search.resp/+`、`/rpc/enqueue.resp/+` |

- 第一版只校验「能连上 broker + 能收发本节点主题」，不做应用层签名；
  若需要防重放，在 `requestId` 上加接入方自己的签名即可，B端 按 `requestId` 幂等。
- 播放控制始终不开放；即使接入方拿到了发布权限，B端 也只订阅 search/enqueue 两个主题。

## 9. 断线与兼容

- 节点表：订阅 `{prefix}/+/health` 维护，retained 立即给出全量；遗嘱 `offline` 或 35s 无更新即剔除，路由规则见 §10。
- B端 断线：正常退出时先补发 retained `health`（`state:"offline"`）再断开，异常断链由 broker 遗嘱兜底；重连后立即重发 retained `health`、`queue` 与 `lyric`（带新 `seq`）。
- 服务器断线：重连后先读 retained `health`/`queue`/`lyric`，再订阅 `events`；`seq` 跳跃则重读快照。
- 重连退避：1s → 2s → 4s → … 上限 30s；重连成功后重置。节点离线期间不接受 `enqueue` 排队（实时行为，过期无意义），直接返回不可用。
- 版本：`v` 不匹配时回 `BAD_REQUEST` 并附 `"supported":[1]`；不得静默降级。
- 兼容规则沿用：未知字段忽略、未知类型跳过、`caps` 未声明即不存在。

## 10. 请求路由（按请求类型分流）

本节是第一优先级：先判断请求是否需要场所绑定，再决定路由。

### 10.1 两类请求

| 类型 | 请求 | 路由约束 |
|---|---|---|
| 无状态只读 | `search.req` | **可跨节点**：任意在线节点、可负载均衡、可扇出聚合 |
| 有状态 | `enqueue.req`、队列/歌词/播放状态读取 | **必须场所绑定**：固定发往该场所的权威节点，不得按负载漂移 |

- 判据只有一个：请求是否会改变或读取某个节点的权威队列与播放状态。会的一律场所绑定。
- 查询结果可以来自任意节点，但「入队到哪」永远由场所决定。
- v1 不做跨节点队列聚合、不做跨节点故障接管。

### 10.2 查询路由（可跨节点）

候选节点：health 本地 35s 内、`state=="online"`、`caps` 含 `search`。

| 模式 | 适用 | 行为 |
|---|---|---|
| A 同源曲库（推荐默认） | 各场所曲库同源同版本 | 查询发给任意/最空闲候选节点，结果可直接在场所节点入队 |
| B 扇出聚合 | 曲库不同源，需要全网发现 | 并行发多个节点，单节点超时互不影响，允许部分成功；逐条标注 `originNode` 并按标题/歌手/时长去重 |
| C 场所优先 | 想先看本店有没有 | 先查场所节点，用户主动「全网搜索」再走 B |

- 扇出预算：建议 ≤8 个节点、单节点超时 5s、总预算 8s；超限返回部分结果并附失败节点列表。
- 检索应答必须标注来源：单节点模式带响应节点；聚合模式每条 item 带 `originNode`。
- 查询**不需要粘性**：同一关键词可以落到不同节点；不要因为上次查的是 N 就固定 N。
- 单个节点超时或报错只影响它的结果，不要让整次查询失败。

### 10.3 入队路由（必须场所绑定）

- 只按 `venue`（`zone`）→ `nodeId` 绑定解析；**不得**用检索结果里的 `originNode` 替代，也不得负载均衡。
- 同源曲库（10.2-A）：跨节点查到的 `trackKey` 与场所节点一致，可直接入队。
- 不同源（10.2-B/C）：本店没有的曲目不能入队。服务端应在**场所节点**重新检索并映射出本地有效
  `trackKey` 再入队；映射失败返回 `TRACK_NOT_FOUND`，不要转发到 `originNode`。
- 在线曲目（`lx:` 前缀）：`trackKey` 由 `platform:songId` 决定，跨节点相同；但播放解析依赖节点本地的
  在线曲目元数据缓存。场所节点没检索过这首时可能解析失败，因此入队前应在场所节点完成一次检索（v1 约束）。
- 队列、歌词、播放状态同属有状态读取，一律读场所节点的 retained 消息。

### 10.4 场所绑定

| 项 | 规则 |
|---|---|
| 二维码内容 | 只带 `venue`（必要时 `venue+zone`）与桌号，**不带 `nodeId`**；由服务端解析节点 |
| 绑定表 | `{venue, zone?, nodeId, enabled}`，部署者维护（配置文件或管理接口），B端 不上报场所 |
| 默认粒度 | 一个场所一条队列 → 绑定一个节点；多个分区各自独立排队时，每个分区各绑一个节点 |
| 换机 | 只改绑定表，不改二维码；换机后旧 `trackKey` 不再可靠，重新搜索即可 |
| 防越权 | 若坚持在 URL 暴露 nodeId，必须加签名或白名单，否则顾客可改参数往别家店入队（不推荐） |
| 未绑定 | 返回 `NODE_NOT_BOUND`，不要回退到任意在线节点 |

`NODE_NOT_BOUND` 是**服务层**错误码，由接入方 API 返回，B端 不会返回它。

### 10.5 一致性与展示

- 入队不绑定「搜索来源节点」：搜索可以跨节点，入队节点只由场所决定。
- 若要标记「本店可取」：以**场所节点自己的检索结果**为准，不要用其他节点的结果冒充本店库存。
- 状态轮询固定读场所节点，避免一个页面同时显示两个节点的队列。
- 绑定变更（换机）后，C端 缓存的 `trackKey` 可能失效，重新搜索即可。

### 10.6 离线、换机与降级

- 场所节点离线（遗嘱 `offline` 或 health 超 35s）：入队/队列/状态返回 503，**不转发到其他场所节点**；
  查询仍可跨节点继续，但结果按 §10.3 处理，不能直接入队到本店。
- 节点重启：`nodeId` 跨重启稳定，绑定继续有效；等 retained `queue` 恢复后再展示队列。
- 节点换机/重装导致 `nodeId` 变化：运维更新绑定；队列不迁移，v1 接受该丢失。
- 降级按业务定：例如 `degraded` 时仍允许查询、但入队返回 503。
- 快照 TTL：参考实现 10 分钟无更新即从内存淘汰；在线判断始终以 health 新鲜度为准。

### 10.7 参考实现现状（必须知道的差距）

- `relay/server.js` 的 `selectNode()` 目前用同一套逻辑处理 search、enqueue 和状态读取，且取「最新健康的在线节点」，
  等于把有状态请求也做了全局漂移。
- 单场所单节点时可用；多场所上线前必须按 §10.1 分流：search 可保持全局（或扇出），
  enqueue/queue/state 必须查场所绑定表。
- 协议层无需改动：信封里的 `node` 字段已经支持显式指定节点。
- 已落地的能力门控：`relay` 在 `/api/search` 前检查所选节点 `health.caps` 是否含 `search`，
  没有则回 `503 SEARCH_DISABLED`（中继侧错误码，B端 不返回它）；`caps` 字段缺失按旧节点处理，不拦。
  C端 按 `error` 码优先出文案，`SOURCE_UNAVAILABLE`/`SEARCH_DISABLED` 用 B端/中继给的 `message`。

## 11. 请求执行策略（超时、重试、限流、同步）

### 11.1 超时

| 请求 | B端 内部上限 | 接入方超时建议 |
|---|---|---|
| `search.req` | 8s（超时回 `INTERNAL`） | 10s |
| `enqueue.req` | 6s 取链预算（入队前解析播放地址，§6；命中直链缓存时仍是毫秒级）；超时回 `SOURCE_UNAVAILABLE` | ≥9s（参考中继 9s），必须大于 B端 的 6s |
| 状态订阅 | `health` 10s、`player.tick` 5s | 15s 无任何消息视为链路异常，主动重连 |

- 超时后重发：检索换新 `nonce`；入队沿用同一 `requestId`、换新 `nonce`（避免重复入队）。
- 超时不是失败结论：入队可能已在 B端 成功，只是应答丢失。以重试返回的缓存结果为准。

### 11.2 幂等与去重

- `requestId` 由接入方生成，**同一次用户操作跨重试保持不变**；B端 缓存 10 分钟，
  重复请求返回第一次的结果（含拒绝结果）。
- `nonce` 每次发送唯一；不要用 `nonce` 做业务去重，也不要让两次不同请求共用一个应答主题。
- 客户端在「已发出、未收到应答」期间必须禁用同一按钮；同一 `requestId` 不允许并发发送。
- MQTT QoS 1 可能重复投递：入队重复由 `requestId` 吸收；检索是只读操作，重复无副作用。

### 11.3 按错误码处置

| 情况 | 动作 |
|---|---|
| `BAD_REQUEST` | 不重试；修正字段或版本后重新发起 |
| `RATE_LIMITED` | 不立即重试；按 60s 滚动窗口等待或提示用户。不得更换 `tag` 绕过限流 |
| `QUEUE_FULL` | 不重试；提示「队列已满，稍后再点」 |
| `TRACK_NOT_FOUND` | 节点已变化或曲目失效；重新搜索取得新 `trackKey` 后再入队 |
| `SOURCE_UNAVAILABLE` | 不自动重试；直接展示 `message`（多半是店家没导音源）。同一首歌稍后再点要用**新 `requestId`**，否则会命中这次拒绝的缓存 |
| `STALE_REQUEST` | 立即重试一次：刷新 `ts`、换新 `nonce`、`requestId` 不变 |
| `INTERNAL` | 可重试：1s / 2s / 4s 退避，最多 3 次；入队沿用 `requestId`，检索换新 `nonce` |
| 无应答（超时） | 同 `INTERNAL`；入队必须沿用 `requestId` 以命中缓存 |
| `NODE_OFFLINE` / `NODE_NOT_BOUND` | 不重试；等 health 恢复或运维修正绑定后由用户重新发起 |

通用规则：自动重试只用于「没有应用层应答」或 `INTERNAL`/`STALE_REQUEST`；其余错误交给上层决策。
超过 30s 的入队请求会因 `ts` 过期被拒，重试前必须重新生成 `ts`。

### 11.4 限流预算

| 层 | 检索 | 入队 | 备注 |
|---|---|---|---|
| B端（权威） | 不设上限（接入方自控） | 6 次/分钟/`guest.tag` | 最终闸门，超限回 `RATE_LIMITED` |
| 参考中继 | 20 次/分钟/客户端 + 60 次/分钟/IP | 12 次/分钟/客户端 + 30 次/分钟/IP | 见 `relay/config.js` |

- 计数维度优先用「用户/桌号」而不是 IP，避免同一 NAT 下互相误伤；IP 只做兜底。
- 接入方预算应低于 B端 上限，给重试留余量。
- 限流按场所隔离更合理（不同场所互不影响），参考实现目前是单场所全局计数。

### 11.5 状态同步与进度插值

- 先读 retained `queue`，再订阅 `events`；`seq` 跳跃直接重读 retained 快照，不等待补发。
- 页面轮询参考中继的 `GET /api/state`（参考实现 2s）即可；只有大屏/高频场景才直接用 MQTT 订阅。
  轮询必须防重入：上一次未返回不发起下一次。
- 进度插值：`positionMs + rate × (本地当前时刻 − 锚点本地时刻)`。锚点取**收到快照的本地时刻**，
  不要用本地时钟直接减 B端 的 `sampledAtMs`（两端时钟可能有秒级偏差）。
- 播放/暂停只看 `rate`；不要用「位置不再变化」推断暂停。
- 歌词渲染位置 = 插值位置 − `audioLatencyMs`。
- 页面不可见时降频到 10–30s 或暂停轮询；恢复可见立即拉一次。

### 11.6 顺序与并发

- `enqueue` 应答顺序不保证与发送顺序一致；排队位置以应答 `queuePosition` 与 `queue` 快照为准，
  不要用本地提交顺序推算。
- 检索与状态轮询可以并行；同一用户的连续点歌应串行提交，等上一单有结果再发下一单。
- 队列满（200）时 B端 拒绝新入队，不自动扩队；接入方应在 UI 上提示而不是无限重试。
