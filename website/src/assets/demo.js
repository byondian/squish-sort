// Playable browser demo: the first four real levels of the Toy Shop.
// Rules match the app: jars hold 4, tap a jar then another to pour, the
// same-kind run on top pours together, a full jar of one kind gets a lid.
(() => {
  const root = document.getElementById('demo');
  if (!root) return;
  const T = JSON.parse(root.dataset.t);
  const LEVELS = [
    { jars: [['strawbie', 'strawbie', 'strawbie'], ['tango', 'tango', 'tango', 'strawbie'], ['tango']], par: 2 },
    { jars: [['strawbie', 'strawbie', 'tango', 'tango'], ['tango', 'tango', 'strawbie', 'strawbie'], []], par: 3 },
    { jars: [['strawbie', 'sunny', 'sunny', 'blu'], ['sunny', 'blu', 'blu', 'strawbie'], ['blu', 'strawbie', 'strawbie', 'sunny'], [], []], par: 7 },
    { jars: [['sunny', 'sunny', 'sunny', 'tango'], ['tango', 'minty', 'strawbie', 'tango'], ['tango', 'minty', 'minty', 'strawbie'], ['minty', 'strawbie', 'strawbie', 'sunny'], [], []], par: 10 },
  ];
  const CAP = 4;
  const $ = s => root.querySelector(s);
  const jarsEl = $('.jars'), movesEl = $('.moves b'), lvlEl = $('.lvl'), undoBtn = $('.undo'), resetBtn = $('.reset');
  const win = $('.win'), steps = [...root.querySelectorAll('.steps li')];
  let level = 0, jars, sel = -1, moves = 0, history = [], ids = 0, pieceEls = new Map();
  const say = msg => { const live = $('.live'); if (live) live.textContent = msg; };

  function load(n) {
    level = n; sel = -1; moves = 0; history = [];
    jars = LEVELS[n].jars.map(j => j.map(kind => ({ id: ++ids, kind })));
    win.classList.remove('show');
    lvlEl.textContent = T.level.replace('{n}', n + 1);
    steps.forEach((s, i) => { s.className = i < n ? 'ok' : i === n ? 'on' : ''; });
    build(); render();
  }
  function build() {
    jarsEl.innerHTML = ''; pieceEls.clear();
    jars.forEach((_, i) => {
      const b = document.createElement('button');
      b.className = 'jar'; b.type = 'button';
      b.innerHTML = '<span class="glass"></span><span class="lid"></span>';
      b.addEventListener('click', () => tap(i));
      jarsEl.appendChild(b);
    });
  }
  const jarEls = () => [...jarsEl.children];
  const done = j => j.length === CAP && j.every(p => p.kind === j[0].kind);
  const runLen = j => { if (!j.length) return 0; const k = j[j.length - 1].kind; let n = 0; for (let i = j.length - 1; i >= 0 && j[i].kind === k; i--) n++; return n; };

  function render(squished = []) {
    const els = jarEls();
    const seen = new Set();
    jars.forEach((j, ji) => {
      const jarEl = els[ji];
      jarEl.classList.toggle('done', done(j));
      jarEl.classList.toggle('sel', ji === sel);
      const label = j.length ? j.map(p => T.names[p.kind] || p.kind).join(', ') : T.empty;
      jarEl.setAttribute('aria-label', T.jar.replace('{n}', ji + 1) + ': ' + label + (done(j) ? ' (' + T.full + ')' : ''));
      const h = jarEl.clientHeight || 300, size = jarEl.clientWidth * .92;
      const run = ji === sel ? runLen(j) : 0;
      j.forEach((p, pi) => {
        seen.add(p.id);
        let pe = pieceEls.get(p.id);
        if (!pe) {
          pe = document.createElement('span'); pe.className = 'piece';
          pe.innerHTML = `<img src="/assets/sq/${p.kind}.webp" alt="" width="96" height="96">`;
          pieceEls.set(p.id, pe);
        }
        if (pe.parentNode !== jarEl) jarEl.appendChild(pe);
        pe.style.bottom = (8 + pi * (h - 24) / CAP * .985) + 'px';
        pe.style.zIndex = pi + 1;
        pe.classList.toggle('lift', pi >= j.length - run);
        if (squished.includes(p.id)) { pe.classList.remove('squish'); void pe.offsetWidth; pe.classList.add('squish'); }
      });
    });
    for (const [id, pe] of pieceEls) if (!seen.has(id)) { pe.remove(); pieceEls.delete(id); }
    movesEl.textContent = moves;
    undoBtn.disabled = !history.length;
  }

  function tap(i) {
    if (win.classList.contains('show')) return;
    const j = jars[i];
    if (sel < 0) {
      if (!j.length || done(j)) { bump(i); return; }
      sel = i; window.ssSound && window.ssSound('squish'); render(); return;
    }
    if (sel === i) { sel = -1; render(); return; }
    const src = jars[sel];
    const top = src[src.length - 1];
    const dstTop = j[j.length - 1];
    if (j.length >= CAP || (dstTop && dstTop.kind !== top.kind)) { bump(i); sel = -1; render(); return; }
    const n = Math.min(runLen(src), CAP - j.length);
    history.push(jars.map(x => x.slice()));
    const moved = src.splice(src.length - n, n);
    j.push(...moved);
    moves++; sel = -1;
    const nowDone = done(j);
    window.ssSound && window.ssSound(nowDone ? 'lid' : 'pour');
    render(moved.map(p => p.id));
    if (nowDone) { say(T.closed); sparkle(jarEls()[i]); }
    if (jars.every(x => !x.length || done(x))) setTimeout(won, 520);
  }
  function bump(i) { const e = jarEls()[i]; e.classList.remove('bad'); void e.offsetWidth; e.classList.add('bad'); }
  function won() {
    const par = LEVELS[level].par;
    const stars = moves <= par ? 3 : moves <= Math.ceil(par * 1.3) ? 2 : 1;
    steps[level].className = 'ok';
    const last = level === LEVELS.length - 1;
    win.querySelector('.stars').textContent = '★'.repeat(stars) + '☆'.repeat(3 - stars);
    win.querySelector('.stars').setAttribute('aria-label', T.stars.replace('{n}', stars));
    win.querySelector('h3').textContent = last ? T.allDone : T.won;
    win.querySelector('.msg').textContent = last ? T.allDoneMsg : T.wonMsg.replace('{n}', moves).replace('{p}', par);
    win.querySelector('.next').hidden = last;
    win.querySelector('.final-cta').hidden = !last;
    win.classList.add('show');
    window.ssSound && window.ssSound('win');
    confetti();
    say(win.querySelector('h3').textContent);
    (last ? win.querySelector('.final-cta a, .final-cta .soon') : win.querySelector('.next'))?.focus({ preventScroll: true });
  }
  function sparkle(jarEl) {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    for (let k = 0; k < 8; k++) {
      const s = document.createElement('span');
      s.textContent = ['✦', '♥', '✧'][k % 3];
      s.style.cssText = `position:absolute;left:50%;top:0;font-size:20px;color:${['#FFD86B', '#FF7EB6', '#7CC8FF'][k % 3]};pointer-events:none;transition:transform .8s cubic-bezier(.2,.8,.3,1),opacity .8s;z-index:20`;
      jarEl.appendChild(s);
      requestAnimationFrame(() => { const a = (k / 8) * Math.PI * 2; s.style.transform = `translate(${Math.cos(a) * 60}px,${Math.sin(a) * 60 - 30}px) scale(1.4)`; s.style.opacity = 0; });
      setTimeout(() => s.remove(), 900);
    }
  }
  function confetti() {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const box = root.querySelector('.board-wrap');
    const c = document.createElement('div'); c.className = 'confetti'; box.appendChild(c);
    const cols = ['#FF7EB6', '#FFD86B', '#7FE0C4', '#7CC8FF', '#C9B6FF'];
    for (let k = 0; k < 40; k++) {
      const s = document.createElement('i');
      const w = 8 + Math.random() * 8;
      s.style.cssText = `position:absolute;left:${50 + (Math.random() - .5) * 20}%;top:40%;width:${w}px;height:${w * .6}px;border-radius:3px;background:${cols[k % 5]};transition:transform 1.2s cubic-bezier(.15,.7,.3,1),opacity 1.2s`;
      c.appendChild(s);
      requestAnimationFrame(() => { s.style.transform = `translate(${(Math.random() - .5) * 600}px,${(Math.random() - .7) * 400}px) rotate(${Math.random() * 720}deg)`; s.style.opacity = 0; });
    }
    setTimeout(() => c.remove(), 1400);
  }

  undoBtn.addEventListener('click', () => { if (!history.length) return; jars = history.pop(); moves = Math.max(0, moves - 1); sel = -1; render(); });
  resetBtn.addEventListener('click', () => load(level));
  win.querySelector('.next').addEventListener('click', () => load(level + 1));
  win.querySelector('.again').addEventListener('click', () => load(0));
  addEventListener('resize', () => render());
  load(0);
})();

// Collection ribbon and the pile: tap a squishy to squeeze it.
document.addEventListener('click', e => {
  const b = e.target.closest('.sq, .pile img');
  if (!b) return;
  const t = b.classList.contains('sq') ? b : b;
  t.classList.remove('squeeze'); void t.offsetWidth; t.classList.add('squeeze');
  if (b.matches('.pile img')) { b.style.transform = `translateY(-${30 + Math.random() * 30}px) rotate(${(Math.random() - .5) * 40}deg)`; setTimeout(() => (b.style.transform = ''), 350); }
  window.ssSound && window.ssSound('squish');
});
