/* Squish Sort soft-body squish, v2 with depth (16 Nov 2026). Game design thread.
   One squishy = a small lattice of points pulled towards a best-fit copy of its rest shape
   ("shape matching", Mueller et al. 2005, quadratic variant). Fingers grab a soft patch of points.
   No dependencies. Works in a browser (window.Squish) and in Node (module.exports) for tests.

   Port notes for SpriteKit: keep SquishBody as is (plain arithmetic), and each frame copy body.p into
   SKWarpGeometryGrid(columns: n, rows: n, sourcePositions: uv, destinationPositions: p normalised to
   the sprite) and assign it to sprite.warpGeometry.

   v2 adds depth, because v1 read as a flat sticker:
   - body.z is a second, finer grid (nz cells a side, in the toy's own picture space) holding how far the
     surface is pushed in. A finger makes a dent there, which fills back slowly (foam) or ripples (jelly, gel).
   - body.tilt slides the painted face a little over the body (parallax), so the toy turns towards a finger.
   - body.surface() packs the dent and the local thickness into bytes for a shader, and Squish.heightField()
     makes the toy's puffy rest shape from its alpha. SquishGL lights the toy from those. */
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
     grabR radius of the firm patch under a finger;  halo strength of the wide soft patch around it
     Depth:
     poke  how deep a finger dents the surface (1 = about the toy's own puffiness);  pokeR radius of the dent, in toy sizes
     zk    spring that fills a dent back in, 1/s^2;  zd its damping, 1/s (high = slow fill, low = ripples)
     zc    speed at which ripples cross the surface, toy sizes per second;  zland how much a landing makes the belly ripple
     puff  how much the whole toy swells while dented (the foam has to go somewhere)
     tk,td spring and damping of the face sliding over the body;  look how far the face turns towards a finger
     Look (used by the drawer): kd strength of light and shade;  gloss and shin size and tightness of the wet highlight;
     ao how dark the inside of a dent gets */
  const MATERIALS = {
    foam: { label: 'Slow-rise foam', k: 300, beta: 0.68, c: 62, quad: 0.55, vp: 0.9, smin: 0.40, smax: 1.7, grav: 9, fric: 0.9, rest: 0.05, press: 0.46, grabR: 0.20, halo: 0.35, land: 0.6, grip: 0.5,
      poke: 0.95, pokeR: 0.13, zk: 77, zd: 60, zc: 0.25, zland: 0, puff: 0.2, tk: 60, td: 14, look: 0.07, kd: 0.6, gloss: 0, shin: 20, ao: 0.42 },
    jelly: { label: 'Jelly', k: 820, beta: 0.7, c: 7.5, quad: 0.6, vp: 1, smin: 0.45, smax: 1.9, grav: 9, fric: 0.55, rest: 0.22, press: 0.44, grabR: 0.20, halo: 0.35, land: 0.75, grip: 0.3,
      poke: 0.8, pokeR: 0.12, zk: 420, zd: 4.5, zc: 0.7, zland: 0.5, puff: 0.15, tk: 180, td: 5, look: 0.08, kd: 0.5, gloss: 0.55, shin: 26, ao: 0.3 },
    gel: { label: 'Gel ball', k: 300, beta: 0.8, c: 12, quad: 0.7, vp: 1, smin: 0.42, smax: 2.1, grav: 11, fric: 0.6, rest: 0.04, press: 0.5, grabR: 0.22, halo: 0.5, land: 1.0, grip: 0.35,
      poke: 1.15, pokeR: 0.16, zk: 90, zd: 8, zc: 0.45, zland: 0.8, puff: 0.25, tk: 50, td: 4, look: 0.09, kd: 0.5, gloss: 0.85, shin: 44, ao: 0.26 },
    mochi: { label: 'Mochi', k: 380, beta: 0.74, c: 12, quad: 0.5, vp: 1, smin: 0.40, smax: 2.6, grav: 9, fric: 1, rest: 0, press: 0.46, grabR: 0.19, halo: 0.3, land: 0.65, grip: 0.9,
      poke: 0.95, pokeR: 0.13, zk: 250, zd: 16, zc: 0.3, zland: 0.2, puff: 0.3, tk: 80, td: 10, look: 0.07, kd: 0.6, gloss: 0.15, shin: 14, ao: 0.4 }
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
    // depth: a finer grid over the same square. z > 0 is pushed in, z < 0 bulges towards the viewer
    const nz = this.nz = o.nz || 32, zc = (nz + 1) * (nz + 1);
    this.z = new Float32Array(zc); this.zv = new Float32Array(zc); this.zl = new Float32Array(zc); this.zmask = new Uint8Array(zc); this.zshape = new Float32Array(zc);
    this.thick = new Float32Array(cnt); this.zres = 3 * nz + 1; this.bytes = new Uint8Array(this.zres * this.zres * 4); this.zcount = 0;
    for (let j = 1; j < nz; j++) for (let i = 1; i < nz; i++) if (inside(i / nz, j / nz)) { const k = j * (nz + 1) + i; this.zmask[k] = 1; this.zcount++; const dx = i / nz - cx, dy = j / nz - cy; this.zshape[k] = Math.exp(-(dx * dx + dy * dy) / 0.06); }
    { // dents fade out towards the outline, so the edge of the toy never shows a cliff
      const Z1 = nz + 1, dd = new Float32Array(zc); for (let k = 0; k < zc; k++) dd[k] = this.zmask[k] ? 99 : 0;
      for (let pass = 0; pass < 2; pass++) for (let a = 0; a < zc; a++) { const k = pass ? zc - 1 - a : a; if (!dd[k]) continue; const i = k % Z1, j = (k / Z1) | 0, s = pass ? 1 : -1;
        if (i + s >= 0 && i + s <= nz) dd[k] = Math.min(dd[k], dd[k + s] + 1); if (j + s >= 0 && j + s <= nz) dd[k] = Math.min(dd[k], dd[k + s * Z1] + 1); }
      this.zedge = new Float32Array(zc); for (let k = 0; k < zc; k++) this.zedge[k] = smooth(0.5, 4, dd[k]);
    }
    this.tilt = { x: 0, y: 0, vx: 0, vy: 0 }; this.zmean = 0;
    this.place(o.x || 0, o.y || 0);
  }

  SquishBody.prototype.place = function (x, y) { // (x, y) = centre of the sprite box
    const S = this.S;
    for (let k = 0; k < this.count; k++) { this.p[k * 2] = x + (this.uv[k * 2] - 0.5) * S; this.p[k * 2 + 1] = y + (this.uv[k * 2 + 1] - 0.5) * S; this.v[k * 2] = 0; this.v[k * 2 + 1] = 0; }
    this.g.set(this.p); this.theta = 0;
    if (this.z) { this.z.fill(0); this.zv.fill(0); this.zmean = 0; this.tilt.x = this.tilt.y = this.tilt.vx = this.tilt.vy = 0; }
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
    // where the finger is on the toy's own picture (0..1), for the dent
    let fu = 0, fv = 0, fw = 0; const r2 = (S * 0.09) * (S * 0.09);
    for (let k = 0; k < this.count; k++) { const dx = this.p[k * 2] - x, dy = this.p[k * 2 + 1] - y, ww = Math.exp(-(dx * dx + dy * dy) / r2) + 1e-9; fu += ww * this.uv[k * 2]; fv += ww * this.uv[k * 2 + 1]; fw += ww; }
    this.pointers[id] = { x, y, sx: x, sy: y, vx: 0, vy: 0, w, off, sc, press: 0, px: (tx - x) * this.mat.press, py: (ty - y) * this.mat.press, t: 0, drag: 0, fu: fu / fw, fv: fv / fw, force: 1 };
    return true;
  };
  /* force (optional): 1 = normal press, up to about 1.6 = pressing hard. Use the touch's contact size where the
     device reports it (UITouch.majorRadius, PointerEvent.width). */
  SquishBody.prototype.move = function (id, x, y, dt, force) {
    const q = this.pointers[id]; if (!q) return;
    if (force != null && isFinite(force)) q.force += 0.3 * (clamp(force, 0.7, 1.6) - q.force);
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
    this.puffed = (this.puffed || 0) + (clamp((M.puff || 0) * this.zmean, 0, 0.08) - (this.puffed || 0)) * (1 - Math.exp(-h / 0.09)); const pf = this.puffed; // a dent pushes the rest of the toy outwards
    const be = M.beta, e1 = be * l1 + (1 - be), e2 = be * l2 + (1 - be);
    let gxx = cp * cp * e1 + sp * sp * e2 - br * 0.5 + pf, gxy = cp * sp * (e1 - e2), gyy = sp * sp * e1 + cp * cp * e2 + br + pf;
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
    const me = this.metric;
    // Depth. The surface is a damped membrane: springs back (zk, zd) and passes ripples along (zc).
    {
      const nz = this.nz, N1 = nz + 1, Z = this.z, ZV = this.zv, ZL = this.zl, ZM = this.zmask;
      const c2 = M.zc * M.zc * nz * nz, zk = M.zk, zdamp = 1 / (1 + M.zd * h);
      if (impact > S * 0.6 && M.zland) { const kick = -Math.min(impact / S, 6) * M.zland * 0.9; for (let k = 0; k < Z.length; k++) if (ZM[k]) ZV[k] += kick * this.zshape[k]; } // a landing makes the belly bulge, then ripple
      for (let j = 1; j < nz; j++) for (let i = 1; i < nz; i++) { const k = j * N1 + i; if (ZM[k]) ZL[k] = Z[k - 1] + Z[k + 1] + Z[k - N1] + Z[k + N1] - 4 * Z[k]; }
      for (let k = 0; k < Z.length; k++) if (ZM[k]) { ZV[k] = (ZV[k] + h * (c2 * ZL[k] - zk * Z[k])) * zdamp; Z[k] += h * ZV[k]; }
      let fuS = 0, fvS = 0;
      for (const id in this.pointers) {
        const q = this.pointers[id], R = M.pokeR, depth = M.poke * q.press * q.force * (1 - 0.3 * smooth(S * 0.07, S * 0.45, q.drag));
        const i0 = Math.max(1, Math.floor((q.fu - 2.6 * R) * nz)), i1 = Math.min(nz - 1, Math.ceil((q.fu + 2.6 * R) * nz)), j0 = Math.max(1, Math.floor((q.fv - 2.6 * R) * nz)), j1 = Math.min(nz - 1, Math.ceil((q.fv + 2.6 * R) * nz));
        for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) { const k = j * N1 + i; if (!ZM[k]) continue;
          const du = i / nz - q.fu, dv = j / nz - q.fv, rr = (du * du + dv * dv) / (R * R), prof = depth * this.zedge[k] * Math.exp(-rr * (0.45 + 0.55 * rr)); // a bowl: flat floor, a clear wall
          if (Z[k] < prof) { Z[k] = prof; if (ZV[k] < 0) ZV[k] = 0; } } // the finger holds the dent open
        fuS += q.fu - this.c0[0]; fvS += q.fv - this.c0[1];
      }
      let zs = 0, zmax = 0, zq = 0;
      for (let k = 0; k < Z.length; k++) if (ZM[k]) { let zz = Z[k]; if (!(zz > -2 && zz < 2)) { zz = Z[k] = clamp(zz || 0, -2, 2); ZV[k] = 0; } if (zz > 0) zs += zz; if (zz > zmax) zmax = zz; zq += zz * zz; }
      this.zmean = this.zcount ? zs / this.zcount : 0;
      const zr = this.zcount ? Math.sqrt(zq / this.zcount) : 0; me.zrate = (me.zrate || 0) + 0.25 * (((zr - (me.Zr || 0)) / h) - (me.zrate || 0)); me.Zr = zr; me.Z = zmax;
      // the painted face slides a little over the body: towards a finger, and lagging behind when the toy moves
      const T = this.tilt, lk = M.look || 0; let tx = 0, ty = 0;
      if (held) { tx = clamp(fuS / held * 2, -1, 1) * lk; ty = clamp(fvS / held * 2, -1, 1) * lk; }
      else { tx = 0.012 * Math.sin(this.breath * 0.63); ty = 0.006 * Math.sin(this.breath * 0.41 + 1); }
      const lvx = clamp(vx / S * 0.007, -0.035, 0.035), lvy = clamp(vy / S * 0.007, -0.035, 0.035), cT = Math.cos(th), sT = Math.sin(th);
      tx -= cT * lvx + sT * lvy; ty -= -sT * lvx + cT * lvy;
      T.vx = (T.vx + h * (M.tk || 60) * (tx - T.x)) / (1 + (M.td || 10) * h); T.x += h * T.vx;
      T.vy = (T.vy + h * (M.tk || 60) * (ty - T.y)) / (1 + (M.td || 10) * h); T.y += h * T.vy;
    }
    let Dn = Math.sqrt(D / this.m) / S;
    if (!(Dn < 2.5)) { for (let k = 0; k < n; k++) { p[k * 2] = isFinite(g[k * 2]) ? g[k * 2] : cx; p[k * 2 + 1] = isFinite(g[k * 2 + 1]) ? g[k * 2 + 1] : cy; v[k * 2] = 0; v[k * 2 + 1] = 0; } Dn = 0; this.z.fill(0); this.zv.fill(0); } // never let it explode
    me.rate += 0.25 * (((Dn - me.D) / h) - me.rate); me.D = Dn;
    me.stretch = Math.max(raw1, raw2) - 1; me.squash = 1 - Math.min(raw1, raw2);
    me.impact = Math.max(me.impact, impact / S); me.speed = Math.sqrt(sp2 / this.m) / S; me.held = held; me.air = contacts === 0;
    me.cx = cx; me.cy = cy; this.theta = th;
  };

  /* Packs the surface for a shader, once per drawn frame. Returns body.bytes: body.zres x body.zres RGBA
     (zres = 3 * nz + 1; the dent grid is smoothed up three times with a cubic B-spline so its light is smooth).
     R and G = the dent as 16 bits (-2..2), B = local thickness (0..2; over 1 where the toy is squeezed
     together in the plane, so it bulges towards the viewer there), A = 255. */
  SquishBody.prototype.surface = function () {
    const n = this.n, N1 = n + 1, p = this.p, T = this.thick, cell = (this.S / n) * (this.S / n);
    const sum = this._sum || (this._sum = new Float32Array(this.count)), wt = this._wt || (this._wt = new Float32Array(this.count)); sum.fill(0); wt.fill(0);
    for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) {
      const a = j * N1 + i, b = a + 1, c = a + N1, d = c + 1;
      const J = 0.5 * Math.abs((p[d * 2] - p[a * 2]) * (p[c * 2 + 1] - p[b * 2 + 1]) - (p[c * 2] - p[b * 2]) * (p[d * 2 + 1] - p[a * 2 + 1])) / cell;
      sum[a] += J; sum[b] += J; sum[c] += J; sum[d] += J; wt[a]++; wt[b]++; wt[c]++; wt[d]++;
    }
    for (let k = 0; k < this.count; k++) T[k] = clamp(Math.pow(Math.max(0.2, sum[k] / wt[k]), -0.8), 0.55, 1.9);
    const nz = this.nz, Z1 = nz + 1, F = 3, R = this.zres, out = this.bytes, Z = this.z, tmp = this._tmp || (this._tmp = new Float32Array(Z1 * R));
    const W = this._bw || (this._bw = [0, 1 / 3, 2 / 3].map((t) => [(1 - t) * (1 - t) * (1 - t) / 6, (3 * t * t * t - 6 * t * t + 4) / 6, (-3 * t * t * t + 3 * t * t + 3 * t + 1) / 6, t * t * t / 6]));
    for (let j = 0; j <= nz; j++) for (let x = 0; x < R; x++) { const i = (x / F) | 0, w = W[x % F], r = j * Z1;
      tmp[j * R + x] = w[0] * Z[r + (i > 0 ? i - 1 : 0)] + w[1] * Z[r + i] + w[2] * Z[r + (i < nz ? i + 1 : nz)] + w[3] * Z[r + (i + 2 < nz ? i + 2 : nz)]; }
    for (let y = 0; y < R; y++) { const j = (y / F) | 0, w = W[y % F], r0 = (j > 0 ? j - 1 : 0) * R, r1 = j * R, r2 = (j < nz ? j + 1 : nz) * R, r3 = (j + 2 < nz ? j + 2 : nz) * R;
      const fy = y / (R - 1) * n, iy = Math.min(n - 1, fy | 0), ay = fy - iy;
      for (let x = 0; x < R; x++) {
        const zf = w[0] * tmp[r0 + x] + w[1] * tmp[r1 + x] + w[2] * tmp[r2 + x] + w[3] * tmp[r3 + x];
        const fx = x / (R - 1) * n, ix = Math.min(n - 1, fx | 0), ax = fx - ix, a = iy * N1 + ix;
        const th = (T[a] * (1 - ax) + T[a + 1] * ax) * (1 - ay) + (T[a + N1] * (1 - ax) + T[a + N1 + 1] * ax) * ay;
        const zz = Math.round(clamp((zf + 2) / 4, 0, 1) * 65535), k = (y * R + x) * 4;
        out[k] = zz >> 8; out[k + 1] = zz & 255; out[k + 2] = Math.round(clamp(th / 2, 0, 1) * 255); out[k + 3] = 255;
      } }
    return out;
  };

  /* The toy's puffy rest shape, made once per toy from its alpha (size x size bytes, row-major).
     Returns size x size RGBA: R and G = height as 16 bits (0..1), B = how much the painted face may slide
     there (0 at the outline, 1 in the middle), A = 255. */
  function heightField(alpha, size, threshold) {
    const N = size, th = threshold == null ? 60 : threshold, d = new Float32Array(N * N), INF = 1e6;
    for (let k = 0; k < N * N; k++) d[k] = alpha[k] > th ? INF : 0;
    const at = (x, y) => (x < 0 || y < 0 || x >= N || y >= N) ? 0 : d[y * N + x];
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) { const k = y * N + x; if (!d[k]) continue; d[k] = Math.min(d[k], at(x - 1, y) + 1, at(x, y - 1) + 1, at(x - 1, y - 1) + 1.414, at(x + 1, y - 1) + 1.414); }
    for (let y = N - 1; y >= 0; y--) for (let x = N - 1; x >= 0; x--) { const k = y * N + x; if (!d[k]) continue; d[k] = Math.min(d[k], at(x + 1, y) + 1, at(x, y + 1) + 1, at(x + 1, y + 1) + 1.414, at(x - 1, y + 1) + 1.414); }
    let dmax = 1e-6; for (let k = 0; k < N * N; k++) { d[k] /= N; if (d[k] > dmax) dmax = d[k]; }
    const h = new Float32Array(N * N), s = new Float32Array(N * N), R0 = Math.min(0.2, dmax * 0.9);
    for (let k = 0; k < N * N; k++) { const t = Math.min(1, d[k] / R0), e = Math.sqrt(1 - (1 - t) * (1 - t)); h[k] = 0.72 * e + 0.28 * Math.min(1, d[k] / dmax); s[k] = smooth(0.03, 0.2, d[k]); }
    const blur = (a, r, passes) => { const t = new Float32Array(N * N);
      for (let q = 0; q < passes; q++) {
        for (let y = 0; y < N; y++) { let acc = 0; for (let x = -r; x <= r; x++) acc += a[y * N + clamp(x, 0, N - 1)]; for (let x = 0; x < N; x++) { t[y * N + x] = acc / (2 * r + 1); acc += a[y * N + clamp(x + r + 1, 0, N - 1)] - a[y * N + clamp(x - r, 0, N - 1)]; } }
        for (let x = 0; x < N; x++) { let acc = 0; for (let y = -r; y <= r; y++) acc += t[clamp(y, 0, N - 1) * N + x]; for (let y = 0; y < N; y++) { a[y * N + x] = acc / (2 * r + 1); acc += t[clamp(y + r + 1, 0, N - 1) * N + x] - t[clamp(y - r, 0, N - 1) * N + x]; } }
      } };
    const r = Math.max(1, Math.round(N / 64)); blur(h, r, 3); blur(s, r, 2);
    const out = new Uint8Array(N * N * 4);
    for (let k = 0; k < N * N; k++) { const v = Math.round(clamp(h[k], 0, 1) * 65535); out[k * 4] = v >> 8; out[k * 4 + 1] = v & 255; out[k * 4 + 2] = Math.round(clamp(s[k], 0, 1) * 255); out[k * 4 + 3] = 255; }
    return out;
  }

  /* Draws any number of bodies with WebGL. Each body needs body.tex (a WebGLTexture) and, for depth, body.htex. */
  function SquishGL(canvas) {
    const gl = this.gl = canvas.getContext('webgl', { alpha: true, premultipliedAlpha: true, antialias: true });
    if (!gl) throw new Error('no webgl');
    this.canvas = canvas;
    const vs = 'attribute vec2 a;attribute vec2 t;uniform vec2 r;varying vec2 q;void main(){q=t;gl_Position=vec4(a.x/r.x*2.-1.,1.-a.y/r.y*2.,0.,1.);}';
    /* s art, hm rest height (heightField), zm surface (body.surface). L light in the toy's own frame.
       m = (kd, gloss, shin, relief), m2 = (pinch, ao, dent relief, depth on/off), e = (1/hm size, zres-1, 1/zres) */
    const fs = [
      'precision highp float;varying vec2 q;uniform sampler2D s;uniform sampler2D hm;uniform sampler2D zm;uniform float o;',
      'uniform vec3 L;uniform vec2 tilt;uniform vec4 m;uniform vec4 m2;uniform vec3 e;',
      'float H(vec2 p){vec4 t=texture2D(hm,p);return (t.r*65280.+t.g*255.)/65535.;}',
      'vec2 zu(vec2 p){return (p*e.y+.5)*e.z;}',
      'float Z(vec2 p){vec4 t=texture2D(zm,zu(p));return (t.r*65280.+t.g*255.)/65535.*4.-2.;}',
      'void main(){',
      ' if(m2.w<.5){gl_FragColor=texture2D(s,q)*o;return;}',
      ' float d1=e.x*1.5,d2=1./e.y;',
      ' vec2 gh=vec2(H(q+vec2(d1,0.))-H(q-vec2(d1,0.)),H(q+vec2(0.,d1))-H(q-vec2(0.,d1)))/(2.*d1);',
      ' vec2 gz=vec2(Z(q+vec2(d2,0.))-Z(q-vec2(d2,0.)),Z(q+vec2(0.,d2))-Z(q-vec2(0.,d2)))/(2.*d2);',
      ' float z=Z(q);vec4 hh=texture2D(hm,q);float th=texture2D(zm,zu(q)).b*2.;',
      ' vec2 p=q-tilt*hh.b-m2.x*gz*hh.b;',
      ' vec4 a=texture2D(s,p);',
      ' vec2 g=gh*th*m.w-gz*m2.z;',
      ' vec3 N=normalize(vec3(-g,1.));',
      ' float nl=dot(N,L)-L.z;',
      ' float al=max(a.a,.0001);vec3 c=a.rgb/al;',
      ' float ink=smoothstep(.1,.38,dot(c,vec3(.3,.59,.11)));',  // 0 on the dark outline, which stays solid
      ' float zin=clamp(z,0.,1.2);float sh=clamp(-nl*m.x,0.,.7)+zin*m2.y;',
      ' c=mix(c,c*c*vec3(.8,.62,.7),clamp(sh,0.,.85));',        // shade is the toy's own colour, deeper
      ' c+=ink*clamp(nl*m.x,0.,.6)*(1.-.5*min(zin,1.))*(vec3(1.,.98,.94)-c)*.75;',   // light
      ' vec3 Hv=normalize(L+vec3(0.,0.,1.));float sp=pow(max(dot(N,Hv),0.),m.z);',
      ' c+=ink*m.y*smoothstep(.25,.95,sp)*(vec3(1.)-c)*.85;',      // wet highlight
      ' gl_FragColor=vec4(clamp(c,0.,1.)*a.a,a.a)*o;}'
    ].join('\n');
    const mk = (type, src) => { const sh = gl.createShader(type); gl.shaderSource(sh, src); gl.compileShader(sh); if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error('shader: ' + gl.getShaderInfoLog(sh)); return sh; };
    const pr = this.prog = gl.createProgram(); gl.attachShader(pr, mk(gl.VERTEX_SHADER, vs)); gl.attachShader(pr, mk(gl.FRAGMENT_SHADER, fs)); gl.linkProgram(pr);
    gl.useProgram(pr);
    this.aPos = gl.getAttribLocation(pr, 'a'); this.aUv = gl.getAttribLocation(pr, 't'); this.U = {};
    ['r', 'o', 's', 'hm', 'zm', 'L', 'tilt', 'm', 'm2', 'e'].forEach((k) => { this.U[k] = gl.getUniformLocation(pr, k); });
    this.bPos = gl.createBuffer(); this.bUv = gl.createBuffer(); this.bIdx = gl.createBuffer(); this.idxN = 0; this.idxCount = 0;
    this.ztex = gl.createTexture(); this.flat = null;
    gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    this.light = [-0.46, -0.62, 0.64]; // from the upper left, towards the viewer
  }
  SquishGL.prototype._params = function (tex) {
    const gl = this.gl;
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return tex;
  };
  SquishGL.prototype.texture = function (source) { // source: canvas or image, any size (clamped, no mipmaps)
    const gl = this.gl, tex = gl.createTexture();
    gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, tex); gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
    return this._params(tex);
  };
  /* bytes: RGBA from Squish.heightField, size x size. Set the result as body.htex and its size as body.hsize. */
  SquishGL.prototype.dataTexture = function (bytes, size, tex) {
    const gl = this.gl; tex = tex || gl.createTexture();
    gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, tex); gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false); gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, size, size, 0, gl.RGBA, gl.UNSIGNED_BYTE, bytes);
    return this._params(tex);
  };
  SquishGL.prototype.resize = function (w, h, dpr) {
    this.w = w; this.h = h; this.canvas.width = Math.round(w * dpr); this.canvas.height = Math.round(h * dpr);
    this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
  };
  SquishGL.prototype.clear = function () { const gl = this.gl; gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT); };
  /* opt.flat = true draws the plain picture with no light (the old look). */
  SquishGL.prototype.draw = function (body, opacity, opt) {
    const gl = this.gl, n = body.n, U = this.U, M = body.mat, depth = !!(body.htex && !(opt && opt.flat));
    if (this.idxN !== n) {
      const idx = new Uint16Array(n * n * 6); let q = 0;
      for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) { const a = j * (n + 1) + i, b = a + 1, c = a + n + 1, d = c + 1; idx[q++] = a; idx[q++] = b; idx[q++] = c; idx[q++] = b; idx[q++] = d; idx[q++] = c; }
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.bIdx); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STATIC_DRAW); this.idxN = n; this.idxCount = idx.length;
    }
    gl.useProgram(this.prog); gl.uniform2f(U.r, this.w, this.h); gl.uniform1f(U.o, opacity == null ? 1 : opacity);
    gl.uniform1i(U.s, 0); gl.uniform1i(U.hm, 1); gl.uniform1i(U.zm, 2);
    if (depth) {
      this.dataTexture(body.surface(), body.zres, this.ztex);
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, body.htex); gl.activeTexture(gl.TEXTURE2); gl.bindTexture(gl.TEXTURE_2D, this.ztex);
      const th = body.theta || 0, c = Math.cos(th), s = Math.sin(th), Lx = this.light[0], Ly = this.light[1]; // the light stays put when the toy turns
      gl.uniform3f(U.L, c * Lx + s * Ly, -s * Lx + c * Ly, this.light[2]);
      gl.uniform2f(U.tilt, body.tilt.x, body.tilt.y);
      gl.uniform4f(U.m, M.kd == null ? 0.5 : M.kd, M.gloss || 0, M.shin || 30, M.relief == null ? 0.2 : M.relief);
      gl.uniform4f(U.m2, M.pinch == null ? 0.004 : M.pinch, M.ao == null ? 0.15 : M.ao, M.zrelief == null ? 0.3 : M.zrelief, 1);
      gl.uniform3f(U.e, 1 / (body.hsize || 128), body.zres - 1, 1 / body.zres);
    } else gl.uniform4f(U.m2, 0, 0, 0, 0);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.bPos); gl.bufferData(gl.ARRAY_BUFFER, body.p, gl.DYNAMIC_DRAW); gl.enableVertexAttribArray(this.aPos); gl.vertexAttribPointer(this.aPos, 2, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.bUv); gl.bufferData(gl.ARRAY_BUFFER, body.uv, gl.STATIC_DRAW); gl.enableVertexAttribArray(this.aUv); gl.vertexAttribPointer(this.aUv, 2, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.bIdx); gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, body.tex);
    gl.drawElements(gl.TRIANGLES, this.idxCount, gl.UNSIGNED_SHORT, 0);
  };

  const api = { MATERIALS, SquishBody, SquishGL, heightField };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.Squish = api;
})(typeof window !== 'undefined' ? window : this);
