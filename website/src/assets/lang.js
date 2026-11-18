// Language menu: a search box that filters the list as you type. Enter opens the first match.
(() => {
  for (const d of document.querySelectorAll('details.lang')) {
    const q = d.querySelector('.lang-q'), items = [...d.querySelectorAll('li[data-s]')];
    if (!q) continue;
    q.hidden = false;
    const norm = s => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
    q.addEventListener('input', () => { const v = norm(q.value.trim()); for (const li of items) li.hidden = !!v && !norm(li.dataset.s).includes(v); });
    q.addEventListener('keydown', e => {
      if (e.key === 'Enter') { const first = items.find(li => !li.hidden); if (first) { e.preventDefault(); location.href = first.querySelector('a').href; } }
      if (e.key === 'Escape') { d.open = false; d.querySelector('summary').focus(); }
    });
    d.addEventListener('toggle', () => { if (d.open) { q.value = ''; items.forEach(li => (li.hidden = false)); if (matchMedia('(hover:hover)').matches) q.focus(); } });
    document.addEventListener('click', e => { if (d.open && !d.contains(e.target)) d.open = false; });
  }
})();
