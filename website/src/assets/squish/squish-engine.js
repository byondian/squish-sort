/* Squish Sort soft-body squish, v1 (16 Nov 2026). Game design thread.
   One squishy = a small lattice of points pulled towards a best-fit copy of its rest shape
   ("shape matching", Mueller et al. 2005, quadratic variant). Fingers grab a soft patch of points.
   No dependencies. Works in a browser (window.Squish) and in Node (module.exports) for tests.

   Port notes for SpriteKit: keep SquishBody as is (plain arithmetic), and each frame copy body.p into
   SKWarpGeometryGrid(columns: n, rows: n, sourcePositions: uv, destinationPositions: p normalised to
   the sprite) and assign it to sprite.warpGeometry. */
(function (root) {
  'use strict';

  /* k     spring towards the goal shape, 1/s^2 (higher = snappier)
     beta  how much of a stretch or squash is allowed to linger (0 rigid, 1 floppy)
     c     damping of deformation, 1/s (high = slow rise, low = wobble)
     quad  how much bending and bulging is allowed
     vp    volume kept when squashed (1 = sides bulge fully)
     smin/smax  limits of squash and stretch
     grav  gravity in body sizes per s^2;  fric floor grip 0..1;  rest bounce 0..1
     land  how much a landing squashes (0 none, 1 splat);  grip how much the base sticks to the floor when pulled
     press how deep a press goes, as a share of the distance to the base
     grabR radius of the firm patch under a finger;  halo strength of the wide soft patch around it */
  const MATERIALS = {
    foam: { label: 'Slow-rise foam', k: 300, beta: 0.68, c: 62, quad: 0.55, vp: 0.9, smin: 0.40, smax: 1.7, grav: 9, fric: 0.9, rest: 0.05, press: 0.46, grabR: 0.20, halo: 0.35, land: 0.6, grip: 0.5 },
    jelly: { label: 'Jelly', k: 700, beta: 0.72, c: 5.5, quad: 0.6, vp: 1, smin: 0.45, smax: 1.9, grav: 9, fric: 0.55, rest: 0.22, press: 0.44, grabR: 0.20, halo: 0.35, land: 0.75, grip: 0.3 },
    gel: { label: 'Gel ball', k: 440, beta: 0.78, c: 5.5, quad: 0.6, vp: 0.9, smin: 0.42, smax: 2.1, grav: 11, fric: 0.6, rest: 0.08, press: 0.44, grabR: 0.22, halo: 0.45, land: 1.0, grip: 0.35 },
    mochi: { label: 'Mochi', k: 380, beta: 0.74, c: 12, quad: 0.5, vp: 1, smin: 0.40, smax: 2.6, grav: 9, fric: 1, rest: 0, press: 0.46, grabR: 0.19, halo: 0.3, land: 0.65, grip: 0.9 }
  };


  function inv5(m) { // m: 25 numbers row-major, returns inverse (Gauss-Jordan)
    const n = 5, a = new Float64Array(50);
    for (let r = 0; r < n; r++) { for (let c = 0; c < n; c++) a[r * 10 + c] = m[r * n + c]; a[r * 10 + n + r] = 1; }
    for (let col = 0; col < n; col++) {
      let piv = col;
      for (let r = col + 1; r < n; r++) if (Math.abs(a[r * 10 + col]) > Math.abs(a[piv * 10 + col])) piv = r;
      if (piv !== col) for (let c = 0; c < 10; c++) { const t = a[col * 10 + c]; a[col * 10 + c] = a[piv * 10 + c]; a[piv * 10 + c] = t; }
      const d = a[col * 10 + col] || 1e-9;
      for (let c = 0; c < 10; c++) a[col * 10 + c] /= d;
      for (let r = 0; r < n; r++) if (r !== col) { const f = a[r * 10 + col]; if (f) for (let c = 0; c < 10; c++) a[r * 10 + c] -= f * a[col * 10 + c]; }
    }
    const out = new Float64Array(25);
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) out[r * n + c] = a[r * 10 + n + c];
    return out;
  }
  const clamp = (x, a, b) => x < a ? a : x > b ? b : x;
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

  /* o: { size (px), n (cells per side, default 10), inside(u,v) -> bool with u,v in 0..1 (art silhouette),
          material: key of MATERIALS or an object, x, y (centre of the sprite box) } */
  function SquishBody(o) {
    const n = this.n = o.n || 10, cnt = this.count = (n + 1) * (n + 1);
    this.S = o.size;
    this.mat = typeof o.material === 'string' ? MATERIALS[o.material] : (o.material || MATERIALS.foam);
    this.uv = new Float32Array(cnt * 2); this.u = new Float32Array(cnt * 2); this.f = new Float32Array(cnt * 5);
    this.p = new Float32Array(cnt * 2); this.v = new Float32Array(cnt * 2); this.g = new Float32Array(cnt * 2);
    this.sim = new Uint8Array(cnt); this.core = new Uint8Array(cnt);
    this.pointers = {}; this.breath = Math.random() * 6; this.theta = 0; this.push = { x: 0, y: 0, sx: 1, sy: 1 };
    this.metric = { D: 0, rate: 0, stretch: 0, squash: 0, impact: 0, speed: 0, held: 0, air: false };
    const inside = o.inside || function () { return true; };
    for (let j = 0; j <= n; j++) for (let i = 0; i <= n; i++) { const k = j * (n + 1) + i; this.uv[k * 2] = i / n; this.uv[k * 2 + 1] = j / n; this.core[k] = inside(i / n, j / n) ? 1 : 0; }
    // simulate the silhouette plus one ring of cells, so the outline itself deforms
    for (let j = 0; j <= n; j++) for (let i = 0; i <= n; i++) {
      let s = 0;
      for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) { const a = i + di, b = j + dj; if (a >= 0 && b >= 0 && a <= n && b <= n && this.core[b * (n + 1) + a]) s = 1; }
      this.sim[j * (n + 1) + i] = s;
    }
    let cx = 0, cy = 0, m = 0, foot = 0, top = 1, left = 1, right = 0;
    for (let k = 0; k < cnt; k++) if (this.sim[k]) { cx += this.uv[k * 2]; cy += this.uv[k * 2 + 1]; m++; }
    for (let k = 0; k < cnt; k++) if (this.core[k]) { foot = Math.max(foot, this.uv[k * 2 + 1]); top = Math.min(top, this.uv[k * 2 + 1]); left = Math.min(left, this.uv[k * 2]); right = Math.max(right, this.uv[k * 2]); }
    cx /= m; cy /= m; this.m = m; this.c0 = [cx, cy];
    // the art's true lowest pixel may sit below the lowest lattice point: o.footV says where (0..1)
    this.footPad = Math.max(0, ((o.footV != null ? o.footV : foot) - foot)) * this.S;
    this.baseV = foot - cy; this.halfW = (right - left) / 2;
    const mean = [0, 0, 0];
    for (let k = 0; k < cnt; k++) { const x = this.uv[k * 2] - cx, y = this.uv[k * 2 + 1] - cy; this.u[k * 2] = x; this.u[k * 2 + 1] = y; if (this.sim[k]) { mean[0] += x * x; mean[1] += y * y; mean[2] += x * y; } }
    mean[0] /= m; mean[1] /= m; mean[2] /= m;
    const Aqq = new Float64Array(25);
    for (let k = 0; k < cnt; k++) {
      const x = this.u[k * 2], y = this.u[k * 2 + 1], q = [x, y, x * x - mean[0], y * y - mean[1], x * y - mean[2]];
      for (let a = 0; a < 5; a++) this.f[k * 5 + a] = q[a];
      if (this.sim[k]) for (let a = 0; a < 5; a++) for (let b = 0; b < 5; b++) Aqq[a * 5 + b] += q[a] * q[b];
    }
    this.M = inv5(Aqq);
    this.place(o.x || 0, o.y || 0);
  }

  SquishBody.prototype.place = function (x, y) { // (x, y) = centre of the sprite box
    const S = this.S;
    for (let k = 0; k < this.count; k++) { this.p[k * 2] = x + (this.uv[k * 2] - 0.5) * S; this.p[k * 2 + 1] = y + (this.uv[k * 2 + 1] - 0.5) * S; this.v[k * 2] = 0; this.v[k * 2 + 1] = 0; }
    this.g.set(this.p); this.theta = 0;
  };
  SquishBody.prototype.setMaterial = function (m) { this.mat = typeof m === 'string' ? MATERIALS[m] : m; };
  SquishBody.prototype.centre = function () {
    let x = 0, y = 0; for (let k = 0; k < this.count; k++) if (this.sim[k]) { x += this.p[k * 2]; y += this.p[k * 2 + 1]; }
    return [x / this.m, y / this.m];
  };
  SquishBody.prototype.bounds = function () {
    let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
    for (let k = 0; k < this.count; k++) if (this.core[k]) { const x = this.p[k * 2], y = this.p[k * 2 + 1]; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    return { x0, x1, y0, y1: y1 + this.footPad };
  };

  /* Fingers. Returns true if the finger landed on the squishy. */
  SquishBody.prototype.grab = function (id, x, y) {
    const S = this.S, R = this.mat.grabR * S; let best = 1e9;
    for (let k = 0; k < this.count; k++) if (this.core[k]) { const d = Math.hypot(this.p[k * 2] - x, this.p[k * 2 + 1] - y); if (d < best) best = d; }
    if (best > S * 0.16) return false;
    const w = new Float32Array(this.count), off = new Float32Array(this.count * 2), sc = new Float32Array(this.count), halo = this.mat.halo || 0;
    for (let k = 0; k < this.count; k++) if (this.sim[k]) {
      const dx = this.p[k * 2] - x, dy = this.p[k * 2 + 1] - y, d2 = (dx * dx + dy * dy) / (R * R);
      w[k] = Math.min(1, Math.exp(-d2) + halo * Math.exp(-d2 / 5.3)); off[k * 2] = dx; off[k * 2 + 1] = dy; // firm dimple plus a soft halo
    }
    const c = this.centre(), b = this.bounds();
    // a press pushes towards the base when resting, or towards the middle when held in the air
    const tx = c[0], ty = this.metric.air ? c[1] : b.y1;
    const ax = x - tx, ay = y - ty, al = ax * ax + ay * ay || 1; // 0 at the base, 1 at the finger: how much of the press each point takes
    for (let k = 0; k < this.count; k++) sc[k] = clamp(((this.p[k * 2] - tx) * ax + (this.p[k * 2 + 1] - ty) * ay) / al, 0, 1.15);
    this.pointers[id] = { x, y, sx: x, sy: y, vx: 0, vy: 0, w, off, sc, press: 0, px: (tx - x) * this.mat.press, py: (ty - y) * this.mat.press, t: 0, drag: 0 };
    return true;
  };
  SquishBody.prototype.move = function (id, x, y, dt) {
    const q = this.pointers[id]; if (!q) return;
    const h = Math.max(dt || 1 / 60, 1 / 240), a = 0.5;
    q.vx += a * ((x - q.x) / h - q.vx); q.vy += a * ((y - q.y) / h - q.vy);
    q.x = x; q.y = y; q.drag = Math.max(q.drag, Math.hypot(x - q.sx, y - q.sy));
  };
  SquishBody.prototype.release = function (id) { const q = this.pointers[id]; delete this.pointers[id]; return q; };
  SquishBody.prototype.held = function () { for (const k in this.pointers) return true; return false; };

  /* world: { floor (y px), left, right, top (px) } */
  SquishBody.prototype.step = function (h, world) {
    const M = this.mat, S = this.S, n = this.count, p = this.p, v = this.v, g = this.g, u = this.u, f = this.f;
    let cx = 0, cy = 0, vx = 0, vy = 0;
    for (let k = 0; k < n; k++) if (this.sim[k]) { cx += p[k * 2]; cy += p[k * 2 + 1]; vx += v[k * 2]; vy += v[k * 2 + 1]; }
    cx /= this.m; cy /= this.m; vx /= this.m; vy /= this.m;
    // best quadratic fit of the current points to the rest shape
    const B = new Float64Array(10); let L = 0, I = 0;
    for (let k = 0; k < n; k++) if (this.sim[k]) {
      const rx = p[k * 2] - cx, ry = p[k * 2 + 1] - cy;
      for (let a = 0; a < 5; a++) { B[a] += rx * f[k * 5 + a]; B[5 + a] += ry * f[k * 5 + a]; }
      L += rx * (v[k * 2 + 1] - vy) - ry * (v[k * 2] - vx); I += rx * rx + ry * ry;
    }
    const A = new Float64Array(10);
    for (let r = 0; r < 2; r++) for (let c = 0; c < 5; c++) { let s = 0; for (let j = 0; j < 5; j++) s += B[r * 5 + j] * this.M[j * 5 + c]; A[r * 5 + c] = s; }
    let a00 = A[0] / S, a01 = A[1] / S, a10 = A[5] / S, a11 = A[6] / S;
    if (!isFinite(a00 + a01 + a10 + a11)) { a00 = 1; a01 = 0; a10 = 0; a11 = 1; }
    const th = Math.atan2(a10 - a01, a00 + a11), ct = Math.cos(th), st = Math.sin(th);
    // stretch part, symmetric: Rt * A
    let sxx = ct * a00 + st * a10, sxy = 0.5 * ((ct * a01 + st * a11) + (-st * a00 + ct * a10)), syy = -st * a01 + ct * a11;
    const ph = 0.5 * Math.atan2(2 * sxy, sxx - syy), cp = Math.cos(ph), sp = Math.sin(ph);
    let l1 = cp * cp * sxx + 2 * cp * sp * sxy + sp * sp * syy, l2 = sp * sp * sxx - 2 * cp * sp * sxy + cp * cp * syy;
    const raw1 = l1, raw2 = l2;
    l1 = clamp(l1, M.smin, M.smax); l2 = clamp(l2, M.smin, M.smax);
    const vol = Math.pow(l1 * l2, -0.5 * M.vp); l1 = clamp(l1 * vol, M.smin, M.smax); l2 = clamp(l2 * vol, M.smin, M.smax);
    // goal = mostly the rest shape, partly the fitted stretch; a slow breath keeps it alive
    this.breath += h; const br = 0.012 * Math.sin(this.breath * 1.9) * (this.held() ? 0 : 1);
    const be = M.beta, e1 = be * l1 + (1 - be), e2 = be * l2 + (1 - be);
    let gxx = cp * cp * e1 + sp * sp * e2 - br * 0.5, gxy = cp * sp * (e1 - e2), gyy = sp * sp * e1 + cp * cp * e2 + br;
    const tg = clamp(th * 0.6, -0.35, 0.35), cg = Math.cos(tg), sg = Math.sin(tg);
    const g00 = (cg * gxx - sg * gxy) * S, g01 = (cg * gxy - sg * gyy) * S, g10 = (sg * gxx + cg * gxy) * S, g11 = (sg * gxy + cg * gyy) * S;
    const dq = tg - th, cq = Math.cos(dq), sq = Math.sin(dq), qs = be * M.quad, lim = S * 1.6, Q = new Float64Array(6);
    for (let c = 0; c < 3; c++) { const x = clamp(A[2 + c], -lim, lim), y = clamp(A[7 + c], -lim, lim); Q[c] = (cq * x - sq * y) * qs; Q[3 + c] = (sq * x + cq * y) * qs; }
    let om = I > 0 ? L / I : 0; om /= (1 + 6 * h);
    const grav = M.grav * S, damp = 1 / (1 + M.c * h);
    let D = 0, sp2 = 0;
    for (let k = 0; k < n; k++) {
      const ux = u[k * 2], uy = u[k * 2 + 1];
      const gx = cx + g00 * ux + g01 * uy + Q[0] * f[k * 5 + 2] + Q[1] * f[k * 5 + 3] + Q[2] * f[k * 5 + 4];
      const gy = cy + g10 * ux + g11 * uy + Q[3] * f[k * 5 + 2] + Q[4] * f[k * 5 + 3] + Q[5] * f[k * 5 + 4];
      g[k * 2] = gx; g[k * 2 + 1] = gy;
      if (!this.sim[k]) continue;
      const rx = p[k * 2] - cx, ry = p[k * 2 + 1] - cy;
      const rvx = vx - om * ry, rvy = vy + om * rx; // rigid part of the motion is not damped
      let dvx = v[k * 2] - rvx, dvy = v[k * 2 + 1] - rvy;
      dvx = (dvx + h * M.k * (gx - p[k * 2])) * damp; dvy = (dvy + h * M.k * (gy - p[k * 2 + 1])) * damp;
      v[k * 2] = rvx + dvx; v[k * 2 + 1] = rvy + dvy + grav * h;
      p[k * 2] += v[k * 2] * h; p[k * 2 + 1] += v[k * 2 + 1] * h;
      // distance from an undeformed copy, for sound and haptics
      const ex = p[k * 2] - (cx + (ct * ux - st * uy) * S), ey = p[k * 2 + 1] - (cy + (st * ux + ct * uy) * S);
      D += ex * ex + ey * ey; sp2 += dvx * dvx + dvy * dvy;
    }
    // fingers hold a soft patch
    let held = 0; const flr = world ? world.floor - this.footPad : 1e9;
    for (const id in this.pointers) {
      const q = this.pointers[id]; held++; q.t += h; q.press += (1 - q.press) * (1 - Math.exp(-h / 0.11));
      const fade = 1 - smooth(S * 0.07, S * 0.45, q.drag), ox = q.px * q.press * fade, oy = q.py * q.press * fade;
      let fx = q.x, fy = q.y; { const dx = fx - cx, dy = fy - cy, d = Math.hypot(dx, dy), mx = S * 1.15; if (d > mx) { fx = cx + dx / d * mx; fy = cy + dy / d * mx; } } // a patch can only be pulled so far from the body
      for (let k = 0; k < n; k++) { const w = q.w[k]; if (w < 0.01) continue; const s = w * 0.5;
        let tx = fx + q.off[k * 2] + ox * q.sc[k], ty = fy + q.off[k * 2 + 1] + oy * q.sc[k];
        if (world) { if (ty > flr) ty = flr; if (world.top != null && ty < world.top) ty = world.top; if (tx < world.left) tx = world.left; if (tx > world.right) tx = world.right; } // a finger cannot push the toy through the floor or a wall
        p[k * 2] += s * (tx - p[k * 2]); p[k * 2 + 1] += s * (ty - p[k * 2 + 1]);
        v[k * 2] += s * (q.vx - v[k * 2]); v[k * 2 + 1] += s * (q.vy - v[k * 2 + 1]); }
    }
    // Floor, walls, ceiling. The whole body is pushed out together (so it never sags under its own weight),
    // and a landing adds a squash on purpose: the far side keeps moving for a moment.
    let impact = 0, contacts = 0;
    if (world) {
      const fl = world.floor - this.footPad;
      let dn = 0, upp = 0, lf = 0, rt = 0, y0 = 1e9, x0 = 1e9, x1 = -1e9, my = 0, mx = 0;
      for (let k = 0; k < n; k++) {
        if (this.sim[k]) { my += v[k * 2 + 1]; mx += v[k * 2]; }
        if (!this.core[k]) continue;
        const x = p[k * 2], y = p[k * 2 + 1];
        if (y - fl > dn) dn = y - fl; if (world.top != null && world.top - y > upp) upp = world.top - y;
        if (world.left - x > lf) lf = world.left - x; if (x - world.right > rt) rt = x - world.right;
        if (y < y0) y0 = y; if (x < x0) x0 = x; if (x > x1) x1 = x;
      }
      my /= this.m; mx /= this.m;
      const land = M.land != null ? M.land : 0.6, Hc = Math.max(S * 0.2, fl - y0), Wc = Math.max(S * 0.2, x1 - x0);
      const cap = S * 0.08, sy = dn > 0 ? -Math.min(dn, cap) : (upp > 0 ? Math.min(upp, cap) : 0), sx = lf > 0 ? Math.min(lf, cap) : (rt > 0 ? -Math.min(rt, cap) : 0);
      const hitF = dn > 0 && my > 0, hitT = upp > 0 && my < 0, hitL = lf > 0 && mx < 0, hitR = rt > 0 && mx > 0;
      if (dn > 0) contacts = 1;
      if (hitF && this.metric.air) impact = Math.max(impact, my);
      if (hitT) impact = Math.max(impact, -my * 0.7); if (hitL) impact = Math.max(impact, -mx * 0.8); if (hitR) impact = Math.max(impact, mx * 0.8);
      const slide = dn > 0 ? mx * Math.min(1, M.fric * h * 14) : 0, soft = S * 6, P = this.push, grip = M.grip || 0;
      // a real landing (not resting contact) starts a short push that squashes the body against the surface
      if (hitF && my > S * 0.6) { P.y = Math.min(my, soft) * land; P.sy = 1; } else if (hitT && -my > S * 0.6) { P.y = Math.min(-my, soft) * land; P.sy = -1; }
      if (hitL && -mx > S * 0.6) { P.x = Math.min(-mx, soft) * land; P.sx = -1; } else if (hitR && mx > S * 0.6) { P.x = Math.min(mx, soft) * land; P.sx = 1; }
      if (P.x > 1 || P.y > 1) {
        for (let k = 0; k < n; k++) { if (!this.sim[k]) continue;
          if (P.y > 1) p[k * 2 + 1] += P.sy * P.y * h * (P.sy > 0 ? clamp((fl - p[k * 2 + 1]) / Hc, 0, 1) : clamp((p[k * 2 + 1] - world.top) / Hc, 0, 1));
          if (P.x > 1) p[k * 2] += P.sx * P.x * h * (P.sx > 0 ? clamp((world.right - p[k * 2]) / Wc, 0, 1) : clamp((p[k * 2] - world.left) / Wc, 0, 1)); }
        const dec = Math.exp(-h / 0.04); P.x *= dec; P.y *= dec;
      }
      for (let k = 0; k < n; k++) {
        if (!this.sim[k]) continue;
        p[k * 2] += sx; p[k * 2 + 1] += sy; v[k * 2] -= slide;
        if (dn > 0 && grip) { const gw = 1 - clamp((fl - p[k * 2 + 1]) / (Hc * 0.7), 0, 1), gf = grip * gw * gw * Math.min(1, h * 30); p[k * 2] -= v[k * 2] * h * gf; v[k * 2] *= (1 - gf); } // the base grips the floor, fading smoothly upwards, so a sideways pull leans and stretches
        if (hitF) v[k * 2 + 1] -= my * (1 + M.rest);
        if (hitT) v[k * 2 + 1] -= my * (1 + M.rest);
        if (hitL) v[k * 2] -= mx * (1 + M.rest);
        if (hitR) v[k * 2] -= mx * (1 + M.rest);
        if (this.core[k]) { // whatever is still outside is put back point by point
          if (p[k * 2 + 1] > fl) p[k * 2 + 1] = fl; else if (world.top != null && p[k * 2 + 1] < world.top) p[k * 2 + 1] = world.top;
          if (p[k * 2] < world.left) p[k * 2] = world.left; else if (p[k * 2] > world.right) p[k * 2] = world.right; }
      }
    }
    for (let k = 0; k < n; k++) if (!this.sim[k]) { p[k * 2] = g[k * 2]; p[k * 2 + 1] = g[k * 2 + 1]; }
    const me = this.metric; let Dn = Math.sqrt(D / this.m) / S;
    if (!(Dn < 2.5)) { for (let k = 0; k < n; k++) { p[k * 2] = isFinite(g[k * 2]) ? g[k * 2] : cx; p[k * 2 + 1] = isFinite(g[k * 2 + 1]) ? g[k * 2 + 1] : cy; v[k * 2] = 0; v[k * 2 + 1] = 0; } Dn = 0; } // never let it explode
    me.rate += 0.25 * (((Dn - me.D) / h) - me.rate); me.D = Dn;
    me.stretch = Math.max(raw1, raw2) - 1; me.squash = 1 - Math.min(raw1, raw2);
    me.impact = Math.max(me.impact, impact / S); me.speed = Math.sqrt(sp2 / this.m) / S; me.held = held; me.air = contacts === 0;
    me.cx = cx; me.cy = cy; this.theta = th;
  };

  /* Draws any number of bodies with WebGL. Each body needs body.tex (a WebGLTexture). */
  function SquishGL(canvas) {
    const gl = this.gl = canvas.getContext('webgl', { alpha: true, premultipliedAlpha: true, antialias: true });
    if (!gl) throw new Error('no webgl');
    this.canvas = canvas;
    const vs = 'attribute vec2 a;attribute vec2 t;uniform vec2 r;varying vec2 q;void main(){q=t;gl_Position=vec4(a.x/r.x*2.-1.,1.-a.y/r.y*2.,0.,1.);}';
    const fs = 'precision mediump float;varying vec2 q;uniform sampler2D s;uniform float o;void main(){gl_FragColor=texture2D(s,q)*o;}';
    const mk = (type, src) => { const sh = gl.createShader(type); gl.shaderSource(sh, src); gl.compileShader(sh); return sh; };
    const pr = this.prog = gl.createProgram(); gl.attachShader(pr, mk(gl.VERTEX_SHADER, vs)); gl.attachShader(pr, mk(gl.FRAGMENT_SHADER, fs)); gl.linkProgram(pr);
    gl.useProgram(pr);
    this.aPos = gl.getAttribLocation(pr, 'a'); this.aUv = gl.getAttribLocation(pr, 't'); this.uRes = gl.getUniformLocation(pr, 'r'); this.uOp = gl.getUniformLocation(pr, 'o');
    this.bPos = gl.createBuffer(); this.bUv = gl.createBuffer(); this.bIdx = gl.createBuffer(); this.idxN = 0; this.idxCount = 0;
    gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  }
  SquishGL.prototype.texture = function (source) { // source: canvas or image, any size (clamped, no mipmaps)
    const gl = this.gl, tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex); gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return tex;
  };
  SquishGL.prototype.resize = function (w, h, dpr) {
    this.w = w; this.h = h; this.canvas.width = Math.round(w * dpr); this.canvas.height = Math.round(h * dpr);
    this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
  };
  SquishGL.prototype.clear = function () { const gl = this.gl; gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT); };
  SquishGL.prototype.draw = function (body, opacity) {
    const gl = this.gl, n = body.n;
    if (this.idxN !== n) {
      const idx = new Uint16Array(n * n * 6); let q = 0;
      for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) { const a = j * (n + 1) + i, b = a + 1, c = a + n + 1, d = c + 1; idx[q++] = a; idx[q++] = b; idx[q++] = c; idx[q++] = b; idx[q++] = d; idx[q++] = c; }
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.bIdx); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STATIC_DRAW); this.idxN = n; this.idxCount = idx.length;
    }
    gl.useProgram(this.prog); gl.uniform2f(this.uRes, this.w, this.h); gl.uniform1f(this.uOp, opacity == null ? 1 : opacity);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.bPos); gl.bufferData(gl.ARRAY_BUFFER, body.p, gl.DYNAMIC_DRAW); gl.enableVertexAttribArray(this.aPos); gl.vertexAttribPointer(this.aPos, 2, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.bUv); gl.bufferData(gl.ARRAY_BUFFER, body.uv, gl.STATIC_DRAW); gl.enableVertexAttribArray(this.aUv); gl.vertexAttribPointer(this.aUv, 2, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.bIdx); gl.bindTexture(gl.TEXTURE_2D, body.tex);
    gl.drawElements(gl.TRIANGLES, this.idxCount, gl.UNSIGNED_SHORT, 0);
  };

  const api = { MATERIALS, SquishBody, SquishGL };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.Squish = api;
})(typeof window !== 'undefined' ? window : this);
