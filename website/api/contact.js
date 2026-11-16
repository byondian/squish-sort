// POST /api/contact: emails a support message to support@squishsort.app via Resend.
// Needs RESEND_API_KEY in the Vercel project (Ian adds it). Nothing is stored here.
const TO = 'support@squishsort.app';
const FROM = 'Squish Sort website <website@squishsort.app>';
const hits = new Map(); // best-effort per-instance rate limit

const clean = (v, n) => String(v ?? '').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '').trim().slice(0, n);
const line = (v, n) => clean(v, n).replace(/[\r\n\t]+/g, ' ');
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'method' }); }
  let b;
  try { b = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {}); } catch (e) { return res.status(400).json({ error: 'invalid' }); }
  // spam traps: hidden field filled, or sent faster than a human types
  if (b.website || (Number(b.t) && Date.now() - Number(b.t) < 2500)) return res.status(200).json({ ok: true });
  const ip = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  const now = Date.now(), list = (hits.get(ip) || []).filter(x => now - x < 3600e3);
  if (hits.size > 5000) for (const [k, v] of hits) if (!v.some(x => now - x < 3600e3)) hits.delete(k); // forget old IPs
  if (list.length >= 5) return res.status(429).json({ error: 'slow down' });
  list.push(now); hits.set(ip, list);

  const name = line(b.name, 80), email = line(b.email, 200), topic = line(b.topic, 60), device = line(b.device, 80);
  const message = clean(b.message, 5000), lang = clean(b.lang, 10);
  if (!message || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) || (lang === 'ko' && !b.consent)) return res.status(400).json({ error: 'invalid' });
  if (!process.env.RESEND_API_KEY) return res.status(503).json({ error: 'not configured' });

  const text = `${message}\n\n--\nFrom: ${name || '-'} <${email}>\nTopic: ${topic}\nDevice: ${device || '-'}\nSite language: ${lang}`;
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${process.env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: FROM, to: [TO], reply_to: email,
      subject: `[Support] ${topic}${name ? ': ' + name : ''}`.slice(0, 140),
      text, html: `<pre style="font:14px/1.5 system-ui;white-space:pre-wrap">${esc(text)}</pre>`,
    }),
  });
  if (!r.ok) { console.error('resend', r.status); return res.status(502).json({ error: 'send' }); }
  return res.status(200).json({ ok: true });
}
