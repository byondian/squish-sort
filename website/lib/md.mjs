// Tiny markdown used by the site build and the Franca translation script.
export const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
export function inline(s) {
  return esc(s)
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (m, t, u) => `<a href="${u}"${/^https?:/.test(u) ? ' rel="noopener"' : ''}>${t}</a>`)
    .replace(/(^|[\s(])((?:support|privacy)@squishsort\.app)/g, '$1<a href="mailto:$2">$2</a>');
}
export function md(src, vars) {
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
