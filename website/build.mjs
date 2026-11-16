// Static site builder for squishsort.app. No dependencies: `node build.mjs`.
// Reads src/, writes dist/. Pages: landing, demo, legal set, support, shop,
// in English, Japanese, Korean and Traditional Chinese.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SITE } from './src/site.mjs';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const SRC = path.join(ROOT, 'src'), OUT = path.join(ROOT, 'dist');
const roster = JSON.parse(fs.readFileSync(path.join(SRC, 'roster.json'), 'utf8'));
const T = {};
for (const l of SITE.langs) T[l.code] = (await import(`./src/i18n/${l.code}.mjs`)).default;

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });
fs.cpSync(path.join(SRC, 'assets'), path.join(OUT, 'assets'), { recursive: true });
fs.cpSync(path.join(SRC, 'static'), OUT, { recursive: true });

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const L = code => SITE.langs.find(l => l.code === code);
const href = (code, slug = '') => '/' + [L(code).path, slug].filter(Boolean).join('/') + (slug || L(code).path ? '' : '');
const write = (rel, html) => { const f = path.join(OUT, rel); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, html); };
const pageFile = (code, slug) => path.join(L(code).path, slug, 'index.html');

// ---------- tiny markdown ----------
function inline(s) {
  return esc(s)
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (m, t, u) => `<a href="${u}"${/^https?:/.test(u) ? ' rel="noopener"' : ''}>${t}</a>`)
    .replace(/(^|[\s(])((?:support|privacy)@squishsort\.app)/g, '$1<a href="mailto:$2">$2</a>');
}
function md(src, vars) {
  src = src.replace(/\{\{(\w+)\}\}/g, (m, k) => (k in vars ? vars[k] : m));
  const lines = src.split('\n');
  let html = '', i = 0, toc = [];
  const slugify = s => s.toLowerCase().replace(/<[^>]+>/g, '').replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-|-$/g, '').slice(0, 60);
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }
    let m;
    if ((m = line.match(/^:::(\w+)/))) {
      const cls = m[1], body = [];
      i++;
      while (i < lines.length && !lines[i].startsWith(':::')) body.push(lines[i++]);
      i++;
      html += `<div class="${cls}">${md(body.join('\n'), vars).html}</div>`;
      continue;
    }
    if ((m = line.match(/^(#{2,3}) (.+?)(?: \{#([\w-]+)\})?$/))) {
      const id = m[3] || slugify(m[2]);
      if (m[1] === '##') toc.push([id, m[2]]);
      html += `<h${m[1].length} id="${id}">${inline(m[2])}</h${m[1].length}>`; i++; continue;
    }
    if (line.startsWith('<')) { html += line; i++; continue; }
    if (/^\|/.test(line)) {
      const rows = [];
      while (i < lines.length && /^\|/.test(lines[i])) rows.push(lines[i++]);
      const cells = r => r.replace(/^\||\|$/g, '').split('|').map(c => c.trim());
      const head = cells(rows[0]);
      html += '<table><thead><tr>' + head.map(c => `<th scope="col">${inline(c)}</th>`).join('') + '</tr></thead><tbody>';
      for (const r of rows.slice(2)) html += '<tr>' + cells(r).map(c => `<td>${inline(c)}</td>`).join('') + '</tr>';
      html += '</tbody></table>';
      continue;
    }
    if (/^(- |\d+\. )/.test(line)) {
      const ordered = /^\d+\. /.test(line), items = [];
      while (i < lines.length && /^(- |\d+\. |  )/.test(lines[i])) {
        if (/^  /.test(lines[i]) && items.length) items[items.length - 1] += ' ' + lines[i].trim();
        else items.push(lines[i].replace(/^(- |\d+\. )/, ''));
        i++;
      }
      const tag = ordered ? 'ol' : 'ul';
      html += `<${tag}>` + items.map(it => `<li>${inline(it)}</li>`).join('') + `</${tag}>`;
      continue;
    }
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^(#|- |\d+\. |\||:::|<)/.test(lines[i])) para.push(lines[i++]);
    html += `<p>${inline(para.join(' '))}</p>`;
  }
  return { html, toc };
}
function readDoc(code, slug) {
  const f = path.join(SRC, 'legal', code, slug + '.md');
  const raw = fs.readFileSync(f, 'utf8');
  const m = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  const meta = {};
  for (const l of m[1].split('\n')) { const k = l.indexOf(':'); meta[l.slice(0, k).trim()] = l.slice(k + 1).trim(); }
  return { meta, body: m[2] };
}

// ---------- chrome ----------
function storeCta(code, from, big = false) {
  const t = T[code];
  if (!SITE.APP_LIVE) return `<span class="soon" role="note">${esc(t.cta.soon)}<small>${esc(t.cta.soonSmall)}</small></span>`;
  return `<a class="store${big ? ' big' : ''}" href="/go/app-store?from=${from}-${code}"><img src="https://tools.applemarketingtools.com/api/badges/download-on-the-app-store/black/${L(code).badge}?size=250x83" alt="${esc(t.cta.badgeAlt)}" width="191" height="64"></a>`;
}
function head(code, { title, description, slug = '', noindex = false }) {
  const alts = SITE.langs.map(l => `<link rel="alternate" hreflang="${l.html}" href="${SITE.origin}${href(l.code, slug)}">`).join('')
    + `<link rel="alternate" hreflang="x-default" href="${SITE.origin}${href('en', slug)}">`;
  return `<!doctype html><html lang="${L(code).html}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${esc(title)}</title><meta name="description" content="${esc(description)}">
<link rel="canonical" href="${SITE.origin}${href(code, slug)}">${alts}
<meta name="theme-color" content="#FFF4E8">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}">
<meta property="og:type" content="website"><meta property="og:url" content="${SITE.origin}${href(code, slug)}">
<meta property="og:image" content="${SITE.origin}/assets/img/og.png"><meta name="twitter:card" content="summary_large_image">
${SITE.APP_LIVE ? `<meta name="apple-itunes-app" content="app-id=${SITE.appStoreId}">` : ''}
${noindex ? '<meta name="robots" content="noindex">' : ''}
<link rel="icon" href="/assets/img/icon-32.png" sizes="32x32"><link rel="apple-touch-icon" href="/assets/img/icon-180.png">
<link rel="preload" href="/assets/fonts/fredoka-latin-wght-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/assets/site.css">
<script defer src="/_vercel/insights/script.js"></script>
</head><body>`;
}
function bar(code, slug = '') {
  const t = T[code];
  const langs = SITE.langs.map(l => `<li><a href="${href(l.code, slug)}" hreflang="${l.html}" lang="${l.html}"${l.code === code ? ' aria-current="true"' : ''}>${l.label}</a></li>`).join('');
  return `<a class="skip" href="#main">${esc(t.skip)}</a>
<header class="bar"><a class="brand" href="${href(code)}"><img src="/assets/img/icon-180.png" alt="" width="36" height="36">Squish Sort</a>
<nav aria-label="Main"><a class="hide-s" href="${href(code)}#play">${esc(t.nav.demo)}</a><a class="hide-s" href="${href(code, 'parents')}">${esc(t.nav.parents)}</a><a href="${href(code, 'support')}">${esc(t.nav.support)}</a>
<details class="lang"><summary aria-label="${esc(t.nav.language)}">🌐 ${L(code).label}</summary><ul>${langs}</ul></details></nav></header>`;
}
function footer(code) {
  const t = T[code];
  const legal = SITE.legalPages.map(s => `<li><a href="${href(code, s)}">${esc(t.legalNames[s][0])}</a></li>`).join('');
  return `<footer><div class="foot">
<div><h4>${esc(t.footer.game)}</h4><ul style="columns:1"><li><a href="${href(code)}">${esc(t.footer.links.home)}</a></li><li><a href="${href(code)}#play">${esc(t.footer.links.demo)}</a></li><li><a href="${href(code, 'support')}">${esc(t.footer.links.support)}</a></li><li><a href="${href(code, 'shop')}">${esc(t.footer.links.shop)}</a></li></ul></div>
<div><h4>${esc(t.footer.legal)}</h4><ul>${legal}<li><a href="${href(code, 'legal')}">${esc(t.footer.links.legalHub)}</a></li></ul></div>
</div><p class="fine">${esc(t.footer.fine)}</p></footer>`;
}
const end = scripts => `${scripts || ''}</body></html>`;

// ---------- landing ----------
const PALETTE = { common: '#7FE0C4', rare: '#7CC8FF', ultra: '#C9B6FF', secret: '#FFD86B' };
const waveTo = (fill, flip = false) => `<svg class="wave" viewBox="0 0 1440 80" preserveAspectRatio="none" aria-hidden="true"${flip ? ' style="transform:scaleY(-1)"' : ''}><path d="M0 40 C240 90 480 0 720 30 C960 60 1200 10 1440 40 V80 H0Z" fill="${fill}"/></svg>`;

function landing(code) {
  const t = T[code];
  const nm = c => (c.names && c.names[L(code).html]) || c.name;
  const heroTiers = ['common', 'rare', 'ultra', 'secret'].reduce((o, r) => (o[r] = roster.collectibles.filter(c => c.rarity === r).map(c => c.id), o), {});
  const names = Object.fromEntries([...roster.collectibles, ...roster.squishRoomToys].map(c => [c.id, nm(c)]));
  const feels = Object.fromEntries([...roster.collectibles, ...roster.squishRoomToys].filter(c => c.feel && c.feel !== 'foam').map(c => [c.id, c.feel]));
  const all = roster.collectibles.filter(c => c.rarity !== 'secret');
  const half = Math.ceil(all.length / 2);
  const sq = c => `<button class="sq" type="button" aria-label="${esc(nm(c))}"><img src="/assets/sq/${c.id}.webp" alt="" width="118" height="118" loading="lazy"><span class="nm">${esc(nm(c))}</span></button>`;
  const row = list => `<div class="ribbon"><div class="track">${list.map(sq).join('')}${list.map(sq).join('').replace(/<button /g, '<button aria-hidden="true" tabindex="-1" ')}</div></div>`;
  const demoT = { ...t.demo, names };
  const worldsImg = ['dino-rex', 'donut', 'lightstick-lamb', 'reindeer'];
  const worldsCol = ['#FFE3EF', '#FFF0C2', '#EEE7FF', '#DDF7EE'];
  const pile = ['strawbie', 'capy', 'axo', 'sparkle-unicorn', 'peach-bun', 'panda-dumpling', 'gummy-bear', 'snowbo', 'tango'];
  return head(code, { title: t.meta.title, description: t.meta.description }) + bar(code) + `
<main id="main">
<section class="hero">
  <div class="bg-blob" style="width:420px;height:420px;background:#FFC7DE;left:-120px;top:40px"></div>
  <div class="bg-blob" style="width:360px;height:360px;background:#CDEBFF;right:-80px;top:260px;animation-delay:-5s"></div>
  <div class="bg-blob" style="width:300px;height:300px;background:#FFF0B8;left:40%;bottom:-60px;animation-delay:-9s"></div>
  <div>
    <h1><span class="s">${esc(t.hero.words[0])}</span> <span class="s">${esc(t.hero.words[1])}</span></h1>
    <p class="tag">${esc(t.hero.tag)}</p>
    <div class="cta-row">${storeCta(code, 'hero')}<a class="btn soft" href="#play">▶ ${esc(t.cta.demo)}</a></div>
    <p class="sub">${esc(t.hero.sub)}</p>
  </div>
  <div class="stage" id="morph" tabindex="0" role="button" aria-label="${esc(t.hero.stageLabel)}" data-names='${esc(JSON.stringify(names))}' data-rarity='${esc(JSON.stringify(t.collect.rarity))}' data-tiers='${esc(JSON.stringify(heroTiers))}' data-feels='${esc(JSON.stringify(feels))}'>
    <span class="who" aria-live="polite"></span>
    <button class="snd" id="snd" type="button" aria-label="${esc(t.hero.sound)}" aria-pressed="true">🔊</button>
    <span class="hint">👆 ${esc(t.hero.hint)}</span>
  </div>
</section>
${waveTo('#FFE3EF')}
<section class="band pink" id="play">
  <p class="kicker">${esc(t.demo.kicker)}</p><h2>${esc(t.demo.title)}</h2>
  <div class="demo" id="demo" data-t='${esc(JSON.stringify(demoT))}'>
    <div class="board-wrap">
      <div class="board-top"><span class="lvl"></span><span class="moves">${esc(t.demo.moves)}: <b>0</b></span>
        <button class="iconbtn undo" type="button" aria-label="${esc(t.demo.undo)}" title="${esc(t.demo.undo)}">↶</button>
        <button class="iconbtn reset" type="button" aria-label="${esc(t.demo.reset)}" title="${esc(t.demo.reset)}">↻</button></div>
      <div class="jars"></div>
      <p class="live sr" aria-live="polite"></p>
      <div class="win" role="dialog" aria-modal="false" aria-labelledby="win-h">
        <div class="stars"></div><h3 id="win-h"></h3><p class="msg"></p>
        <button class="btn next" type="button">${esc(t.demo.next)} →</button>
        <div class="final-cta cta-row" hidden style="justify-content:center">${storeCta(code, 'demo', true)}<button class="btn soft again" type="button">${esc(t.demo.again)}</button></div>
      </div>
    </div>
    <div class="side"><h3>${esc(t.demo.sideTitle)}</h3><ol class="steps">${[1, 2, 3, 4].map(n => `<li>${n}</li>`).join('')}</ol>
      <p class="lede">${esc(t.demo.lede)}</p><ul class="howto">${t.demo.howto.map(h => `<li>${esc(h)}</li>`).join('')}</ul></div>
  </div>
</section>
${waveTo('#FFE3EF', true)}
<section class="band" id="squishies">
  <p class="kicker">${esc(t.collect.kicker)}</p><h2>${esc(t.collect.title)}</h2><p class="lede">${esc(t.collect.lede)}</p>
  ${row(all.slice(0, half))}${row(all.slice(half))}
  <p class="rarity">${t.collect.rarity.map((r, i) => `<span style="--c:${Object.values(PALETTE)[i]}">${esc(r)}</span>`).join('')} <a href="${href(code, 'purchases')}#drop">${esc(t.collect.oddsLink)} →</a></p>
</section>
${waveTo('#EEE7FF')}
<section class="band grape">
  <p class="kicker">${esc(t.worlds.kicker)}</p><h2>${esc(t.worlds.title)}</h2>
  <div class="path">
    <svg class="road" viewBox="0 0 100 400" preserveAspectRatio="none" aria-hidden="true"><path d="M20 20 C90 60 90 110 50 140 S10 230 50 260 S90 340 80 390" fill="none" stroke="#fff" stroke-width="3" stroke-dasharray="1 3" stroke-linecap="round" vector-effect="non-scaling-stroke" style="stroke-width:10px"/></svg>
    ${t.worlds.list.map(([n, d], i) => `<div class="stop"><div class="disc" style="--c:${worldsCol[i]}"><img src="/assets/sq/${worldsImg[i]}.webp" alt="" width="110" height="110" loading="lazy"></div><div><h3>${esc(n)}${i === 3 ? ` <span class="badge">${esc(t.worlds.xmasBadge)}</span>` : ''}</h3><p>${esc(d)}</p></div></div>`).join('')}
  </div>
</section>
${waveTo('#EEE7FF', true)}
<section class="band">
  <p class="kicker">${esc(t.extras.kicker)}</p><h2>${esc(t.extras.title)}</h2>
  <div class="promises">${t.extras.list.map(([e, h, p]) => `<div class="promise"><span class="dot" aria-hidden="true">${e}</span><div><h3>${esc(h)}</h3><p>${esc(p)}</p></div></div>`).join('')}</div>
</section>
${waveTo('#DDF7EE')}
<section class="band mint">
  <p class="kicker">${esc(t.promise.kicker)}</p><h2>${esc(t.promise.title)}</h2>
  <div class="promises">${t.promise.list.map(([e, h, p]) => `<div class="promise"><span class="dot" aria-hidden="true">${e}</span><div><h3>${esc(h)}</h3><p>${esc(p)}</p></div></div>`).join('')}</div>
  <p style="margin-top:22px"><a class="btn soft" href="${href(code, 'parents')}">${esc(t.promise.link)} →</a></p>
</section>
${waveTo('#DDF7EE', true)}
<section class="final">
  <div class="pile" aria-hidden="true">${pile.map((id, i) => `<img src="/assets/sq/${id}.webp" alt="" width="110" height="110" loading="lazy" style="left:${4 + i * 10.5}%;bottom:${[0, 40, 6, 70, 0, 36, 8, 60, 2][i]}px;transform:rotate(${[-8, 6, -3, 10, 4, -10, 7, -5, 9][i]}deg)">`).join('')}</div>
  <h2>${esc(t.final.title)}</h2><p class="lede" style="margin:0 auto 22px">${esc(t.final.text)}</p>
  <div class="cta-row" style="justify-content:center">${storeCta(code, 'footer', true)}</div>
</section>
</main>` + footer(code) + end('<script src="/assets/squish/squish-engine.js" defer></script><script src="/assets/squish/squish-audio.js" defer></script><script src="/assets/morph.js" defer></script><script src="/assets/demo.js" defer></script>');
}

// ---------- documents ----------
function vars(code) {
  const t = T[code], o = SITE.operator;
  return {
    operator: o.name, country: ({ ja: 'ルクセンブルク', ko: '룩셈부르크', 'zh-hant': '盧森堡' })[code] || o.country,
    postal: o.postal || t.doc.onRequest, phone: o.phone || t.doc.onRequest,
    support: SITE.email.support, privacy: SITE.email.privacy, updated: SITE.updated,
    h: href(code).replace(/\/$/, ''),
  };
}
function docPage(code, slug) {
  const t = T[code];
  const { meta, body } = readDoc(code, slug);
  const { html, toc } = md(body, vars(code));
  const tocHtml = toc.length > 4 ? `<nav aria-label="${esc(t.doc.contents)}"><h2 style="font-size:18px;margin:0 0 8px">${esc(t.doc.contents)}</h2><ol class="toc">${toc.map(([id, h]) => `<li><a href="#${id}">${inline(h)}</a></li>`).join('')}</ol></nav>` : '';
  const peek = { privacy: 'snooze', terms: 'butter-bar', ads: 'golden-mic', purchases: 'golden-gummy', parents: 'peach-bun', delete: 'gloop', cookies: 'cream-puff', accessibility: 'capy', imprint: 'golden-shop-cat' }[slug] || 'pip';
  return head(code, { title: `${meta.title} | Squish Sort`, description: meta.description, slug }) + bar(code, slug) + `
<main id="main" class="doc"><img class="peek" src="/assets/sq/${peek}.webp" alt="" width="120" height="120">
<h1>${esc(meta.title)}</h1><p class="meta">${esc(t.doc.updated)}: ${SITE.updated}</p>
${tocHtml}${html}</main>` + footer(code) + end();
}
function legalHub(code) {
  const t = T[code];
  return head(code, { title: `${t.legalHub.title} | Squish Sort`, description: t.legalHub.lede, slug: 'legal' }) + bar(code, 'legal') + `
<main id="main" class="doc"><img class="peek" src="/assets/sq/golden-shop-cat.webp" alt="" width="120" height="120"><h1>${esc(t.legalHub.title)}</h1><p class="lede">${esc(t.legalHub.lede)}</p>
<ul class="legal-list">${[...SITE.legalPages, 'support'].map(s => `<li><a href="${href(code, s)}">${esc(s === 'support' ? t.support.title : t.legalNames[s][0])} <span>${esc(s === 'support' ? t.footer.links.support : t.legalNames[s][1])}</span></a></li>`).join('')}</ul></main>` + footer(code) + end();
}
function support(code) {
  const t = T[code], s = t.support;
  const sub = x => esc(x).replace('{support}', `<a href="mailto:${SITE.email.support}">${SITE.email.support}</a>`).replace('{privacy}', `<a href="mailto:${SITE.email.privacy}">${SITE.email.privacy}</a>`);
  return head(code, { title: `${s.title} | Squish Sort`, description: s.lede, slug: 'support' }) + bar(code, 'support') + `
<main id="main" class="doc"><img class="peek" src="/assets/sq/elfie.webp" alt="" width="120" height="120">
<h1>${esc(s.title)}</h1><p class="lede">${esc(s.lede)}</p>
<h2>${esc(s.faqTitle)}</h2>${s.faq.map(([q, a]) => `<details class="faq"><summary>${esc(q)}</summary><p>${inline(a)}</p></details>`).join('')}
<h2 id="contact">${esc(s.formTitle)}</h2>
<p class="note">${esc(s.kid)}</p>
<form class="contact" id="contact-form" novalidate data-t='${esc(JSON.stringify({ sending: s.sending, ok: s.ok, err: s.err.replace('{email}', SITE.email.support), send: s.send }))}'>
  <input type="hidden" name="lang" value="${code}"><input type="hidden" name="t" value="">
  <label class="hp" aria-hidden="true">Website<input name="website" tabindex="-1" autocomplete="off"></label>
  <div class="row"><label>${esc(s.name)}<input name="name" maxlength="80" autocomplete="nickname"></label>
  <label>${esc(s.email)}<input name="email" type="email" required maxlength="200" autocomplete="email" inputmode="email"></label></div>
  <div class="row"><label>${esc(s.topic)}<select name="topic">${s.topics.map(o => `<option>${esc(o)}</option>`).join('')}</select></label>
  <label>${esc(s.device)}<input name="device" maxlength="80"></label></div>
  <label>${esc(s.message)}<textarea name="message" required maxlength="5000"></textarea></label>
  ${s.consent ? `<label class="check"><input type="checkbox" name="consent" required> <span>${esc(s.consent)} <a href="${href(code, 'privacy')}#support">→</a></span></label>` : `<p class="note">${esc(s.notice)} <a href="${href(code, 'privacy')}#support">→</a></p>`}
  <button class="btn" type="submit">${esc(s.send)}</button>
  <p class="status" role="status" aria-live="polite"></p>
</form>
<p>${sub(s.direct)}</p></main>` + footer(code) + end('<script src="/assets/contact.js" defer></script>');
}
function shop(code) {
  const t = T[code], s = t.shop;
  const data = { items: s.items, go: s.go, soon: s.soon, gateNo: s.gateNo };
  return head(code, { title: `${s.title} | Squish Sort`, description: s.lede, slug: 'shop', noindex: false }) + bar(code, 'shop') + `
<main id="main" class="doc"><img class="peek" src="/assets/sq/golden-shop-cat.webp" alt="" width="120" height="120">
<h1>${esc(s.title)}</h1><p class="lede">${esc(s.lede)}</p>
<div class="gate" id="gate"><h2 style="margin-top:0">${esc(s.gateTitle)}</h2><p>${esc(s.gateText)}</p>
<form id="gate-form"><label class="sr" for="gy">${esc(s.gateYear)}</label><input id="gy" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" placeholder="${esc(s.gateYear)}" required> <button class="btn" type="submit">${esc(s.gateGo)}</button></form><p class="status err" id="gate-msg" role="status"></p></div>
<div id="shop" hidden data-t='${esc(JSON.stringify(data))}'>
<p class="note"><strong>${esc(s.disclosure)}</strong> ${esc(s.amazon)}</p>
<p><label>${esc(s.country)} <select id="shop-country"></select></label></p>
<div class="shelf" id="shelf"></div>
<h2>${esc(s.safetyTitle)}</h2><ul>${s.safety.map(x => `<li>${esc(x)}</li>`).join('')}</ul>
</div></main>` + footer(code) + end('<script src="/assets/shop.js" defer></script>');
}
function notFound() {
  const t = T.en.notFound;
  return head('en', { title: t.title, description: t.text, noindex: true }) + bar('en') + `<main id="main" class="doc" style="text-align:center"><img src="/assets/sq/gloop.webp" alt="" width="160" height="160" style="margin:20px auto"><h1>${esc(t.title)}</h1><p>${esc(t.text)}</p><p><a class="btn" href="/">${esc(t.home)}</a></p></main>` + footer('en') + end();
}

// ---------- emit ----------
const urls = [];
for (const l of SITE.langs) {
  const c = l.code;
  write(pageFile(c, ''), landing(c)); urls.push(href(c));
  write(pageFile(c, 'legal'), legalHub(c)); urls.push(href(c, 'legal'));
  write(pageFile(c, 'support'), support(c)); urls.push(href(c, 'support'));
  write(pageFile(c, 'shop'), shop(c)); urls.push(href(c, 'shop'));
  for (const s of SITE.legalPages) { write(pageFile(c, s), docPage(c, s)); urls.push(href(c, s)); }
}
write('404.html', notFound());
write('sitemap.xml', `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls.map(u => `<url><loc>${SITE.origin}${u}</loc><lastmod>${SITE.updated}</lastmod></url>`).join('')}</urlset>\n`);
write('robots.txt', `User-agent: *\nAllow: /\nSitemap: ${SITE.origin}/sitemap.xml\n`);
write('.well-known/apple-app-site-association', JSON.stringify({ applinks: { details: [{ appIDs: [`${SITE.teamId}.${SITE.bundleId}`], components: [{ '/': '/open/*', comment: 'Reserved for future deep links' }] }] } }, null, 2));
console.log(`Built ${urls.length} pages into dist/`);

// ---------- Vercel Build Output API ----------
// The Vercel project builds from the repo root (so game branches without
// website/ changes are skipped cleanly) and reads .vercel/output from there.
if (process.env.VERCEL || process.argv.includes('--vercel')) {
  const VO = path.join(process.cwd(), '.vercel', 'output');
  fs.rmSync(VO, { recursive: true, force: true });
  fs.cpSync(OUT, path.join(VO, 'static'), { recursive: true });
  const overrides = {};
  const walk = d => { for (const f of fs.readdirSync(path.join(OUT, d), { withFileTypes: true })) { const r = path.posix.join(d, f.name); if (f.isDirectory()) walk(r); else if (f.name === 'index.html' && d) overrides[r] = { path: d }; } };
  walk('');
  overrides['config.json'] = { contentType: 'application/json' };
  overrides['.well-known/apple-app-site-association'] = { contentType: 'application/json' };
  overrides['app-ads.txt'] = { contentType: 'text/plain; charset=utf-8' };
  for (const fn of ['contact', 'go']) {
    const dir = path.join(VO, 'functions', 'api', fn + '.func');
    fs.mkdirSync(dir, { recursive: true });
    fs.copyFileSync(path.join(ROOT, 'api', fn + '.js'), path.join(dir, 'index.mjs'));
    fs.writeFileSync(path.join(dir, '.vc-config.json'), JSON.stringify({ runtime: 'nodejs22.x', handler: 'index.mjs', launcherType: 'Nodejs', shouldAddHelpers: true }));
  }
  const sec = {
    'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), interest-cohort=()',
    'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
    'Content-Security-Policy': "default-src 'self'; img-src 'self' data: https://tools.applemarketingtools.com; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
  };
  const routes = [
    { src: '^/(.+)/$', headers: { Location: '/$1' }, status: 308 },
    { src: '^/go/app-store$', dest: '/api/go' },
    { src: '^/(.*)$', headers: sec, continue: true },
    { src: '^/config\\.json$', headers: { 'Cache-Control': 'public, max-age=300, s-maxage=300', 'Access-Control-Allow-Origin': '*' }, continue: true },
    { src: '^/app-ads\\.txt$', headers: { 'Cache-Control': 'public, max-age=3600' }, continue: true },
    { src: '^/assets/(.*)$', headers: { 'Cache-Control': 'public, max-age=86400, stale-while-revalidate=604800' }, continue: true },
    { handle: 'filesystem' },
    { src: '^/.*$', dest: '/404.html', status: 404 },
  ];
  fs.writeFileSync(path.join(VO, 'config.json'), JSON.stringify({ version: 3, routes, overrides }, null, 1));
  console.log('Wrote Vercel build output to', VO);
}
