// Support form: posts to /api/contact, which emails support@ through Resend.
(() => {
  const f = document.getElementById('contact');
  if (!f) return;
  const T = JSON.parse(f.dataset.t), st = f.querySelector('.status'), btn = f.querySelector('button[type=submit]');
  f.elements.t.value = String(Date.now());
  f.addEventListener('submit', async e => {
    e.preventDefault();
    if (!f.reportValidity()) return;
    btn.disabled = true; btn.textContent = T.sending; st.className = 'status'; st.textContent = '';
    try {
      const body = Object.fromEntries(new FormData(f));
      const r = await fetch('/api/contact', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
      if (!r.ok) throw new Error(String(r.status));
      f.reset(); f.elements.t.value = String(Date.now());
      st.className = 'status ok'; st.textContent = T.ok;
    } catch (err) {
      st.className = 'status err'; st.textContent = T.err;
    } finally { btn.disabled = false; btn.textContent = T.send; }
  });
})();
