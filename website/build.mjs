import crypto from 'node:crypto';
// Static site builder for squishsort.app. No dependencies: `node build.mjs`.
// Reads src/, writes dist/. Pages: landing, demo, legal set, support, shop,
// in English, Japanese, Korean and Traditional Chinese.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SITE } from './src/site.mjs';
import { esc, inline, md } from './lib/md.mjs';
import { WS } from './src/workshop/page.mjs';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const SRC = path.join(ROOT, 'src'), OUT = path.join(ROOT, 'dist');
const roster = JSON.parse(fs.readFileSync(path.join(SRC, 'roster.json'), 'utf8'));
// cache-buster: assets are cached for a day, so their URLs change whenever any of them does
const V = (() => { const h = crypto.createHash('sha1'); for (const f of fs.readdirSync(path.join(SRC, 'assets'), { recursive: true }).sort()) { const fp = path.join(SRC, 'assets', f); if (/\.(js|css)$/.test(f)) h.update(fs.readFileSync(fp)); } return h.digest('hex').slice(0, 8); })();
const T = {};
// every language falls back to English for any string it does not have yet

// The Jelly pop logo as live text (Fredoka Bold). Outline and fill are two
// stacked spans, never ::before, so iPhone draws the outline behind the fill.
const LOGO = [[['S', -8], ['q', 4], ['u', -3], ['i', 6], ['s', -5], ['h', 5]], [['S', 6], ['o', -4], ['r', 5], ['t', -7]]];
const logo = (cls) => `<span class="logo ${cls}" aria-hidden="true">${LOGO.map((line, li) => `<span class="ln">${line.map(([c, r], i) => `<span class="L ${li ? 'li' : 'pk'}" style="--r:${r}deg;--d:${(li ? .5 + i * .08 : i * .08).toFixed(2)}s"><span class="b">${c}</span><span class="f">${c}</span></span>`).join('')}</span>`).join('')}</span>`;
const merge = (base, over) => { if (over == null) return base; if (typeof base !== 'object' || base === null) return over; const o = Array.isArray(base) ? base.slice() : { ...base }; for (const k of Object.keys(over)) o[k] = merge(base[k], over[k]); return o; };
for (const l of SITE.langs) { const own = (await import(`./src/i18n/${l.code}.mjs`)).default; T[l.code] = l.code === 'en' ? own : merge(T.en, own); }
const enName = new Intl.DisplayNames(['en'], { type: 'language' });

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });
fs.cpSync(path.join(SRC, 'assets'), path.join(OUT, 'assets'), { recursive: true });
fs.cpSync(path.join(SRC, 'static'), OUT, { recursive: true });

const L = code => SITE.langs.find(l => l.code === code);
const href = (code, slug = '') => '/' + [L(code).path, slug].filter(Boolean).join('/') + (slug || L(code).path ? '' : '');
const write = (rel, html) => { const f = path.join(OUT, rel); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, html); };
const pageFile = (code, slug) => path.join(L(code).path, slug, 'index.html');

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
function head(code, { title, description, slug = '', noindex = false, canon = null }) {
  const alts = SITE.langs.map(l => `<link rel="alternate" hreflang="${l.html}" href="${SITE.origin}${href(l.code, slug)}">`).join('')
    + `<link rel="alternate" hreflang="x-default" href="${SITE.origin}${href('en', slug)}">`;
  return `<!doctype html><html lang="${L(code).html}"${L(code).dir === 'rtl' ? ' dir="rtl"' : ''}><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${esc(title)}</title><meta name="description" content="${esc(description)}">
<link rel="canonical" href="${SITE.origin}${canon || href(code, slug)}">${canon ? '' : alts}
<meta name="theme-color" content="#FFF4E8">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}">
<meta property="og:type" content="website"><meta property="og:url" content="${SITE.origin}${href(code, slug)}">
<meta property="og:image" content="${SITE.origin}/assets/img/og.png"><meta name="twitter:card" content="summary_large_image">
${SITE.APP_LIVE ? `<meta name="apple-itunes-app" content="app-id=${SITE.appStoreId}">` : ''}
${noindex ? '<meta name="robots" content="noindex">' : ''}
<link rel="icon" href="/assets/img/icon-32.png" sizes="32x32"><link rel="apple-touch-icon" href="/assets/img/icon-180.png">
<link rel="preload" href="/assets/fonts/fredoka-latin-wght-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/assets/site.css?v=${V}">
<script defer src="/_vercel/insights/script.js"></script>
</head><body>`;
}
function bar(code, slug = '') {
  const t = T[code];
  const sorted = [...SITE.langs].sort((a, b) => enName.of(a.html).localeCompare(enName.of(b.html), 'en'));
  const langs = sorted.map(l => { const n = enName.of(l.html); return `<li data-s="${esc((l.label + ' ' + n + ' ' + l.html).toLowerCase())}"><a href="${href(l.code, slug)}" hreflang="${l.html}" lang="${l.html}"${l.code === code ? ' aria-current="true"' : ''}>${l.label}${n !== l.label ? ` <small lang="en">${esc(n)}</small>` : ''}</a></li>`; }).join('');
  return `<a class="skip" href="#main">${esc(t.skip)}</a>
<header class="bar"><a class="brand" href="${href(code)}" aria-label="Squish Sort"><img src="/assets/img/icon-180.png" alt="" width="36" height="36">${logo('mini')}</a>
<nav aria-label="Main"><a class="hide-s" href="${href(code)}#play">${esc(t.nav.demo)}</a><a class="hide-s" href="${href(code, 'parents')}">${esc(t.nav.parents)}</a><a href="${href(code, 'support')}">${esc(t.nav.support)}</a>
<details class="lang"><summary aria-label="${esc(t.nav.language)}">🌐 ${L(code).label}</summary><div class="lang-pop"><input type="search" class="lang-q" placeholder="${esc(t.nav.findLanguage)}" aria-label="${esc(t.nav.findLanguage)}" autocomplete="off" hidden><ul>${langs}</ul></div></details></nav></header>`;
}
function footer(code) {
  const t = T[code];
  const legal = SITE.legalPages.map(s => `<li><a href="${href(code, s)}">${esc(t.legalNames[s][0])}</a></li>`).join('');
  return `<footer><div class="foot">
<div><h4>${esc(t.footer.game)}</h4><ul style="columns:1"><li><a href="${href(code)}">${esc(t.footer.links.home)}</a></li><li><a href="${href(code)}#play">${esc(t.footer.links.demo)}</a></li><li><a href="${href(code, 'support')}">${esc(t.footer.links.support)}</a></li><li><a href="${href(code, 'shop')}">${esc(t.footer.links.shop)}</a></li><li><a href="${href(wsCode(code), 'workshop')}"${wsCode(code) === code ? '' : ' lang="en"'}>${esc(WS[wsCode(code)].name)}</a></li><li><a href="${href('en', 'partners')}"${code === 'en' ? '' : ' lang="en"'}>Partner with us</a></li></ul></div>
<div><h4>${esc(t.footer.legal)}</h4><ul>${legal}<li><a href="${href(code, 'legal')}">${esc(t.footer.links.legalHub)}</a></li></ul></div>
</div><p class="fine">${esc(t.footer.fine)}</p></footer>`;
}
const end = scripts => `<script src="/assets/lang.js?v=${V}" defer></script>${scripts || ''}</body></html>`;

// ---------- landing ----------
const PALETTE = { common: '#7FE0C4', rare: '#7CC8FF', ultra: '#C9B6FF', secret: '#FFD86B' };
const waveTo = (fill, flip = false) => `<svg class="wave" viewBox="0 0 1440 80" preserveAspectRatio="none" aria-hidden="true"${flip ? ' style="transform:scaleY(-1)"' : ''}><path d="M0 40 C240 90 480 0 720 30 C960 60 1200 10 1440 40 V80 H0Z" fill="${fill}"/></svg>`;

function landing(code) {
  const t = T[code];
  const nm = c => (c.names && c.names[L(code).html]) || c.name;
  const heroTiers = ['common', 'rare', 'ultra', 'secret'].reduce((o, r) => (o[r] = roster.collectibles.filter(c => c.rarity === r).map(c => c.id), o), {});
  const names = Object.fromEntries([...roster.collectibles, ...roster.squishRoomToys].map(c => [c.id, nm(c)]));
  const feels = Object.fromEntries([...roster.collectibles, ...roster.squishRoomToys].filter(c => c.feel && c.feel !== 'jelly').map(c => [c.id, c.feel]));
  const all = roster.collectibles.filter(c => c.rarity !== 'secret');
  const half = Math.ceil(all.length / 2);
  const sq = c => `<button class="sq" type="button" aria-label="${esc(nm(c))}"><img src="/assets/sq/${c.id}.webp" alt="" width="118" height="118" loading="lazy"><span class="nm">${esc(nm(c))}</span></button>`;
  const row = list => `<div class="ribbon"><div class="track">${list.map(sq).join('')}${list.map(sq).join('').replace(/<button /g, '<button aria-hidden="true" tabindex="-1" ')}</div></div>`;
  const demoT = { ...t.demo, names, worlds: t.worlds.list.slice(0, 3).map(w => w[0]) };
  const demoWorlds = [['toyshop', 'dino-rex'], ['sweetfactory', 'donut'], ['starlight', 'lightstick-lamb']];
  const worldsImg = ['dino-rex', 'donut', 'lightstick-lamb', 'floaty-otter', 'snoozy-sloth', 'reindeer'];
  const worldsCol = ['#FFE3EF', '#FFF0C2', '#EEE7FF', '#DCF4FF', '#E6F7D9', '#DDF7EE'];
  const pile = ['strawbie', 'capy', 'axo', 'sparkle-unicorn', 'peach-bun', 'panda-dumpling', 'gummy-bear', 'snowbo', 'tango'];
  return head(code, { title: t.meta.title, description: t.meta.description }) + bar(code) + `
<main id="main">
<section class="hero">
  <div class="bg-blob" style="width:420px;height:420px;background:#FFC7DE;left:-120px;top:40px"></div>
  <div class="bg-blob" style="width:360px;height:360px;background:#CDEBFF;right:-80px;top:260px;animation-delay:-5s"></div>
  <div class="bg-blob" style="width:300px;height:300px;background:#FFF0B8;left:40%;bottom:-60px;animation-delay:-9s"></div>
  <div>
    <h1 aria-label="Squish Sort">${logo('big')}</h1>
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
      <p class="wrap-tip" hidden>🍬 ${esc(t.demo.wrapTip)}</p>
      <div class="jars"></div>
      <p class="live sr" aria-live="polite"></p>
      <div class="win" role="dialog" aria-modal="false" aria-labelledby="win-h">
        <div class="stars"></div><h3 id="win-h"></h3><p class="msg"></p>
        <button class="btn next" type="button">${esc(t.demo.next)} →</button>
        <div class="final-cta cta-row" hidden style="justify-content:center">${storeCta(code, 'demo', true)}<button class="btn soft again" type="button">${esc(t.demo.again)}</button></div>
      </div>
    </div>
    <div class="side"><h3>${esc(t.demo.sideTitle)}</h3>
      <ul class="dworlds">${demoWorlds.map(([w, img], i) => `<li data-w="${w}"><img src="/assets/sq/${img}.webp" alt="" width="44" height="44"><span>${esc(demoT.worlds[i])}</span><ol class="steps">${[1, 2].map(n => `<li>${i * 2 + n}</li>`).join('')}</ol></li>`).join('')}</ul>
      <p class="lede">${esc(t.demo.lede)}</p><ul class="howto">${t.demo.howto.map(h => `<li>${esc(h)}</li>`).join('')}</ul></div>
  </div>
</section>
${waveTo('#FFE3EF', true)}
<section class="band" id="clips">
  <p class="kicker">${esc(t.clips.kicker)}</p><h2>${esc(t.clips.title)}</h2>
  <div class="clips">${t.clips.list.map(([h, d], i) => `<figure class="clip"><div class="phone"><video src="/assets/clips/clip${i + 1}.mp4?v=${V}" poster="/assets/clips/clip${i + 1}.webp" muted loop playsinline preload="none" aria-label="${esc(h)}"></video><button class="vsnd" type="button" aria-pressed="false">🔇 <span>${esc(t.clips.sound)}</span></button></div><figcaption><h3>${esc(h)}</h3><p>${esc(d)}</p></figcaption></figure>`).join('')}</div>
</section>
<section class="band" id="squishies">
  <p class="kicker">${esc(t.collect.kicker)}</p><h2>${esc(t.collect.title)}</h2><p class="lede">${esc(t.collect.lede)}</p>
  ${row(all.slice(0, half))}${row(all.slice(half))}
  <p class="rarity">${t.collect.rarity.map((r, i) => `<span style="--c:${Object.values(PALETTE)[i]}">${esc(r)}</span>`).join('')} <a href="${href(code, 'purchases')}#drop">${esc(t.collect.oddsLink)} →</a></p>
</section>
${waveTo('#EEE7FF')}
<section class="band grape">
  <p class="kicker">${esc(t.worlds.kicker)}</p><h2>${esc(t.worlds.title)}</h2>
  <div class="path">
    <svg class="road" viewBox="0 0 100 400" preserveAspectRatio="none" aria-hidden="true"><path d="M20 10 C90 40 90 80 50 110 S10 180 50 210 S90 280 50 310 S10 370 70 395" fill="none" stroke="#fff" stroke-width="3" stroke-dasharray="1 3" stroke-linecap="round" vector-effect="non-scaling-stroke" style="stroke-width:10px"/></svg>
    ${t.worlds.list.map(([n, d], i) => `<div class="stop"><div class="disc" style="--c:${worldsCol[i]}"><img src="/assets/sq/${worldsImg[i]}.webp" alt="" width="110" height="110" loading="lazy"></div><div><h3>${esc(n)}${i === t.worlds.list.length - 1 ? ` <span class="badge">${esc(t.worlds.xmasBadge)}</span>` : ''}</h3><p>${esc(d)}</p></div></div>`).join('')}
  </div>
</section>
${waveTo('#EEE7FF', true)}
<section class="band">
  <p class="kicker">${esc(t.extras.kicker)}</p><h2>${esc(t.extras.title)}</h2>
  <div class="promises">${t.extras.list.map(([e, h, p]) => `<div class="promise"><span class="dot" aria-hidden="true">${e}</span><div><h3>${esc(h)}</h3><p>${esc(p)}</p></div></div>`).join('')}</div>
  <p style="margin-top:22px"><a class="btn soft" href="${href(wsCode(code), 'workshop')}"${wsCode(code) === code ? '' : ' hreflang="en"'}>🎨 ${esc(t.wsLink)} →</a></p>
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
</main>` + footer(code) + end(`<script src="/assets/squish/squish-engine.js?v=${V}" defer></script><script src="/assets/squish/squish-audio.js?v=${V}" defer></script><script src="/assets/morph.js?v=${V}" defer></script><script src="/assets/demo.js?v=${V}" defer></script><script src="/assets/clips.js?v=${V}" defer></script>`);
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
  const own = L(code).legal, { meta, body } = readDoc(own ? code : 'en', slug);
  const { html, toc } = md(body, own ? vars(code) : { ...vars('en'), h: href(code).replace(/\/$/, '') });
  const tocHtml = toc.length > 4 ? `<nav aria-label="${esc(t.doc.contents)}"><h2 style="font-size:18px;margin:0 0 8px">${esc(t.doc.contents)}</h2><ol class="toc">${toc.map(([id, h]) => `<li><a href="#${id}">${inline(h)}</a></li>`).join('')}</ol></nav>` : '';
  const peek = { privacy: 'snooze', terms: 'butter-bar', ads: 'golden-mic', purchases: 'golden-gummy', parents: 'peach-bun', delete: 'gloop', cookies: 'cream-puff', accessibility: 'capy', imprint: 'golden-shop-cat' }[slug] || 'pip';
  const note = own ? '' : `<p class="note" lang="${L(code).html}">${esc(t.doc.englishOnly)}</p>`;
  return head(code, { title: `${meta.title} | Squish Sort`, description: meta.description, slug, canon: own ? null : href('en', slug) }) + bar(code, slug) + `
<main id="main" class="doc"${own ? '' : ' lang="en"'}><img class="peek" src="/assets/sq/${peek}.webp" alt="" width="120" height="120">
${note}<h1>${esc(meta.title)}</h1><p class="meta">${esc(t.doc.updated)}: ${SITE.updated}</p>
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
<p>${sub(s.direct)}</p></main>` + footer(code) + end(`<script src="/assets/contact.js?v=${V}" defer></script>`);
}
function partners() {
  const code = 'en', t = T.en, s = t.support;
  const P = {
    title: 'Partner with us', lede: 'Not a paid post. We build a new game every week. You bring the audience. We share the revenue.',
    how: [['We build.', 'A new mobile game or app most weeks. Squish Sort went from a name to a 365-level game on testers’ phones in three days.'],
      ['You share it your way.', 'Early builds, ready-made clips and your own tracked link.'],
      ['We both earn.', 'A share of revenue from every game you help launch, for as long as the partnership runs.']],
    gets: ['Revenue share on every title you promote, not a one-off fee', 'Early TestFlight builds before anyone else', 'Your own original character in the game, designed with you', 'A say in what we make next, built around what your audience asks for'],
    who: 'Creators on TikTok, YouTube Shorts or Instagram Reels who make squishy, ASMR, satisfying, cosy-game or mobile-game content. 10k followers is plenty. Fit matters more than size.',
    rules: ['Every partner post is labelled as an ad or paid partnership.', 'No fake reviews and no paying viewers to install.', 'Either side can stop with 30 days’ notice; revenue already earned is still paid.'],
  };
  const owner = SITE.byondianUrl ? `<a href="${esc(SITE.byondianUrl)}" rel="noopener">Byondian</a>` : 'Byondian';
  const f = { sending: s.sending, ok: 'Thanks! We read every message and will reply by email.', err: s.err.replace('{email}', SITE.email.support), send: 'Send' };
  return head(code, { title: 'Partner with us | Squish Sort', description: P.lede, slug: 'partners', canon: '/partners' }) + bar(code) + `
<main id="main" class="doc partners"><img class="peek" src="/assets/sq/sparkle-unicorn.webp" alt="" width="120" height="120">
<p class="kicker">For creators</p><h1>${esc(P.title)}</h1><p class="lede">${esc(P.lede)}</p>
<p><a class="btn" href="#contact">Get in touch</a></p>
<h2>How it works</h2><ol class="how3">${P.how.map(([a, b], i) => `<li><span class="n">${i + 1}</span><div><strong>${esc(a)}</strong> ${esc(b)}</div></li>`).join('')}</ol>
<h2>What partners get</h2><ul>${P.gets.map(x => `<li>${esc(x)}</li>`).join('')}</ul>
<h2>Who we’re looking for</h2><p>${esc(P.who)}</p>
<h2>The ground rules</h2><ul>${P.rules.map(x => `<li>${esc(x)}</li>`).join('')}</ul>
<h2 id="contact">Get in touch</h2>
<form class="contact" id="contact-form" novalidate data-t='${esc(JSON.stringify(f))}'>
  <input type="hidden" name="lang" value="en"><input type="hidden" name="t" value=""><input type="hidden" name="kind" value="partner"><input type="hidden" name="topic" value="Partner">
  <label class="hp" aria-hidden="true">Website<input name="website" tabindex="-1" autocomplete="off"></label>
  <div class="row"><label>Your name<input name="name" maxlength="80" autocomplete="name"></label>
  <label>Email address for our reply<input name="email" type="email" required maxlength="200" autocomplete="email" inputmode="email"></label></div>
  <label>Where you post (a link to your profile)<input name="channel" maxlength="200" inputmode="url"></label>
  <label>Tell us about your content<textarea name="message" required maxlength="5000"></textarea></label>
  <p class="note">This form is for adults (18 and over). We use these details only to reply to you. <a href="${href(code, 'privacy')}#support">See the privacy policy →</a></p>
  <button class="btn" type="submit">${esc(f.send)}</button>
  <p class="status" role="status" aria-live="polite"></p>
</form>
<p class="fine-print">Made by Ian, an independent developer. ${owner}</p></main>` + footer(code) + end(`<script src="/assets/contact.js?v=${V}" defer></script>`);
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
</div></main>` + footer(code) + end(`<script src="/assets/shop.js?v=${V}" defer></script>`);
}
// ---------- Squishy Workshop (the kids app): en, ja, ko, zh-hant ----------
const WS_LANGS = ['en', 'ja', 'ko', 'zh-hant'];
const wsCode = code => WS_LANGS.includes(code) ? code : 'en';
function workshopPage(code) {
  const W = WS[code];
  const pile = ['peach-bun', 'capy', 'sparkle-unicorn', 'axo', 'gummy-bear', 'jelly'];
  return head(code, { title: W.title, description: W.lede, slug: 'workshop', canon: href(code, 'workshop') }) + bar(code) + `
<main id="main" class="doc"><img class="peek" src="/assets/sq/fan-sign-hamster.webp" alt="" width="120" height="120">
<p class="kicker">${esc(W.kicker)}</p><h1>${esc(W.name)}</h1><p class="lede">${esc(W.lede)}</p>
<p><span class="soon" role="note">${esc(W.soon)}<small>${esc(W.soonSmall)}</small></span></p>
<p class="ws-pile" aria-hidden="true">${pile.map(id => `<img src="/assets/sq/${id}.webp" alt="" width="72" height="72" loading="lazy">`).join('')}</p>
<h2>${esc(W.how)}</h2><ol class="how3">${W.steps.map(([e, a, b]) => `<li><span class="n" aria-hidden="true">${e}</span><div><strong>${esc(a)}</strong><br>${esc(b)}</div></li>`).join('')}</ol>
<h2>${esc(W.grown)}</h2><ul>${W.parents.map(x => `<li>${esc(x)}</li>`).join('')}</ul>
<p><a class="btn soft" href="${href(code, 'workshop/privacy')}">${esc(W.privacy)} →</a></p>
<h2>${esc(W.bigger)}</h2><p>${esc(W.older)} <a href="${href(code)}">${esc(W.meet)} →</a></p>
</main>` + footer(code) + end();
}
function workshopPrivacy(code) {
  const t = T[code];
  const raw = fs.readFileSync(path.join(SRC, 'workshop', `privacy.${code}.md`), 'utf8');
  const m = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/), meta = {};
  for (const l of m[1].split('\n')) { const k = l.indexOf(':'); meta[l.slice(0, k).trim()] = l.slice(k + 1).trim(); }
  const { html } = md(m[2], vars(code));
  return head(code, { title: meta.title, description: meta.description, slug: 'workshop/privacy', canon: href(code, 'workshop/privacy') }) + bar(code) + `
<main id="main" class="doc"><img class="peek" src="/assets/sq/snooze.webp" alt="" width="120" height="120">
<h1>${esc(meta.title)}</h1><p class="meta">${esc(t.doc.updated)}: ${SITE.updated}</p>${html}</main>` + footer(code) + end();
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
  if (c === 'en') { write(pageFile(c, 'partners'), partners()); urls.push(href(c, 'partners')); }
  if (WS_LANGS.includes(c)) { write(pageFile(c, 'workshop'), workshopPage(c)); write(pageFile(c, 'workshop/privacy'), workshopPrivacy(c)); urls.push(href(c, 'workshop'), href(c, 'workshop/privacy')); }
  for (const s of SITE.legalPages) { write(pageFile(c, s), docPage(c, s)); if (l.legal) urls.push(href(c, s)); }
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
