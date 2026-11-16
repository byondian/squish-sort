// The giant squishy in the hero, drawn from the game's real art.
// Squeeze it, stretch it, let go: it pops into another squishy. Every few pops
// you uncover a rare one, then an ultra rare, each with its own fanfare.
// With WebGL it is a real soft body (the game's squish engine and live ASMR sound,
// /assets/squish/); without WebGL, or with Reduce Motion, it falls back to SVG + springs.
// No libraries. Pauses when off screen.
(() => {
  const stage = document.getElementById('morph');
  if (!stage) return;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const NS = 'http://www.w3.org/2000/svg';
  const W = 400, H = 420, CX = 200, BASE = 372, SIZE = 330; // art box, anchored at bottom centre
  const TAU = Math.PI * 2, pow = Math.pow;
  const el = (t, a = {}, p) => { const e = document.createElementNS(NS, t); for (const k in a) e.setAttribute(k, a[k]); if (p) p.appendChild(e); return e; };
  const ease = x => (x < .5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2);

  const names = JSON.parse(stage.dataset.names || '{}');
  const rarityWords = JSON.parse(stage.dataset.rarity || '[]');
  const tiers = JSON.parse(stage.dataset.tiers || '{}');
  const feels = JSON.parse(stage.dataset.feels || '{}');
  const ART = id => `/assets/art/${id}.svg`;
  const shuffle = a => { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };

  // The reveal ladder: a few commons, then a rare, a few more, then an ultra rare.
  // Every second round ends with a golden secret squishy.
  const ROUND = ['common', 'common', 'common', 'common', 'rare', 'common', 'common', 'common', 'ultra'];
  const LADDER = [...ROUND, ...ROUND.slice(0, -1), 'secret'];
  const bags = {}, pick = tier => { const all = tiers[tier] || []; if (!all.length) return 'strawbie'; if (!bags[tier] || !bags[tier].length) bags[tier] = shuffle(all); return bags[tier].pop(); };
  if (tiers.common) tiers.common = tiers.common.filter(id => id !== 'strawbie');
  let step = 0, current = 'strawbie', upcoming = null;
  const plan = () => { const tier = LADDER[step % LADDER.length]; const id = pick(tier); upcoming = { tier, id }; const im = new Image(); im.src = ART(id); };

  // DOM
  const svg = el('svg', { viewBox: `0 0 ${W} ${H}`, 'aria-hidden': 'true' }, stage);
  const defs = el('defs', {}, svg);
  const rb = el('linearGradient', { id: 'mrainbow', x1: '0', y1: '0', x2: '1', y2: '1' }, defs);
  const RAINBOW = ['#FF9CC8', '#FFD86B', '#7FE0C4', '#7CC8FF', '#B48CFF'];
  RAINBOW.forEach((c, i) => el('stop', { offset: i / 4, 'stop-color': c }, rb));
  // jelly wobble: a gentle displacement that swells when it's poked
  const filt = el('filter', { id: 'mjelly', x: '-15%', y: '-15%', width: '130%', height: '130%' }, defs);
  const turb = el('feTurbulence', { type: 'fractalNoise', baseFrequency: '0.012', numOctaves: '1', seed: '3', result: 'n' }, filt);
  const disp = el('feDisplacementMap', { in: 'SourceGraphic', in2: 'n', scale: '0', xChannelSelector: 'R', yChannelSelector: 'G' }, filt);

  const rays = el('g', { opacity: 0 }, svg);
  for (let i = 0; i < 12; i++) el('path', { d: `M-9 -150 L0 -214 L9 -150Z`, transform: `rotate(${i * 30})` }, rays);
  const halo = el('circle', { cx: CX, cy: BASE - SIZE * .42, r: 150, fill: 'none', stroke: 'url(#mrainbow)', 'stroke-width': 14, opacity: 0 }, svg);
  const shadow = el('ellipse', { cx: CX, cy: BASE + 6, rx: SIZE * .36, ry: 13, fill: '#3B2A4A', opacity: '.1' }, svg);
  const body = el('g', reduce ? {} : { filter: 'url(#mjelly)' }, svg);
  const mkImg = () => el('image', { x: -SIZE / 2, y: -SIZE * .93, width: SIZE, height: SIZE, preserveAspectRatio: 'xMidYMax meet' }, body);
  let imgA = mkImg(), imgB = mkImg();
  imgA.setAttribute('href', ART(current)); imgB.setAttribute('opacity', 0);
  const fx = el('g', {}, svg);

  // ---- soft body (WebGL). SB stays null until the first toy is ready, so the SVG shows meanwhile.
  let SB = null, softTry = null;
  if (!reduce && window.Squish && window.SquishAudio) {
    try {
      const canvas = document.createElement('canvas'); canvas.className = 'soft'; canvas.setAttribute('aria-hidden', 'true');
      const glr = new Squish.SquishGL(canvas);
      softTry = { canvas, glr, audio: new SquishAudio(), tex: {}, world: { floor: 0, left: 0, right: 0, top: 0 }, S: 0, scale: 1, ox: 0, w: 0, body: null, feel: 'foam', acc: 0, ptrs: {}, size0: {}, pend: 0 };
    } catch (e) { softTry = null; }
  }
  function softLayout(o) {
    const r = stage.getBoundingClientRect(), w = r.width, h = r.height, dpr = Math.min(devicePixelRatio || 1, 2);
    o.glr.resize(w, h, dpr); o.w = w;
    o.scale = Math.min(w / W, h / H); o.ox = (w - W * o.scale) / 2; const oy = (h - H * o.scale) / 2;
    o.world.floor = oy + BASE * o.scale; o.world.left = 2; o.world.right = w - 2; o.world.top = 2;
    o.S = SIZE * o.scale * .96;
  }
  function softTexture(o, id, done) {
    if (o.tex[id]) return done(o.tex[id]);
    const img = new Image(), size = 768;
    img.onload = () => {
      const c = document.createElement('canvas'); c.width = c.height = size; c.getContext('2d').drawImage(img, 0, 0, size, size);
      const m = document.createElement('canvas'); m.width = m.height = 64; const mx = m.getContext('2d'); mx.drawImage(c, 0, 0, 64, 64);
      const d = mx.getImageData(0, 0, 64, 64).data; let foot = 0;
      for (let y = 63; y >= 0 && !foot; y--) for (let x = 0; x < 64; x++) if (d[(y * 64 + x) * 4 + 3] > 60) { foot = (y + 1) / 64; break; }
      const inside = (u, v) => { const px = Math.min(63, Math.max(0, Math.round(u * 63))), py = Math.min(63, Math.max(0, Math.round(v * 63))); return d[(py * 64 + px) * 4 + 3] > 60; };
      // v2 engine: a height field from the art's alpha gives the toy depth (light, shade, dents)
      const hN = 128, hc = document.createElement('canvas'); hc.width = hc.height = hN; const hx = hc.getContext('2d'); hx.drawImage(c, 0, 0, hN, hN);
      const hd = hx.getImageData(0, 0, hN, hN).data, al = new Uint8Array(hN * hN); for (let i = 0; i < hN * hN; i++) al[i] = hd[i * 4 + 3];
      done(o.tex[id] = { tex: o.glr.texture(c), htex: o.glr.dataTexture(Squish.heightField(al, hN), hN), hsize: hN, footV: foot || 1, inside });
    };
    img.onerror = () => {};
    img.src = ART(id);
  }
  function softSpawn(id, drop) {
    const o = SB || softTry; if (!o) return;
    const ticket = ++o.pend;
    softTexture(o, id, t => {
      if (ticket !== o.pend) return; // a newer swap won
      const feel = feels[id] || 'jelly', S = o.S;
      const b = new Squish.SquishBody({ size: S, n: 12, inside: t.inside, footV: t.footV, material: feel, x: o.w / 2, y: o.world.floor - S / 2 - (drop ? S * .32 : 0) });
      b.tex = t.tex; b.htex = t.htex; b.hsize = t.hsize; o.body = b; o.feel = feel; o.ptrs = {};
      if (!SB) { // first toy ready: switch the hero over from SVG to the soft body
        SB = o; stage.insertBefore(o.canvas, svg.nextSibling);
        o.shade = document.createElement('div'); o.shade.className = 'shade'; stage.insertBefore(o.shade, svg);
        const top = el('svg', { viewBox: `0 0 ${W} ${H}`, class: 'fxl', 'aria-hidden': 'true' }); top.appendChild(fx); stage.insertBefore(top, o.canvas.nextSibling);
        body.style.display = 'none'; shadow.style.display = 'none';
        stage.classList.add('softon'); // the page can scroll from around the toy; only touches on the toy are kept
        o.audio.enabled = !muted;
      }
    });
  }
  const softKick = (vy, shear) => { // whole-body nudge: vy in body sizes/s, shear tips the top sideways
    const b = SB && SB.body; if (!b || b.held()) return; const S = b.S, fl = SB.world.floor;
    for (let k = 0; k < b.count; k++) { b.v[k * 2 + 1] += vy * S; b.v[k * 2] += shear * S * Math.max(0, (fl - b.p[k * 2 + 1]) / S); }
  };
  const softPan = () => { const b = SB && SB.body; if (!b) return 0; const c = b.centre(); return Math.max(-1, Math.min(1, c[0] / SB.w * 2 - 1)) * .6; };

  // state: squash springs (sx, sy), a stretch toward the pointer, a lean, and the wobble
  let sx = 1, sy = 1, vsx = 0, vsy = 0, tsx = 1, tsy = 1;
  let st = 0, vst = 0, sdx = 0, sdy = -1; // stretch amount along a direction
  let lean = 0, vlean = 0, wob = 0, glow = 0, glowKind = '', fade = 1;
  let hy = 0, vhy = 0, lastInput = -1e9, nextIdle = performance.now() + 1600, idleCount = 0; // hop height, idle show
  let held = false, ptr = null, start = null, touched = false, idleKick = performance.now() + 3500;
  let visible = true, last = performance.now(), swapAt = 0;

  // sound (WebAudio, made on the fly, starts only after a tap)
  let ac = null, muted = false;
  try { muted = localStorage.getItem('ss-muted') === '1'; } catch (e) {}
  const sndBtn = document.getElementById('snd');
  const setSnd = () => { if (sndBtn) { sndBtn.textContent = muted ? '🔇' : '🔊'; sndBtn.setAttribute('aria-pressed', String(!muted)); } };
  setSnd();
  sndBtn && sndBtn.addEventListener('click', e => { e.stopPropagation(); muted = !muted; setSnd(); if (SB) { SB.audio.unlock(); SB.audio.enabled = !muted; } try { localStorage.setItem('ss-muted', muted ? '1' : '0'); } catch (err) {} });
  window.ssSound = kind => {
    if (muted) return;
    try {
      ac = ac || (SB && SB.audio.ctx) || new (window.AudioContext || window.webkitAudioContext)();
      const t = ac.currentTime;
      if (kind === 'rare' || kind === 'ultra') return fanfare(kind, t);
      const o = ac.createOscillator(), g = ac.createGain();
      const f = { squish: [520, 160, .22], pop: [380, 900, .16], pour: [300, 520, .12], lid: [700, 1100, .1], win: [520, 1040, .35] }[kind] || [400, 200, .2];
      o.type = 'sine'; o.frequency.setValueAtTime(f[0], t); o.frequency.exponentialRampToValueAtTime(f[1], t + f[2]);
      g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(.25, t + .015); g.gain.exponentialRampToValueAtTime(.0001, t + f[2]);
      o.connect(g).connect(ac.destination); o.start(t); o.stop(t + f[2] + .02);
      if (kind === 'squish') { // a little foam under the boop
        const len = ac.sampleRate * .18, buf = ac.createBuffer(1, len, ac.sampleRate), d = buf.getChannelData(0);
        for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * pow(1 - i / len, 2);
        const src = ac.createBufferSource(), lp = ac.createBiquadFilter(), g2 = ac.createGain();
        lp.type = 'lowpass'; lp.frequency.value = 900; g2.gain.value = .18; src.buffer = buf;
        src.connect(lp).connect(g2).connect(ac.destination); src.start(t);
      }
    } catch (e) {}
  };
  // the "you found a rare one" sounds: a sparkly chime for rare, a bigger fanfare for ultra
  function fanfare(kind, t) {
    const tone = (freq, at, dur, type, vol) => {
      const o = ac.createOscillator(), g = ac.createGain();
      o.type = type; o.frequency.setValueAtTime(freq, t + at);
      g.gain.setValueAtTime(.0001, t + at); g.gain.exponentialRampToValueAtTime(vol, t + at + .02); g.gain.exponentialRampToValueAtTime(.0001, t + at + dur);
      o.connect(g).connect(ac.destination); o.start(t + at); o.stop(t + at + dur + .05);
    };
    const notes = kind === 'rare' ? [1047, 1319, 1568, 2093] : [523, 659, 784, 1047, 1319, 1568, 2093];
    const gapT = kind === 'rare' ? .07 : .075;
    notes.forEach((f, i) => { tone(f, i * gapT, kind === 'rare' ? .35 : .5, 'triangle', .16); if (kind === 'ultra') tone(f / 2, i * gapT, .5, 'sine', .08); });
    if (kind === 'ultra') { const end = notes.length * gapT; [1047, 1319, 1568].forEach(f => tone(f, end, 1.1, 'sine', .09)); }
    const dur = kind === 'rare' ? .6 : 1.4, len = ac.sampleRate * dur, buf = ac.createBuffer(1, len, ac.sampleRate), d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * pow(1 - i / len, 3) * (Math.random() < .08 ? 1 : .15);
    const src = ac.createBufferSource(), hp = ac.createBiquadFilter(), g2 = ac.createGain();
    hp.type = 'highpass'; hp.frequency.value = 5000; g2.gain.value = kind === 'rare' ? .12 : .18; src.buffer = buf;
    src.connect(hp).connect(g2).connect(ac.destination); src.start(t + .05);
  }

  // the rarity banner
  const banner = document.createElement('span');
  banner.className = 'rarity-pop'; banner.setAttribute('aria-live', 'polite');
  stage.appendChild(banner);
  function announce(tier) {
    const word = rarityWords[{ rare: 1, ultra: 2, secret: 3 }[tier]];
    if (!word) return;
    banner.textContent = word + '!';
    banner.className = 'rarity-pop ' + tier;
    void banner.offsetWidth; banner.classList.add('show');
  }

  // particles
  const parts = [];
  const STAR = 'M0 -9 L2.6 -2.6 9 0 2.6 2.6 0 9 -2.6 2.6 -9 0 -2.6 -2.6Z', HEART = 'M0 4 C-8 -4 -6 -10 0 -6 C6 -10 8 -4 0 4Z';
  function burst(tier) {
    if (reduce) return;
    const n = tier === 'ultra' || tier === 'secret' ? 36 : tier === 'rare' ? 24 : tier === 'auto' ? 6 : 12, cy = BASE - SIZE * .45;
    for (let i = 0; i < n; i++) {
      const a = Math.random() * TAU, sp = (3 + Math.random() * 5) * (tier === 'common' ? 1 : 1.4);
      const col = tier === 'ultra' ? RAINBOW[i % 5] : tier === 'rare' || tier === 'secret' ? '#FFD86B' : ['#FFD86B', '#FF7EB6', '#7FE0C4'][i % 3];
      const node = i % 3 === 2 && tier === 'common'
        ? el('path', { d: HEART, fill: '#FF7EB6', stroke: '#3B2A4A', 'stroke-width': 2 }, fx)
        : i % 3 === 1 ? el('circle', { r: 5 + Math.random() * 6, fill: col, stroke: '#3B2A4A', 'stroke-width': 2.5 }, fx)
          : el('path', { d: STAR, fill: col, stroke: '#3B2A4A', 'stroke-width': 2 }, fx);
      parts.push({ node, x: CX + Math.cos(a) * 90, y: cy + Math.sin(a) * 90, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 3, life: 1, rot: Math.random() * 360 });
    }
  }

  // the swap: squash down, change squishy at the bottom of the squash, boing back up
  function popNext() {
    if (!upcoming) plan();
    const { tier, id } = upcoming; step++;
    swapTo(id, tier);
    window.ssSound(tier === 'common' ? 'pop' : tier === 'secret' ? 'ultra' : tier);
    plan();
  }
  // the idle show picks from everyone except secrets, quietly, with no banner
  const everyone = [...(tiers.common || []), ...(tiers.rare || []), ...(tiers.ultra || []), 'strawbie'];
  let idleBag = [];
  function idlePop() {
    if (!idleBag.length) idleBag = shuffle(everyone);
    let id = idleBag.pop(); if (id === current) id = idleBag.pop() || 'strawbie';
    if (SB) return swapTo(id, 'auto');
    const im = new Image(); im.src = ART(id);
    tsx = 1.25; tsy = .7; setTimeout(() => { tsx = 1; tsy = 1; swapTo(id, 'auto'); }, reduce ? 0 : 110);
  }
  function swapTo(id, tier) {
    current = id;
    if (SB) softSpawn(id, true);
    [imgA, imgB] = [imgB, imgA];
    imgA.setAttribute('href', ART(id)); fade = 0;
    vsx -= .1; vsy += .22; vlean += (Math.random() - .5) * .25; wob = Math.max(wob, tier === 'common' || tier === 'auto' ? .6 : 1);
    burst(tier);
    if (tier !== 'common' && tier !== 'auto') {
      [...rays.children].forEach((r, i) => r.setAttribute('fill', tier === 'ultra' ? RAINBOW[i % 5] : tier === 'secret' ? (i % 2 ? '#F5B83D' : '#FFE9A8') : i % 2 ? '#FFD86B' : '#FFF1B8'));
      glow = 1; glowKind = tier; announce(tier); vsy += .1;
    }
    const who = stage.querySelector('.who'); if (who) who.textContent = names[id] || '';
  }
  // soft body: let the squish breathe back a moment, then the next squishy plops in
  function letGo() { if (SB) { swapAt = performance.now() + 650; return; } tsx = 1.3; tsy = .66; swapAt = performance.now() + (reduce ? 0 : 70); }

  // input
  const toLocal = e => { const r = svg.getBoundingClientRect(); return [(e.clientX - r.left) * (W / r.width), (e.clientY - r.top) * (H / r.height)]; };
  const contact = e => e.pointerType === 'touch' ? Math.max(e.width || 0, e.height || 0) : 0;
  const softXY = e => { const r = stage.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
  stage.addEventListener('pointerdown', e => {
    if (e.target.closest('.snd')) return;
    if (SB) {
      if (!muted) SB.audio.unlock();
      const q = softXY(e);
      if (!SB.body || !SB.body.grab(e.pointerId, q[0], q[1])) return;
      SB.ptrs[e.pointerId] = e.timeStamp; SB.size0[e.pointerId] = contact(e); SB.grabbed = true; held = true; touched = true; lastInput = performance.now();
      try { stage.setPointerCapture(e.pointerId); } catch (err) {}
      if (!upcoming) plan();
      const h = stage.querySelector('.hint'); if (h) h.style.opacity = 0;
      e.preventDefault(); return;
    }
    held = true; ptr = start = toLocal(e); touched = true; lastInput = performance.now();
    stage.setPointerCapture(e.pointerId);
    tsx = 1.16; tsy = .8; wob = Math.max(wob, .5);
    vlean += (start[0] - CX) / 2400;
    window.ssSound('squish');
    if (!upcoming) plan();
    const h = stage.querySelector('.hint'); if (h) h.style.opacity = 0;
  });
  stage.addEventListener('touchstart', e => { if (SB && SB.grabbed) e.preventDefault(); SB && (SB.grabbed = false); }, { passive: false });
  stage.addEventListener('touchmove', e => { if (SB && Object.keys(SB.ptrs).length) e.preventDefault(); }, { passive: false });
  stage.addEventListener('pointermove', e => {
    if (SB) { const t0 = SB.ptrs[e.pointerId]; if (t0 == null || !SB.body) return; const q = softXY(e), c0 = SB.size0[e.pointerId], c1 = contact(e);
      const force = c0 > 4 && c1 > 4 ? 1 + Math.max(0, Math.min(1.2, (c1 - c0) / Math.max(c0, 20))) * .5 : 1; // a firmer press = a bigger fingertip
      SB.body.move(e.pointerId, q[0], q[1], (e.timeStamp - t0) / 1000, force); SB.ptrs[e.pointerId] = e.timeStamp; return; }
    if (held) ptr = toLocal(e);
  });
  const release = e => {
    if (SB) {
      if (!e || SB.ptrs[e.pointerId] == null) return; delete SB.ptrs[e.pointerId];
      const b = SB.body; if (!b) return;
      const deep = b.metric.D > .05; b.release(e.pointerId);
      if (b.held()) return;
      if (deep && (SB.feel === 'mochi' || SB.feel === 'gel')) SB.audio.pop(Math.min(.3, b.metric.D * 1.6), softPan());
      held = false; lastInput = performance.now(); nextIdle = lastInput + 4500; letGo(); return;
    }
    if (!held) return; held = false; ptr = start = null; lastInput = performance.now(); nextIdle = lastInput + 4500;
    letGo();
  };
  stage.addEventListener('pointerup', release);
  stage.addEventListener('pointercancel', release);
  stage.addEventListener('keydown', e => {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    e.preventDefault(); touched = true; lastInput = nextIdle = performance.now(); nextIdle += 4500; if (!upcoming) plan();
    if (SB && SB.body) { // keyboard: a quick press on the top of the toy
      if (!muted) SB.audio.unlock();
      const b = SB.body, c = b.centre(), bb = b.bounds();
      if (b.grab('key', c[0], bb.y0 + b.S * .06)) setTimeout(() => { b.release('key'); letGo(); }, 260); else letGo();
      return;
    }
    window.ssSound('squish'); letGo();
  });

  // loop
  function frame(now) {
    const dt = Math.min(33, now - last) / 16.67; last = now;
    if (!visible) return requestAnimationFrame(frame);

    if (swapAt && now >= swapAt && !(SB && SB.body && SB.body.held())) { swapAt = 0; tsx = 1; tsy = 1; popNext(); }

    // drag: stretch toward the pointer, squash across it
    let tst = 0;
    if (held && ptr && start) {
      const dx = ptr[0] - start[0], dy = ptr[1] - start[1], d = Math.hypot(dx, dy);
      if (d > 4) { sdx = dx / d; sdy = dy / d; tst = Math.min(.45, d / 360); }
    }
    vst += (tst - st) * .18 * dt; vst *= pow(.78, dt); st += vst * dt;

    // idle show: when nobody is squeezing, it hops, wiggles, squishes itself and turns into someone new
    if (!held && !swapAt && !reduce && visible && now > nextIdle && now - lastInput > 4000) {
      const n = idleCount++ % 6;
      if (SB) {
        if (n === 0) softKick(-2.1, 0); // hop
        else if (n === 2) { softKick(0, .9); setTimeout(() => softKick(0, -1.6), 260); setTimeout(() => softKick(0, .9), 520); } // wiggle
        else if (n % 2 === 1) idlePop();
        else softKick(-1.1, 0); // little bounce
      }
      else if (n === 0) { vhy = 7.5 + Math.random() * 2; tsx = 1.12; tsy = .86; setTimeout(() => { tsx = 1; tsy = 1; }, 120); } // hop
      else if (n === 2) { vlean += .09; setTimeout(() => (vlean -= .16), 260); setTimeout(() => (vlean += .1), 520); wob = Math.max(wob, .4); } // wiggle
      else if (n % 2 === 1) idlePop(); // squish into someone new
      else { vsy -= .12; vsx += .07; wob = Math.max(wob, .5); } // jiggle
      nextIdle = now + 1500 + Math.random() * 900;
    }
    // hop: a little gravity, with a squash on landing
    if (hy > 0 || vhy > 0) {
      vhy -= .55 * dt; hy += vhy * dt;
      if (hy <= 0) { hy = 0; if (vhy < -2) { vsx += .09; vsy -= .16; wob = Math.max(wob, .45); } vhy = 0; }
    }

    if (SB && SB.body) {
      const b = SB.body, dts = Math.min(.05, dt * 16.67 / 1000);
      SB.acc += dts; let n = 0; while (SB.acc >= 1 / 120 && n < 8) { b.step(1 / 120, SB.world); SB.acc -= 1 / 120; n++; } if (n === 8) SB.acc = 0;
      SB.audio.update(dts, b.metric, SB.feel, softPan());
      SB.glr.clear(); SB.glr.draw(b, 1);
      const bb = b.bounds(), fl = SB.world.floor, lift = Math.max(0, fl - bb.y1), sw = (bb.x1 - bb.x0) * Math.max(.5, 1.05 - lift / (b.S * 2)), sh = SB.shade.style;
      sh.width = sw + 'px'; sh.height = sw * .16 + 'px'; sh.left = ((bb.x0 + bb.x1) / 2 - sw / 2) + 'px'; sh.top = (fl - sw * .08) + 'px'; sh.opacity = Math.max(.25, 1 - lift / (b.S * 1.2));
    }
    const breathe = reduce ? 0 : Math.sin(now / 700) * .014;
    vsx += ((tsx - breathe) - sx) * .16 * dt; vsy += ((tsy + breathe) - sy) * .16 * dt;
    vsx *= pow(.8, dt); vsy *= pow(.8, dt); sx += vsx * dt; sy += vsy * dt;
    vlean += -lean * .12 * dt; vlean *= pow(.85, dt); lean += vlean * dt;
    wob = Math.max(0, wob - .02 * dt);
    if (fade < 1) fade = Math.min(1, fade + .12 * dt);

    // matrix: stretch along (sdx, sdy) by st, then squash, lean, anchored at the bottom centre
    const k = st, a11 = 1 + k * sdx * sdx, a12 = k * sdx * sdy, a22 = 1 + k * sdy * sdy;
    const c = Math.cos(lean), s = Math.sin(lean);
    const m11 = sx * a11, m12 = sy * a12, m21 = sx * a12, m22 = sy * a22; // stretch ∘ squash
    const A = c * m11 - s * m21, B = s * m11 + c * m21, C = c * m12 - s * m22, D = s * m12 + c * m22; // then lean
    body.setAttribute('transform', `matrix(${A} ${B} ${C} ${D} ${CX} ${BASE - hy * 5})`);
    imgA.setAttribute('opacity', fade); imgB.setAttribute('opacity', 1 - fade);
    const pop = 1 - fade; imgA.setAttribute('transform', pop ? `scale(${.86 + .14 * fade})` : '');
    if (!reduce) { disp.setAttribute('scale', (wob * 22).toFixed(1)); turb.setAttribute('baseFrequency', (0.010 + 0.004 * Math.sin(now / 300)).toFixed(4)); }
    const lift = Math.max(.55, 1 - hy * 5 / 160);
    shadow.setAttribute('rx', SIZE * .36 * sx * (1 + st * .3) * lift); shadow.setAttribute('opacity', .1 * Math.min(1.3, sx) * lift);

    // rare: golden rays spin behind; ultra: a rainbow ring pulses out too
    if (glow > 0) {
      glow = Math.max(0, glow - .006 * dt);
      const g = ease(glow), cy = BASE - SIZE * .42;
      rays.setAttribute('opacity', g);
      rays.setAttribute('transform', `translate(${CX} ${cy}) rotate(${reduce ? 0 : now / 30 % 360}) scale(${.9 + .15 * Math.sin(now / 200)})`);
      if (glowKind === 'ultra' || glowKind === 'secret') { const ph = (now / 900) % 1; halo.setAttribute('r', 150 * (1 + ph * .6)); halo.setAttribute('opacity', g * (1 - ph)); }
      else halo.setAttribute('opacity', 0);
    } else { rays.setAttribute('opacity', 0); halo.setAttribute('opacity', 0); }

    for (let i = parts.length - 1; i >= 0; i--) {
      const q = parts[i]; q.vy += .25 * dt; q.x += q.vx * dt; q.y += q.vy * dt; q.life -= .018 * dt; q.rot += 6 * dt;
      q.node.setAttribute('transform', `translate(${q.x} ${q.y}) rotate(${q.rot}) scale(${Math.max(0, q.life)})`);
      if (q.life <= 0) { q.node.remove(); parts.splice(i, 1); }
    }
    requestAnimationFrame(frame);
  }
  if (softTry) {
    softLayout(softTry); softSpawn(current, false);
    let rt = 0; addEventListener('resize', () => { clearTimeout(rt); rt = setTimeout(() => { const o = SB || softTry, s0 = o.S; softLayout(o); if (Math.abs(o.S - s0) > s0 * .05) softSpawn(current, false); }, 150); });
  }
  new IntersectionObserver(es => { visible = es[0].isIntersecting; }).observe(stage);
  const who = stage.querySelector('.who'); if (who) who.textContent = names[current] || '';
  requestAnimationFrame(frame);
})();
