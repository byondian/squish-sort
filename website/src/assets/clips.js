// Gameplay clips: play muted while on screen, pause when off screen. The button turns sound on for one clip at a time.
(() => {
  const vids = [...document.querySelectorAll('.clip video')];
  if (!vids.length) return;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const io = new IntersectionObserver(es => es.forEach(e => {
    const v = e.target;
    if (e.isIntersecting && !reduce) { v.preload = 'auto'; v.play().catch(() => {}); } else v.pause();
  }), { threshold: 0.4 });
  vids.forEach(v => io.observe(v));
  document.querySelectorAll('.clip .vsnd').forEach(b => b.addEventListener('click', () => {
    const v = b.parentElement.querySelector('video'), on = v.muted;
    vids.forEach(o => { o.muted = true; const ob = o.parentElement.querySelector('.vsnd'); ob.setAttribute('aria-pressed', 'false'); ob.firstChild.textContent = '🔇 '; });
    if (on) { v.muted = false; v.play().catch(() => {}); b.setAttribute('aria-pressed', 'true'); b.firstChild.textContent = '🔊 '; }
  }));
})();
