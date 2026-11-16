// Squishy Shop: grown-up gate, then affiliate links per country.
// Tags live here, not in the app. An empty tag means plain links (no commission).
(() => {
  const SHOPS = {
    GB: { name: 'Amazon.co.uk', base: 'https://www.amazon.co.uk/s?k=', tag: '' },
    US: { name: 'Amazon.com', base: 'https://www.amazon.com/s?k=', tag: '' },
    CA: { name: 'Amazon.ca', base: 'https://www.amazon.ca/s?k=', tag: '' },
    AU: { name: 'Amazon.com.au', base: 'https://www.amazon.com.au/s?k=', tag: '' },
    JP: { name: 'Amazon.co.jp', base: 'https://www.amazon.co.jp/s?k=', tag: '', q: { 'slow-rising': '低反発 スクイーズ', food: 'スクイーズ パン', animal: 'スクイーズ 動物', mochi: 'もちもち スクイーズ ミニ', jumbo: 'ジャンボ スクイーズ', advent: 'スクイーズ アドベントカレンダー', keyring: 'スクイーズ キーホルダー', kit: 'スクイーズ 手作り キット' } },
  };
  const QUERY = { 'slow-rising': 'slow rising squishy', food: 'food squishy toy', animal: 'animal squishy toy', mochi: 'mini mochi squishy pack', jumbo: 'jumbo squishy', advent: 'squishy advent calendar', keyring: 'squishy keychain', kit: 'diy paint your own squishy kit' };
  const PICS = { 'slow-rising': ['peach-bun', '#FFE3EF'], food: ['donut', '#FFF0C2'], animal: ['capy', '#E9DCC9'], mochi: ['mochi-ice', '#E1F1FF'], jumbo: ['panda-dumpling', '#EEE7FF'], advent: ['starry-tree', '#DDF7EE'], keyring: ['pip', '#FFF0C2'], kit: ['sparkle-unicorn', '#FFE3EF'] };
  const box = document.getElementById('shop'), gate = document.getElementById('gate');
  if (!box) return;
  const T = JSON.parse(box.dataset.t);
  const show = () => { gate.hidden = true; box.hidden = false; render(); };
  let ok = false;
  try { ok = sessionStorage.getItem('ss-grownup') === '1'; } catch (e) {}
  if (ok) show();
  document.getElementById('gate-form').addEventListener('submit', e => {
    e.preventDefault();
    const y = parseInt(document.getElementById('gy').value, 10), now = new Date().getFullYear();
    if (y > 1900 && now - y - 1 >= 18) { try { sessionStorage.setItem('ss-grownup', '1'); } catch (err) {} show(); }
    else document.getElementById('gate-msg').textContent = T.gateNo;
  });
  const sel = document.getElementById('shop-country');
  const guess = () => { const l = (navigator.language || '').toUpperCase(); const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || '';
    if (l.startsWith('JA') || tz === 'Asia/Tokyo') return 'JP'; if (tz.startsWith('Australia')) return 'AU'; if (l.endsWith('-CA') || /Toronto|Vancouver|Montreal|Edmonton|Winnipeg|Halifax/.test(tz)) return 'CA';
    if (tz.startsWith('America')) return 'US'; return 'GB'; };
  Object.entries(SHOPS).forEach(([k, v]) => sel.add(new Option(`${v.name}`, k)));
  sel.value = guess();
  sel.addEventListener('change', render);
  function render() {
    const s = SHOPS[sel.value], shelf = document.getElementById('shelf');
    shelf.innerHTML = '';
    for (const [id, name, desc] of T.items) {
      const q = (s.q && s.q[id]) || QUERY[id];
      const url = s.base + encodeURIComponent(q) + (s.tag ? '&tag=' + encodeURIComponent(s.tag) : '');
      const [pic, col] = PICS[id];
      const row = document.createElement('div'); row.className = 'item';
      row.innerHTML = `<span class="pic" style="--c:${col}"><img src="/assets/sq/${pic}.webp" alt="" width="80" height="80"></span><div><h3></h3><p></p><a class="go" rel="sponsored noopener" target="_blank"></a></div>`;
      row.querySelector('h3').textContent = name; row.querySelector('p').textContent = desc;
      const a = row.querySelector('a'); a.href = url; a.textContent = T.go.replace('{shop}', s.name) + ' ↗';
      shelf.appendChild(row);
    }
  }
})();
