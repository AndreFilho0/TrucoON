// Painel ao vivo do multicast do TrucoON.
//
// Abre um canal Phoenix ("painel:trace") em CADA peer do grupo e junta os
// eventos numa visão só:
//
//   send     → um ponto sai do peer de origem e voa até o destino
//   recv     → chegou (em ordem, adiantado e foi para a fila, ou duplicado)
//   queues   → retrato das filas: canal FIFO (hold-back) e ordenação
//   deliver  → a ordenação liberou a mensagem para a aplicação
//   apply    → a réplica aplicou o comando (com o hash encadeado)
//
// Para a animação contar a história certa, os eventos de um peer que
// dependem de um pacote ainda "voando" esperam o ponto pousar.

(() => {
  "use strict";

  // ---------------------------------------------------------------- estado

  const S = {
    mode: null,
    controls: false,
    ids: [], // ids dos peers, em ordem
    info: {}, // id -> {region, url}
    conns: {}, // id -> {socket, channel}
    snap: {}, // id -> último retrato das filas
    feed: {}, // id -> últimas chegadas
    delivered: {}, // id -> últimas entregas
    applied: {}, // id -> últimos comandos aplicados (mais novo primeiro)
    chain: {}, // id -> {applied, chain}
    rooms: {}, // id -> {code -> sala (visão pública)}
    pending: {}, // id -> fila de eventos a processar
    timers: {},
    dots: [],
    flying: new Map(), // chave do pacote -> [pontos]
    lamportId: {}, // "ts.origem" -> id da mensagem (para colorir os ACKs)
    showAcks: false,
    race: null,
    pos: {}, // id -> {x, y}
    els: {}, // id -> elementos da coluna
  };

  const BASE_FLIGHT = 450; // ms de voo quando a rede não tem atraso
  const MAX_FLIGHT = 4000;
  const NODE_Y = 112;
  const NODE_R = 30;
  const svgNS = "http://www.w3.org/2000/svg";

  const $ = (sel) => document.querySelector(sel);
  const esc = (s) =>
    String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

  // Rótulo de jogada: pedidos (truco, seis, nove, doze) em destaque e naipes
  // vermelhos em vermelho. Escapa o texto antes de marcar.
  const fmt = (label) =>
    esc(label)
      .replace(/\b(truco|seis|nove|doze)!/g, '<b class="call">$1!</b>')
      .replace(/([QJKA237])([♥♦])/g, '<b class="red">$1$2</b>')
      .replace(/([QJKA2347])([♣♠])/g, "<b>$1$2</b>");

  // ---------------------------------------------------------------- cores

  function hashStr(s) {
    let h = 2166136261;
    for (const ch of String(s)) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
    return h >>> 0;
  }
  const hue = (s) => (hashStr(s) * 137.508) % 360;
  const colorOf = (id) => `hsl(${hue(id)} 80% 66%)`;

  function pktColor(pkt) {
    if (!pkt) return "#94a3b8";
    if (pkt.kind === "rack") return "#64748b";
    if (pkt.kind === "tack") {
      const id = S.lamportId[pkt.ref];
      return id ? colorOf(id) : "#f9a8d4";
    }
    return pkt.id ? colorOf(pkt.id) : "#cbd5e1";
  }

  // ---------------------------------------------------------------- textos

  const MODE = {
    none: ["SEM ORDEM · UDP cru", "UDP cru: pacotes podem se perder e chegar fora de ordem. Nenhuma fila."],
    fifo: [
      "FIFO",
      "Canal confiável FIFO: nada se perde e cada remetente chega em ordem, mas remetentes diferentes chegam em ordens diferentes (sem ordem total).",
    ],
    total: [
      "ORDEM TOTAL · Lamport",
      "Relógios de Lamport: cada mensagem espera na fila ordenada por (relógio, id) até ter ACK de todos; só então vai para a aplicação.",
    ],
    sequencer: [
      "ORDEM TOTAL · sequenciador",
      "Sequenciador: o peer de menor id numera cada mensagem (g) e todos entregam em ordem crescente de g.",
    ],
  };

  // ---------------------------------------------------------------- conexão

  function wsUrl(httpUrl) {
    const u = new URL(httpUrl);
    u.protocol = u.protocol === "https:" ? "wss:" : "ws:";
    u.pathname = "/painel/socket";
    return u.toString();
  }

  function connect(url, onHello) {
    const socket = new Phoenix.Socket(wsUrl(url), { params: {} });
    socket.connect();
    const channel = socket.channel("painel:trace", {});
    let peerId = null;

    channel.on("ev", (e) => peerId != null && onEvent(peerId, e));
    channel
      .join()
      .receive("ok", (hello) => {
        peerId = hello.peer_id;
        onHello(hello, { socket, channel });
      })
      .receive("error", () => setBadge("#mode", "erro ao conectar", "bad"));
    return { socket, channel };
  }

  function boot() {
    const first = connect(location.origin, (hello, conn) => {
      if (!hello.ready || !hello.peers.length) {
        setBadge("#mode", "aguardando o grupo se formar…", "muted");
        conn.channel.leave();
        conn.socket.disconnect();
        setTimeout(boot, 1500);
        return;
      }
      if (S.ids.length) return; // reconexão: já montado

      S.mode = hello.mode;
      S.controls = hello.controls;
      S.ids = hello.peers.map((p) => p.id).sort((a, b) => a - b);
      hello.peers.forEach((p) => (S.info[p.id] = p));
      buildUI(hello);

      // este peer já está conectado; abre os outros
      registerHello(hello, conn);
      hello.peers
        .filter((p) => p.id !== hello.peer_id)
        .forEach((p) => connect(p.url, (h, c) => registerHello(h, c)));
    });
    return first;
  }

  function registerHello(h, conn) {
    const id = h.peer_id;
    if (id == null || !S.info[id]) return;
    S.conns[id] = conn;
    S.info[id].faults = h.faults;
    if (h.queues) S.snap[id] = h.queues;
    if (h.replica) {
      S.chain[id] = { applied: h.replica.applied, chain: h.replica.chain };
      S.applied[id] = h.replica.recent.map((r, i) => ({
        n: h.replica.applied - i,
        label: r.label || r.cmd,
        ok: r.ok,
        reason: r.ok ? null : "",
        color: colorOf(r.uid),
        mine: false,
      }));
    }
    S.els[id].root.classList.remove("offline");
    renderPeer(id);
    renderConsistency();
    if (id === S.ids[0] && h.faults) syncSliders(h.faults);
  }

  // ---------------------------------------------------------------- eventos

  function onEvent(peerId, e) {
    if (e.ev === "send") return launch(peerId, e); // começa a voar já
    (S.pending[peerId] ||= []).push(e);
    pump(peerId);
  }

  // Processa a fila de eventos de um peer, segurando uma chegada enquanto o
  // ponto correspondente ainda está no ar.
  function pump(id) {
    clearTimeout(S.timers[id]);
    const q = S.pending[id] || [];
    const now = performance.now();

    while (q.length) {
      const e = q[0];
      if (e.ev === "recv" && q.length < 80 && expectsDot(e)) {
        const dot = findDot(e.key);
        if (dot && !dot.dropped) {
          const landAt = dot.start + dot.dur;
          if (now < landAt) {
            S.timers[id] = setTimeout(() => pump(id), landAt - now + 5);
            return;
          }
        } else if (!dot) {
          // o "send" do outro peer pode ainda estar a caminho pelo WebSocket
          e._seen ||= now;
          if (now - e._seen < 120) {
            S.timers[id] = setTimeout(() => pump(id), 25);
            return;
          }
        }
        if (dot) consumeDot(e.key, dot);
      }
      q.shift();
      apply(id, e);
    }
  }

  const expectsDot = (e) => e.pkt?.layer !== "a" || S.showAcks;

  function apply(id, e) {
    switch (e.ev) {
      case "recv":
        if (e.pkt.layer === "a" && !S.showAcks) return;
        pushFeed(id, e);
        flashNode(id);
        break;
      case "queues":
        S.snap[id] = e;
        renderQueues(id);
        updateNode(id);
        break;
      case "deliver":
        S.delivered[id] = [e, ...(S.delivered[id] || [])].slice(0, 3);
        renderDelivered(id);
        break;
      case "apply":
        onApply(id, e);
        break;
    }
  }

  function onApply(id, e) {
    S.chain[id] = { applied: e.applied, chain: e.chain };
    const list = S.applied[id] || [];
    list.unshift({
      n: e.applied,
      label: e.label,
      ok: e.ok,
      reason: e.reason,
      color: colorOf(e.id),
      mine: e.mine,
      fresh: true,
    });
    S.applied[id] = list.slice(0, 10);
    if (e.code && e.room) (S.rooms[id] ||= {})[e.code] = e.room;
    renderApplied(id);
    renderConsistency();
    if (S.race && e.code === S.race.code) renderRace();
  }

  // ---------------------------------------------------------------- UI fixa

  function buildUI(hello) {
    const [label, text] = MODE[hello.mode] || [hello.mode, ""];
    setBadge("#mode", label, "gold");
    $("#mode-text").textContent = text;
    $("#controls").hidden = !S.controls;

    const peers = $("#peers");
    peers.style.setProperty("--n", S.ids.length);
    peers.innerHTML = "";

    for (const id of S.ids) {
      const info = S.info[id];
      const root = document.createElement("article");
      root.className = "peer offline";
      root.innerHTML = `
        <div class="peer-head">
          <div><h2>Peer ${id}</h2><small>${esc(info.region)} · ${esc(new URL(info.url).host)}</small></div>
          <span class="seat-box" hidden></span>
        </div>
        <section class="layer">
          <h3>① Chegou pela rede</h3>
          <div class="feed"></div>
        </section>
        <section class="layer">
          <h3>② Canal FIFO · fila de espera <em class="ch-meta"></em></h3>
          <div class="channel"></div>
        </section>
        <section class="layer">
          <h3>③ Ordenação <em class="ord-meta"></em></h3>
          <div class="chips ordering"></div>
          <div class="feed delivered" style="min-height:0"></div>
        </section>
        <section class="layer">
          <h3>④ Réplica · comandos aplicados <span class="chain"></span></h3>
          <div class="applied"></div>
        </section>`;
      peers.appendChild(root);
      S.els[id] = {
        root,
        feed: root.querySelector(".feed"),
        channel: root.querySelector(".channel"),
        chMeta: root.querySelector(".ch-meta"),
        ordering: root.querySelector(".ordering"),
        ordMeta: root.querySelector(".ord-meta"),
        delivered: root.querySelector(".delivered"),
        applied: root.querySelector(".applied"),
        chain: root.querySelector(".chain"),
        seat: root.querySelector(".seat-box"),
      };
    }

    buildNet();
    requestAnimationFrame(frame);
  }

  // ---------------------------------------------------------------- rede (SVG)

  const net = $("#net");
  let gLinks, gDots, gNodes;

  function el(tag, attrs = {}, parent) {
    const n = document.createElementNS(svgNS, tag);
    for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
    if (parent) parent.appendChild(n);
    return n;
  }

  function buildNet() {
    net.innerHTML = "";
    gLinks = el("g", {}, net);
    gDots = el("g", {}, net);
    gNodes = el("g", {}, net);
    layout();
    window.addEventListener("resize", layout);
  }

  function layout() {
    const box = net.getBoundingClientRect();
    const single = getComputedStyle($("#peers")).gridTemplateColumns.split(" ").length === 1;
    S.ids.forEach((id, i) => {
      let x;
      if (single) x = (box.width * (i + 1)) / (S.ids.length + 1);
      else {
        const r = S.els[id].root.getBoundingClientRect();
        x = r.left + r.width / 2 - box.left;
      }
      S.pos[id] = { x, y: NODE_Y };
    });
    net.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
    drawLinks();
    drawNodes();
  }

  function drawLinks() {
    gLinks.innerHTML = "";
    for (const a of S.ids)
      for (const b of S.ids) {
        if (a === b) continue;
        const p = pathFn(a, b);
        const pts = [];
        for (let t = 0; t <= 1.0001; t += 0.05) pts.push(p(t));
        el("path", { class: "link", d: "M" + pts.map((q) => `${q.x},${q.y}`).join(" L") }, gLinks);
      }
  }

  function drawNodes() {
    gNodes.innerHTML = "";
    for (const id of S.ids) {
      const { x, y } = S.pos[id];
      const g = el("g", { class: "node", "data-id": id, transform: `translate(${x},${y})` }, gNodes);
      el("circle", { class: "body", r: NODE_R }, g);
      el("text", { y: 5 }, g).textContent = `P${id}`;
      el("text", { class: "sub", y: NODE_R + 16 }, g).textContent = S.info[id].region;
      el("text", { class: "clock", y: NODE_R + 32 }, g);
      S.els[id].node = g;
      updateNode(id);
    }
  }

  function updateNode(id) {
    const g = S.els[id]?.node;
    if (!g) return;
    const o = S.snap[id]?.ordering || {};
    let t = "";
    if (S.mode === "total" && o.clock != null) t = `relógio L = ${o.clock}`;
    if (S.mode === "sequencer" && o.sequencer === id) t = `★ sequenciador · próximo g ${o.next_g}`;
    g.querySelector(".clock").textContent = t;
  }

  function flashNode(id) {
    const g = S.els[id]?.node;
    if (!g) return;
    g.classList.remove("flash");
    void g.getBBox();
    g.classList.add("flash");
  }

  // caminho de a até b: arco por cima (esquerda→direita) ou por baixo
  function pathFn(a, b) {
    const A = S.pos[a],
      B = S.pos[b];
    if (a === b) {
      const r = 18;
      return (t) => ({
        x: A.x + r * Math.sin(2 * Math.PI * t),
        y: A.y - NODE_R - r + r * Math.cos(2 * Math.PI * t),
      });
    }
    const dx = B.x - A.x;
    const bend = Math.min(90, 34 + Math.abs(dx) * 0.18) * (dx > 0 ? -1 : 1);
    const C = { x: (A.x + B.x) / 2, y: (A.y + B.y) / 2 + bend * 2 };
    return (t) => ({
      x: (1 - t) ** 2 * A.x + 2 * (1 - t) * t * C.x + t * t * B.x,
      y: (1 - t) ** 2 * A.y + 2 * (1 - t) * t * C.y + t * t * B.y,
    });
  }

  function launch(from, e) {
    if (e.pkt?.kind === "msg" && e.pkt.ts) S.lamportId[e.pkt.ts] = e.pkt.id;
    if (e.pkt?.layer === "a" && !S.showAcks) return;
    if (!S.pos[from] || !S.pos[e.to]) return;

    const dur = Math.min(MAX_FLIGHT, e.delay > 0 ? e.delay : BASE_FLIGHT);
    const color = pktColor(e.pkt);
    const g = el("g", {}, gDots);
    const kind = e.pkt?.kind;

    if (kind === "rack") el("circle", { r: 3.5, fill: color }, g);
    else if (kind === "tack") el("rect", { x: -5, y: -5, width: 10, height: 10, fill: color, transform: "rotate(45)", opacity: 0.85 }, g);
    else if (kind === "req") el("rect", { x: -6, y: -6, width: 12, height: 12, rx: 2, fill: color }, g);
    else el("circle", { r: 7, fill: color }, g);

    if (e.retx) el("circle", { r: 11, fill: "none", stroke: "#fbbf24", "stroke-width": 2, "stroke-dasharray": "3 3" }, g);

    if (kind === "msg" || kind === "req" || kind === "ord") {
      const parts = [kind === "ord" ? `g${e.pkt.g}` : e.pkt.ts || e.pkt.id, e.pkt.label];
      el("text", { class: "pkt-label", x: 10, y: -9 }, g).textContent = parts.filter(Boolean).join(" · ").slice(0, 34);
    }

    const dot = { key: e.key, from, to: e.to, start: performance.now(), dur, g, path: pathFn(from, e.to), dropped: e.dropped };
    S.dots.push(dot);
    if (!e.dropped) {
      const list = S.flying.get(e.key) || [];
      list.push(dot);
      S.flying.set(e.key, list);
    }
  }

  const findDot = (key) => (S.flying.get(key) || [])[0];

  function consumeDot(key, dot) {
    const list = (S.flying.get(key) || []).filter((d) => d !== dot);
    list.length ? S.flying.set(key, list) : S.flying.delete(key);
  }

  function frame(now) {
    S.dots = S.dots.filter((d) => {
      let t = (now - d.start) / d.dur;

      if (d.dropped && t >= 0.5) {
        if (!d.boom) {
          d.boom = now;
          d.g.innerHTML = "";
          el("text", { class: "lost-x", y: 6 }, d.g).textContent = "✕";
        }
        const age = (now - d.boom) / 700;
        d.g.setAttribute("opacity", Math.max(0, 1 - age));
        if (age >= 1) return d.g.remove(), false;
        return true;
      }

      if (t >= 1) {
        // pousou: some e libera a chave se ninguém consumiu
        d.g.remove();
        setTimeout(() => consumeDot(d.key, d), 2000);
        return false;
      }
      const p = d.path(Math.max(0, t));
      d.g.setAttribute("transform", `translate(${p.x},${p.y})`);
      return true;
    });
    requestAnimationFrame(frame);
  }

  // ---------------------------------------------------------------- colunas

  // Atualiza uma lista de chips por chave, animando quem entra e quem sai.
  function renderChips(container, items) {
    if (items.length) container.querySelectorAll(".empty").forEach((e) => e.remove());
    const existing = new Map();
    for (const c of container.querySelectorAll(":scope > .chip:not(.leave)")) existing.set(c.dataset.key, c);

    let prev = null;
    for (const it of items) {
      let c = existing.get(it.key);
      if (c) existing.delete(it.key);
      else {
        c = document.createElement("span");
        c.dataset.key = it.key;
        c.classList.add("enter");
        setTimeout(() => c.classList.remove("enter"), 400);
      }
      c.className = `chip ${it.cls || ""} ${c.classList.contains("enter") ? "enter" : ""}`;
      c.style.setProperty("--c", it.color);
      if (c.innerHTML !== it.html) c.innerHTML = it.html;
      if (prev ? prev.nextSibling !== c : container.firstChild !== c) container.insertBefore(c, prev ? prev.nextSibling : container.firstChild);
      prev = c;
    }
    for (const c of existing.values()) {
      c.classList.add("leave");
      setTimeout(() => c.remove(), 300);
    }
  }

  function renderPeer(id) {
    renderFeed(id);
    renderQueues(id);
    renderDelivered(id);
    renderApplied(id);
    updateNode(id);
  }

  const STATUS = { in_order: "em ordem", held_back: "adiantada → fila", duplicate: "duplicada", ack: "ack" };

  function pushFeed(id, e) {
    S.feed[id] = [e, ...(S.feed[id] || [])].slice(0, 4);
    renderFeed(id, true);
  }

  function renderFeed(id, fresh) {
    const box = S.els[id].feed;
    const list = S.feed[id] || [];
    if (!list.length) return (box.innerHTML = `<span class="empty">nada ainda</span>`);
    box.innerHTML = list
      .map((e, i) => {
        const p = e.pkt;
        const what =
          p.kind === "rack"
            ? `ACK do canal (até nº ${p.cum})`
            : p.kind === "tack"
              ? `ACK de P${p.acker} para ${p.ref}`
              : `${p.seq != null ? "nº " + p.seq + " · " : ""}${fmt(p.label || p.kind)}${p.g ? " · g" + p.g : ""}`;
        return `<div class="${fresh && i === 0 ? "enter" : ""}"><span class="tag ${e.status}">${STATUS[e.status] || e.status}</span>
          <span style="color:${pktColor(p)}">●</span> de P${e.from}: ${what}</div>`;
      })
      .join("");
  }

  function renderQueues(id) {
    const els = S.els[id];
    const snap = S.snap[id];
    if (!snap) return;

    // ② canal FIFO
    if (S.mode === "none") {
      els.channel.innerHTML = `<span class="empty">desligado: UDP cru, sem número de sequência</span>`;
      els.chMeta.textContent = "";
    } else {
      const unacked = Object.values(snap.channel?.unacked || {}).reduce((n, l) => n + l.length, 0);
      els.chMeta.textContent = unacked ? `${unacked} sem ACK` : "";
      if (!els.channel.dataset.built) {
        els.channel.innerHTML = S.ids
          .map((src) => `<div class="row" data-src="${src}"><span class="lbl"></span><span class="chips"></span></div>`)
          .join("");
        els.channel.dataset.built = "1";
      }
      for (const src of S.ids) {
        const row = els.channel.querySelector(`[data-src="${src}"]`);
        const ch = snap.channel?.in?.[src] || { expected: 1, held: [] };
        row.querySelector(".lbl").textContent = `de P${src} · espera nº ${ch.expected}`;
        renderChips(
          row.querySelector(".chips"),
          ch.held.map((m) => ({
            key: `${src}-${m.seq}`,
            color: pktColor(m),
            html: `<span class="k">nº ${m.seq}</span> ${fmt(m.label || m.kind)}`,
          })),
        );
      }
    }

    // ③ ordenação
    const o = snap.ordering || { queue: [] };
    if (S.mode === "total") {
      els.ordMeta.textContent = `fila por (relógio, id) · L=${o.clock}`;
      renderChips(
        els.ordering,
        o.queue.map((m, i) => ({
          key: m.ts,
          cls: i === 0 ? "head" : "",
          color: pktColor(m),
          html: `<span class="k">${m.ts}</span> ${fmt(m.label)} <span class="acks" title="ACKs recebidos">${S.ids
            .map((p) => `<i class="${m.acks.includes(p) ? "on" : ""}"></i>`)
            .join("")}</span>`,
        })),
      );
      if (!o.queue.length) emptyOrdering(els, "vazia: tudo já foi entregue");
    } else if (S.mode === "sequencer") {
      els.ordMeta.textContent = `espera g = ${o.expected}`;
      renderChips(
        els.ordering,
        o.queue.map((m) => ({ key: "g" + m.g, color: pktColor(m), html: `<span class="k">g${m.g}</span> ${fmt(m.label)}` })),
      );
      if (!o.queue.length) emptyOrdering(els, "vazia: entregue tudo até g = " + (o.expected - 1));
    } else {
      els.ordMeta.textContent = "";
      emptyOrdering(els, "sem fila: entrega assim que o canal entrega");
    }
  }

  function emptyOrdering(els, text) {
    if (els.ordering.querySelector(".chip:not(.leave)")) return;
    const old = els.ordering.querySelector(".empty");
    if (old) return (old.textContent = text);
    els.ordering.insertAdjacentHTML("beforeend", `<span class="empty" data-key="_empty">${esc(text)}</span>`);
  }

  function renderDelivered(id) {
    const list = S.delivered[id] || [];
    S.els[id].delivered.innerHTML = list
      .map(
        (d, i) =>
          `<div class="${i === 0 ? "enter" : ""}">↓ entregue <span style="color:${colorOf(d.id)}">●</span> ${fmt(d.msg?.label || "")} ${
            d.order ? `<small style="color:var(--muted)">(${esc(d.order)})</small>` : ""
          }</div>`,
      )
      .join("");
  }

  function renderApplied(id) {
    const els = S.els[id];
    const list = S.applied[id] || [];
    const c = S.chain[id];
    if (c) {
      els.chain.textContent = c.chain;
      els.chain.style.background = `hsl(${hue(c.chain)} 70% 62%)`;
      els.chain.title = "hash encadeado da sequência de comandos (mesma cor = mesma ordem)";
    }
    els.applied.innerHTML = list.length
      ? list
          .map(
            (a) => `<div class="item ${a.fresh ? "enter" : ""}" style="--c:${a.color}">
              <span class="n">#${a.n}</span>
              <span class="lab">${a.mine ? "★ " : ""}${fmt(a.label)}</span>
              <span class="res ${a.ok ? "ok" : "err"}">${a.ok ? "✓" : "✗ " + esc(a.reason || "")}</span></div>`,
          )
          .join("")
      : `<span class="empty">nenhum comando ainda</span>`;
    list.forEach((a) => (a.fresh = false));
  }

  // ---------------------------------------------------------------- consistência

  function renderConsistency() {
    const known = S.ids.map((id) => S.chain[id]).filter(Boolean);
    if (known.length < S.ids.length) return setBadge("#consistency", "—", "muted");
    const counts = new Set(known.map((c) => c.applied));
    if (counts.size > 1) return setBadge("#consistency", "réplicas aplicando…", "muted");
    const same = new Set(known.map((c) => c.chain)).size === 1;
    setBadge(
      "#consistency",
      same ? `✓ mesma sequência nas ${known.length} réplicas` : "✗ réplicas aplicaram em ordens diferentes",
      same ? "ok" : "bad",
    );
  }

  function setBadge(sel, text, cls) {
    const b = $(sel);
    b.textContent = text;
    b.className = `badge ${cls || ""}`;
  }

  // ---------------------------------------------------------------- controles

  async function post(url, path, body) {
    const r = await fetch(url + path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || r.status);
    return r.json();
  }

  function syncSliders(f) {
    $("#delay").value = f.delay_max;
    $("#delay-out").textContent = `${f.delay_max} ms`;
    $("#loss").value = Math.round(f.loss * 100);
    $("#loss-out").textContent = `${Math.round(f.loss * 100)}%`;
  }

  function setFaults(body) {
    return Promise.all(S.ids.map((id) => post(S.info[id].url, "/api/painel/faults", body).catch(() => null)));
  }

  $("#delay").addEventListener("input", (e) => ($("#delay-out").textContent = `${e.target.value} ms`));
  $("#delay").addEventListener("change", (e) => {
    const d = Number(e.target.value);
    setFaults({ delay_min: Math.round(d * 0.5), delay_max: d });
  });
  $("#loss").addEventListener("input", (e) => ($("#loss-out").textContent = `${e.target.value}%`));
  $("#loss").addEventListener("change", (e) => setFaults({ loss: Number(e.target.value) / 100 }));
  $("#show-acks").addEventListener("change", (e) => (S.showAcks = e.target.checked));

  $("#clear").addEventListener("click", () => {
    for (const id of S.ids) {
      S.feed[id] = [];
      S.delivered[id] = [];
      S.applied[id] = [];
      renderPeer(id);
      S.els[id].seat.hidden = true;
    }
    S.race = null;
    $("#race-result").hidden = true;
  });

  // ---------------------------------------------------------------- disputa

  $("#race").addEventListener("click", async () => {
    const btn = $("#race");
    btn.disabled = true;
    try {
      const racers = Math.min(4, Math.max(2, S.ids.length));
      const first = S.info[S.ids[0]].url;
      const { code, players } = await post(first, "/api/painel/race", { racers });
      S.race = { code, players, phase: "setup" };
      renderRace();

      // espera a mesa (anfitrião + jogadores) existir em todas as réplicas
      const need = players.length + 1;
      const t0 = Date.now();
      while (!S.ids.every((id) => (S.rooms[id]?.[code]?.members?.length || 0) >= need)) {
        if (Date.now() - t0 > 60000) throw new Error("a mesa não chegou a todas as réplicas");
        await new Promise((r) => setTimeout(r, 100));
      }

      // todos pedem a cadeira 0 AO MESMO TEMPO, cada um por um peer diferente
      S.race.phase = "race";
      S.race.via = players.map((p, i) => ({ p, peer: S.ids[i % S.ids.length] }));
      renderRace();
      await Promise.all(
        S.race.via.map(({ p, peer }) => post(S.info[peer].url, "/api/painel/race/seat", { code, player_id: p.id, seat: 0 })),
      );
    } catch (err) {
      const box = $("#race-result");
      box.hidden = false;
      box.className = "race bad";
      box.textContent = `Não deu para disputar: ${err.message}`;
    } finally {
      btn.disabled = false;
    }
  });

  function seat0(id) {
    const room = S.rooms[id]?.[S.race.code];
    return room?.seats?.find((s) => s.seat === 0)?.player?.name || null;
  }

  function renderRace() {
    const r = S.race;
    const box = $("#race-result");
    if (!r) return;
    box.hidden = false;

    if (r.phase === "setup") {
      box.className = "race";
      box.innerHTML = `<strong>Disputa de cadeira</strong> preparando a mesa <code>${esc(r.code)}</code> em todas as réplicas…`;
      return;
    }

    const who = S.ids.map((id) => [id, seat0(id)]);
    for (const [id, name] of who) {
      const s = S.els[id].seat;
      s.hidden = false;
      s.textContent = `cadeira 0: ${name || "…"}`;
      s.style.borderColor = name ? colorOf(name) : "";
      s.style.color = name ? colorOf(name) : "";
    }

    const via = r.via.map(({ p, peer }) => `${esc(p.name)} pelo P${peer}`).join(", ");
    const done = who.every(([, n]) => n);
    const same = new Set(who.map(([, n]) => n)).size === 1;
    box.className = `race ${done ? (same ? "ok" : "bad") : ""}`;
    box.innerHTML = `<strong>Disputa de cadeira</strong> ${via} pedem a cadeira 0 ao mesmo tempo. ${
      !done
        ? "Aguardando as réplicas…"
        : same
          ? `<span style="color:var(--ok)">✓ Todas as réplicas deram a cadeira para <b>${esc(who[0][1])}</b>.</span>`
          : `<span style="color:var(--bad)">✗ As réplicas divergiram: ${who.map(([id, n]) => `P${id} → ${esc(n)}`).join(" · ")}</span>`
    }`;
  }

  boot();
})();
