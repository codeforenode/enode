(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);

  const SOURCE_URL = 'https://github.com/codeforenode/enode';

  const state = {
    server: null,
    appliedAt: 0,
    seat: '',
    clientId: '',
    polling: false,
    featuredItems: [],
    featuredOffset: 0,
  };

  // 「已点」判定：本地刚点过的 + 队列里已有的，两者并集。
  const pickedKeys = new Set();
  const queueKeys = new Set();
  let lastQueueSig = '';
  let featuredLoading = false;
  let featuredDone = false;
  let featuredAttempts = 0;
  let featuredTimer = null;

  // ---------------- 工具 ----------------

  function randomHex(bytes) {
    const a = new Uint8Array(bytes);
    crypto.getRandomValues(a);
    return Array.from(a, (b) => b.toString(16).padStart(2, '0')).join('');
  }

  function fmt(ms) {
    const total = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
    const m = Math.floor(total / 60);
    const s = total % 60;
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  async function api(path, options = {}) {
    const res = await fetch(path, { cache: 'no-store', ...options });
    let data = null;
    try {
      data = await res.json();
    } catch {
      data = null;
    }
    if (!res.ok) {
      const err = new Error((data && data.message) || '请求失败');
      err.status = res.status;
      err.code = data && data.error;
      throw err;
    }
    return data || {};
  }

  function messageFor(err) {
    if (!err) return '请求失败';
    // 先按业务码出文案，避免 503/422 被通用状态文案覆盖掉有效提示。
    if (err.code === 'SEARCH_DISABLED') return err.message || '本店暂未开通在线点歌';
    if (err.code === 'SOURCE_UNAVAILABLE') return err.message || '这首歌本店暂时放不了，换一首试试';
    if (err.status === 503) return '点歌机不在线';
    if (err.status === 429) return err.message || '太频繁了，稍后再试';
    if (err.status === 404) return '这首歌已下架';
    if (err.status === 409 && err.code === 'QUEUE_FULL') return '队列已满，等会儿再点';
    return err.message || '请求失败';
  }

  let toastTimer = null;
  function toast(text, isError = false) {
    const box = $('toast');
    box.textContent = text;
    box.classList.toggle('error', isError);
    box.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => box.classList.add('hidden'), 2600);
  }

  function hint(text, isError = false) {
    const box = $('searchHint');
    box.textContent = text || '';
    box.classList.toggle('error', isError);
  }

  // ---------------- 桌号 ----------------

  let seatCallback = null;

  function setSeat(value) {
    state.seat = value;
    localStorage.setItem('kj.seat', value);
    updateSeatChip();
    if (state.server) renderQueue(state.server.queue || []);
  }

  function updateSeatChip() {
    const chip = $('seatChip');
    chip.textContent = state.seat || '选桌号';
    chip.classList.toggle('set', Boolean(state.seat));
  }

  function askSeat(callback) {
    seatCallback = callback || null;
    $('seatInput').value = state.seat;
    $('seatDialog').showModal();
    setTimeout(() => $('seatInput').focus(), 60);
  }

  function closeSeatDialog() {
    seatCallback = null;
    $('seatDialog').close();
  }

  // ---------------- 渲染 ----------------

  function renderProgress() {
    const s = state.server;
    const fill = $('progressFill');
    const posText = $('posText');
    const durText = $('durText');
    const p = s && s.player;
    if (!p) {
      fill.style.width = '0%';
      posText.textContent = '00:00';
      durText.textContent = '00:00';
      return;
    }
    const elapsed = p.rate === 1 ? Math.max(0, Date.now() - state.appliedAt) : 0;
    let pos = Number(p.positionMs) || 0;
    pos += elapsed;
    const dur = Number(p.durationMs) || 0;
    if (dur > 0) pos = Math.min(pos, dur);
    fill.style.width = dur > 0 ? `${Math.min(100, (pos / dur) * 100)}%` : '0%';
    posText.textContent = fmt(pos);
    durText.textContent = dur > 0 ? fmt(dur) : '--:--';
  }

  function renderNow(s) {
    const p = s.player;
    $('nowEmpty').classList.toggle('hidden', Boolean(p));
    $('nowBody').classList.toggle('hidden', !p);
    if (!p) return;
    $('nowTitle').textContent = p.title || '未知曲目';
    const bits = [];
    if (p.artist) bits.push(p.artist);
    if (p.guest && p.guest.seat) bits.push(`来自 ${p.guest.seat}`);
    if (!s.playing) bits.push('已暂停');
    $('nowArtist').textContent = bits.join(' · ');
  }

  function renderQueue(queue) {
    const list = $('queue');
    list.replaceChildren();
    $('queueCount').textContent = queue.length ? String(queue.length) : '';
    $('queueEmpty').classList.toggle('hidden', queue.length > 0);

    queueKeys.clear();
    for (const item of queue) {
      if (item && typeof item.trackKey === 'string') queueKeys.add(item.trackKey);
    }
    // 队列快照已经回来了，「已点」就交还给队列判断，播完后该行可以再点一次。
    for (const key of [...pickedKeys]) if (queueKeys.has(key)) pickedKeys.delete(key);

    queue.forEach((item, index) => {
      const li = document.createElement('li');
      if (state.seat && item.guest && item.guest.seat === state.seat) li.classList.add('mine');
      li.append(el('span', 'idx', String(index + 1)));
      const meta = el('div', 'row-meta');
      meta.append(el('div', 'row-title', item.title || '未知曲目'));
      const sub = [];
      if (item.artist) sub.push(item.artist);
      if (item.guest && item.guest.seat) sub.push(`${item.guest.seat} 桌`);
      meta.append(el('div', 'row-sub', sub.join(' · ')));
      li.append(meta);
      list.append(li);
    });

    // 只在队列集合真的变了才重绘歌单，避免每 2s 把用户正要点的按钮换掉。
    const sig = [...queueKeys].sort().join('|');
    if (sig !== lastQueueSig) {
      lastQueueSig = sig;
      if (state.featuredItems.length) renderFeatured();
    }
  }

  function applyState(s) {
    state.server = s;
    state.appliedAt = Date.now();
    const online = s.online === true;
    $('statusDot').className = `status-dot ${online ? 'online' : 'offline'}`;
    $('offline').classList.toggle('hidden', online);
    if (online) {
      const depth = Number(s.queueDepth) || 0;
      $('nodeLabel').textContent = depth > 0 ? `已连接 · 队列 ${depth} 首` : '已连接 · 待机';
    } else {
      $('nodeLabel').textContent = s.relay === 'offline' ? '中继未连接' : '点歌机离线';
    }
    renderNow(s);
    renderQueue(Array.isArray(s.queue) ? s.queue : []);
    renderProgress();
  }

  // ---------------- 数据 ----------------

  async function poll() {
    if (state.polling) return;
    state.polling = true;
    try {
      applyState(await api(`/api/state?cid=${encodeURIComponent(state.clientId)}`));
    } catch {
      $('statusDot').className = 'status-dot offline';
      $('offline').classList.remove('hidden');
      $('nodeLabel').textContent = '连接中继失败';
    } finally {
      state.polling = false;
    }
  }

  // ---------------- 出厂歌单 ----------------

  // 首屏一次给 8 条：一屏能扫完，又不至于把「等待队列」挤出视线。
  const FEATURED_PAGE = 8;

  function renderFeatured() {
    const card = $('featuredCard');
    const all = state.featuredItems;
    if (!all.length) {
      card.classList.add('hidden');
      return;
    }
    card.classList.remove('hidden');
    $('featuredMore').classList.toggle('hidden', all.length <= FEATURED_PAGE);

    const list = $('featuredList');
    list.replaceChildren();
    const size = Math.min(FEATURED_PAGE, all.length);
    const start = state.featuredOffset % all.length;
    for (let i = 0; i < size; i++) {
      const item = all[(start + i) % all.length];
      const li = document.createElement('li');
      const meta = el('div', 'row-meta');
      meta.append(el('div', 'row-title', item.title || '未知曲目'));
      const sub = [];
      if (item.artist) sub.push(item.artist);
      if (item.durationMs) sub.push(fmt(item.durationMs));
      meta.append(el('div', 'row-sub', sub.join(' · ')));

      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'pick';
      const inQueue = queueKeys.has(item.trackKey);
      const justPicked = pickedKeys.has(item.trackKey);
      btn.textContent = inQueue ? '队列中' : justPicked ? '已点' : '点歌';
      btn.disabled = inQueue || justPicked;
      if (!btn.disabled) {
        btn.addEventListener('click', () => enqueue(item, btn));
      }
      li.append(meta, btn);
      list.append(li);
    }
  }

  function nextFeaturedBatch() {
    const all = state.featuredItems;
    if (all.length <= FEATURED_PAGE) return;
    state.featuredOffset = (state.featuredOffset + FEATURED_PAGE) % all.length;
    renderFeatured();
  }

  // 歌单由节点检索解析而来，没就绪就过一会儿再问；最多试几轮，避免离线时空转。
  async function loadFeatured() {
    if (featuredLoading || featuredDone) return;
    featuredLoading = true;
    featuredAttempts += 1;
    try {
      const data = await api('/api/featured');
      const items = Array.isArray(data.items) ? data.items : [];
      if (items.length) {
        state.featuredItems = items;
        renderFeatured();
      }
      if (data.ready === true) {
        featuredDone = true;
        return;
      }
    } catch {
      // 拿不到就安静地不显示，歌单只是填充，不该抢搜索的主路径。
    } finally {
      featuredLoading = false;
      if (!featuredDone && featuredAttempts < 6) {
        clearTimeout(featuredTimer);
        featuredTimer = setTimeout(loadFeatured, 10000);
      }
    }
  }

  function renderResults(data) {
    const list = $('results');
    list.replaceChildren();
    const items = Array.isArray(data.items) ? data.items : [];
    if (!items.length) {
      hint('没有找到，换个关键词试试', true);
      return;
    }
    hint(`共 ${Number(data.total) || items.length} 条结果`);
    for (const item of items) {
      const li = document.createElement('li');
      const meta = el('div', 'row-meta');
      meta.append(el('div', 'row-title', item.title || '未知曲目'));
      const sub = [];
      if (item.artist) sub.push(item.artist);
      if (item.durationMs) sub.push(fmt(item.durationMs));
      sub.push(String(item.trackKey || '').startsWith('local:') ? '本机' : '在线');
      meta.append(el('div', 'row-sub', sub.join(' · ')));
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'pick';
      btn.textContent = '点歌';
      btn.addEventListener('click', () => enqueue(item, btn));
      li.append(meta, btn);
      list.append(li);
    }
  }

  let searching = false;
  async function doSearch() {
    if (searching) return;
    const q = $('q').value.trim();
    if (!q) {
      hint('输入歌名或歌手', true);
      return;
    }
    searching = true;
    const btn = $('searchBtn');
    btn.disabled = true;
    btn.textContent = '搜索中';
    hint('正在搜索…');
    try {
      const data = await api(`/api/search?q=${encodeURIComponent(q)}&limit=12&cid=${encodeURIComponent(state.clientId)}`);
      renderResults(data);
    } catch (err) {
      hint(messageFor(err), true);
    } finally {
      searching = false;
      btn.disabled = false;
      btn.textContent = '搜索';
    }
  }

  async function enqueue(track, btn) {
    const trackKey = track.trackKey;
    const title = track.title || '未知曲目';
    if (!state.seat) {
      askSeat(() => enqueue(track, null));
      return;
    }
    if (btn) {
      btn.disabled = true;
      btn.textContent = '点歌中';
    }
    try {
      const result = await api('/api/enqueue', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          trackKey,
          seat: state.seat,
          clientId: state.clientId,
          // 节点重启后在线曲目缓存会清空，这三项让节点能按歌名重新映射出有效的 trackKey。
          title,
          artist: track.artist || '',
          durationMs: Number(track.durationMs) || 0,
        }),
      });
      const pos = Number(result.queuePosition);
      toast(pos > 0 ? `已点《${title}》 · 第 ${pos} 位` : `已点《${title}》`);
      pickedKeys.add(trackKey);
      if (state.featuredItems.length) renderFeatured();
      poll();
    } catch (err) {
      toast(messageFor(err), true);
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.textContent = '点歌';
      }
    }
  }

  // ---------------- 启动 ----------------

  function boot() {
    if (SOURCE_URL) {
      const link = $('sourceLink');
      link.href = SOURCE_URL;
      link.classList.remove('hidden');
    }
    const params = new URLSearchParams(location.search);
    const urlSeat = (params.get('seat') || '').trim().slice(0, 16);
    state.seat = urlSeat || (localStorage.getItem('kj.seat') || '').trim().slice(0, 16);

    state.clientId = localStorage.getItem('kj.client') || '';
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(state.clientId)) {
      state.clientId = `g-${randomHex(8)}`;
      localStorage.setItem('kj.client', state.clientId);
    }
    if (state.seat) localStorage.setItem('kj.seat', state.seat);
    updateSeatChip();

    $('seatChip').addEventListener('click', () => askSeat(null));
    $('seatCancel').addEventListener('click', closeSeatDialog);
    $('seatOk').addEventListener('click', () => {
      const value = $('seatInput').value.trim().slice(0, 16);
      if (!value) {
        $('seatInput').focus();
        return;
      }
      setSeat(value);
      const callback = seatCallback;
      seatCallback = null;
      $('seatDialog').close();
      if (callback) callback();
    });
    $('seatInput').addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        $('seatOk').click();
      }
    });
    $('seatDialog').addEventListener('click', (event) => {
      if (event.target === $('seatDialog')) closeSeatDialog();
    });

    $('searchBtn').addEventListener('click', doSearch);
    $('featuredMore').addEventListener('click', nextFeaturedBatch);
    $('q').addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        doSearch();
      }
    });

    const urlQuery = (params.get('q') || '').trim().slice(0, 64);
    if (urlQuery) {
      $('q').value = urlQuery;
      doSearch();
    }

    poll();
    setInterval(poll, 2000);
    setInterval(renderProgress, 250);
    loadFeatured();
  }

  boot();
})();
