import Foundation

/// A rope body for long squishies such as Taffy Snake, and for floppy limbs (tails, ears, trunks).
/// A chain of points along a spine: pulling straightens its curves (it uncoils) and letting go
/// coils it back up. Ported line for line from the design thread's squish-rope.js v1, and held to
/// it by a parity test.
///
/// Each step: (1) Verlet with gravity and a little damping; (2) a coil spring towards a best-fit
/// turned copy of the rest shape, much weaker while a finger holds it; (3) a few passes of
/// constraints: segment lengths, local curl, fingers, floor and walls; (4) a finger held still
/// bulges the tube under it.
public final class SquishRope {
    public struct Material: Sendable {
        public var k: Double
        public var heldK: Double
        public var curl: Double
        public var upright: Double
        public var smin: Double
        public var smax: Double
        public var give: Double
        public var damp: Double
        public var grav: Double
        public var fric: Double
        public var rest: Double
        public var iters: Int
        public var squeeze: Double
        public var squeezeLen: Double

        public init(k: Double, heldK: Double, curl: Double, upright: Double = 0, smin: Double = 0.8, smax: Double,
                    give: Double = 0.25, damp: Double, grav: Double, fric: Double = 0.6, rest: Double = 0.3,
                    iters: Int = 8, squeeze: Double = 0.2, squeezeLen: Double = 0.1) {
            self.k = k; self.heldK = heldK; self.curl = curl; self.upright = upright
            self.smin = smin; self.smax = smax; self.give = give; self.damp = damp; self.grav = grav
            self.fric = fric; self.rest = rest; self.iters = iters; self.squeeze = squeeze; self.squeezeLen = squeezeLen
        }

        public static let taffy = Material(k: 300, heldK: 0.04, curl: 0.05, upright: 3, smin: 0.86, smax: 1.22, give: 0.35,
                                           damp: 1.1, grav: 9, fric: 0.85, rest: 0.42, iters: 8, squeeze: 0.3, squeezeLen: 0.12)
        public static let trunk = Material(k: 900, heldK: 0.05, curl: 0.12, upright: 0, smin: 0.8, smax: 2.4, give: 0.25,
                                           damp: 2.2, grav: 4, fric: 0.6, rest: 0.3, iters: 8, squeeze: 0.2, squeezeLen: 0.1)
    }

    public struct World: Sendable {
        public var floor: Double
        public var left: Double
        public var right: Double
        public init(floor: Double, left: Double, right: Double) {
            self.floor = floor; self.left = left; self.right = right
        }
    }

    public struct Metric: Sendable {
        public var D = 0.0
        public var rate = 0.0
        public var stretch = 0.0
        public var squash = 0.0
        /// 0 coiled, 1 pulled out straight.
        public var unravel = 0.0
        public var impact = 0.0
        public var speed = 0.0
        public var held = false
        /// Set once on let-go after a good pull: the caller plays the spring-back and clears it.
        public var recoil = 0.0
    }

    /// Where a limb grows from: a point on the body and the body's turn, read every step.
    public struct Root: Sendable {
        public var x: Double
        public var y: Double
        public var a: Double
        public init(x: Double, y: Double, a: Double) {
            self.x = x; self.y = y; self.a = a
        }
    }

    private struct Pointer {
        var i: Int
        var x: Double
        var y: Double
        var ox: Double
        var oy: Double
        var still: Double
        var sx: Double
        var sy: Double
    }

    public let n: Int
    public let scale: Double
    public let size: Double
    public let material: Material
    /// Points, x then y. `q` holds the step before, `r` the rest shape round its middle.
    public private(set) var p: [Double]
    private var q: [Double]
    private var r: [Double]
    private var L0: [Double]
    private var Lk: [Double]
    private var bend: [Double]
    /// How much each point's tube is bulged by a squeeze (1 is none).
    public private(set) var w: [Double]
    private var inv: [Double]
    public private(set) var rad: [Double]
    public var root: (() -> Root)?
    public let restLen: Double
    public let restE2E: Double
    private let headAngle0: Double
    private var ga: Double?
    private var pointers: [Int: Pointer] = [:]
    private var squeezeAmt = 0.0
    private var squeezeAt = -1
    public var metric = Metric()
    public private(set) var angle = 0.0
    public private(set) var length = 0.0

    /// Sample cubic Bezier segments (art units) and resample to n points spaced evenly along the curve.
    public static func resample(cubics: [[Double]], n: Int) -> (pts: [(x: Double, y: Double)], length: Double) {
        var pts: [(x: Double, y: Double)] = []
        for c in cubics {
            for i in 0...60 {
                if i == 0 && !pts.isEmpty { continue }
                let t = Double(i) / 60, u = 1 - t
                let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
                pts.append((a * c[0] + b * c[2] + d * c[4] + e * c[6], a * c[1] + b * c[3] + d * c[5] + e * c[7]))
            }
        }
        var acc = [0.0]
        for i in 1..<pts.count { acc.append(acc[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        let total = acc[acc.count - 1]
        var out: [(x: Double, y: Double)] = []
        var j = 0
        for i in 0..<n {
            let s = total * Double(i) / Double(n - 1)
            while j < acc.count - 2 && acc[j + 1] < s { j += 1 }
            let f = (s - acc[j]) / max(1e-9, acc[j + 1] - acc[j])
            out.append((pts[j].x + (pts[j + 1].x - pts[j].x) * f, pts[j].y + (pts[j + 1].y - pts[j].y) * f))
        }
        return (out, total)
    }

    /// A polyline in art units instead of cubics.
    public static func resample(points: [[Double]], n: Int) -> (pts: [(x: Double, y: Double)], length: Double) {
        var c: [[Double]] = []
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            c.append([a[0], a[1], a[0] + (b[0] - a[0]) / 3, a[1] + (b[1] - a[1]) / 3,
                      a[0] + 2 * (b[0] - a[0]) / 3, a[1] + 2 * (b[1] - a[1]) / 3, b[0], b[1]])
        }
        return resample(cubics: c, n: n)
    }

    /// `cubics` or `points` in art units (120 = the toy's box), `size` in points for 120 units, `x`, `y` where
    /// the middle of the chain goes, `radius` the tube's half-thickness and `headR` the head's, in art units.
    public init(cubics: [[Double]]? = nil, points: [[Double]]? = nil, n: Int = 28, size: Double = 240,
                x: Double = 0, y: Double = 0, radius: Double = 15.5, headR: Double = 22,
                material: Material = .taffy, root: (() -> Root)? = nil) {
        self.n = n
        self.size = size
        self.material = material
        let sc = size / 120
        scale = sc
        let rs = points.map { SquishRope.resample(points: $0, n: n) } ?? SquishRope.resample(cubics: cubics ?? [], n: n)
        p = [Double](repeating: 0, count: n * 2)
        q = [Double](repeating: 0, count: n * 2)
        var r = [Double](repeating: 0, count: n * 2)
        var L0 = [Double](repeating: 0, count: n - 1)
        Lk = [Double](repeating: 1, count: n - 1)
        var bend = [Double](repeating: 0, count: n)
        w = [Double](repeating: 1, count: n)
        inv = [Double](repeating: 1, count: n)
        var rad = [Double](repeating: 0, count: n)
        var cx = 0.0, cy = 0.0
        for pt in rs.pts { cx += pt.x; cy += pt.y }
        cx /= Double(n); cy /= Double(n)
        for i in 0..<n {
            r[i * 2] = (rs.pts[i].x - cx) * sc
            r[i * 2 + 1] = (rs.pts[i].y - cy) * sc
        }
        for i in 0..<(n - 1) { L0[i] = hypot(r[i * 2 + 2] - r[i * 2], r[i * 2 + 3] - r[i * 2 + 1]) }
        // Signed height of each joint over the line between its neighbours, as a share of that line's length.
        if n > 2 {
            for i in 1..<(n - 1) {
                let ax = r[i * 2 - 2], ay = r[i * 2 - 1], bx = r[i * 2 + 2], by = r[i * 2 + 3]
                let dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy
                bend[i] = ((r[i * 2] - (ax + bx) / 2) * -dy + (r[i * 2 + 1] - (ay + by) / 2) * dx) / l2
            }
        }
        let tube = radius * sc, head = headR * sc
        for i in 0..<n { rad[i] = i < 2 ? head : tube }
        self.r = r
        self.L0 = L0
        self.bend = bend
        self.rad = rad
        self.root = root
        restLen = rs.length * sc
        restE2E = hypot(r[(n - 1) * 2] - r[0], r[(n - 1) * 2 + 1] - r[1])
        headAngle0 = atan2(r[1] - r[3], r[0] - r[2])
        place(x: x, y: y)
    }

    public func place(x: Double, y: Double) {
        for i in 0..<n {
            p[i * 2] = x + r[i * 2]; q[i * 2] = p[i * 2]
            p[i * 2 + 1] = y + r[i * 2 + 1]; q[i * 2 + 1] = p[i * 2 + 1]
        }
    }

    public func nearest(x: Double, y: Double) -> (i: Int, d: Double) {
        var best = -1, bd = Double.infinity
        for i in 0..<n {
            let d = hypot(p[i * 2] - x, p[i * 2 + 1] - y) - rad[i]
            if d < bd { bd = d; best = i }
        }
        return (best, bd)
    }

    /// Returns false when the touch misses it (more than a finger's width away).
    @discardableResult
    public func grab(_ id: Int, x: Double, y: Double) -> Bool {
        let h = nearest(x: x, y: y)
        if h.d > size * 0.12 { return false }
        let i = root != nil ? max(2, h.i) : h.i
        pointers[id] = Pointer(i: i, x: x, y: y, ox: p[i * 2] - x, oy: p[i * 2 + 1] - y, still: 0, sx: x, sy: y)
        return true
    }

    public func move(_ id: Int, x: Double, y: Double) {
        guard var f = pointers[id] else { return }
        f.x = x; f.y = y
        if hypot(x - f.sx, y - f.sy) > size * 0.04 { f.still = -1; f.sx = x; f.sy = y }
        pointers[id] = f
    }

    public func release(_ id: Int) {
        let had = pointers.removeValue(forKey: id) != nil
        if had && !isHeld && metric.unravel > 0.25 { metric.recoil = metric.unravel }
    }

    public var isHeld: Bool { !pointers.isEmpty }

    /// `h`: step in seconds (use 1/240 and several steps per frame).
    public func step(_ h: Double, world: World) {
        let M = material, S = size, held = isHeld
        let g = M.grav * S, damp = 1 - M.damp * h
        var speed = 0.0
        // 1. Verlet
        var vy0 = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let vx = (p[i * 2] - q[i * 2]) * damp, vy = (p[i * 2 + 1] - q[i * 2 + 1]) * damp
            vy0[i] = vy
            q[i * 2] = p[i * 2]; q[i * 2 + 1] = p[i * 2 + 1]
            p[i * 2] += vx; p[i * 2 + 1] += vy + g * h * h
            speed += hypot(vx, vy) / h
        }
        // Squeeze: a finger held still for a moment bulges the tube under it.
        let ids = pointers.keys.sorted()
        var sq = false, at = -1
        for id in ids {
            guard var f = pointers[id], f.still >= 0 else { continue }
            f.still += h
            if f.still > 0.12 { sq = true; at = f.i }
            pointers[id] = f
        }
        squeezeAmt += ((sq ? 1 : 0) - squeezeAmt) * min(1, h * (sq ? 9 : 5))
        if at >= 0 { squeezeAt = at }
        for i in 0..<n {
            let d = squeezeAt < 0 ? 99.0 : Double(abs(i - squeezeAt))
            let e = exp(-(d * d) / 5) * squeezeAmt
            w[i] = 1 + M.squeeze * e
            if i < n - 1 { Lk[i] = 1 - M.squeezeLen * e }
        }
        // 2. Coil spring: pull towards the best-fit turned rest shape.
        if let root {
            // A limb holds its rest curl in the body's frame, and its first two points ride on the body.
            let R = root(), co = cos(R.a), si = sin(R.a)
            let a = min(max(M.k * h * h, 0), 1) * (held ? M.heldK : 1)
            let r0x = r[0], r0y = r[1]
            for i in 0..<n {
                let rx = r[i * 2] - r0x, ry = r[i * 2 + 1] - r0y
                let gx = R.x + co * rx - si * ry, gy = R.y + si * rx + co * ry
                if i < 2 {
                    p[i * 2] = gx; p[i * 2 + 1] = gy; inv[i] = 0
                } else {
                    p[i * 2] += (gx - p[i * 2]) * a; p[i * 2 + 1] += (gy - p[i * 2 + 1]) * a
                }
            }
            angle = R.a
        } else {
            var cx = 0.0, cy = 0.0
            for i in 0..<n { cx += p[i * 2]; cy += p[i * 2 + 1] }
            cx /= Double(n); cy /= Double(n)
            var A = 0.0, B = 0.0
            for i in 0..<n {
                let dx = p[i * 2] - cx, dy = p[i * 2 + 1] - cy, rx = r[i * 2], ry = r[i * 2 + 1]
                A += rx * dy - ry * dx; B += rx * dx + ry * dy
            }
            var th = atan2(A, B)
            // Goal angle: follows it while held; when let go it eases back to upright (never more than
            // 0.5 rad ahead of where it is), so it rolls back the right way up with a wobble.
            if held || ga == nil {
                ga = th
            } else if var goal = ga {
                goal += -goal * min(1, M.upright * h)
                var off = goal - th
                while off > Double.pi { off -= 2 * Double.pi }
                while off < -Double.pi { off += 2 * Double.pi }
                goal = th + min(max(off, -0.5), 0.5)
                ga = goal
                th = goal
            }
            let co = cos(th), si = sin(th)
            let a = min(max(M.k * h * h, 0), 1) * (held ? M.heldK : 1)
            for i in 0..<n {
                let rx = r[i * 2], ry = r[i * 2 + 1]
                p[i * 2] += (cx + co * rx - si * ry - p[i * 2]) * a
                p[i * 2 + 1] += (cy + si * rx + co * ry - p[i * 2 + 1]) * a
            }
            angle = th
        }
        // 3. Constraints
        for id in ids { if let f = pointers[id] { inv[f.i] = 0 } }
        if root != nil { inv[0] = 0; inv[1] = 0 }
        let curl = M.curl * (held ? 0.35 : 1)
        for _ in 0..<M.iters {
            for i in 0..<(n - 1) {
                let j = i + 1
                let dx = p[j * 2] - p[i * 2], dy = p[j * 2 + 1] - p[i * 2 + 1]
                var d = hypot(dx, dy)
                if d == 0 { d = 1e-6 }
                let L = L0[i] * Lk[i]
                var target = d
                if d > L * M.smax { target = L * M.smax } else if d < L * M.smin { target = L * M.smin } else { target = d + (L - d) * M.give }
                let wi = inv[i], wj = inv[j], ws = wi + wj
                if ws == 0 { continue }
                let c = (d - target) / d / ws
                p[i * 2] += dx * c * wi; p[i * 2 + 1] += dy * c * wi
                p[j * 2] -= dx * c * wj; p[j * 2 + 1] -= dy * c * wj
            }
            if n > 2 {
                for i in 1..<(n - 1) {
                    let ax = p[i * 2 - 2], ay = p[i * 2 - 1], bx = p[i * 2 + 2], by = p[i * 2 + 3]
                    let dx = bx - ax, dy = by - ay
                    let tx = (ax + bx) / 2 - dy * bend[i], ty = (ay + by) / 2 + dx * bend[i]
                    let ex = (tx - p[i * 2]) * curl, ey = (ty - p[i * 2 + 1]) * curl
                    p[i * 2] += ex * inv[i]; p[i * 2 + 1] += ey * inv[i]
                    p[i * 2 - 2] -= ex * 0.5 * inv[i - 1]; p[i * 2 - 1] -= ey * 0.5 * inv[i - 1]
                    p[i * 2 + 2] -= ex * 0.5 * inv[i + 1]; p[i * 2 + 3] -= ey * 0.5 * inv[i + 1]
                }
            }
            // Fingers: the grabbed point follows, its offset fading so it ends up under the finger.
            for id in ids {
                guard var f = pointers[id] else { continue }
                f.ox *= 0.995; f.oy *= 0.995
                p[f.i * 2] = f.x + f.ox; p[f.i * 2 + 1] = f.y + f.oy
                pointers[id] = f
            }
            for i in 0..<n {
                if inv[i] == 0 { continue }
                let rr = rad[i] * (i < 2 ? 1 : w[i])
                if p[i * 2 + 1] > world.floor - rr { p[i * 2 + 1] = world.floor - rr }
                if p[i * 2] < world.left + rr { p[i * 2] = world.left + rr }
                if p[i * 2] > world.right - rr { p[i * 2] = world.right - rr }
            }
        }
        for i in 0..<n { inv[i] = 1 }
        // Floor contact: friction, and a bounce off fast landings only.
        var impact = 0.0
        for i in 0..<n {
            let rr = rad[i] * (i < 2 ? 1 : w[i])
            if p[i * 2 + 1] >= world.floor - rr - 0.5 {
                q[i * 2] += (p[i * 2] - q[i * 2]) * M.fric
                let v = vy0[i] / h
                if v > S * 0.6 {
                    q[i * 2 + 1] = p[i * 2 + 1] + vy0[i] * M.rest
                    impact = max(impact, v / S)
                } else if q[i * 2 + 1] < p[i * 2 + 1] {
                    q[i * 2 + 1] = p[i * 2 + 1]
                }
            }
        }
        // Numbers for sound and haptics.
        var len = 0.0
        for i in 0..<(n - 1) { len += hypot(p[i * 2 + 2] - p[i * 2], p[i * 2 + 3] - p[i * 2 + 1]) }
        let e2e = hypot(p[(n - 1) * 2] - p[0], p[(n - 1) * 2 + 1] - p[1])
        let un = min(max((e2e - restE2E) / max(1, restLen - restE2E), 0), 1.2)
        metric.rate = (un - metric.unravel) / h * 0.15
        metric.unravel = un
        metric.stretch = max(0, len / restLen - 1) + un * 0.5
        metric.squash = squeezeAmt * M.squeeze
        metric.D = metric.squash + un * 0.2
        metric.speed = speed / Double(n) / S
        metric.held = held
        if impact > 0.5 { metric.impact = max(metric.impact, impact) }
        length = len
    }

    /// How far the neck has turned from its rest direction, in radians.
    public func headTurn() -> Double {
        atan2(p[1] - p[3], p[0] - p[2]) - headAngle0
    }
}
