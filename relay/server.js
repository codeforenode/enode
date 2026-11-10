'use strict';

const http = require('node:http');
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const mqtt = require('mqtt');

const cfg = require('./config');

const cfgError = cfg.validate();
if (cfgError) {
  console.error(`[relay] ${cfgError}；请通过环境变量提供 MQTT 参数（见 README）`);
  process.exit(1);
}

const PREFIX = cfg.mqtt.topicPrefix;
const PUBLIC_ROOT = path.join(__dirname, '..', 'guest');
const NODE_ID = '[A-Za-z0-9_-]{1,64}';

const healthRe = new RegExp(`^${escapeRe(PREFIX)}/(${NODE_ID})/health$`);
const queueRe = new RegExp(`^${escapeRe(PREFIX)}/(${NODE_ID})/queue$`);
const eventsRe = new RegExp(`^${escapeRe(PREFIX)}/(${NODE_ID})/events$`);
const respRe = new RegExp(`^${escapeRe(PREFIX)}/(${NODE_ID})/rpc/(search|enqueue)\\.resp/([A-Za-z0-9_-]{1,64})$`);

const NODE_FRESH_MS = 35000;
const NODE_TTL_MS = 10 * 60 * 1000;

/** @type {Map<string, {id: string, health: any, healthAt: number, snapshot: any, snapshotAt: number, anchor: any}>} */
const nodes = new Map();
/** @type {Map<string, {resolve: Function, reject: Function, timer: NodeJS.Timeout, node: string}>} */
const pending = new Map();
/** @type {Map<string, number[]>} */
const rateHits = new Map();

let client = null;
let mqttConnected = false;

const STATIC_FILES = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/index.html', ['index.html', 'text/html; charset=utf-8']],
  ['/app.js', ['app.js', 'text/javascript; charset=utf-8']],
  ['/style.css', ['style.css', 'text/css; charset=utf-8']],
]);

const ERROR_STATUS = {
  BAD_REQUEST: 400,
  RATE_LIMITED: 429,
  QUEUE_FULL: 409,
  TRACK_NOT_FOUND: 404,
  SOURCE_UNAVAILABLE: 422,
  STALE_REQUEST: 409,
  INTERNAL: 502,
};

// ---------------- MQTT ----------------

function escapeRe(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function connectMqtt() {
  const c = mqtt.connect({
    host: cfg.mqtt.host,
    port: cfg.mqtt.port,
    protocol: cfg.mqtt.tls ? 'mqtts' : 'mqtt',
    username: cfg.mqtt.username || undefined,
    password: cfg.mqtt.password || undefined,
    clientId: `kjrelay-${crypto.randomBytes(4).toString('hex')}`,
    keepalive: 30,
    clean: true,
    reconnectPeriod: 3000,
    connectTimeout: 8000,
  });
  client = c;

  c.on('connect', () => {
    mqttConnected = true;
    console.log('[relay] MQTT connected');
    c.subscribe(
      [
        `${PREFIX}/+/health`,
        `${PREFIX}/+/queue`,
        `${PREFIX}/+/events`,
        `${PREFIX}/+/rpc/search.resp/+`,
        `${PREFIX}/+/rpc/enqueue.resp/+`,
      ],
      { qos: 1 },
      (err) => {
        if (err) console.warn('[relay] subscribe failed:', err.message);
      },
    );
  });

  c.on('reconnect', () => console.log('[relay] MQTT reconnecting'));
  c.on('close', () => {
    mqttConnected = false;
  });
  c.on('error', (err) => console.warn('[relay] MQTT error:', err.message));
  c.on('message', onMqttMessage);
}

function onMqttMessage(topic, payload) {
  const text = payload.toString('utf8');
  const resp = topic.match(respRe);
  if (resp) {
    settleRpc(resp[1], resp[3], text);
    return;
  }

  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return;
  }
  if (!body || typeof body !== 'object') return;

  let m = topic.match(healthRe);
  if (m) {
    const n = getNode(m[1]);
    n.health = body;
    n.healthAt = Date.now();
    return;
  }

  m = topic.match(queueRe);
  if (m) {
    const n = getNode(m[1]);
    n.snapshot = body;
    n.snapshotAt = Date.now();
    const p = body.player;
    if (p && typeof p.positionMs === 'number') {
      updateAnchor(n, p.positionMs, p.rate, p.sampledAtMs);
    }
    return;
  }

  m = topic.match(eventsRe);
  if (m && body.type === 'player.tick' && body.data) {
    const n = getNode(m[1]);
    updateAnchor(n, body.data.positionMs, body.data.rate, body.data.sampledAtMs);
  }
}

function getNode(id) {
  let n = nodes.get(id);
  if (!n) {
    n = { id, health: null, healthAt: 0, snapshot: null, snapshotAt: 0, anchor: null };
    nodes.set(id, n);
  }
  return n;
}

/**
 * 位置插值锚点用「中继收到的时刻」而不是 B端 的采样时钟，
 * 这样 PC 与平板的时钟偏差不会影响 H5 显示的进度。
 */
function updateAnchor(n, positionMs, rate, bSampledAt) {
  if (typeof positionMs !== 'number' || !Number.isFinite(positionMs)) return;
  const r = rate === 1 ? 1 : 0;
  const bTs = typeof bSampledAt === 'number' ? bSampledAt : 0;
  if (n.anchor && bTs > 0 && bTs < n.anchor.bTs) return;
  n.anchor = { positionMs: Math.max(0, positionMs), rate: r, atMs: Date.now(), bTs };
}

function estimatePosition(n, now) {
  const a = n.anchor;
  if (!a) return 0;
  const pos = a.positionMs + (a.rate ? Math.max(0, now - a.atMs) : 0);
  const dur = n.snapshot && n.snapshot.player ? n.snapshot.player.durationMs : 0;
  return dur > 0 ? Math.min(pos, dur) : pos;
}

function selectNode(now = Date.now()) {
  let best = null;
  for (const n of nodes.values()) {
    if (!n.health || n.health.state !== 'online') continue;
    if (now - n.healthAt > NODE_FRESH_MS) continue;
    if (!best || n.healthAt > best.healthAt) best = n;
  }
  return best;
}

function settleRpc(nodeId, nonce, text) {
  const p = pending.get(nonce);
  if (!p || p.node !== nodeId) return;
  pending.delete(nonce);
  clearTimeout(p.timer);
  let env;
  try {
    env = JSON.parse(text);
  } catch {
    p.reject(httpError(502, 'BAD_RESPONSE', '节点应答无法解析'));
    return;
  }
  const payload = env && typeof env.payload === 'object' && env.payload ? env.payload : {};
  p.resolve(payload);
}

function rpc(node, kind, payload) {
  return new Promise((resolve, reject) => {
    const c = client;
    if (!c || !mqttConnected) return reject(httpError(503, 'RELAY_OFFLINE', '中继未连接'));
    const nonce = crypto.randomBytes(8).toString('hex');
    const timer = setTimeout(() => {
      pending.delete(nonce);
      reject(httpError(504, 'TIMEOUT', '节点响应超时'));
    }, cfg.rpcTimeoutMs);
    pending.set(nonce, { resolve, reject, timer, node: node.id });
    const envelope = {
      v: 1,
      type: `${kind}.req`,
      node: node.id,
      ts: Date.now(),
      nonce,
      payload,
    };
    c.publish(`${PREFIX}/${node.id}/rpc/${kind}.req`, JSON.stringify(envelope), { qos: 1 }, (err) => {
      if (!err) return;
      clearTimeout(timer);
      pending.delete(nonce);
      reject(httpError(502, 'PUBLISH_FAILED', '请求发送失败'));
    });
  });
}

// ---------------- HTTP API ----------------

function apiState() {
  const now = Date.now();
  const base = {
    serverTime: now,
    relay: mqttConnected ? 'online' : 'offline',
  };
  const node = selectNode(now);
  if (!node) {
    return { ...base, online: false, node: null, playing: false, player: null, queue: [], queueDepth: 0, updatedAt: 0 };
  }
  const snap = node.snapshot || {};
  const hasSnapshot = node.snapshotAt > 0;
  const queue = Array.isArray(snap.queue) ? snap.queue : [];
  const player = snap.player;
  const rate = player ? (node.anchor ? node.anchor.rate : player.rate === 1 ? 1 : 0) : 0;
  // health 10 秒才刷新一次，播放状态以 retained queue 快照为准。
  const depth = hasSnapshot
    ? queue.length + (player ? 1 : 0)
    : node.health && typeof node.health.queueDepth === 'number'
      ? node.health.queueDepth
      : 0;
  return {
    ...base,
    online: true,
    node: node.id,
    playing: Boolean(player) && rate === 1,
    player: player
      ? {
          ...player,
          positionMs: Math.round(estimatePosition(node, now)),
          rate,
        }
      : null,
    queue,
    queueDepth: depth,
    updatedAt: Math.max(node.snapshotAt, node.healthAt),
  };
}

async function apiSearch(url, req) {
  const q = (url.searchParams.get('q') || '').trim();
  if (!q || [...q].length > 64) throw httpError(400, 'BAD_REQUEST', '搜索词需为 1–64 字');
  const rawLimit = Number(url.searchParams.get('limit') || 20);
  const limit = Number.isFinite(rawLimit) ? Math.min(50, Math.max(1, Math.trunc(rawLimit))) : 20;
  const who = requesterKey(req, url.searchParams.get('cid'));
  const ip = req.socket.remoteAddress || 'unknown';
  if (
    !allowRate('sip:' + ip, cfg.limits.searchPerMinutePerIp) ||
    !allowRate('s:' + who, cfg.limits.searchPerMinute)
  ) {
    throw httpError(429, 'RATE_LIMITED', '搜索太频繁，稍后再试');
  }
  const node = requireNode();
  // 节点自己声明没有检索能力（未导入音源脚本）时别把请求打过去。
  // caps 缺失视为旧版本节点，按能力齐全处理。
  const caps = node.health && node.health.caps;
  if (Array.isArray(caps) && !caps.includes('search')) {
    throw httpError(503, 'SEARCH_DISABLED', '本店暂未开通在线点歌');
  }
  const payload = await rpc(node, 'search', { q, offset: 0, limit });
  if (!payload.ok) throw fromPayload(payload);
  return {
    node: node.id,
    total: typeof payload.total === 'number' ? payload.total : 0,
    items: Array.isArray(payload.items) ? payload.items : [],
  };
}

async function apiEnqueue(req, body) {
  const trackKey = typeof body.trackKey === 'string' ? body.trackKey.trim() : '';
  if (!trackKey || trackKey.length > 128) throw httpError(400, 'BAD_REQUEST', '曲目参数非法');
  const seat = typeof body.seat === 'string' ? body.seat.trim().slice(0, 16) : '';
  const who = requesterKey(req, typeof body.clientId === 'string' ? body.clientId : '');
  const ip = req.socket.remoteAddress || 'unknown';
  if (
    !allowRate('eip:' + ip, cfg.limits.enqueuePerMinutePerIp) ||
    !allowRate('e:' + who, cfg.limits.enqueuePerMinute)
  ) {
    throw httpError(429, 'RATE_LIMITED', '点歌太频繁，稍后再试');
  }
  const node = requireNode();
  const requestId = `g-${crypto.randomBytes(6).toString('hex')}`;
  const guest = {};
  if (seat) guest.seat = seat;
  guest.tag = who;
  const payload = await rpc(node, 'enqueue', { trackKey, requestId, guest });
  if (!payload.ok) throw fromPayload(payload);
  return {
    node: node.id,
    accepted: true,
    queuePosition: typeof payload.queuePosition === 'number' ? payload.queuePosition : null,
    requestId,
  };
}

function requireNode() {
  const node = selectNode();
  if (!node) throw httpError(503, 'NODE_OFFLINE', '点歌机不在线');
  return node;
}

function fromPayload(payload) {
  // B端 拒绝入队时给的是 reason，协议错误信封给的是 error。
  const code = pickCode(payload) || 'INTERNAL';
  const message = typeof payload.message === 'string' ? payload.message : undefined;
  return httpError(ERROR_STATUS[code] || 502, code, message);
}

function pickCode(payload) {
  for (const key of ['error', 'reason']) {
    const value = payload[key];
    if (typeof value === 'string' && value) return value;
  }
  return null;
}

function requesterKey(req, rawClientId) {
  const cid = String(rawClientId || '').trim();
  if (/^[A-Za-z0-9_-]{8,64}$/.test(cid)) return cid;
  return `ip:${req.socket.remoteAddress || 'unknown'}`;
}

function allowRate(key, perMinute) {
  const now = Date.now();
  const kept = (rateHits.get(key) || []).filter((t) => now - t < 60000);
  if (kept.length >= perMinute) {
    rateHits.set(key, kept);
    return false;
  }
  kept.push(now);
  rateHits.set(key, kept);
  return true;
}

// ---------------- HTTP 服务 ----------------

function httpError(status, code, message) {
  const err = new Error(message || code);
  err.status = status;
  err.code = code;
  err.publicMessage = message;
  return err;
}

function sendJson(res, status, body) {
  const data = Buffer.from(JSON.stringify(body));
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': data.length,
    'Cache-Control': 'no-store',
  });
  res.end(data);
}

function sendText(res, status, text) {
  const data = Buffer.from(text);
  res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8', 'Content-Length': data.length });
  res.end(data);
}

function readJson(req, limit = 4096) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(httpError(413, 'PAYLOAD_TOO_LARGE', '请求体过大'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try {
        const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        resolve(body && typeof body === 'object' ? body : {});
      } catch {
        reject(httpError(400, 'BAD_JSON', '请求体不是 JSON'));
      }
    });
    req.on('error', reject);
  });
}

async function serveStatic(pathname, req, res) {
  if (pathname === '/favicon.ico') {
    res.writeHead(204);
    return res.end();
  }
  const entry = STATIC_FILES.get(pathname);
  if (!entry) return sendText(res, 404, 'not found');
  let data;
  try {
    data = await fs.readFile(path.join(PUBLIC_ROOT, entry[0]));
  } catch {
    return sendText(res, 404, 'not found');
  }
  res.writeHead(200, {
    'Content-Type': entry[1],
    'Content-Length': data.length,
    'Cache-Control': 'no-cache',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'",
  });
  res.end(req.method === 'HEAD' ? undefined : data);
}

async function handle(req, res) {
  const url = new URL(req.url || '/', 'http://relay');
  const { pathname } = url;

  if (pathname.startsWith('/api/')) {
    try {
      if (pathname === '/api/state' && req.method === 'GET') {
        return sendJson(res, 200, apiState());
      }
      if (pathname === '/api/search' && req.method === 'GET') {
        return sendJson(res, 200, await apiSearch(url, req));
      }
      if (pathname === '/api/enqueue' && req.method === 'POST') {
        const body = await readJson(req);
        return sendJson(res, 200, await apiEnqueue(req, body));
      }
      return sendJson(res, 404, { error: 'NOT_FOUND', message: '接口不存在' });
    } catch (err) {
      const status = err.status || 500;
      if (status >= 500) console.warn('[relay] api error', pathname, err.code || '', err.message);
      return sendJson(res, status, {
        error: err.code || 'INTERNAL',
        message: err.publicMessage || '服务异常',
      });
    }
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return sendJson(res, 405, { error: 'METHOD_NOT_ALLOWED' });
  }
  return serveStatic(pathname, req, res);
}

// ---------------- 启动 ----------------

connectMqtt();

setInterval(() => {
  const now = Date.now();
  for (const [id, n] of nodes) {
    if (now - Math.max(n.healthAt, n.snapshotAt, n.anchor ? n.anchor.atMs : 0) > NODE_TTL_MS) {
      nodes.delete(id);
    }
  }
  for (const [key, hits] of rateHits) {
    const kept = hits.filter((t) => now - t < 60000);
    if (kept.length) rateHits.set(key, kept);
    else rateHits.delete(key);
  }
}, 60000).unref();

const server = http.createServer((req, res) => {
  handle(req, res).catch((err) => {
    console.warn('[relay] unhandled:', err.message);
    if (!res.headersSent) sendText(res, 500, 'internal error');
    else res.end();
  });
});

server.listen(cfg.http.port, cfg.http.host, () => {
  console.log(`[relay] listening on http://${cfg.http.host}:${cfg.http.port}`);
  console.log(`[relay] MQTT ${cfg.mqtt.host}:${cfg.mqtt.port} (${cfg.mqtt.tls ? 'tls' : 'plain'})`);
});

function shutdown() {
  console.log('[relay] shutting down');
  try {
    if (client) client.end(true);
  } catch {}
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1500).unref();
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
