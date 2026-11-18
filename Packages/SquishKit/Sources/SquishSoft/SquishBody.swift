import Foundation

/// The soft body behind every squeezable squishy: a small lattice of points
/// pulled towards a best-fit copy of its rest shape ("shape matching", Mueller
/// et al. 2005, quadratic variant). Fingers grab a soft patch of points.
///
/// This is a line-for-line port of `Squish.SquishBody` in the design thread's
/// squish-engine.js, which is the reference. Keep the two in step: storage is
/// single precision and the arithmetic double, exactly as in the page, and
/// SquishSoftTests replays the page's own numbers against it.
/// Coordinates are y-down, like the page.
public final class SquishBody {
    public struct World: Sendable {
        public var floor: Double
        public var left: Double
        public var right: Double
        public var top: Double?

        public init(floor: Double, left: Double, right: Double, top: Double? = nil) {
            self.floor = floor
            self.left = left
            self.right = right
            self.top = top
        }
    }

    /// The numbers that drive sound and haptics.
    public struct Metric: Sendable {
        /// How far the body is from an undeformed copy of itself, in body sizes.
        public var D = 0.0
        /// How fast `D` is changing: positive is pressing in, negative is rising back.
        public var rate = 0.0
        public var stretch = 0.0
        public var squash = 0.0
        /// The hardest landing since this was last set to zero, in body sizes per second.
        public var impact = 0.0
        public var speed = 0.0
        public var held = 0
        public var air = false
        public var cx = 0.0
        public var cy = 0.0
        /// The deepest point of the dent (positive is pushed in).
        public var Z = 0.0
        /// How fast the dent as a whole is changing.
        public var zrate = 0.0
        var Zr = 0.0
    }

    /// The painted face slides a little over the body: towards a finger, and lagging behind when the toy moves.
    public struct Tilt: Sendable {
        public var x = 0.0
        public var y = 0.0
        var vx = 0.0
        var vy = 0.0
    }

    public struct Pointer {
        public var x: Double
        public var y: Double
        var sx: Double
        var sy: Double
        public var vx = 0.0
        public var vy = 0.0
        var w: [Float]
        var off: [Float]
        var sc: [Float]
        var press = 0.0
        var px: Double
        var py: Double
        var t = 0.0
        var drag = 0.0
        /// Where the finger is on the toy's own picture (0...1), for the dent.
        var fu = 0.0
        var fv = 0.0
        /// 1 = a normal press, up to about 1.6 = pressing hard.
        var force = 1.0
        /// How much toy lies between the finger and each side (below, above, left, right).
        var rb = 1.0
        var rt = 1.0
        var rl = 1.0
        var rr = 1.0
        /// Where the finger effectively is this step.
        var ex = 0.0
        var ey = 0.0
    }

    public struct Bounds: Sendable {
        public var x0: Double
        public var x1: Double
        public var y0: Double
        public var y1: Double
    }

    /// Cells per side. The lattice has `(n + 1) * (n + 1)` points.
    public let n: Int
    public let count: Int
    /// Size of the sprite's square, in points.
    public let size: Double
    public var material: SquishMaterial
    /// Rest positions in 0...1, row by row from the top left.
    public private(set) var uv: [Float]
    /// Current positions, two numbers per point.
    public private(set) var p: [Float]
    public private(set) var metric = Metric()
    public private(set) var theta = 0.0
    public var breath: Double
    /// 0 turns the idle breath off (Reduce Motion).
    public var breathScale = 1.0

    private var u: [Float]
    private var f: [Float]
    private var v: [Float]
    private var g: [Float]
    private var sim: [Bool]
    private var core: [Bool]
    private var pointers: [Int: Pointer] = [:]
    private var push = (x: 0.0, y: 0.0, sx: 1.0, sy: 1.0)
    private var m = 1.0
    private var minv = [Double](repeating: 0, count: 25)
    public private(set) var footPad = 0.0
    public private(set) var baseV = 0.0
    public private(set) var halfW = 0.0
    public private(set) var c0 = (x: 0.5, y: 0.5)
    /// The art's own box in the picture, 0...1.
    private var box = (l: 0.0, r: 1.0, t: 0.0, b: 1.0)
    /// The fitted stretch along its two main directions and their angle, for the drawer:
    /// the painted face keeps more of its own shape than the outline does.
    public private(set) var fit = (first: 1.0, second: 1.0, angle: 0.0)

    /// How far the painted face should be pulled back towards its own shape when the
    /// outline is squashed: a real toy's front bulges towards you, it does not flatten
    /// like a drawing. `keep` is how much of its shape the face keeps (0 none, 1 all).
    /// The three numbers are a symmetric 2 by 2 matrix (xx, xy, yy) for the light shader.
    public func faceStretch(keep: Double) -> (xx: Double, xy: Double, yy: Double) {
        let first: Double = min(max(fit.first, 0.3), 2.4)
        let second: Double = min(max(fit.second, 0.3), 2.4)
        let a1: Double = min(max(pow(first, keep), 0.62), 1.3) - 1
        let a2: Double = min(max(pow(second, keep), 0.62), 1.3) - 1
        let cp: Double = cos(fit.angle), sp: Double = sin(fit.angle)
        let xx: Double = cp * cp * a1 + sp * sp * a2
        let xy: Double = cp * sp * (a1 - a2)
        let yy: Double = sp * sp * a1 + cp * cp * a2
        return (xx, xy, yy)
    }

    // Depth: a finer grid over the same square. z > 0 is pushed in, z < 0 bulges towards the viewer.
    /// Cells per side of the dent grid.
    public let nz: Int
    /// The dent grid, `(nz + 1) * (nz + 1)` values, row by row from the top left.
    public private(set) var z: [Float]
    private var zv: [Float]
    private var zl: [Float]
    private var zmask: [Bool]
    private var zshape: [Float]
    private var zedge: [Float]
    private var zcount = 0
    private var zmean = 0.0
    private var puffed = 0.0
    private var thick: [Float]
    /// Side of the packed surface that `surface()` returns.
    public let zres: Int
    private var bytes: [UInt8]
    private var surfaceSum: [Float]
    private var surfaceWeight: [Float]
    private var surfaceRows: [Float]
    public private(set) var tilt = Tilt()

    /// - Parameters:
    ///   - inside: whether the art covers the point (u, v), both 0...1 with v downwards.
    ///   - footV: where the art's true lowest pixel sits (0...1), if below the lowest lattice point.
    ///   - x, y: the centre of the sprite's square.
    public init(size: Double, n: Int = 12, material: SquishMaterial, x: Double = 0, y: Double = 0,
                footV: Double? = nil, breath: Double = Double.random(in: 0..<6), nz: Int = 32,
                inside: (Double, Double) -> Bool = { _, _ in true }) {
        self.n = n
        self.nz = nz
        let zc = (nz + 1) * (nz + 1)
        z = [Float](repeating: 0, count: zc)
        zv = [Float](repeating: 0, count: zc)
        zl = [Float](repeating: 0, count: zc)
        zmask = [Bool](repeating: false, count: zc)
        zshape = [Float](repeating: 0, count: zc)
        zedge = [Float](repeating: 0, count: zc)
        zres = 3 * nz + 1
        bytes = [UInt8](repeating: 0, count: (3 * nz + 1) * (3 * nz + 1) * 4)
        surfaceRows = [Float](repeating: 0, count: (nz + 1) * (3 * nz + 1))
        let cnt = (n + 1) * (n + 1)
        thick = [Float](repeating: 0, count: cnt)
        surfaceSum = [Float](repeating: 0, count: cnt)
        surfaceWeight = [Float](repeating: 0, count: cnt)
        count = cnt
        self.size = size
        self.material = material
        self.breath = breath
        uv = [Float](repeating: 0, count: cnt * 2)
        u = [Float](repeating: 0, count: cnt * 2)
        f = [Float](repeating: 0, count: cnt * 5)
        p = [Float](repeating: 0, count: cnt * 2)
        v = [Float](repeating: 0, count: cnt * 2)
        g = [Float](repeating: 0, count: cnt * 2)
        sim = [Bool](repeating: false, count: cnt)
        core = [Bool](repeating: false, count: cnt)
        let dn = Double(n)
        for j in 0...n {
            for i in 0...n {
                let k = j * (n + 1) + i
                uv[k * 2] = Float(Double(i) / dn)
                uv[k * 2 + 1] = Float(Double(j) / dn)
                core[k] = inside(Double(i) / dn, Double(j) / dn)
            }
        }
        // Simulate the silhouette plus one ring of cells, so the outline itself deforms.
        for j in 0...n {
            for i in 0...n {
                var s = false
                for dj in -1...1 {
                    for di in -1...1 {
                        let a = i + di, b = j + dj
                        if a >= 0, b >= 0, a <= n, b <= n, core[b * (n + 1) + a] { s = true }
                    }
                }
                sim[j * (n + 1) + i] = s
            }
        }
        var cx = 0.0, cy = 0.0, mm = 0.0, foot = 0.0, top = 1.0, left = 1.0, right = 0.0
        for k in 0..<cnt where sim[k] {
            cx += Double(uv[k * 2])
            cy += Double(uv[k * 2 + 1])
            mm += 1
        }
        for k in 0..<cnt where core[k] {
            foot = max(foot, Double(uv[k * 2 + 1]))
            top = min(top, Double(uv[k * 2 + 1]))
            left = min(left, Double(uv[k * 2]))
            right = max(right, Double(uv[k * 2]))
        }
        // An empty silhouette would divide by zero: treat the whole square as the toy.
        if mm == 0 {
            for k in 0..<cnt {
                sim[k] = true
                core[k] = true
                cx += Double(uv[k * 2])
                cy += Double(uv[k * 2 + 1])
            }
            mm = Double(cnt)
            foot = 1
            top = 0
            left = 0
            right = 1
        }
        cx /= mm
        cy /= mm
        m = mm
        c0 = (cx, cy)
        footPad = max(0, (footV ?? foot) - foot) * size
        baseV = foot - cy
        halfW = (right - left) / 2
        box = (left, right, top, max(foot, footV ?? foot))
        var mean = [0.0, 0.0, 0.0]
        for k in 0..<cnt {
            let x = Double(uv[k * 2]) - cx, y = Double(uv[k * 2 + 1]) - cy
            u[k * 2] = Float(x)
            u[k * 2 + 1] = Float(y)
            if sim[k] {
                mean[0] += x * x
                mean[1] += y * y
                mean[2] += x * y
            }
        }
        mean[0] /= mm
        mean[1] /= mm
        mean[2] /= mm
        var aqq = [Double](repeating: 0, count: 25)
        for k in 0..<cnt {
            let x = Double(u[k * 2]), y = Double(u[k * 2 + 1])
            let q = [x, y, x * x - mean[0], y * y - mean[1], x * y - mean[2]]
            for a in 0..<5 { f[k * 5 + a] = Float(q[a]) }
            if sim[k] {
                for a in 0..<5 {
                    for b in 0..<5 { aqq[a * 5 + b] += q[a] * q[b] }
                }
            }
        }
        minv = SquishBody.inv5(aqq)
        let dz = Double(nz)
        for j in 1..<nz {
            for i in 1..<nz where inside(Double(i) / dz, Double(j) / dz) {
                let k = j * (nz + 1) + i
                zmask[k] = true
                zcount += 1
                let dx = Double(i) / dz - cx, dy = Double(j) / dz - cy
                zshape[k] = Float(exp(-(dx * dx + dy * dy) / 0.06))
            }
        }
        // Dents fade out towards the outline, so the edge of the toy never shows a cliff.
        let z1 = nz + 1
        var dd = [Float](repeating: 0, count: zc)
        for k in 0..<zc { dd[k] = zmask[k] ? 99 : 0 }
        for pass in 0..<2 {
            for a in 0..<zc {
                let k = pass == 1 ? zc - 1 - a : a
                if dd[k] == 0 { continue }
                let i = k % z1, j = k / z1, s = pass == 1 ? 1 : -1
                if i + s >= 0, i + s <= nz { dd[k] = min(dd[k], dd[k + s] + 1) }
                if j + s >= 0, j + s <= nz { dd[k] = min(dd[k], dd[k + s * z1] + 1) }
            }
        }
        for k in 0..<zc { zedge[k] = Float(SquishBody.smooth(0.5, 4, Double(dd[k]))) }
        place(x: x, y: y)
    }

    /// Puts the body, undeformed and still, with the centre of its square at (x, y).
    public func place(x: Double, y: Double) {
        for k in 0..<count {
            p[k * 2] = Float(x + (Double(uv[k * 2]) - 0.5) * size)
            p[k * 2 + 1] = Float(y + (Double(uv[k * 2 + 1]) - 0.5) * size)
            v[k * 2] = 0
            v[k * 2 + 1] = 0
        }
        g = p
        theta = 0
        clearDent()
        zmean = 0
        tilt = Tilt()
    }

    private func clearDent() {
        for k in z.indices {
            z[k] = 0
            zv[k] = 0
        }
    }

    /// Slides the whole body sideways without changing its shape or speed (the Buddy walking home).
    /// Not part of the reference engine: the app calls it only while the toy sits still.
    public func shift(dx: Double) {
        for k in 0..<count {
            p[k * 2] += Float(dx)
            g[k * 2] += Float(dx)
        }
    }

    /// Stops all movement where it is (Reduce Motion: let go without a throw).
    public func stop() {
        for i in v.indices { v[i] = 0 }
    }

    /// The landing has been heard and felt: start listening for the next one.
    public func clearImpact() { metric.impact = 0 }

    public func centre() -> (x: Double, y: Double) {
        var x = 0.0, y = 0.0
        for k in 0..<count where sim[k] {
            x += Double(p[k * 2])
            y += Double(p[k * 2 + 1])
        }
        return (x / m, y / m)
    }

    public func bounds() -> Bounds {
        var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9
        for k in 0..<count where core[k] {
            let x = Double(p[k * 2]), y = Double(p[k * 2 + 1])
            if x < x0 { x0 = x }
            if x > x1 { x1 = x }
            if y < y0 { y0 = y }
            if y > y1 { y1 = y }
        }
        return Bounds(x0: x0, x1: x1, y0: y0, y1: y1 + footPad)
    }

    // MARK: - Fingers

    /// Returns true if the finger landed on the squishy.
    @discardableResult
    /// `dent` puts the dent somewhere other than the patch: press-only places take the patch near the
    /// top of the toy, so the whole toy squashes, and leave the dent under the finger.
    public func grab(_ id: Int, x: Double, y: Double, dent: (x: Double, y: Double)? = nil) -> Bool {
        let S = size, R = material.grabR * S
        var best = 1e9
        for k in 0..<count where core[k] {
            let d = hypot(Double(p[k * 2]) - x, Double(p[k * 2 + 1]) - y)
            if d < best { best = d }
        }
        if best > S * 0.16 { return false }
        var w = [Float](repeating: 0, count: count)
        var off = [Float](repeating: 0, count: count * 2)
        var sc = [Float](repeating: 0, count: count)
        let halo = material.halo
        for k in 0..<count where sim[k] {
            let dx = Double(p[k * 2]) - x, dy = Double(p[k * 2 + 1]) - y, d2 = (dx * dx + dy * dy) / (R * R)
            // A firm dimple plus a soft halo.
            w[k] = Float(min(1, exp(-d2) + halo * exp(-d2 / 5.3)))
            off[k * 2] = Float(dx)
            off[k * 2 + 1] = Float(dy)
        }
        let c = centre(), b = bounds()
        // A press pushes towards the base when resting, or towards the middle when held in the air.
        // Mostly straight down, so an off-centre press does not fold the toy over.
        let tx = metric.air ? c.x : x + 0.35 * (c.x - x), ty = metric.air ? c.y : b.y1
        let ax = x - tx, ay = y - ty
        var al = ax * ax + ay * ay
        if al == 0 { al = 1 }
        // 0 at the base, 1 at the finger: how much of the press each point takes.
        for k in 0..<count {
            let share = ((Double(p[k * 2]) - tx) * ax + (Double(p[k * 2 + 1]) - ty) * ay) / al
            sc[k] = Float(SquishBody.clamp(share, 0, 1.15))
        }
        // Where the finger is on the toy's own picture (0...1), for the dent.
        var fu = 0.0, fv = 0.0, fw = 0.0
        let r2 = (S * 0.09) * (S * 0.09)
        let zx = dent?.x ?? x, zy = dent?.y ?? y
        for k in 0..<count {
            let dx = Double(p[k * 2]) - zx, dy = Double(p[k * 2 + 1]) - zy
            let ww = exp(-(dx * dx + dy * dy) / r2) + 1e-9
            fu += ww * Double(uv[k * 2])
            fv += ww * Double(uv[k * 2 + 1])
            fw += ww
        }
        let fu0 = fu / fw, fv0 = fv / fw
        var made = Pointer(x: x, y: y, sx: x, sy: y, w: w, off: off, sc: sc,
                           px: (tx - x) * material.press, py: (ty - y) * material.press, fu: fu0, fv: fv0)
        made.rb = max(b.y1 - y, (box.b - fv0) * S)
        made.rt = max(y - b.y0, (fv0 - box.t) * S)
        made.rl = max(x - b.x0, (fu0 - box.l) * S)
        made.rr = max(b.x1 - x, (box.r - fu0) * S)
        pointers[id] = made
        return true
    }

    /// `force`: 1 = a normal press, up to about 1.6 = pressing hard (from the touch's contact size).
    public func move(_ id: Int, x: Double, y: Double, dt: Double, force: Double? = nil) {
        guard var q = pointers[id] else { return }
        if let force, force.isFinite { q.force += 0.3 * (SquishBody.clamp(force, 0.7, 1.6) - q.force) }
        let h = max(dt > 0 ? dt : 1.0 / 60, 1.0 / 240), a = 0.5
        q.vx += a * ((x - q.x) / h - q.vx)
        q.vy += a * ((y - q.y) / h - q.vy)
        q.x = x
        q.y = y
        q.drag = max(q.drag, hypot(x - q.sx, y - q.sy))
        pointers[id] = q
    }

    @discardableResult
    public func release(_ id: Int) -> Pointer? {
        pointers.removeValue(forKey: id)
    }

    public func releaseAll() { pointers.removeAll() }

    public var isHeld: Bool { !pointers.isEmpty }

    // MARK: - Step

    public func step(_ h: Double, world: World?) {
        let M = material, S = size, n = count
        var cx = 0.0, cy = 0.0, vx = 0.0, vy = 0.0
        for k in 0..<n where sim[k] {
            cx += Double(p[k * 2])
            cy += Double(p[k * 2 + 1])
            vx += Double(v[k * 2])
            vy += Double(v[k * 2 + 1])
        }
        cx /= m
        cy /= m
        vx /= m
        vy /= m
        // Best quadratic fit of the current points to the rest shape.
        var B = [Double](repeating: 0, count: 10)
        var L = 0.0, I = 0.0
        for k in 0..<n where sim[k] {
            let rx = Double(p[k * 2]) - cx, ry = Double(p[k * 2 + 1]) - cy
            for a in 0..<5 {
                let fa = Double(f[k * 5 + a])
                B[a] += rx * fa
                B[5 + a] += ry * fa
            }
            L += rx * (Double(v[k * 2 + 1]) - vy) - ry * (Double(v[k * 2]) - vx)
            I += rx * rx + ry * ry
        }
        var A = [Double](repeating: 0, count: 10)
        for r in 0..<2 {
            for c in 0..<5 {
                var s = 0.0
                for j in 0..<5 { s += B[r * 5 + j] * minv[j * 5 + c] }
                A[r * 5 + c] = s
            }
        }
        var a00 = A[0] / S, a01 = A[1] / S, a10 = A[5] / S, a11 = A[6] / S
        if !(a00 + a01 + a10 + a11).isFinite {
            a00 = 1
            a01 = 0
            a10 = 0
            a11 = 1
        }
        let th = atan2(a10 - a01, a00 + a11), ct = cos(th), st = sin(th)
        // Stretch part, symmetric: Rt * A.
        let sxx = ct * a00 + st * a10
        let sxy = 0.5 * ((ct * a01 + st * a11) + (-st * a00 + ct * a10))
        let syy = -st * a01 + ct * a11
        let ph = 0.5 * atan2(2 * sxy, sxx - syy), cp = cos(ph), sp = sin(ph)
        var l1 = cp * cp * sxx + 2 * cp * sp * sxy + sp * sp * syy
        var l2 = sp * sp * sxx - 2 * cp * sp * sxy + cp * cp * syy
        let raw1 = l1, raw2 = l2
        l1 = SquishBody.clamp(l1, M.smin, M.smax)
        l2 = SquishBody.clamp(l2, M.smin, M.smax)
        let vol = pow(l1 * l2, -0.5 * M.vp)
        l1 = SquishBody.clamp(l1 * vol, M.smin, M.smax)
        l2 = SquishBody.clamp(l2 * vol, M.smin, M.smax)
        // Goal = mostly the rest shape, partly the fitted stretch; a slow breath keeps it alive.
        breath += h
        let br = 0.012 * sin(breath * 1.9) * (isHeld ? 0 : 1) * breathScale
        // A dent pushes the rest of the toy outwards.
        puffed += (SquishBody.clamp(M.puff * zmean, 0, 0.08) - puffed) * (1 - exp(-h / 0.09))
        let pf = puffed
        let be = M.beta, e1 = be * l1 + (1 - be), e2 = be * l2 + (1 - be)
        let gxx = cp * cp * e1 + sp * sp * e2 - br * 0.5 + pf
        let gxy = cp * sp * (e1 - e2)
        let gyy = sp * sp * e1 + cp * cp * e2 + br + pf
        let tg = SquishBody.clamp(th * 0.6, -0.35, 0.35), cg = cos(tg), sg = sin(tg)
        let g00 = (cg * gxx - sg * gxy) * S, g01 = (cg * gxy - sg * gyy) * S
        let g10 = (sg * gxx + cg * gxy) * S, g11 = (sg * gxy + cg * gyy) * S
        let dq = tg - th, cq = cos(dq), sq = sin(dq), qs = be * M.quad, lim = S * 1.6
        var Q = [Double](repeating: 0, count: 6)
        for c in 0..<3 {
            let x = SquishBody.clamp(A[2 + c], -lim, lim), y = SquishBody.clamp(A[7 + c], -lim, lim)
            Q[c] = (cq * x - sq * y) * qs
            Q[3 + c] = (sq * x + cq * y) * qs
        }
        var om = I > 0 ? L / I : 0
        om /= (1 + 6 * h)
        let grav = M.grav * S, damp = 1 / (1 + M.c * h)
        var D = 0.0, sp2 = 0.0
        // The goal shape knows about the floor and walls. Without this, a toy pushed down aims half of
        // itself below the floor, and that half collapses flat onto it: the "folded drawing" look.
        var gdn = 0.0, gup = 0.0, glf = 0.0, grt = 0.0
        let wfl = world.map { $0.floor - footPad } ?? 0
        for k in 0..<n {
            let ux = Double(u[k * 2]), uy = Double(u[k * 2 + 1])
            let f2 = Double(f[k * 5 + 2]), f3 = Double(f[k * 5 + 3]), f4 = Double(f[k * 5 + 4])
            let gx: Double = cx + g00 * ux + g01 * uy + Q[0] * f2 + Q[1] * f3 + Q[2] * f4
            let gy: Double = cy + g10 * ux + g11 * uy + Q[3] * f2 + Q[4] * f3 + Q[5] * f4
            g[k * 2] = Float(gx)
            g[k * 2 + 1] = Float(gy)
            if let world, core[k] {
                if gy - wfl > gdn { gdn = gy - wfl }
                if let top = world.top, top - gy > gup { gup = top - gy }
                if world.left - gx > glf { glf = world.left - gx }
                if gx - world.right > grt { grt = gx - world.right }
            }
        }
        let gsx = glf > 0 ? glf : -grt, gsy = gdn > 0 ? -gdn : gup
        for k in 0..<n {
            let ux = Double(u[k * 2]), uy = Double(u[k * 2 + 1])
            g[k * 2] = Float(Double(g[k * 2]) + gsx)
            g[k * 2 + 1] = Float(Double(g[k * 2 + 1]) + gsy)
            let gx = Double(g[k * 2]), gy = Double(g[k * 2 + 1])
            if !sim[k] { continue }
            let rx = Double(p[k * 2]) - cx, ry = Double(p[k * 2 + 1]) - cy
            // The rigid part of the motion is not damped.
            let rvx = vx - om * ry, rvy = vy + om * rx
            var dvx = Double(v[k * 2]) - rvx, dvy = Double(v[k * 2 + 1]) - rvy
            dvx = (dvx + h * M.k * (gx - Double(p[k * 2]))) * damp
            dvy = (dvy + h * M.k * (gy - Double(p[k * 2 + 1]))) * damp
            v[k * 2] = Float(rvx + dvx)
            v[k * 2 + 1] = Float(rvy + dvy + grav * h)
            p[k * 2] = Float(Double(p[k * 2]) + Double(v[k * 2]) * h)
            p[k * 2 + 1] = Float(Double(p[k * 2 + 1]) + Double(v[k * 2 + 1]) * h)
            // Distance from an undeformed copy, for sound and haptics.
            let ex = Double(p[k * 2]) - (cx + (ct * ux - st * uy) * S)
            let ey = Double(p[k * 2 + 1]) - (cy + (st * ux + ct * uy) * S)
            D += ex * ex + ey * ey
            sp2 += dvx * dvx + dvy * dvy
        }
        // Fingers hold a soft patch.
        var held = 0
        let flr = world.map { $0.floor - footPad } ?? 1e9
        let firm = M.firm
        let ids = pointers.keys.sorted()
        // Where each finger effectively is: it cannot pull a patch too far from the body, and two fingers
        // cannot pinch the toy between them thinner than its limit.
        for id in ids {
            guard var q = pointers[id] else { continue }
            var fx = q.x, fy = q.y
            let ddx = fx - cx, ddy = fy - cy, dd = hypot(ddx, ddy), far = S * 1.15
            if dd > far {
                fx = cx + ddx / dd * far
                fy = cy + ddy / dd * far
            }
            q.ex = fx
            q.ey = fy
            pointers[id] = q
        }
        for a in 0..<ids.count {
            for b in (a + 1)..<max(a + 1, ids.count) {
                guard var A = pointers[ids[a]], var B = pointers[ids[b]] else { continue }
                let d0 = hypot(A.fu - B.fu, A.fv - B.fv) * S * firm
                let dx = B.ex - A.ex, dy = B.ey - A.ey, d = hypot(dx, dy)
                if d < d0 && d0 > 1 {
                    let nx = d > 0.5 ? dx / d : 1, ny = d > 0.5 ? dy / d : 0, add = (d0 - d) / 2
                    A.ex -= nx * add
                    A.ey -= ny * add
                    B.ex += nx * add
                    B.ey += ny * add
                    pointers[ids[a]] = A
                    pointers[ids[b]] = B
                }
            }
        }
        for id in ids {
            guard var q = pointers[id] else { continue }
            held += 1
            q.t += h
            q.press += (1 - q.press) * (1 - exp(-h / 0.11))
            pointers[id] = q
            let fade = 1 - SquishBody.smooth(S * 0.07, S * 0.45, q.drag)
            let ox = q.px * q.press * fade, oy = q.py * q.press * fade
            var fx = q.ex, fy = q.ey
            if let world {
                // The toy has a core. A finger can squash the part between it and a surface to a share (firm)
                // of its thickness and no further: past that the finger just sinks in and the dent takes over.
                var ex = fx + ox, ey = fy + oy
                let ex0 = ex, ey0 = ey
                if ey > flr - firm * q.rb { ey = flr - firm * q.rb }
                if let top = world.top, ey < top + firm * q.rt { ey = top + firm * q.rt }
                if ex < world.left + firm * q.rl { ex = world.left + firm * q.rl }
                if ex > world.right - firm * q.rr { ex = world.right - firm * q.rr }
                fx += ex - ex0
                fy += ey - ey0
            }
            // The patch is not a rigid plate. The part of it between the finger and a surface is squeezed in
            // proportion, so the far edge of the toy lands on the surface instead of the lower half piling up flat.
            var rd = 1.0, ru = 1.0, rl = 1.0, rr = 1.0
            if let world {
                rd = SquishBody.clamp((flr - fy) / q.rb, 0.05, 1)
                if let top = world.top { ru = SquishBody.clamp((fy - top) / q.rt, 0.05, 1) }
                rl = SquishBody.clamp((fx - world.left) / q.rl, 0.05, 1)
                rr = SquishBody.clamp((world.right - fx) / q.rr, 0.05, 1)
            }
            for k in 0..<n {
                let w = Double(q.w[k])
                if w < 0.01 { continue }
                let s = w * 0.5
                let ofx = Double(q.off[k * 2]), ofy = Double(q.off[k * 2 + 1])
                var tx: Double = fx + ofx * (ofx < 0 ? rl : rr) + ox * Double(q.sc[k])
                var ty: Double = fy + ofy * (ofy > 0 ? rd : ru) + oy * Double(q.sc[k])
                // A finger cannot push the toy through the floor or a wall.
                if let world {
                    if ty > flr { ty = flr }
                    if let top = world.top, ty < top { ty = top }
                    if tx < world.left { tx = world.left }
                    if tx > world.right { tx = world.right }
                }
                p[k * 2] = Float(Double(p[k * 2]) + s * (tx - Double(p[k * 2])))
                p[k * 2 + 1] = Float(Double(p[k * 2 + 1]) + s * (ty - Double(p[k * 2 + 1])))
                v[k * 2] = Float(Double(v[k * 2]) + s * (q.vx - Double(v[k * 2])))
                v[k * 2 + 1] = Float(Double(v[k * 2 + 1]) + s * (q.vy - Double(v[k * 2 + 1])))
            }
        }
        // A soft toy cannot be squashed paper thin. Past its limit (firm) it pushes back hard, in any
        // direction, so fully squished it is a fat pancake and the finger simply sinks into it.
        let lo = min(raw1, raw2)
        if lo < firm {
            let gm = SquishBody.smooth(firm, firm * 0.62, lo) * 0.55
            for k in 0..<n where sim[k] {
                p[k * 2] = Float(Double(p[k * 2]) + (Double(g[k * 2]) - Double(p[k * 2])) * gm)
                p[k * 2 + 1] = Float(Double(p[k * 2 + 1]) + (Double(g[k * 2 + 1]) - Double(p[k * 2 + 1])) * gm)
            }
        }
        // Floor, walls, ceiling. The whole body is pushed out together (so it never sags under its
        // own weight), and a landing adds a squash on purpose: the far side keeps moving for a moment.
        var impact = 0.0
        var contacts = 0
        if let world {
            let fl = world.floor - footPad
            let top = world.top
            var dn = 0.0, upp = 0.0, lf = 0.0, rt = 0.0, y0 = 1e9, x0 = 1e9, x1 = -1e9, my = 0.0, mx = 0.0
            for k in 0..<n {
                if sim[k] {
                    my += Double(v[k * 2 + 1])
                    mx += Double(v[k * 2])
                }
                if !core[k] { continue }
                let x = Double(p[k * 2]), y = Double(p[k * 2 + 1])
                if y - fl > dn { dn = y - fl }
                if let top, top - y > upp { upp = top - y }
                if world.left - x > lf { lf = world.left - x }
                if x - world.right > rt { rt = x - world.right }
                if y < y0 { y0 = y }
                if x < x0 { x0 = x }
                if x > x1 { x1 = x }
            }
            my /= m
            mx /= m
            let land = M.land, Hc = max(S * 0.2, fl - y0), Wc = max(S * 0.2, x1 - x0)
            let cap = S * 0.08
            let sy = dn > 0 ? -min(dn, cap) : (upp > 0 ? min(upp, cap) : 0)
            let sx = lf > 0 ? min(lf, cap) : (rt > 0 ? -min(rt, cap) : 0)
            let hitF = dn > 0 && my > 0, hitT = upp > 0 && my < 0, hitL = lf > 0 && mx < 0, hitR = rt > 0 && mx > 0
            if dn > 0 { contacts = 1 }
            if hitF && metric.air { impact = max(impact, my) }
            if hitT { impact = max(impact, -my * 0.7) }
            if hitL { impact = max(impact, -mx * 0.8) }
            if hitR { impact = max(impact, mx * 0.8) }
            // Only a real hit bounces. Slow contact just stops, or a resting toy would hop from its own breathing.
            let eY = abs(my) > S * 0.6 ? M.rest : 0.0, eX = abs(mx) > S * 0.6 ? M.rest : 0.0
            let slide = dn > 0 ? mx * min(1, M.fric * h * 14) : 0
            let soft = S * 6, grip = M.grip
            // A real landing (not resting contact) starts a short push that squashes the body against the surface.
            if hitF && my > S * 0.6 {
                push.y = min(my, soft) * land
                push.sy = 1
            } else if hitT && -my > S * 0.6 {
                push.y = min(-my, soft) * land
                push.sy = -1
            }
            if hitL && -mx > S * 0.6 {
                push.x = min(-mx, soft) * land
                push.sx = -1
            } else if hitR && mx > S * 0.6 {
                push.x = min(mx, soft) * land
                push.sx = 1
            }
            if push.x > 1 || push.y > 1 {
                let topY = top ?? 0
                for k in 0..<n where sim[k] {
                    if push.y > 1 {
                        let py = Double(p[k * 2 + 1])
                        let share = push.sy > 0 ? SquishBody.clamp((fl - py) / Hc, 0, 1) : SquishBody.clamp((py - topY) / Hc, 0, 1)
                        p[k * 2 + 1] = Float(py + push.sy * push.y * h * share)
                    }
                    if push.x > 1 {
                        let px = Double(p[k * 2])
                        let share = push.sx > 0 ? SquishBody.clamp((world.right - px) / Wc, 0, 1) : SquishBody.clamp((px - world.left) / Wc, 0, 1)
                        p[k * 2] = Float(px + push.sx * push.x * h * share)
                    }
                }
                let dec = exp(-h / 0.04)
                push.x *= dec
                push.y *= dec
            }
            for k in 0..<n where sim[k] {
                p[k * 2] = Float(Double(p[k * 2]) + sx)
                p[k * 2 + 1] = Float(Double(p[k * 2 + 1]) + sy)
                v[k * 2] = Float(Double(v[k * 2]) - slide)
                if dn > 0 && grip != 0 {
                    // The base grips the floor, fading smoothly upwards, so a sideways pull leans and stretches.
                    let gw = 1 - SquishBody.clamp((fl - Double(p[k * 2 + 1])) / (Hc * 0.7), 0, 1)
                    let gf = grip * gw * gw * min(1, h * 30)
                    p[k * 2] = Float(Double(p[k * 2]) - Double(v[k * 2]) * h * gf)
                    v[k * 2] = Float(Double(v[k * 2]) * (1 - gf))
                }
                if hitF { v[k * 2 + 1] = Float(Double(v[k * 2 + 1]) - my * (1 + eY)) }
                if hitT { v[k * 2 + 1] = Float(Double(v[k * 2 + 1]) - my * (1 + eY)) }
                if hitL { v[k * 2] = Float(Double(v[k * 2]) - mx * (1 + eX)) }
                if hitR { v[k * 2] = Float(Double(v[k * 2]) - mx * (1 + eX)) }
                if core[k] {
                    // Whatever is still outside is put back point by point.
                    if Double(p[k * 2 + 1]) > fl {
                        p[k * 2 + 1] = Float(fl)
                    } else if let top, Double(p[k * 2 + 1]) < top {
                        p[k * 2 + 1] = Float(top)
                    }
                    if Double(p[k * 2]) < world.left {
                        p[k * 2] = Float(world.left)
                    } else if Double(p[k * 2]) > world.right {
                        p[k * 2] = Float(world.right)
                    }
                }
            }
        }
        for k in 0..<n where !sim[k] {
            p[k * 2] = g[k * 2]
            p[k * 2 + 1] = g[k * 2 + 1]
        }
        // Depth. The surface is a damped membrane: it springs back (zk, zd) and passes ripples along (zc).
        do {
            let N1 = nz + 1, dz = Double(nz)
            let c2 = M.zc * M.zc * dz * dz, zk = M.zk, zdamp = 1 / (1 + M.zd * h)
            if impact > S * 0.6 && M.zland != 0 {
                // A landing makes the belly bulge, then ripple.
                let kick = -min(impact / S, 6) * M.zland * 0.9
                for k in z.indices where zmask[k] { zv[k] = Float(Double(zv[k]) + kick * Double(zshape[k])) }
            }
            for j in 1..<nz {
                for i in 1..<nz {
                    let k = j * N1 + i
                    if zmask[k] {
                        let across: Double = Double(z[k - 1]) + Double(z[k + 1])
                        let down: Double = Double(z[k - N1]) + Double(z[k + N1])
                        zl[k] = Float(across + down - 4 * Double(z[k]))
                    }
                }
            }
            for k in z.indices where zmask[k] {
                zv[k] = Float((Double(zv[k]) + h * (c2 * Double(zl[k]) - zk * Double(z[k]))) * zdamp)
                z[k] = Float(Double(z[k]) + h * Double(zv[k]))
            }
            var fuS = 0.0, fvS = 0.0
            for id in pointers.keys.sorted() {
                guard let q = pointers[id] else { continue }
                let R = M.pokeR
                let depth = M.poke * q.press * q.force * (1 - 0.3 * SquishBody.smooth(S * 0.07, S * 0.45, q.drag))
                let reach: Double = 2.6 * R
                let i0: Int = max(1, Int(((q.fu - reach) * dz).rounded(.down)))
                let i1: Int = min(nz - 1, Int(((q.fu + reach) * dz).rounded(.up)))
                let j0: Int = max(1, Int(((q.fv - reach) * dz).rounded(.down)))
                let j1: Int = min(nz - 1, Int(((q.fv + reach) * dz).rounded(.up)))
                if i0 <= i1 && j0 <= j1 {
                    for j in j0...j1 {
                        for i in i0...i1 {
                            let k = j * N1 + i
                            if !zmask[k] { continue }
                            let du = Double(i) / dz - q.fu, dv = Double(j) / dz - q.fv, rr = (du * du + dv * dv) / (R * R)
                            // A bowl: flat floor, a clear wall.
                            let prof = depth * Double(zedge[k]) * exp(-rr * (0.45 + 0.55 * rr))
                            // The finger holds the dent open.
                            if Double(z[k]) < prof {
                                z[k] = Float(prof)
                                if zv[k] < 0 { zv[k] = 0 }
                            }
                        }
                    }
                }
                fuS += q.fu - c0.x
                fvS += q.fv - c0.y
            }
            var zs = 0.0, zmax = 0.0, zq = 0.0
            for k in z.indices where zmask[k] {
                var zz = Double(z[k])
                if !(zz > -2 && zz < 2) {
                    zz = SquishBody.clamp(zz.isNaN ? 0 : zz, -2, 2)
                    z[k] = Float(zz)
                    zv[k] = 0
                }
                if zz > 0 { zs += zz }
                if zz > zmax { zmax = zz }
                zq += zz * zz
            }
            zmean = zcount > 0 ? zs / Double(zcount) : 0
            let zr = zcount > 0 ? (zq / Double(zcount)).squareRoot() : 0
            metric.zrate += 0.25 * (((zr - metric.Zr) / h) - metric.zrate)
            metric.Zr = zr
            metric.Z = zmax
            // The painted face slides a little over the body.
            let lk = M.look
            var tx = 0.0, ty = 0.0
            if held > 0 {
                tx = SquishBody.clamp(fuS / Double(held) * 2, -1, 1) * lk
                ty = SquishBody.clamp(fvS / Double(held) * 2, -1, 1) * lk
            } else {
                tx = 0.012 * sin(breath * 0.63) * breathScale
                ty = 0.006 * sin(breath * 0.41 + 1) * breathScale
            }
            let lvx: Double = SquishBody.clamp(vx / S * 0.007, -0.035, 0.035)
            let lvy: Double = SquishBody.clamp(vy / S * 0.007, -0.035, 0.035)
            let cT = cos(th), sT = sin(th)
            tx -= cT * lvx + sT * lvy
            ty -= -sT * lvx + cT * lvy
            tilt.vx = (tilt.vx + h * M.tk * (tx - tilt.x)) / (1 + M.td * h)
            tilt.x += h * tilt.vx
            tilt.vy = (tilt.vy + h * M.tk * (ty - tilt.y)) / (1 + M.td * h)
            tilt.y += h * tilt.vy
        }
        var Dn = (D / m).squareRoot() / S
        if !(Dn < 2.5) {
            // Never let it explode.
            for k in 0..<n {
                p[k * 2] = g[k * 2].isFinite ? g[k * 2] : Float(cx)
                p[k * 2 + 1] = g[k * 2 + 1].isFinite ? g[k * 2 + 1] : Float(cy)
                v[k * 2] = 0
                v[k * 2 + 1] = 0
            }
            Dn = 0
            clearDent()
        }
        metric.rate += 0.25 * (((Dn - metric.D) / h) - metric.rate)
        metric.D = Dn
        metric.stretch = max(raw1, raw2) - 1
        metric.squash = 1 - min(raw1, raw2)
        metric.impact = max(metric.impact, impact / S)
        metric.speed = (sp2 / m).squareRoot() / S
        metric.held = held
        metric.air = contacts == 0
        metric.cx = cx
        metric.cy = cy
        theta = th
        fit = (raw1, raw2, ph)
    }

    // MARK: - Surface

    /// Packs the surface for the shader, once per drawn frame: `zres` by `zres` RGBA, top row first.
    /// R and G = the dent as 16 bits (-2...2), smoothed up three times with a cubic B-spline so its
    /// light is smooth. B = local thickness (0...2; over 1 where the toy is squeezed together in the
    /// plane, so it bulges towards the viewer there). A = 255.
    public func surface() -> [UInt8] {
        let N1 = n + 1
        let cell = (size / Double(n)) * (size / Double(n))
        for k in 0..<count {
            surfaceSum[k] = 0
            surfaceWeight[k] = 0
        }
        for j in 0..<n {
            for i in 0..<n {
                let a = j * N1 + i, b = a + 1, c = a + N1, d = c + 1
                let ax = Double(p[d * 2]) - Double(p[a * 2]), ay = Double(p[c * 2 + 1]) - Double(p[b * 2 + 1])
                let bx = Double(p[c * 2]) - Double(p[b * 2]), by = Double(p[d * 2 + 1]) - Double(p[a * 2 + 1])
                let J: Double = 0.5 * abs(ax * ay - bx * by) / cell
                for k in [a, b, c, d] {
                    surfaceSum[k] = Float(Double(surfaceSum[k]) + J)
                    surfaceWeight[k] += 1
                }
            }
        }
        for k in 0..<count {
            let share = Double(surfaceSum[k]) / Double(surfaceWeight[k])
            thick[k] = Float(SquishBody.clamp(pow(max(0.2, share), -0.8), 0.55, 1.9))
        }
        let Z1 = nz + 1, F = 3, R = zres
        let W = SquishBody.splineWeights
        for j in 0...nz {
            let r = j * Z1
            for x in 0..<R {
                let i = x / F, w = W[x % F]
                let a = Double(z[r + (i > 0 ? i - 1 : 0)]), b = Double(z[r + min(i, nz)])
                let c = Double(z[r + (i < nz ? i + 1 : nz)]), d = Double(z[r + (i + 2 < nz ? i + 2 : nz)])
                let row: Double = w[0] * a + w[1] * b + w[2] * c + w[3] * d
                surfaceRows[j * R + x] = Float(row)
            }
        }
        let dn = Double(n)
        for y in 0..<R {
            let j = y / F, w = W[y % F]
            let r0 = (j > 0 ? j - 1 : 0) * R, r1 = min(j, nz) * R, r2 = (j < nz ? j + 1 : nz) * R, r3 = (j + 2 < nz ? j + 2 : nz) * R
            let fy = Double(y) / Double(R - 1) * dn, iy = min(n - 1, Int(fy)), ay = fy - Double(iy)
            for x in 0..<R {
                let s0: Double = w[0] * Double(surfaceRows[r0 + x]), s1: Double = w[1] * Double(surfaceRows[r1 + x])
                let s2: Double = w[2] * Double(surfaceRows[r2 + x]), s3: Double = w[3] * Double(surfaceRows[r3 + x])
                let zf: Double = s0 + s1 + s2 + s3
                let fx = Double(x) / Double(R - 1) * dn, ix = min(n - 1, Int(fx)), ax = fx - Double(ix), a = iy * N1 + ix
                let top: Double = Double(thick[a]) * (1 - ax) + Double(thick[a + 1]) * ax
                let bottom: Double = Double(thick[a + N1]) * (1 - ax) + Double(thick[a + N1 + 1]) * ax
                let th: Double = top * (1 - ay) + bottom * ay
                let zz = Int((SquishBody.clamp((zf + 2) / 4, 0, 1) * 65535).rounded())
                let k = (y * R + x) * 4
                bytes[k] = UInt8(zz >> 8)
                bytes[k + 1] = UInt8(zz & 255)
                bytes[k + 2] = UInt8((SquishBody.clamp(th / 2, 0, 1) * 255).rounded())
                bytes[k + 3] = 255
            }
        }
        return bytes
    }

    private static let splineWeights: [[Double]] = [0.0, 1.0 / 3, 2.0 / 3].map(splineWeight)

    /// Cubic B-spline weights of the four nearest dent values, `t` of the way from one to the next.
    private static func splineWeight(_ t: Double) -> [Double] {
        let u: Double = 1 - t
        let t2: Double = t * t
        let t3: Double = t2 * t
        let w0: Double = u * u * u / 6
        let w1: Double = (3 * t3 - 6 * t2 + 4) / 6
        let w2: Double = (-3 * t3 + 3 * t2 + 3 * t + 1) / 6
        let w3: Double = t3 / 6
        return [w0, w1, w2, w3]
    }

    /// The toy's puffy rest shape, made once per toy from its alpha (`size` by `size` bytes, top row first).
    /// Returns `size` by `size` RGBA: R and G = height as 16 bits (0...1), B = how much the painted
    /// face may slide there (0 at the outline, 1 in the middle), A = 255.
    public static func heightField(alpha: [UInt8], size N: Int, threshold: UInt8 = 60) -> [UInt8] {
        guard N > 0, alpha.count >= N * N else { return [] }
        var d = [Float](repeating: 0, count: N * N)
        for k in 0..<(N * N) { d[k] = alpha[k] > threshold ? 1e6 : 0 }
        func at(_ x: Int, _ y: Int) -> Double { (x < 0 || y < 0 || x >= N || y >= N) ? 0 : Double(d[y * N + x]) }
        for y in 0..<N {
            for x in 0..<N {
                let k = y * N + x
                if d[k] == 0 { continue }
                let straight: Double = min(at(x - 1, y) + 1, at(x, y - 1) + 1)
                let slant: Double = min(at(x - 1, y - 1) + 1.414, at(x + 1, y - 1) + 1.414)
                let best: Double = min(Double(d[k]), straight, slant)
                d[k] = Float(best)
            }
        }
        for y in stride(from: N - 1, through: 0, by: -1) {
            for x in stride(from: N - 1, through: 0, by: -1) {
                let k = y * N + x
                if d[k] == 0 { continue }
                let straight: Double = min(at(x + 1, y) + 1, at(x, y + 1) + 1)
                let slant: Double = min(at(x + 1, y + 1) + 1.414, at(x - 1, y + 1) + 1.414)
                let best: Double = min(Double(d[k]), straight, slant)
                d[k] = Float(best)
            }
        }
        var dmax = 1e-6
        for k in 0..<(N * N) {
            d[k] = Float(Double(d[k]) / Double(N))
            if Double(d[k]) > dmax { dmax = Double(d[k]) }
        }
        var h = [Float](repeating: 0, count: N * N), s = [Float](repeating: 0, count: N * N)
        let R0 = min(0.2, dmax * 0.9)
        for k in 0..<(N * N) {
            let dk = Double(d[k])
            let t = min(1, dk / R0), e = (1 - (1 - t) * (1 - t)).squareRoot()
            h[k] = Float(0.72 * e + 0.28 * min(1, dk / dmax))
            s[k] = Float(smooth(0.03, 0.2, dk))
        }
        func blur(_ a: inout [Float], _ r: Int, _ passes: Int) {
            var t = [Float](repeating: 0, count: N * N)
            let span = Double(2 * r + 1)
            func cl(_ v: Int) -> Int { v < 0 ? 0 : (v > N - 1 ? N - 1 : v) }
            for _ in 0..<passes {
                for y in 0..<N {
                    var acc = 0.0
                    for x in -r...r { acc += Double(a[y * N + cl(x)]) }
                    for x in 0..<N {
                        t[y * N + x] = Float(acc / span)
                        acc += Double(a[y * N + cl(x + r + 1)]) - Double(a[y * N + cl(x - r)])
                    }
                }
                for x in 0..<N {
                    var acc = 0.0
                    for y in -r...r { acc += Double(t[cl(y) * N + x]) }
                    for y in 0..<N {
                        a[y * N + x] = Float(acc / span)
                        acc += Double(t[cl(y + r + 1) * N + x]) - Double(t[cl(y - r) * N + x])
                    }
                }
            }
        }
        let r = max(1, Int((Double(N) / 64).rounded()))
        blur(&h, r, 3)
        blur(&s, r, 2)
        var out = [UInt8](repeating: 0, count: N * N * 4)
        for k in 0..<(N * N) {
            let v = Int((clamp(Double(h[k]), 0, 1) * 65535).rounded())
            out[k * 4] = UInt8(v >> 8)
            out[k * 4 + 1] = UInt8(v & 255)
            out[k * 4 + 2] = UInt8((clamp(Double(s[k]), 0, 1) * 255).rounded())
            out[k * 4 + 3] = 255
        }
        return out
    }

    // MARK: - Helpers

    static func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { x < a ? a : (x > b ? b : x) }

    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = clamp((x - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)
    }

    /// Inverse of a 5 by 5 matrix, row by row (Gauss-Jordan).
    static func inv5(_ mat: [Double]) -> [Double] {
        let n = 5
        var a = [Double](repeating: 0, count: 50)
        for r in 0..<n {
            for c in 0..<n { a[r * 10 + c] = mat[r * n + c] }
            a[r * 10 + n + r] = 1
        }
        for col in 0..<n {
            var piv = col
            for r in (col + 1)..<max(col + 1, n) where abs(a[r * 10 + col]) > abs(a[piv * 10 + col]) { piv = r }
            if piv != col {
                for c in 0..<10 { a.swapAt(col * 10 + c, piv * 10 + c) }
            }
            var d = a[col * 10 + col]
            if d == 0 { d = 1e-9 }
            for c in 0..<10 { a[col * 10 + c] /= d }
            for r in 0..<n where r != col {
                let factor = a[r * 10 + col]
                if factor != 0 {
                    for c in 0..<10 { a[r * 10 + c] -= factor * a[col * 10 + c] }
                }
            }
        }
        var out = [Double](repeating: 0, count: 25)
        for r in 0..<n {
            for c in 0..<n { out[r * n + c] = a[r * 10 + n + c] }
        }
        return out
    }
}
