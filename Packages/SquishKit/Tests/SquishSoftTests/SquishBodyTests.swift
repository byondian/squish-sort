import XCTest
@testable import SquishSoft

final class SquishBodyTests: XCTestCase {
    private let world = SquishBody.World(floor: 600, left: 0, right: 400, top: 0)
    private let h = 1.0 / 120
    private let size = 280.0

    private func oval(_ u: Double, _ v: Double) -> Bool {
        let a = (u - 0.5) / 0.42, b = (v - 0.55) / 0.4
        return a * a + b * b < 1
    }

    private func body(_ feel: SquishFeel, x: Double = 200, y: Double? = nil) -> SquishBody {
        SquishBody(size: size, n: 12, material: SquishTuning.standard.material(feel), x: x, y: y ?? world.floor - size / 2,
                   footV: 0.96, breath: 0, inside: oval)
    }

    private func mark(_ b: SquishBody) -> [Double] {
        let bb = b.bounds(), m = b.metric
        let packed = b.surface()
        var dent = 0.0, thickness = 0.0
        for k in stride(from: 0, to: packed.count, by: 4) {
            dent += Double(packed[k]) * 256 + Double(packed[k + 1])
            thickness += Double(packed[k + 2])
        }
        let cells = Double(b.zres * b.zres)
        return [bb.x0, bb.x1, bb.y0, bb.y1, Double(b.p[12]), Double(b.p[13]), Double(b.p[168]), Double(b.p[169]),
                Double(b.p[300]), Double(b.p[301]), m.D, m.rate, m.stretch, m.squash, m.speed, m.impact,
                m.Z, m.zrate, b.tilt.x, b.tilt.y, Double(b.z[16 * 33 + 16]), Double(b.z[10 * 33 + 14]), dent / cells, thickness / cells]
    }

    /// The same script as the design thread's page engine (squish-engine.js run in Node):
    /// settle, press, drag while pressing harder, add a second finger, let go, pick up, throw at a wall, land.
    private func script(_ feel: SquishFeel) -> [[Double]] {
        let b = body(feel)
        var marks: [[Double]] = []
        for _ in 0..<60 { b.step(h, world: world) }
        marks.append(mark(b))
        let top = b.bounds()
        XCTAssertTrue(b.grab(1, x: 200, y: top.y0 + 60))
        for _ in 0..<72 { b.step(h, world: world) }
        marks.append(mark(b))
        for i in 1...30 {
            b.move(1, x: 200 + Double(i) * 3, y: top.y0 + 60 - Double(i) * 2, dt: h, force: 1.5)
            b.step(h, world: world)
        }
        marks.append(mark(b))
        b.grab(2, x: 150, y: 520)
        for i in 1...30 {
            b.move(2, x: 150 - Double(i) * 2, y: 520, dt: h)
            b.step(h, world: world)
        }
        marks.append(mark(b))
        b.release(1)
        b.release(2)
        for _ in 0..<24 { b.step(h, world: world) }
        marks.append(mark(b))
        for _ in 0..<216 { b.step(h, world: world) }
        marks.append(mark(b))
        b.grab(3, x: b.metric.cx, y: b.metric.cy)
        let x0 = b.metric.cx, y0 = b.metric.cy
        for i in 1...40 {
            b.move(3, x: x0 + Double(i) * 4, y: y0 - Double(i) * 6, dt: h)
            b.step(h, world: world)
        }
        marks.append(mark(b))
        b.release(3)
        for _ in 0..<60 { b.step(h, world: world) }
        marks.append(mark(b))
        for _ in 0..<240 { b.step(h, world: world) }
        marks.append(mark(b))
        return marks
    }

    func testThePortMatchesThePageEngine() {
        for feel in SquishFeel.allCases {
            let got = script(feel)
            guard let want = SquishBodyTests.reference[feel.rawValue] else { return XCTFail("no reference for \(feel)") }
            XCTAssertEqual(got.count, want.count)
            for (row, (g, w)) in zip(got, want).enumerated() {
                for column in 0..<min(g.count, w.count) {
                    // Positions in points, the numbers behind sound and haptics, then the dent and the packed surface.
                    let slack = column < 10 ? 0.5 : (column < 22 ? 0.02 + abs(w[column]) * 0.05 : 0.5 + abs(w[column]) * 0.002)
                    XCTAssertEqual(g[column], w[column], accuracy: slack, "\(feel) mark \(row) column \(column)")
                }
            }
        }
    }

    /// Spec section 4: press the top for 0.6 s, then let go.
    func testEachFeelLooksAsMeasured() {
        // Height and width when pressed, as a share of the resting size (the test's plain oval, run through the page engine).
        let expected: [SquishFeel: (height: ClosedRange<Double>, width: ClosedRange<Double>)] = [
            .foam: (0.48...0.62, 1.06...1.21), .jelly: (0.56...0.70, 1.20...1.36),
            .gel: (0.46...0.60, 1.25...1.41), .mochi: (0.50...0.64, 1.26...1.43),
        ]
        for feel in SquishFeel.allCases {
            let b = body(feel)
            for _ in 0..<120 { b.step(h, world: world) }
            let rest = b.bounds()
            let restH = rest.y1 - rest.y0, restW = rest.x1 - rest.x0
            XCTAssertTrue(b.grab(1, x: 200, y: rest.y0 + 2))
            for _ in 0..<72 { b.step(h, world: world) }
            let pressed = b.bounds()
            let want = expected[feel]!
            XCTAssertTrue(want.height.contains((pressed.y1 - pressed.y0) / restH), "\(feel) height \((pressed.y1 - pressed.y0) / restH)")
            XCTAssertTrue(want.width.contains((pressed.x1 - pressed.x0) / restW), "\(feel) width \((pressed.x1 - pressed.x0) / restW)")
            XCTAssertGreaterThan(b.metric.D, 0.05, "\(feel)")
            // The finger has pushed a dent into the toy.
            let dent = b.metric.Z
            XCTAssertGreaterThan(dent, 0.5, "\(feel)")
            b.release(1)
            var tallest = 0.0
            var backAt: Double?
            var bump = 0.0
            var halfFilledAt: Double?
            for i in 1...480 {
                b.step(h, world: world)
                bump = min(bump, Double(b.z.min() ?? 0))
                if halfFilledAt == nil, b.metric.Z < dent / 2 { halfFilledAt = Double(i) * h }
                let now = b.bounds()
                let height = (now.y1 - now.y0) / restH
                tallest = max(tallest, height)
                if backAt == nil, height >= 0.9 { backAt = Double(i) * h }
            }
            switch feel {
            case .foam:
                XCTAssertLessThan(tallest, 1.02, "foam creeps back and never overshoots")
                XCTAssertGreaterThan(backAt ?? 0, 0.7, "foam is slow to rise")
                XCTAssertGreaterThan(halfFilledAt ?? 0, 0.3, "the dent in foam creeps back")
                XCTAssertGreaterThan(bump, -0.01, "and never passes flat")
            case .jelly:
                XCTAssertLessThan(backAt ?? 9, 0.15, "jelly snaps back")
                XCTAssertGreaterThan(tallest, 1.05, "and overshoots")
                XCTAssertLessThan(bump, -0.25, "the dent pops out as a bump")
            case .gel:
                XCTAssertLessThan(tallest, 1.02, "gel flows back with no bounce")
                XCTAssertTrue((0.25...0.6).contains(backAt ?? 9), "in about half a second")
                XCTAssertLessThan(bump, -0.15, "with a low bump")
            case .mochi:
                XCTAssertLessThan(backAt ?? 9, 0.3)
                XCTAssertLessThan(tallest, 1.02, "mochi settles with no bounce")
            }
            XCTAssertLessThan(b.metric.Z, 0.01, "\(feel): the dent is gone in the end")
        }
    }

    func testNothingTearsOrLeavesTheRoom() {
        var rng = SystemRandomNumberGenerator()
        for feel in SquishFeel.allCases {
            let b = body(feel)
            b.grab(1, x: 200, y: 450)
            b.grab(2, x: 220, y: 520)
            for i in 0..<1200 {
                if i % 2 == 0 {
                    b.move(1, x: Double.random(in: -200...600, using: &rng), y: Double.random(in: -300...900, using: &rng), dt: h * 2,
                           force: Double.random(in: 0.7...1.7, using: &rng))
                    b.move(2, x: Double.random(in: -200...600, using: &rng), y: Double.random(in: -300...900, using: &rng), dt: h * 2)
                }
                b.step(h, world: world)
                XCTAssertLessThan(b.metric.D, 2.5)
            }
            b.releaseAll()
            for _ in 0..<600 { b.step(h, world: world) }
            let end = b.bounds()
            for value in b.p { XCTAssertTrue(value.isFinite) }
            for value in b.z { XCTAssertTrue(abs(value) < 0.01, "\(feel): the dent grid is flat again") }
            XCTAssertGreaterThanOrEqual(end.x0, world.left - 0.5)
            XCTAssertLessThanOrEqual(end.x1, world.right + 0.5)
            XCTAssertLessThanOrEqual(end.y1, world.floor + 0.5)
            XCTAssertLessThan(b.metric.D, 0.05, "\(feel) comes back to its own shape")
        }
    }

    func testATouchOffTheToyDoesNotGrab() {
        let b = body(.foam)
        XCTAssertFalse(b.grab(1, x: 20, y: 100))
        XCTAssertFalse(b.isHeld)
        XCTAssertTrue(b.grab(1, x: 200, y: 480))
        XCTAssertTrue(b.isHeld)
    }

    func testReduceMotionHalvesThePressAndStopsTheBreath() {
        let tuning = SquishTuning.standard
        XCTAssertEqual(tuning.material(.foam, reduceMotion: true).press, tuning.material(.foam).press / 2, accuracy: 1e-9)
        XCTAssertEqual(tuning.material(.gel, reduceMotion: true).poke, tuning.material(.gel).poke / 2, accuracy: 1e-9)
        XCTAssertEqual(tuning.material(.jelly, reduceMotion: true).look, 0, "the face stays put")
        let b = body(.foam)
        b.breathScale = 0
        for _ in 0..<240 { b.step(h, world: world) }
        let first = b.bounds()
        for _ in 0..<100 { b.step(h, world: world) }
        let later = b.bounds()
        XCTAssertEqual(first.y0, later.y0, accuracy: 0.5, "the breath alone would move it about 3 points")
        XCTAssertEqual(b.tilt.x, 0, accuracy: 1e-4, "and the face does not sway")
    }

    func testEveryFeelHasItsNumbers() throws {
        let tuning = SquishTuning.standard
        for feel in SquishFeel.allCases { XCTAssertNotNil(tuning.feels[feel.rawValue]) }
        XCTAssertEqual(SquishFeel(named: nil), .foam)
        XCTAssertEqual(SquishFeel(named: "slime"), .foam)
        XCTAssertEqual(SquishFeel(named: "mochi"), .mochi)
        // The table is plain data, so the design thread can retune it without touching the code.
        let copy = try JSONDecoder().decode(SquishTuning.self, from: JSONEncoder().encode(tuning))
        XCTAssertEqual(copy, tuning)
    }

    /// The puffy rest shape, against the page's own `heightField` for the same oval.
    func testTheRestShapeMatchesThePage() {
        let n = 128
        var alpha = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n where oval(Double(x) / Double(n - 1), Double(y) / Double(n - 1)) { alpha[y * n + x] = 255 }
        }
        let field = SquishBody.heightField(alpha: alpha, size: n)
        XCTAssertEqual(field.count, n * n * 4)
        var height = 0.0, slide = 0.0
        for k in stride(from: 0, to: field.count, by: 4) {
            height += Double(field[k]) * 256 + Double(field[k + 1])
            slide += Double(field[k + 2])
        }
        XCTAssertEqual(height / Double(n * n), 23616.126, accuracy: 3)
        XCTAssertEqual(slide / Double(n * n), 71.5177, accuracy: 0.05)
        func at(_ x: Int, _ y: Int) -> (height: Int, slide: Int) {
            let k = (y * n + x) * 4
            return (Int(field[k]) * 256 + Int(field[k + 1]), Int(field[k + 2]))
        }
        XCTAssertEqual(Double(at(64, 70).height), 64733, accuracy: 4, "domed in the middle")
        XCTAssertEqual(at(64, 70).slide, 255)
        XCTAssertEqual(Double(at(64, 22).height), 20794, accuracy: 40, "rounded off at the edge")
        XCTAssertEqual(at(3, 3).height, 0, "flat outside the toy")
        XCTAssertTrue(SquishBody.heightField(alpha: [], size: n).isEmpty)
    }

    // MARK: - Sound

    private func metric(D: Double = 0, rate: Double = 0, held: Int = 1, speed: Double = 0, impact: Double = 0, stretch: Double = 0) -> SquishBody.Metric {
        var m = SquishBody.Metric()
        m.D = D
        m.rate = rate
        m.held = held
        m.speed = speed
        m.impact = impact
        m.stretch = stretch
        return m
    }

    func testFoamSoundFollowsThePress() {
        var mixer = SquishSoundMixer()
        var rng = SystemRandomNumberGenerator()
        let still = mixer.frame(dt: 1.0 / 60, metric: metric(), feel: .foam, rng: &rng)
        XCTAssertEqual(still.loops["air_out"] ?? 0, 0)
        XCTAssertTrue(still.grains.isEmpty)
        XCTAssertNil(still.thud)
        var pressGrains = 0
        for _ in 0..<60 {
            let f = mixer.frame(dt: 1.0 / 60, metric: metric(D: 0.1, rate: 0.2), feel: .foam, rng: &rng)
            XCTAssertEqual(f.loops["air_out"] ?? 0, 0.11, accuracy: 1e-9)
            XCTAssertEqual(f.loops["air_in"] ?? 0, 0)
            XCTAssertTrue(f.grains.allSatisfy { $0.set == "crackle_press" && (0.16...0.42).contains($0.volume) && abs($0.pan) <= 0.25 })
            pressGrains += f.grains.count
        }
        XCTAssertEqual(Double(pressGrains), 64, accuracy: 1, "320 a second for each unit of rate")
        // Hard presses are capped.
        let hard = mixer.frame(dt: 1.0 / 60, metric: metric(D: 0.2, rate: 5), feel: .foam, rng: &rng)
        XCTAssertEqual(hard.loops["air_out"] ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(hard.grains.count, 6)
        // Rising after being let go: a breath in and sparse crackles for as long as it rises.
        mixer.reset()
        var riseGrains = 0
        for _ in 0..<60 {
            let f = mixer.frame(dt: 1.0 / 60, metric: metric(D: 0.1, rate: -0.01, held: 0), feel: .foam, rng: &rng)
            XCTAssertEqual(f.loops["air_in"] ?? 0, 0.008, accuracy: 1e-9)
            XCTAssertTrue(f.grains.allSatisfy { $0.set == "crackle_rise" && $0.volume <= 0.231 })
            riseGrains += f.grains.count
        }
        XCTAssertEqual(Double(riseGrains), 24, accuracy: 1, "3.2 from the rate plus 9 + 40 x 0.3")
        let done = mixer.frame(dt: 1.0 / 60, metric: metric(D: 0.005, rate: -0.001, held: 0), feel: .foam, rng: &rng)
        XCTAssertTrue(done.grains.isEmpty)
    }

    func testJellyGelAndMochiSounds() {
        var mixer = SquishSoundMixer()
        var rng = SystemRandomNumberGenerator()
        let shallow = mixer.frame(dt: 1.0 / 60, metric: metric(D: 0, rate: 0.5, speed: 0.5), feel: .jelly, rng: &rng)
        XCTAssertEqual(shallow.loops["squelch_low"] ?? 0, 0.085, accuracy: 1e-9)
        XCTAssertEqual(shallow.loops["squelch_high"] ?? 0, 0, accuracy: 1e-9)
        XCTAssertEqual(shallow.loops["hum"] ?? 0, 0.04, accuracy: 1e-9)
        let deep = mixer.frame(dt: 1.0 / 60, metric: metric(D: 0.5, rate: -3, speed: 9), feel: .jelly, rng: &rng)
        XCTAssertEqual(deep.loops["squelch_low"] ?? 0, 0, accuracy: 1e-9)
        XCTAssertEqual(deep.loops["squelch_high"] ?? 0, 0.22, accuracy: 1e-9)
        XCTAssertEqual(deep.loops["hum"] ?? 0, 0.1, accuracy: 1e-9)
        let gel = mixer.frame(dt: 1.0 / 60, metric: metric(D: 1.0 / 6, rate: 2), feel: .gel, rng: &rng)
        XCTAssertEqual((gel.loops["squelch_low"] ?? 0) + (gel.loops["squelch_high"] ?? 0), 0.26, accuracy: 1e-9)
        // Mochi creaks only while it is being stretched further.
        mixer.reset()
        _ = mixer.frame(dt: 1.0 / 60, metric: metric(stretch: 0), feel: .mochi, rng: &rng)
        let pulled = mixer.frame(dt: 1.0 / 60, metric: metric(stretch: 0.002), feel: .mochi, rng: &rng)
        XCTAssertEqual(pulled.loops["creak"] ?? 0, 0.144, accuracy: 1e-6)
        let easing = mixer.frame(dt: 1.0 / 60, metric: metric(stretch: 0.001), feel: .mochi, rng: &rng)
        XCTAssertEqual(easing.loops["creak"] ?? 0, 0)
    }

    func testLandingsThudAndDeepSqueezesPop() {
        var mixer = SquishSoundMixer()
        var rng = SystemRandomNumberGenerator()
        XCTAssertNil(mixer.frame(dt: 1.0 / 60, metric: metric(held: 0, impact: 0.4), feel: .foam, rng: &rng).thud)
        let foam = mixer.frame(dt: 1.0 / 60, metric: metric(held: 0, impact: 2.3), feel: .foam, rng: &rng)
        XCTAssertEqual(foam.thud ?? 0, 0.22, accuracy: 1e-9)
        XCTAssertTrue(foam.grains.isEmpty)
        let jelly = mixer.frame(dt: 1.0 / 60, metric: metric(held: 0, impact: 9), feel: .jelly, rng: &rng)
        XCTAssertEqual(jelly.thud ?? 0, 0.34, accuracy: 1e-9)
        XCTAssertEqual(jelly.grains.filter { $0.set == "bubble" }.count, 3)
        XCTAssertNil(mixer.pop(depth: 0.2, feel: .foam))
        XCTAssertNil(mixer.pop(depth: 0.04, feel: .mochi))
        XCTAssertEqual(mixer.pop(depth: 0.1, feel: .mochi) ?? 0, 0.16, accuracy: 1e-9)
        XCTAssertEqual(mixer.pop(depth: 0.4, feel: .gel) ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(mixer.hapticIntensity(metric: metric(D: 0.1)), 0.3, accuracy: 1e-9)
        XCTAssertEqual(mixer.hapticIntensity(metric: metric(D: 0.9)), 1, accuracy: 1e-9)
        var dented = metric(D: 0.1)
        dented.Z = 0.5
        XCTAssertEqual(mixer.hapticIntensity(metric: dented), 0.5, accuracy: 1e-9, "the dent adds to it")
        XCTAssertEqual(mixer.hapticIntensity(metric: metric(D: 0.3, held: 0)), 0, "nothing while the toy rises on its own")
    }

    // MARK: - Board pieces

    func testPieceSpringRingsAndSettles() {
        var s = PieceSpring()
        s.velocity = -3
        var lowest = 0.0, highest = 0.0
        for _ in 0..<240 {
            s.advance(1.0 / 120)
            lowest = min(lowest, s.value)
            highest = max(highest, s.value)
        }
        XCTAssertEqual(lowest, -0.051, accuracy: 0.006, "a lift is a quick stretch upwards")
        XCTAssertGreaterThan(highest, 0.01, "then it rings")
        XCTAssertTrue(s.isResting)
        // A hard landing never squashes past 0.3.
        var hard = PieceSpring()
        hard.velocity = PieceSpring.landingKick(speed: 100)
        var peak = 0.0
        for _ in 0..<240 {
            hard.advance(1.0 / 120)
            peak = max(peak, hard.value)
        }
        XCTAssertEqual(peak, 0.3, accuracy: 0.002)
        XCTAssertEqual(PieceSpring.landingKick(speed: 5), 3, accuracy: 1e-9)
        // A lean follows its target.
        var lean = PieceSpring()
        lean.target = 0.2
        for _ in 0..<240 { lean.advance(1.0 / 60) }
        XCTAssertEqual(lean.value, 0.2, accuracy: 0.001)
    }

    /// Made by running the script above through squish-engine.js in Node, 16 Nov 2026.
    static let reference: [String: [[Double]]] = [
        "foam": [
            [83.3550491, 316.644928, 378.14502, 600.000027, 200.0, 329.976868, 200.0, 471.346832, 223.333557, 587.866455, 0.0006660582, -0.0100097497, -0.0000010324996, 0.00152934673, 0.0146214678, 0.824999978, 0.0, 0.0, 0.00208414014, 0.00491796181, 0.0, 0.0, 32768.0, 127.306515],
            [75.4239273, 324.576111, 458.211487, 600.000027, 200.0, 392.128082, 200.0, 528.12384, 225.130035, 587.848389, 0.102000903, 0.00857517623, 0.0642265408, 0.386216609, 0.292127694, 0.824999978, 0.94494766, 0.0122187579, 0.000065208694, -0.0229316044, 0.443169028, 0.651131034, 33479.1898, 152.254544],
            [160.667679, 400.0, 334.869415, 578.436489, 282.951569, 306.193878, 289.586395, 418.95166, 297.755219, 563.995972, 0.0532209007, 0.0207579086, 0.0750862435, 0.00192938027, 0.0937352411, 1.01105734, 1.11159003, -0.398769363, -0.00305141742, -0.0225672266, 0.518399656, 0.752565324, 33615.0785, 128.211287],
            [135.936707, 399.905212, 323.231689, 558.20065, 288.112488, 281.467224, 287.578857, 415.174622, 282.90741, 543.011658, 0.054758285, 0.211941271, 0.166236849, 0.0282181317, 0.211661669, 1.01105734, 1.02837145, 0.000354912308, -0.0206956779, -0.00657767079, 0.482293785, 0.708615541, 33607.6981, 126.227442],
            [143.799988, 396.470062, 365.167084, 594.729458, 286.782196, 318.19696, 283.319519, 457.321014, 285.186096, 580.89447, 0.0410087515, -0.0737641827, 0.127254258, 0.0333778608, 0.0978339299, 1.01105734, 0.788923919, -0.288195966, -0.00842767015, 0.000493206771, 0.36805895, 0.532430708, 33426.4895, 123.530556],
            [152.553543, 388.857635, 378.667084, 600.000027, 271.057953, 331.291687, 270.807953, 471.576813, 293.85379, 587.377869, 0.0043803922, -0.0125784488, 0.0145555616, 0.00800078866, 0.0141946108, 1.7206283, 0.0531543195, -0.0204188661, 0.0101705383, 0.00414239895, 0.0286642946, 0.0366610251, 32826.8143, 126.884153],
            [255.973877, 400.0, 148.388306, 377.042233, 349.020966, 88.3634796, 398.939423, 232.411407, 381.906677, 361.974243, 0.148264403, 0.386413895, 0.0201450939, 0.37614885, 0.333417552, 1.7206283, 0.629805088, 0.0928283962, 0.00160221559, 0.0106138402, 0.586993098, 0.0226770397, 33260.8506, 158.435328],
            [194.213135, 400.0, 153.149231, 402.505062, 301.04071, 99.433754, 312.159149, 255.204727, 325.950989, 389.355225, 0.0544817551, -0.0641404636, 0.12695784, 0.12112735, 0.0980656574, 1.7206283, 0.309841961, -0.112071235, 0.00529365161, 0.000437506443, 0.282940358, 0.0119965849, 33028.3276, 127.113933],
            [162.990082, 399.94278, 381.600433, 600.000027, 281.48703, 335.330841, 281.499481, 473.266571, 305.123932, 587.849365, 0.006215105, -0.0031681291, 0.0153823284, 0.017975261, 0.00395538949, 4.27716513, 0.0153673347, -0.00610628525, -0.00831874881, -0.00232902746, 0.0140902279, 0.00149787765, 32786.2693, 127.79052],
        ],
        "jelly": [
            [85.3943481, 314.605682, 372.612762, 600.000027, 200.0, 324.730835, 200.0, 468.278229, 222.866241, 587.866577, 0.00804400927, -0.00603427952, 0.02542619, 0.0173624459, 0.0237572271, 0.824999964, 0.0, -0.0176060009, 0.00358755915, 0.00465395615, -0.00421959162, -0.00236917031, 32752.1174, 126.99713],
            [67.1326065, 332.867401, 432.267029, 600.000027, 200.0, 368.839691, 200.0, 516.248108, 226.978851, 587.596191, 0.076168725, 0.00556942572, 0.126055537, 0.243431129, 1.25721486, 0.824999964, 0.796564281, 0.00990894364, 0.000210543737, -0.0264965395, 0.261370689, 0.527077675, 33308.9625, 134.144224],
            [164.846664, 392.534027, 329.53241, 587.95419, 281.210358, 300.254608, 289.258087, 416.609375, 295.089783, 573.103516, 0.0543919695, 0.211265156, 0.150878602, 0.0368667095, 0.429806848, 0.824999964, 0.866545558, -0.366724989, -0.00851993077, -0.0272106372, 0.28433311, 0.57338351, 33348.8378, 129.695611],
            [139.270554, 399.16098, 317.945801, 560.315029, 290.28714, 277.999023, 288.359222, 411.93277, 288.914337, 539.422913, 0.0511604934, 0.154231589, 0.166539156, 0.0362552956, 0.322926663, 0.824999964, 0.866888225, -0.00421249453, -0.0520827164, 0.0179377316, 0.284445554, 0.573610246, 33379.8762, 126.327134],
            [156.956558, 399.977142, 364.934998, 590.491116, 268.263947, 315.1008, 273.186188, 461.407166, 307.972198, 578.357788, 0.026285135, 0.094864843, 0.0620666801, 0.0325106343, 0.291343965, 0.824999964, 0.0484227948, -1.31048187, 0.0406422641, -0.00751383106, -0.120146818, -0.0997360125, 32527.5172, 126.598257],
            [157.662247, 388.185303, 373.535889, 600.000027, 272.006104, 326.44104, 272.820068, 468.697968, 296.720642, 586.998535, 0.00556033577, 0.0190019647, 0.0162228245, 0.0125055461, 0.0235277027, 1.79246104, 0.00188590318, -0.00589607843, 0.00898045677, 0.00398573963, -0.00297462218, 0.000700191304, 32761.5376, 127.033053],
            [217.013077, 400.0, 134.466705, 378.357205, 308.761475, 83.9348068, 387.434662, 229.442383, 341.2677, 364.706329, 0.123129681, 0.220122225, 0.0946497937, 0.238233479, 1.53850565, 1.79246104, 0.529923081, 0.0718090666, -0.000354202978, 0.0220842638, 0.486715347, 0.00267005363, 33128.679, 153.739186],
            [139.249619, 369.52713, 139.081482, 371.936337, 257.275421, 86.8360519, 253.649796, 237.336563, 277.586609, 359.803009, 0.0236219849, -0.13749345, 0.0501456384, 0.0211421497, 0.465234894, 1.79246104, 0.026617175, -0.237543663, 0.00262870512, -0.0110574888, 0.018462237, -0.0262143426, 32675.8656, 125.403125],
            [128.155777, 364.045349, 380.476654, 600.000027, 246.089874, 334.437683, 246.097397, 472.648224, 269.722351, 587.847412, 0.00440959697, -0.0193890991, 0.0113997592, 0.0130134205, 0.020238306, 4.47054164, 0.00212782784, -0.000321715833, -0.00941114716, -0.00237219876, 0.00192932447, 0.000897004618, 32774.5635, 128.0],
        ],
        "gel": [
            [85.5782776, 314.421753, 373.442322, 600.000027, 200.0, 325.17569, 200.0, 468.757355, 223.047363, 587.866577, 0.00757007926, 0.0349951553, 0.0205923081, 0.0180335846, 0.0357338405, 0.91666666, 0.00880710501, 0.0290838183, 0.00309686963, 0.00742694953, 0.00844532531, 0.00283307326, 32789.8728, 127.082899],
            [68.979126, 331.020935, 460.592072, 600.000027, 200.0, 392.795776, 200.0, 529.065125, 227.256424, 587.866699, 0.107282833, 0.0102838663, 0.115209113, 0.392472384, 0.81160862, 0.91666666, 1.14503813, 0.0179511921, -0.00114871782, -0.0409073207, 0.720228672, 0.942886949, 34115.0108, 144.787438],
            [165.655441, 399.918854, 326.913544, 581.124783, 282.847107, 297.406708, 289.260834, 416.751251, 300.580292, 565.815063, 0.0549065482, 0.0818980988, 0.130211667, -0.0047330698, 0.257315314, 0.989831347, 1.24563432, -0.741275895, -0.00422158849, -0.0251681563, 0.787184417, 1.02572322, 34286.3574, 126.026251],
            [142.056335, 399.645721, 318.946564, 560.00137, 287.93335, 275.499847, 285.06781, 412.93866, 283.419434, 544.436401, 0.0504720796, 0.172983044, 0.157874142, 0.0159811948, 0.44604653, 0.989831347, 1.24612677, 0.0130518878, -0.0391005094, 0.0043260018, 0.783813417, 1.02612889, 34342.9072, 121.649697],
            [153.042877, 393.144897, 372.431702, 600.000027, 284.474335, 319.043549, 278.361389, 465.524658, 290.241547, 584.438721, 0.0333525413, -0.195680363, 0.103754519, 0.0376850413, 0.270118838, 1.90546561, 0.0789882094, -1.36976206, -0.0205077039, 0.0144853911, -0.0108157219, -0.0445603803, 32900.9655, 122.17462],
            [155.392014, 387.614471, 375.440887, 600.000027, 272.352264, 328.208069, 271.6026, 469.778229, 294.27887, 587.639954, 0.00278227862, 0.0180374245, 0.00789784213, 0.00444201894, 0.0328925722, 1.90546561, 0.000262748857, -0.000363417233, 0.00842716134, 0.00414089966, 0.000080005877, 0.000227689656, 32767.7909, 127.091296],
            [269.005371, 400.0, 135.138489, 375.259854, 350.339752, 56.6660347, 397.754547, 230.230377, 384.501465, 360.582306, 0.155995504, 0.435779035, 0.0815001847, 0.437251157, 0.878973279, 1.90546561, 0.763632119, 0.143866025, -0.00271115789, 0.0147018775, 0.730967402, 0.043686077, 33706.3928, 160.921671],
            [171.795593, 400.0, 222.600174, 452.93948, 287.633209, 166.450134, 283.508087, 320.145142, 307.610687, 440.734253, 0.0301892551, 0.0357238748, 0.0361972026, 0.0256754381, 0.130119136, 1.90546561, 0.000966635474, -0.260221211, 0.00903809033, -0.0125410225, -0.00917529035, -0.0246402733, 32648.7503, 125.491444],
            [153.139999, 393.34491, 384.259186, 600.000027, 273.276733, 338.705872, 273.246582, 474.747742, 297.293274, 587.855835, 0.0112330719, -0.0216707252, 0.0300193127, 0.0311413762, 0.0230583166, 4.76848825, 0.000156241993, 0.000417743031, -0.0091400597, -0.00344856538, 0.000151856191, 0.000077753386, 32768.3046, 127.883728],
        ],
        "mochi": [
            [85.6709213, 314.329071, 372.897705, 600.000027, 200.0, 324.864807, 200.0, 468.442719, 223.061096, 587.866577, 0.00820274033, 0.0207460971, 0.0233091829, 0.0193350041, 0.0203325282, 0.825000002, 0.000264033995, -0.00278436918, 0.00282395566, 0.00605174013, 0.000255721388, 0.000110791159, 32768.5645, 127.007759],
            [63.6559143, 336.344116, 443.670776, 600.000027, 199.999985, 378.369873, 200.0, 522.347595, 226.924255, 587.681213, 0.0925419614, 0.0112511575, 0.146994878, 0.298729798, 0.767662316, 0.825000002, 0.94591397, 0.0118203453, -0.000197692552, -0.0257312374, 0.398043931, 0.6784091, 33472.5276, 135.324264],
            [140.824265, 385.742523, 332.435822, 596.660855, 275.312531, 305.966644, 288.839355, 417.161346, 268.742706, 581.666016, 0.0806450892, 0.304984699, 0.216881059, 0.020182143, 0.295118956, 0.825000002, 1.02901626, -0.465132866, -0.00268069527, -0.0235323922, 0.433013648, 0.738010049, 33538.123, 128.233075],
            [118.087204, 398.911133, 318.224915, 571.457119, 290.381866, 281.180634, 289.125275, 412.086426, 273.238617, 549.592529, 0.0837702473, 0.237613005, 0.275766697, 0.0277064584, 0.309185165, 0.825000002, 1.02942312, 0.0148791724, -0.0257663091, -0.0011553704, 0.433184862, 0.738301873, 33719.0172, 124.654905],
            [166.9599, 397.213806, 370.46698, 594.427395, 283.149719, 319.352264, 275.110199, 467.609344, 301.763702, 578.932617, 0.0224540052, -0.175647491, 0.0338338882, 0.0500439828, 0.289764399, 0.825000002, 0.00600687042, 0.245242493, -0.00369609578, 0.00504691645, -0.0690667778, -0.127493188, 32622.3626, 125.773515],
            [163.321686, 394.878937, 375.099182, 600.000027, 278.825165, 327.835114, 279.042175, 469.619598, 302.653412, 587.479187, 0.00366682507, 0.0200249964, 0.010924267, 0.00683242459, 0.0251225499, 1.75317448, 1.2155661e-7, -8.26106646e-7, 0.00978547263, 0.00392985103, -1.98505514e-8, -4.20461923e-8, 32767.7911, 127.097035],
            [229.26236, 400.0, 147.853073, 391.780636, 321.326263, 93.2975235, 395.016541, 230.519867, 352.859833, 376.635193, 0.145744143, 0.207134385, 0.0923382169, 0.286619376, 0.861106943, 1.75317448, 0.629781365, 0.0931768535, -0.00116884974, 0.0123374288, 0.587105632, 0.0014112239, 33242.7841, 154.520778],
            [161.736542, 392.733398, 167.564606, 397.0191, 276.55426, 115.579071, 280.925049, 263.086487, 301.259552, 384.775665, 0.0224964004, 0.0589933354, 0.0337314591, 0.00756223579, 0.0883810356, 1.75317448, 0.0170531813, -0.019462655, 0.00595839486, -0.00540564427, 0.0146567449, -0.000275036378, 32780.0523, 125.79424],
            [158.942215, 396.773865, 382.162994, 600.000027, 277.808014, 336.283752, 277.848602, 473.582733, 301.738617, 587.829895, 0.00751709245, -0.0187894952, 0.0199344108, 0.0211172924, 0.020134499, 4.35698462, 6.16509155e-8, -3.3582728e-7, -0.00893531963, -0.00260816842, 6.02485741e-8, 3.24435518e-8, 32768.0, 127.847805],
        ]
    ]
}
