// The giant shape-shifting squishy in the hero. Poke it, squeeze it, stretch it.
// Every release turns it into another squishy, like the Morph Squad in the game.
// Plain SVG + springs, no libraries. Pauses when off screen.
(() => {
  const stage = document.getElementById('morph');
  if (!stage) return;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const NS = 'http://www.w3.org/2000/svg';
  const N = 72, CX = 200, CY = 214, R = 128, BASE = CY + R * 0.86;
  const TAU = Math.PI * 2;
  const el = (t, a = {}, p) => { const e = document.createElementNS(NS, t); for (const k in a) e.setAttribute(k, a[k]); if (p) p.appendChild(e); return e; };
  const sgn = Math.sign, abs = Math.abs, pow = Math.pow;
  const gauss = (x, w) => Math.exp(-(x * x) / (2 * w * w));
  const wrap = a => { while (a > Math.PI) a -= TAU; while (a < -Math.PI) a += TAU; return a; };
  const flatBottom = (p, at = 0.74, k = 0.35) => (p[1] > at ? [p[0] * (1 + (p[1] - at) * 0.25), at + (p[1] - at) * k] : p);
  const polar = (t, r) => [Math.sin(t) * r, -Math.cos(t) * r];

  // Unit-space outlines (radius ~1, y down). t = angle from the top, clockwise.
  const SHAPES = [
    { id: 'morphy', fill: '#C9B6FF', sheen: 1, face: { y: .12 }, pt: t => flatBottom(polar(t, .9 + .12 * abs(Math.cos(3.5 * t)))) },
    { id: 'strawbie', fill: '#FF6B7A', face: { y: .05 }, decor: 'leaf', pt: t => { let [x, y] = polar(t, 1); x *= 1.06; y *= .86; if (y > 0) { x *= 1 - .5 * y; y *= 1.08; } return [x * .96, y * .96 + .04]; } },
    { id: 'tango', fill: '#FF9A3C', face: { y: .16, muzzle: '#FFE7CF' }, pt: t => flatBottom(polar(t, 1 + .46 * gauss(wrap(t - .66), .17) + .46 * gauss(wrap(t + .66), .17))) },
    { id: 'grapey', fill: '#A98BF0', face: { y: -.02 }, pt: t => { const s = Math.sin(t), c = Math.cos(t); if (c > 0) return [s, -c * 1.05]; const n = 2 / 5; let x = sgn(s) * pow(abs(s), n) * .98, y = pow(abs(c), n) * .92; y += .08 * Math.sin(t * 7) * pow(abs(c), 2); return [x, y]; } },
    { id: 'lumi', fill: '#FF8FC0', face: { y: .2 }, pt: t => flatBottom(polar(t, .95 + .8 * gauss(wrap(t - .3), .085) + .8 * gauss(wrap(t + .3), .085))) },
    { id: 'centre-star', fill: '#A6E07A', face: { y: .06 }, pt: t => polar(t, .78 + .34 * pow((Math.cos(5 * t) + 1) / 2, 1.6)) },
    { id: 'peach-bun', fill: '#FFAE8A', face: { y: .14 }, decor: 'peach', pt: t => flatBottom(polar(t, 1 + .24 * pow(Math.max(0, Math.cos(t)), 14))) },
    { id: 'dino-rex', fill: '#6FD6B0', face: { y: .16 }, pt: t => flatBottom(polar(t, 1 + (abs(t) < 1.15 ? .17 * pow(Math.max(0, Math.cos(8 * t)), 3) : 0))) },
    { id: 'jelly', fill: '#FF5E7A', face: { y: .1 }, pt: t => { const s = Math.sin(t), c = Math.cos(t), n = 2 / 4.5; let x = sgn(s) * pow(abs(s), n) * .9, y = -sgn(c) * pow(abs(c), n) * .9; x *= 1 - .08 * Math.min(0, y); return [x, y + .02]; } },
    { id: 'gloop', fill: '#FF9EC9', face: { y: .1 }, pt: t => flatBottom(polar(t, 1)) },
  ];
  const names = JSON.parse(stage.dataset.names || '{}');
  const ANG = Array.from({ length: N }, (_, i) => (i / N) * TAU);
  for (const s of SHAPES) s.pts = ANG.map(t => s.pt(t));

  // DOM
  const svg = el('svg', { viewBox: '0 0 400 420', 'aria-hidden': 'true' }, stage);
  const defs = el('defs', {}, svg);
  const shine = el('radialGradient', { id: 'mshine', cx: '.34', cy: '.26', r: '.75' }, defs);
  el('stop', { offset: '0', 'stop-color': '#fff', 'stop-opacity': '.8' }, shine);
  el('stop', { offset: '.42', 'stop-color': '#fff', 'stop-opacity': '0' }, shine);
  const rb = el('linearGradient', { id: 'mrainbow', x1: '0', y1: '0', x2: '1', y2: '1' }, defs);
  ['#FF9CC8', '#FFD86B', '#7FE0C4', '#7CC8FF', '#B48CFF'].forEach((c, i) => el('stop', { offset: i / 4, 'stop-color': c }, rb));
  const shadow = el('ellipse', { cx: CX, cy: BASE + 12, rx: R * .9, ry: 14, fill: '#3B2A4A', opacity: '.1' }, svg);
  const body = el('path', { stroke: '#3B2A4A', 'stroke-width': 9, 'stroke-linejoin': 'round' }, svg);
  const sheen = el('path', { fill: 'url(#mrainbow)', opacity: 0 }, svg);
  const gloss = el('path', { fill: 'url(#mshine)' }, svg);
  const decor = el('g', {}, svg);
  const face = el('g', {}, svg);
  const blushL = el('ellipse', { rx: 17, ry: 10, fill: '#FF7EB6', opacity: '.5' }, face);
  const blushR = el('ellipse', { rx: 17, ry: 10, fill: '#FF7EB6', opacity: '.5' }, face);
  const muzzle = el('ellipse', { rx: 40, ry: 26, fill: '#FFE7CF', opacity: 0 }, face);
  const eyeL = el('g', {}, face), eyeR = el('g', {}, face);
  const mkEye = g => ({ ball: el('ellipse', { rx: 13, ry: 14, fill: '#3B2A4A' }, g), hi: el('circle', { r: 5, fill: '#fff' }, g), hi2: el('circle', { r: 2.2, fill: '#fff' }, g), x: el('path', { d: 'M-12 -10 L8 0 L-12 10', fill: 'none', stroke: '#3B2A4A', 'stroke-width': 7, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', opacity: 0 }, g) });
  const EL = mkEye(eyeL), ER = mkEye(eyeR);
  ER.x.setAttribute('d', 'M12 -10 L-8 0 L12 10');
  const mouth = el('path', { fill: '#FF6B7A', stroke: '#3B2A4A', 'stroke-width': 6, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }, face);
  const fx = el('g', {}, svg);

  const DECOR = {
    leaf: '<path d="M-38 -8 q16 -34 38 -14 q22 -20 38 14 q-19 14 -38 2 q-19 12 -38 -2Z" fill="#6FCF8E" stroke="#3B2A4A" stroke-width="8" stroke-linejoin="round"/><path d="M0 -20 v-26" stroke="#3B2A4A" stroke-width="8" stroke-linecap="round"/>',
    peach: '<path d="M6 -6 q24 -30 52 -12 q-22 22 -52 12Z" fill="#7FD48E" stroke="#3B2A4A" stroke-width="7" stroke-linejoin="round"/>',
  };

  // state
  let cur = 0, from = 0, to = 0, mt = 1;
  const disp = new Float32Array(N), vel = new Float32Array(N), pull = new Float32Array(N);
  let sx = 1, sy = 1, vsx = 0, vsy = 0, tsx = 1, tsy = 1;
  let held = false, heldAt = 0, ptr = null, look = [0, 0], blinkAt = performance.now() + 2500, blink = 0, squeezeFace = 0;
  let visible = true, last = performance.now(), touched = false, idleKick = performance.now() + 4000;

  const ease = x => (x < .5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2);
  const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  const mix = (a, b, k) => { const A = hex(a), B = hex(b); return '#' + A.map((v, i) => Math.round(v + (B[i] - v) * k).toString(16).padStart(2, '0')).join(''); };

  function outline() {
    const A = SHAPES[from].pts, B = SHAPES[to].pts, k = ease(mt);
    const out = new Array(N);
    for (let i = 0; i < N; i++) {
      let x = A[i][0] + (B[i][0] - A[i][0]) * k, y = A[i][1] + (B[i][1] - A[i][1]) * k;
      const len = Math.hypot(x, y) || 1, d = (disp[i] + pull[i]) / R;
      x += (x / len) * d; y += (y / len) * d;
      let px = CX + x * R, py = CY + y * R;
      px = CX + (px - CX) * sx; py = BASE - (BASE - py) * sy;
      out[i] = [px, py];
    }
    return out;
  }
  function pathOf(p, s = 1, ox = 0, oy = 0) {
    const n = p.length, q = i => p[(i + n) % n];
    let d = `M${(q(0)[0] - CX) * s + CX + ox} ${(q(0)[1] - CY) * s + CY + oy}`;
    for (let i = 0; i < n; i++) {
      const p0 = q(i - 1), p1 = q(i), p2 = q(i + 1), p3 = q(i + 2);
      const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6], c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
      const T = v => [((v[0] - CX) * s + CX + ox).toFixed(1), ((v[1] - CY) * s + CY + oy).toFixed(1)];
      d += `C${T(c1)} ${T(c2)} ${T(p2)}`;
    }
    return d + 'Z';
  }

  // sound (WebAudio, made on the fly, starts only after a tap)
  let ac = null, muted = false;
  try { muted = localStorage.getItem('ss-muted') === '1'; } catch (e) {}
  const sndBtn = document.getElementById('snd');
  const setSnd = () => { if (sndBtn) { sndBtn.textContent = muted ? '🔇' : '🔊'; sndBtn.setAttribute('aria-pressed', String(!muted)); } };
  setSnd();
  sndBtn && sndBtn.addEventListener('click', e => { e.stopPropagation(); muted = !muted; setSnd(); try { localStorage.setItem('ss-muted', muted ? '1' : '0'); } catch (err) {} });
  window.ssSound = kind => {
    if (muted) return;
    try {
      ac = ac || new (window.AudioContext || window.webkitAudioContext)();
      const t = ac.currentTime, o = ac.createOscillator(), g = ac.createGain();
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

  // particles
  const parts = [];
  function burst(color) {
    if (reduce) return;
    for (let i = 0; i < 14; i++) {
      const a = Math.random() * TAU, sp = 3 + Math.random() * 5;
      const kind = i % 3;
      const node = kind === 0
        ? el('path', { d: 'M0 -9 L2.6 -2.6 9 0 2.6 2.6 0 9 -2.6 2.6 -9 0 -2.6 -2.6Z', fill: '#FFD86B', stroke: '#3B2A4A', 'stroke-width': 2 }, fx)
        : kind === 1 ? el('circle', { r: 6 + Math.random() * 6, fill: color, stroke: '#3B2A4A', 'stroke-width': 2.5 }, fx)
          : el('path', { d: 'M0 4 C-8 -4 -6 -10 0 -6 C6 -10 8 -4 0 4Z', fill: '#FF7EB6', stroke: '#3B2A4A', 'stroke-width': 2 }, fx);
      parts.push({ node, x: CX + Math.cos(a) * 80, y: CY + Math.sin(a) * 80, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 3, life: 1, rot: Math.random() * 360 });
    }
  }

  function morphNext() {
    from = to; to = (to + 1) % SHAPES.length; mt = 0;
    const s = SHAPES[to];
    burst(s.fill);
    vsx += .05; vsy -= .09; // boing
    for (let i = 0; i < N; i++) vel[i] += (Math.random() - .5) * 60;
    const who = stage.querySelector('.who');
    if (who) who.textContent = names[s.id] || '';
    window.ssSound('pop');
  }

  // input
  const toLocal = e => { const r = svg.getBoundingClientRect(); return [(e.clientX - r.left) * (400 / r.width), (e.clientY - r.top) * (420 / r.height)]; };
  function poke(p, strength) {
    const a = Math.atan2(p[0] - CX, -(p[1] - CY));
    for (let i = 0; i < N; i++) { const da = wrap(ANG[i] - a); vel[i] -= strength * gauss(da, .45); }
  }
  stage.addEventListener('pointerdown', e => {
    if (e.target.closest('.snd')) return;
    held = true; heldAt = performance.now(); ptr = toLocal(e); touched = true;
    stage.setPointerCapture(e.pointerId);
    poke(ptr, 260); tsx = 1.14; tsy = .84; squeezeFace = 1;
    window.ssSound('squish');
    const h = stage.querySelector('.hint'); if (h) h.style.opacity = 0;
  });
  stage.addEventListener('pointermove', e => { const p = toLocal(e); look = [(p[0] - CX) / 200, (p[1] - CY) / 200]; if (held) ptr = p; });
  const release = () => {
    if (!held) return; held = false; ptr = null; tsx = 1; tsy = 1; squeezeFace = 0;
    pull.fill(0); vsx -= .08; vsy += .14;
    morphNext();
  };
  stage.addEventListener('pointerup', release);
  stage.addEventListener('pointercancel', release);
  stage.addEventListener('keydown', e => {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    e.preventDefault(); poke([CX, CY - R], 260); vsx += .1; vsy -= .16; touched = true; morphNext();
  });

  // loop
  function frame(now) {
    const dt = Math.min(33, now - last) / 16.67; last = now;
    if (!visible) return requestAnimationFrame(frame);
    if (mt < 1) mt = Math.min(1, mt + .045 * dt);

    // drag stretch: points facing the pointer reach for it
    if (held && ptr) {
      const a = Math.atan2(ptr[0] - CX, -(ptr[1] - CY));
      const dist = Math.hypot(ptr[0] - CX, ptr[1] - CY);
      const over = Math.max(0, Math.min(90, dist - R * .9));
      for (let i = 0; i < N; i++) pull[i] += ((over * .8 * gauss(wrap(ANG[i] - a), .38)) - pull[i]) * .2 * dt;
    }
    // idle wobble invites a poke
    if (!touched && !reduce && now > idleKick) { idleKick = now + 3500; poke([CX + 60, CY - R], 120); vsy -= .05; }

    // jelly springs: each point springs home and to its neighbours
    const k = .09, damp = .86, nb = .22;
    for (let i = 0; i < N; i++) {
      const l = disp[(i - 1 + N) % N], r = disp[(i + 1) % N];
      vel[i] += (-k * disp[i] + nb * (l + r - 2 * disp[i])) * dt;
    }
    for (let i = 0; i < N; i++) { vel[i] *= pow(damp, dt); disp[i] += vel[i] * .06 * dt; }
    const breathe = reduce ? 0 : Math.sin(now / 700) * .012;
    vsx += ((tsx - breathe) - sx) * .16 * dt; vsy += ((tsy + breathe) - sy) * .16 * dt;
    vsx *= pow(.8, dt); vsy *= pow(.8, dt); sx += vsx * dt; sy += vsy * dt;

    const p = outline();
    const d = pathOf(p);
    const sA = SHAPES[from], sB = SHAPES[to], k2 = ease(mt);
    body.setAttribute('d', d); body.setAttribute('fill', mix(sA.fill, sB.fill, k2));
    sheen.setAttribute('d', d); sheen.setAttribute('opacity', ((sA.sheen || 0) * (1 - k2) + (sB.sheen || 0) * k2) * .45);
    gloss.setAttribute('d', d);
    shadow.setAttribute('rx', R * .95 * sx);

    // face rides on the squash
    const fy = (sA.face.y + (sB.face.y - sA.face.y) * k2);
    const fcx = CX + look[0] * 10, fcy = BASE - (BASE - (CY + fy * R)) * sy + look[1] * 6;
    const gap = 42 * sx;
    if (now > blinkAt) { blink = 1; if (now > blinkAt + 120) { blink = 0; blinkAt = now + 2200 + Math.random() * 3000; } }
    for (const [g, E, side] of [[eyeL, EL, -1], [eyeR, ER, 1]]) {
      g.setAttribute('transform', `translate(${fcx + side * gap} ${fcy - 6}) scale(1 ${blink ? .12 : 1})`);
      E.ball.setAttribute('opacity', squeezeFace ? 0 : 1); E.hi.setAttribute('opacity', squeezeFace ? 0 : 1); E.hi2.setAttribute('opacity', squeezeFace ? 0 : 1);
      E.x.setAttribute('opacity', squeezeFace ? 1 : 0);
      E.hi.setAttribute('cx', -4 + look[0] * 3); E.hi.setAttribute('cy', -5 + look[1] * 3); E.hi2.setAttribute('cx', 5); E.hi2.setAttribute('cy', 4);
    }
    blushL.setAttribute('cx', fcx - gap - 22); blushL.setAttribute('cy', fcy + 18);
    blushR.setAttribute('cx', fcx + gap + 22); blushR.setAttribute('cy', fcy + 18);
    const mz = (sA.face.muzzle ? 1 - k2 : 0) + (sB.face.muzzle ? k2 : 0);
    muzzle.setAttribute('cx', fcx); muzzle.setAttribute('cy', fcy + 24); muzzle.setAttribute('opacity', mz);
    mouth.setAttribute('d', squeezeFace
      ? `M${fcx - 14} ${fcy + 16} q14 26 28 0 Z`
      : `M${fcx - 12} ${fcy + 18} q12 14 24 0`);
    mouth.setAttribute('fill', squeezeFace ? '#FF6B7A' : 'none');

    // decor fades with the morph
    const topY = Math.min(...p.map(v => v[1]));
    let html = '';
    if (sA.decor && k2 < 1) html += `<g opacity="${1 - k2}" transform="translate(${CX} ${topY + 16})">${DECOR[sA.decor]}</g>`;
    if (sB.decor) html += `<g opacity="${k2}" transform="translate(${CX} ${topY + 16})">${DECOR[sB.decor]}</g>`;
    decor.innerHTML = html;

    for (let i = parts.length - 1; i >= 0; i--) {
      const q = parts[i]; q.vy += .25 * dt; q.x += q.vx * dt; q.y += q.vy * dt; q.life -= .018 * dt; q.rot += 6 * dt;
      q.node.setAttribute('transform', `translate(${q.x} ${q.y}) rotate(${q.rot}) scale(${Math.max(0, q.life)})`);
      if (q.life <= 0) { q.node.remove(); parts.splice(i, 1); }
    }
    requestAnimationFrame(frame);
  }
  new IntersectionObserver(es => { visible = es[0].isIntersecting; }).observe(stage);
  const who = stage.querySelector('.who'); if (who) who.textContent = names[SHAPES[0].id] || '';
  requestAnimationFrame(frame);
})();
