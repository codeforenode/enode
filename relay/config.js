'use strict';

// 开源发布版不内置任何 broker 凭据：MQTT 参数从环境变量读取。
// 日志不得打印凭据值。
const mqtt = {
  host: (process.env.MQTT_HOST || '').trim(),
  port: Number(process.env.MQTT_PORT || 1883),
  tls: /^(1|true|yes|tls|ssl)$/i.test(process.env.MQTT_TLS || ''),
  username: process.env.MQTT_USERNAME || '',
  password: process.env.MQTT_PASSWORD || '',
  topicPrefix: (process.env.MQTT_TOPIC_PREFIX || 'node').trim(),
};

module.exports = {
  mqtt,
  node: {
    // 本中继服务的权威节点（可选）。填了 nodeId（形如 nd-xxxx）就只认它，它离线时直接报错、
    // 不回退到别的节点；留空则由中继自动固定第一台在线节点，选定后不再变。单节点部署通常不用设。
    target: (process.env.TARGET_NODE || '').trim(),
  },
  http: {
    host: '0.0.0.0',
    port: Number(process.env.PORT || 8080),
  },
  limits: {
    // 每个客户端（浏览器）每分钟；桌客各自独立。
    searchPerMinute: 20,
    enqueuePerMinute: 12,
    // 歌单只在进页面时拉一次，限得比检索宽；「换一批」在本地切，不再请求。
    featuredPerMinutePerIp: 30,
    // 每个来源 IP 每分钟，防止随意更换 clientId 绕过单机限额。
    searchPerMinutePerIp: 60,
    enqueuePerMinutePerIp: 30,
  },
  // B端 检索内部已限时 8s，这里留一点网络余量。
  rpcTimeoutMs: 9000,

  /** 返回问题描述；null 表示参数齐全。只描述缺哪个变量，不回显值。 */
  validate() {
    if (!mqtt.host) return '未设置 MQTT_HOST（broker 地址）';
    if (!Number.isInteger(mqtt.port) || mqtt.port < 1 || mqtt.port > 65535) {
      return 'MQTT_PORT 需为 1–65535 的整数';
    }
    if (!mqtt.topicPrefix || /[#+\s]/.test(mqtt.topicPrefix)) {
      return 'MQTT_TOPIC_PREFIX 不能为空，且不能含 #、+ 或空格';
    }
    if (module.exports.node.target && !/^[A-Za-z0-9_-]{1,64}$/.test(module.exports.node.target)) {
      return 'TARGET_NODE 只能包含字母、数字、下划线和短横线（1–64 位）';
    }
    return null;
  },
};
