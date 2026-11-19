/* 局域网歌词页的隐藏设置面板。
   由 lyric_http 注入到页面末尾，投放页（file://）不加载这份脚本。

   设置存在浏览器本地（localStorage）：OBS 的每个浏览器源、每台手机各自有
   独立的存储，所以同一个地址在不同屏上可以有不同样式。?p=名字 给存储再
   分一层命名空间，同一浏览器里调试多块屏时用。

   打开方式：双击页面任意空白处，或访问 ?panel=1。
   覆盖项在每次轮询 apply 时合并进服务端样式，改完立即生效。 */
(function () {
  'use strict';

  var qs = new URLSearchParams(location.search);
  var profile = (qs.get('p') || '').replace(/[^A-Za-z0-9_-]/g, '');
  var storeKey = 'enode.share.style' + (profile ? '.' + profile : '');

  var ov = {};
  try { ov = JSON.parse(localStorage.getItem(storeKey) || '') || {}; } catch (e) { ov = {}; }
  if (typeof ov !== 'object' || Array.isArray(ov) || !ov) ov = {};

  function persist() {
    try {
      if (Object.keys(ov).length) localStorage.setItem(storeKey, JSON.stringify(ov));
      else localStorage.removeItem(storeKey);
    } catch (e) {}
  }

  function clamp(v, lo, hi) { v = Number(v); return isFinite(v) ? Math.max(lo, Math.min(hi, v)) : lo; }
  function str(v) { return v == null ? '' : String(v); }

  // #rrggbb → ARGB 整数：payload 里的颜色都是 Dart 的 AARRGGBB，直接给字符串会渲染失败。
  function hexArgb(h) {
    var m = /^#?([0-9a-fA-F]{6})$/.exec(str(h).trim());
    return m ? ((0xFF000000 | parseInt(m[1], 16)) >>> 0) : null;
  }

  // 把本地覆盖合并进服务端样式；只在副本上改，payload 本身不动。
  function mergedStyle(base) {
    var s = {};
    for (var k in base) s[k] = base[k];
    var names = ['textWidth', 'textHeight', 'lineGap', 'otherOpacity', 'strokeWidth', 'vertical'];
    for (var i = 0; i < names.length; i++) {
      if (ov[names[i]] != null) {
        var v = Number(ov[names[i]]);
        if (isFinite(v)) s[names[i]] = v;
      }
    }
    if (ov.lines != null) s.lines = Math.round(clamp(ov.lines, 1, 6));
    if (ov.align) s.align = ov.align;
    if (ov.shadow != null) s.shadow = !!ov.shadow;
    if (ov.currentColor) { var c1 = hexArgb(ov.currentColor); if (c1 != null) s.currentColor = c1; }
    if (ov.otherColor) { var c2 = hexArgb(ov.otherColor); if (c2 != null) s.otherColor = c2; }
    if (ov.fontSizeScale != null) s.fontSize = (base.fontSize || 88) * clamp(ov.fontSizeScale, 0.3, 3);
    return s;
  }

  // 包一层 apply：轮询每次都全量 apply，覆盖必须在这一步打上去才不会被冲掉。
  // lastData 存合并**前**的原始 payload：重放时重新合并，fontSizeScale 这类
  // 相对值才不会被叠加两次，改设置也能立刻生效，不用等下一轮轮询。
  var origApply = null;
  var lastData = null;
  function wrapApply() {
    if (!window.enode || !window.enode.apply || window.enode.__sharePatched) return;
    origApply = window.enode.apply;
    window.enode.__sharePatched = true;
    window.enode.apply = function (data) {
      if (data) lastData = data;
      if (data && data.style) data.style = mergedStyle(data.style);
      return origApply.call(window.enode, data);
    };
  }
  wrapApply();
  setInterval(wrapApply, 500);

  function replay() {
    if (!lastData || !origApply) return;
    var copy = Object.assign({}, lastData);
    if (copy.style) copy.style = mergedStyle(copy.style);
    origApply.call(window.enode, copy);
  }

  // ---------------------------------------------------------------- 面板 UI

  var DEFAULTS = {
    lines: 2,
    fontSizeScale: 1,
    textWidth: 100,
    textHeight: 100,
    lineGap: 0,
    currentColor: '#3DDC84',
    otherColor: '#8B979F',
    otherOpacity: 100,
    strokeWidth: 3,
    shadow: true,
    align: 'center',
    vertical: 50
  };

  // 字号存倍率（fontSizeScale），滑条按百分比展示；其余与 payload 的样式字段同名。
  var SECTIONS = [
    {
      title: '排版',
      fields: [
        { k: 'lines', label: '行数', type: 'select', opts: [1, 2, 3, 4] },
        { k: 'fontSizeScale', label: '字号', type: 'range', min: 30, max: 300, step: 5, unit: '%', mul: 100 },
        { k: 'textWidth', label: '字宽', type: 'range', min: 40, max: 200, step: 5, unit: '%' },
        { k: 'textHeight', label: '字高', type: 'range', min: 40, max: 200, step: 5, unit: '%' },
        { k: 'lineGap', label: '行距', type: 'range', min: 0, max: 120, step: 2 },
        { k: 'align', label: '对齐', type: 'select', opts: ['left', 'center', 'right'],
          names: { left: '左对齐', center: '居中', right: '右对齐' } },
        { k: 'vertical', label: '垂直位置', type: 'range', min: 0, max: 100, step: 1, unit: '%' }
      ]
    },
    {
      title: '颜色',
      fields: [
        { k: 'currentColor', label: '当前句', type: 'color' },
        { k: 'otherColor', label: '其他行', type: 'color' },
        { k: 'otherOpacity', label: '其他行透明度', type: 'range', min: 0, max: 100, step: 5, unit: '%' }
      ]
    },
    {
      title: '效果',
      fields: [
        { k: 'strokeWidth', label: '描边', type: 'range', min: 0, max: 12, step: 0.5, unit: 'px' },
        { k: 'shadow', label: '阴影', type: 'check' }
      ]
    }
  ];

  var CSS = [
    '#enode-share-panel{position:fixed;top:16px;right:16px;width:328px;max-height:calc(100vh - 32px);',
    'overflow:auto;color:#e8edf2;background:rgba(17,22,29,.92);',
    '-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);',
    "font:13px/1.5 'Segoe UI','Microsoft YaHei',system-ui,sans-serif;",
    'border:1px solid rgba(255,255,255,.09);border-radius:14px;box-shadow:0 12px 40px rgba(0,0,0,.5);',
    'z-index:2147483647;user-select:none;scrollbar-width:thin;scrollbar-color:#39434f transparent;}',
    '#enode-share-panel::-webkit-scrollbar{width:6px}',
    '#enode-share-panel::-webkit-scrollbar-thumb{background:#39434f;border-radius:3px}',
    '#enode-share-panel .hd{display:flex;align-items:center;gap:8px;padding:13px 16px 11px;',
    'border-bottom:1px solid rgba(255,255,255,.07);position:sticky;top:0;',
    'background:rgba(17,22,29,.96);z-index:1;}',
    '#enode-share-panel .hd .dot{width:7px;height:7px;border-radius:50%;background:#3ddc84;',
    'box-shadow:0 0 8px rgba(61,220,132,.8);flex:none;}',
    '#enode-share-panel .hd .tt{font-size:14px;font-weight:600;letter-spacing:.02em;}',
    '#enode-share-panel .hd .pf{font-size:11px;color:#8fa0ae;background:rgba(255,255,255,.07);',
    'border-radius:5px;padding:1px 6px;}',
    '#enode-share-panel .hd .x{margin-left:auto;background:none;border:0;color:#7d8894;',
    'font-size:18px;line-height:1;cursor:pointer;padding:2px 6px;border-radius:6px;transition:.15s;}',
    '#enode-share-panel .hd .x:hover{color:#fff;background:rgba(255,255,255,.1)}',
    '#enode-share-panel .bd{padding:6px 16px 14px;}',
    '#enode-share-panel .sc{font-size:11px;font-weight:600;color:#7d8894;letter-spacing:.12em;',
    'margin:13px 0 4px;text-transform:uppercase;}',
    '#enode-share-panel .rw{display:flex;align-items:center;gap:10px;margin:7px 0;}',
    '#enode-share-panel .lb{flex:0 0 84px;color:#c3ccd5;}',
    '#enode-share-panel .vl{flex:0 0 52px;text-align:right;color:#8fa0ae;font-size:12px;',
    'font-variant-numeric:tabular-nums;}',
    '#enode-share-panel input[type=range]{flex:1;min-width:0;-webkit-appearance:none;appearance:none;',
    'height:4px;border-radius:2px;background:linear-gradient(90deg,#3ddc84 var(--f,0%),#39434f var(--f,0%));',
    'outline:none;cursor:pointer;}',
    '#enode-share-panel input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;appearance:none;',
    'width:15px;height:15px;border-radius:50%;background:#fff;border:2px solid #3ddc84;',
    'box-shadow:0 1px 4px rgba(0,0,0,.5);transition:transform .12s;}',
    '#enode-share-panel input[type=range]::-webkit-slider-thumb:hover{transform:scale(1.18)}',
    '#enode-share-panel input[type=range]::-moz-range-thumb{width:13px;height:13px;border-radius:50%;',
    'background:#fff;border:2px solid #3ddc84;}',
    '#enode-share-panel input[type=color]{width:40px;height:24px;padding:0;border:1px solid rgba(255,255,255,.18);',
    'border-radius:6px;background:none;cursor:pointer;flex:none;}',
    '#enode-share-panel input[type=color]::-webkit-color-swatch-wrapper{padding:2px}',
    '#enode-share-panel input[type=color]::-webkit-color-swatch{border:none;border-radius:4px}',
    '#enode-share-panel .hex{font-size:11px;color:#8fa0ae;width:60px;}',
    '#enode-share-panel select{flex:1;background:#232b34;color:inherit;border:1px solid rgba(255,255,255,.12);',
    'border-radius:7px;padding:4px 8px;cursor:pointer;outline:none;}',
    '#enode-share-panel select:hover{border-color:rgba(255,255,255,.25)}',
    '#enode-share-panel .sw{position:relative;width:36px;height:20px;flex:none;cursor:pointer;}',
    '#enode-share-panel .sw input{position:absolute;opacity:0;inset:0;margin:0;cursor:pointer;}',
    '#enode-share-panel .sw .tr{position:absolute;inset:0;border-radius:10px;background:#39434f;transition:.18s;}',
    '#enode-share-panel .sw .tr:before{content:"";position:absolute;left:2px;top:2px;width:16px;height:16px;',
    'border-radius:50%;background:#aab4be;transition:.18s;}',
    '#enode-share-panel .sw input:checked + .tr{background:rgba(61,220,132,.32)}',
    '#enode-share-panel .sw input:checked + .tr:before{transform:translateX(16px);background:#3ddc84;}',
    '#enode-share-panel .btns{display:flex;gap:8px;margin-top:14px;padding-top:12px;',
    'border-top:1px solid rgba(255,255,255,.07);}',
    '#enode-share-panel .bt{flex:1;background:rgba(255,255,255,.06);color:#d5dbe1;border:0;',
    'border-radius:8px;padding:7px 0;cursor:pointer;font-size:12.5px;transition:.15s;}',
    '#enode-share-panel .bt:hover{background:rgba(255,80,80,.14);color:#ff8f8f;}',
    '#enode-share-panel .ft{margin-top:9px;font-size:11px;color:#5d6873;text-align:center;}'
  ].join('');

  var panel = null;
  var refreshers = [];

  function set(k, v) {
    ov[k] = v;
    persist();
    replay();
  }

  function val(f) {
    return ov[f.k] != null ? ov[f.k] : DEFAULTS[f.k];
  }

  function display(f, v) {
    if (f.mul) v = v * f.mul;
    return (f.unit ? v + f.unit : v);
  }

  function paintRange(ctl) {
    var min = Number(ctl.min), max = Number(ctl.max);
    var f = (Number(ctl.value) - min) / Math.max(1e-6, max - min);
    ctl.style.setProperty('--f', (Math.round(f * 1000) / 10) + '%');
  }

  // 颜色控件旁边显示 hex；滑条左段亮色填充（原生 range 在 WebKit 里没有进度色）。
  function buildField(f) {
    var rw = document.createElement('div');
    rw.className = 'rw';
    rw.appendChild(Object.assign(document.createElement('span'),
      { className: 'lb', textContent: f.label }));
    if (f.type === 'select') {
      var sel = document.createElement('select');
      for (var j = 0; j < f.opts.length; j++) {
        var o = document.createElement('option');
        o.value = f.opts[j];
        o.textContent = f.names ? f.names[f.opts[j]] : String(f.opts[j]);
        sel.appendChild(o);
      }
      sel.value = String(val(f));
      sel.addEventListener('change', function (f, sel) {
        return function () { set(f.k, f.k === 'lines' ? Number(sel.value) : sel.value); };
      }(f, sel));
      rw.appendChild(sel);
      refreshers.push(function (f, sel) {
        return function () { sel.value = String(val(f)); };
      }(f, sel));
    } else if (f.type === 'check') {
      var sw = document.createElement('label');
      sw.className = 'sw';
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = !!val(f);
      var tr = document.createElement('span');
      tr.className = 'tr';
      sw.appendChild(cb);
      sw.appendChild(tr);
      sw.appendChild(Object.assign(document.createElement('span'),
        { className: 'hex', textContent: cb.checked ? '开' : '关' }));
      cb.addEventListener('change', function (f, cb, hx) {
        return function () { hx.textContent = cb.checked ? '开' : '关'; set(f.k, cb.checked); };
      }(f, cb, sw.lastChild));
      rw.appendChild(sw);
      refreshers.push(function (f, cb, hx) {
        return function () {
          cb.checked = !!val(f);
          hx.textContent = cb.checked ? '开' : '关';
        };
      }(f, cb, sw.lastChild));
    } else if (f.type === 'color') {
      var ctl = document.createElement('input');
      ctl.type = 'color';
      ctl.value = val(f);
      var hx = document.createElement('span');
      hx.className = 'hex';
      hx.textContent = String(val(f)).toUpperCase();
      ctl.addEventListener('input', function (f, ctl, hx) {
        return function () { hx.textContent = ctl.value.toUpperCase(); set(f.k, ctl.value); };
      }(f, ctl, hx));
      rw.appendChild(ctl);
      rw.appendChild(hx);
      refreshers.push(function (f, ctl, hx) {
        return function () {
          ctl.value = val(f);
          hx.textContent = String(val(f)).toUpperCase();
        };
      }(f, ctl, hx));
    } else {
      var rg = document.createElement('input');
      rg.type = 'range';
      rg.min = f.min;
      rg.max = f.max;
      rg.step = f.step;
      var cur = val(f);
      rg.value = f.mul ? cur * f.mul : cur;
      var vl = document.createElement('span');
      vl.className = 'vl';
      vl.textContent = display(f, cur);
      paintRange(rg);
      rg.addEventListener('input', function (f, rg, vl) {
        return function () {
          paintRange(rg);
          var v = f.mul ? Number(rg.value) / f.mul : Number(rg.value);
          set(f.k, v);
          vl.textContent = display(f, v);
        };
      }(f, rg, vl));
      rw.appendChild(rg);
      rw.appendChild(vl);
      refreshers.push(function (f, rg, vl) {
        return function () {
          var cur = val(f);
          rg.value = f.mul ? cur * f.mul : cur;
          paintRange(rg);
          vl.textContent = display(f, cur);
        };
      }(f, rg, vl));
    }
    return rw;
  }

  function build() {
    if (panel) return;
    var style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);

    panel = document.createElement('div');
    panel.id = 'enode-share-panel';

    var hd = document.createElement('div');
    hd.className = 'hd';
    hd.appendChild(Object.assign(document.createElement('span'), { className: 'dot' }));
    hd.appendChild(Object.assign(document.createElement('span'),
      { className: 'tt', textContent: '歌词页设置' }));
    if (profile) {
      hd.appendChild(Object.assign(document.createElement('span'),
        { className: 'pf', textContent: profile }));
    }
    var close = document.createElement('button');
    close.className = 'x';
    close.type = 'button';
    close.title = '关闭';
    close.textContent = '×';
    close.addEventListener('click', function () { toggle(false); });
    hd.appendChild(close);
    panel.appendChild(hd);

    var bd = document.createElement('div');
    bd.className = 'bd';
    for (var s = 0; s < SECTIONS.length; s++) {
      bd.appendChild(Object.assign(document.createElement('div'),
        { className: 'sc', textContent: SECTIONS[s].title }));
      for (var i = 0; i < SECTIONS[s].fields.length; i++) {
        bd.appendChild(buildField(SECTIONS[s].fields[i]));
      }
    }

    var btns = document.createElement('div');
    btns.className = 'btns';
    var reset = document.createElement('button');
    reset.className = 'bt';
    reset.type = 'button';
    reset.textContent = '恢复跟随应用设置';
    reset.addEventListener('click', function () {
      ov = {};
      persist();
      for (var i = 0; i < refreshers.length; i++) refreshers[i]();
      replay();
    });
    btns.appendChild(reset);
    bd.appendChild(btns);
    bd.appendChild(Object.assign(document.createElement('div'),
      { className: 'ft', textContent: '双击页面空白处可开关此面板' }));
    panel.appendChild(bd);

    document.body.appendChild(panel);
  }

  function toggle(show) {
    if (show === undefined) show = !panel || panel.style.display === 'none';
    if (show) {
      build();
      for (var i = 0; i < refreshers.length; i++) refreshers[i]();
      panel.style.display = 'block';
    } else if (panel) {
      panel.style.display = 'none';
    }
  }

  // 双击空白处唤出；面板内的双击不响应，避免拖滑条时误关。
  document.addEventListener('dblclick', function (e) {
    if (e.target && e.target.closest && e.target.closest('#enode-share-panel')) return;
    toggle();
  });
  if (qs.get('panel') != null) toggle(true);
})();
