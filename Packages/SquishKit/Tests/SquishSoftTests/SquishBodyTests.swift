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
            .foam: (0.48...0.62, 1.06...1.21), .jelly: (0.51...0.64, 1.26...1.41),
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
                XCTAssertGreaterThan(tallest, 1.04, "and overshoots")
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

    /// Spec section 4a: pressed hard and held, the toy is a fat pancake and not a folded sheet.
    func testAHardPressNeverFoldsTheToyFlat() {
        for feel in SquishFeel.allCases {
            let b = body(feel)
            for _ in 0..<120 { b.step(h, world: world) }
            let rest = b.bounds()
            let restH = rest.y1 - rest.y0
            let still = b.faceStretch(keep: 0.5)
            XCTAssertEqual(still.xx, 0, accuracy: 0.05, "\(feel)")
            XCTAssertEqual(still.yy, 0, accuracy: 0.05, "\(feel)")
            XCTAssertTrue(b.grab(1, x: 200, y: rest.y0 + 2))
            var thinnest = 1.0
            for i in 1...240 {
                // The finger drives on down through the floor, harder than any real press.
                b.move(1, x: 200, y: rest.y0 + 2 + Double(i) * 3, dt: h, force: 1.5)
                b.step(h, world: world)
                let now = b.bounds()
                thinnest = min(thinnest, (now.y1 - now.y0) / restH)
            }
            XCTAssertGreaterThan(thinnest, 0.42, "\(feel) keeps a core")
            let face = b.faceStretch(keep: 0.5)
            for value in [face.xx, face.xy, face.yy] {
                XCTAssertTrue((-0.39...0.31).contains(value), "\(feel) face \(value)")
            }
            XCTAssertLessThan(face.yy, -0.15, "\(feel): the face is pulled back towards its own shape")
            b.release(1)
            for _ in 0..<480 { b.step(h, world: world) }
            let after = b.bounds()
            XCTAssertEqual((after.y1 - after.y0) / restH, 1, accuracy: 0.06, "\(feel) comes back whole")
        }
    }

    /// Spec section 6, press-only places: the patch near the top, the dent under the finger.
    func testAPressOnlyTouchSquashesTheWholeToy() {
        let expected: [SquishFeel: Double] = [.foam: 0.537, .jelly: 0.566, .gel: 0.519, .mochi: 0.563]
        for feel in SquishFeel.allCases {
            let b = body(feel)
            for _ in 0..<120 { b.step(h, world: world) }
            let rest = b.bounds()
            let restH = rest.y1 - rest.y0
            XCTAssertTrue(b.grab(1, x: 200, y: rest.y0 + 0.08 * b.size, dent: (x: 200, y: (rest.y0 + rest.y1) / 2)))
            for _ in 0..<108 { b.step(h, world: world) }
            let pressed = b.bounds()
            XCTAssertEqual((pressed.y1 - pressed.y0) / restH, expected[feel]!, accuracy: 0.03, "\(feel)")
            XCTAssertGreaterThan(b.metric.Z, 0.7, "\(feel): and the dent is there")
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
        XCTAssertEqual(SquishFeel(named: nil), .jelly)
        XCTAssertEqual(SquishFeel(named: "slime"), .jelly)
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
        XCTAssertEqual(shallow.loops["squelch_low"] ?? 0, 0.065, accuracy: 1e-9)
        XCTAssertEqual(shallow.loops["squelch_high"] ?? 0, 0, accuracy: 1e-9)
        XCTAssertEqual(shallow.loops["hum"] ?? 0, 0.025, accuracy: 1e-9)
        XCTAssertTrue(shallow.grains.allSatisfy { $0.set == "bubble" && (0.04...0.1001).contains($0.volume) }, "the gel ball's bubbles, quieter")
        let deep = mixer.frame(dt: 1.0 / 60, metric: metric(D: 0.5, rate: -3, speed: 9), feel: .jelly, rng: &rng)
        XCTAssertEqual(deep.loops["squelch_low"] ?? 0, 0, accuracy: 1e-9)
        XCTAssertEqual(deep.loops["squelch_high"] ?? 0, 0.18, accuracy: 1e-9)
        XCTAssertEqual(deep.loops["hum"] ?? 0, 0.07, accuracy: 1e-9)
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
            [83.355072, 316.644897, 378.144928, 600.000027, 200.0, 328.847198, 200.0, 471.346832, 223.333557, 587.866455, 0.00061929968, -0.0103635215, -0.00000125085517, 0.00152877681, 0.0160622789, 0.825000012, 0.0, 0.0, 0.00208414013, 0.00491541768, 0.0, 0.0, 32768.0, 127.07089],
            [74.3491287, 325.650818, 459.960236, 596.603848, 200.0, 371.243042, 200.0, 527.06073, 225.794205, 584.466003, 0.110164764, 0.0156221794, 0.0751002712, 0.414879517, 0.314012947, 0.825000012, 0.944947779, 0.0122187692, 0.0000652105787, -0.0217218627, 0.443166435, 0.651132584, 33479.1891, 154.854926],
            [161.769028, 400.0, 334.337799, 566.433743, 282.271606, 300.811279, 289.113739, 418.807434, 301.533295, 553.013977, 0.0390384955, -0.195544737, 0.038329672, 0.0210533865, 0.147411042, 1.02428492, 1.11159015, -0.398769404, -0.00376563666, -0.0203697974, 0.518396854, 0.752567172, 33615.0782, 127.848656],
            [137.284271, 399.901764, 323.079041, 551.596768, 287.429718, 278.250275, 287.505432, 415.136047, 283.58606, 538.019165, 0.043904904, 0.202843705, 0.124246746, 0.0386625345, 0.229129628, 1.02428492, 1.02837157, -0.000543005967, -0.0207172841, -0.00440014986, 0.482290953, 0.70861727, 33591.6734, 128.34637],
            [144.923141, 396.607635, 363.302643, 590.054287, 285.463348, 315.086151, 282.728058, 455.904266, 286.415192, 577.167114, 0.0351716564, -0.0490726828, 0.105335344, 0.033701657, 0.0798458118, 1.02428492, 0.788924038, -0.286890838, -0.00840194661, 0.00165428583, 0.368056953, 0.532431841, 33414.0435, 124.320757],
            [153.036301, 389.369385, 378.776001, 600.000027, 271.475342, 330.646362, 271.287384, 471.64859, 294.457672, 587.428894, 0.00431545286, -0.0127574265, 0.0143624051, 0.00788336469, 0.0148917304, 1.79434238, 0.0531543233, -0.0203875961, 0.0101699388, 0.00414125218, 0.028664168, 0.036661081, 32825.9354, 126.750877],
            [214.789413, 400.0, 149.359207, 376.071408, 296.894989, 102.215363, 348.820984, 232.510315, 349.359039, 361.341431, 0.0859650396, -0.0138729348, 0.0137232983, 0.206707248, 0.314811142, 1.79434238, 0.629798472, 0.0928304776, 0.00128849075, 0.0106122798, 0.58702445, 0.0226770788, 33260.3322, 157.261877],
            [40.9694824, 259.993744, 158.69162, 397.384426, 154.96611, 105.822319, 159.291519, 255.906219, 178.57634, 383.693298, 0.0364175606, -0.00500234496, 0.0733190364, 0.0634390523, 0.0549309422, 1.79434238, 0.309837312, -0.112071567, 0.0135804939, 0.000433710303, 0.282958686, 0.0119966986, 33028.0793, 125.638963],
            [0.21382679, 237.518982, 381.863281, 600.000027, 118.956528, 335.255127, 118.892975, 473.408997, 142.392273, 587.818542, 0.00676026, -0.00403511281, 0.0169325709, 0.0194189286, 0.00519093694, 4.35177708, 0.0153670441, -0.00610596349, -0.00832504926, -0.00232921279, 0.0140910204, 0.00149795588, 32786.2578, 127.704751],
        ],
        "jelly": [
            [85.8076935, 314.192322, 370.97525, 600.000027, 200.0, 323.211517, 200.0, 467.354004, 222.787643, 587.86615, 0.0102355113, 0.00149900928, 0.0325460888, 0.0217855554, 0.00632771108, 0.880000498, 0.0, 0.0273863599, 0.00369664161, 0.00541073058, -0.00745315803, -0.00301352027, 32745.9028, 126.784462],
            [62.2656784, 337.734344, 447.827026, 600.000027, 200.0, 367.112457, 200.0, 521.381165, 228.401489, 587.566101, 0.100255819, 0.00323805518, 0.162426017, 0.325837074, 1.04358459, 0.880000498, 0.896135151, 0.0104037701, 0.000905023027, -0.0165403575, 0.362913728, 0.650828004, 33470.5639, 136.404506],
            [169.299713, 397.888641, 325.998932, 578.472256, 284.895325, 294.642517, 289.609283, 415.287903, 305.316803, 563.728821, 0.0417297959, 0.140910985, 0.111441958, 0.0155989784, 0.297087445, 1.07563485, 0.974864125, -0.454920327, -0.0108765989, -0.0281507363, 0.394797117, 0.708005786, 33514.1426, 127.73334],
            [144.196365, 398.829895, 316.045959, 556.353298, 289.028625, 273.838715, 287.100098, 411.103729, 289.083923, 538.872253, 0.0417102707, 0.137793564, 0.134165919, 0.02374688, 0.359615317, 1.07563485, 0.975249588, -0.00775491828, -0.0548995273, 0.0211375539, 0.394953221, 0.708285749, 33559.1631, 124.769795],
            [162.960724, 399.956146, 363.932526, 585.566738, 276.279297, 312.678375, 275.695038, 459.948456, 307.302795, 572.525085, 0.0176835855, 0.0350110329, 0.00692349388, 0.0158591647, 0.268116142, 1.07563485, 0.0200413037, -0.528972687, 0.0306894019, -0.00207472252, -0.218159273, -0.289815694, 32326.2387, 126.78223],
            [155.306015, 385.679474, 373.76709, 600.000027, 271.470764, 326.574677, 270.595001, 468.862274, 293.211761, 587.68573, 0.00573871322, 0.0212661095, 0.0164370944, 0.0128972942, 0.0245478795, 1.96322508, 0.00109044218, -0.00119054392, 0.00991517367, 0.00353712349, -0.00108276866, 0.000991707668, 32765.1502, 127.059092],
            [196.658081, 400.0, 137.676483, 374.225155, 285.614288, 92.9787903, 342.022491, 229.520706, 333.500366, 360.609528, 0.0738820554, -0.0187438682, 0.0652144274, 0.133238009, 0.728750695, 1.96322508, 0.596776843, 0.0867869887, -0.00310891713, 0.021391492, 0.555535197, 0.00620693341, 33243.7239, 147.822085],
            [25.5464001, 249.956665, 166.924591, 396.968899, 139.776917, 111.664581, 134.639069, 264.581604, 158.688416, 384.757416, 0.0282425632, 0.0477777373, 0.0373837807, 0.0403346923, 0.109039229, 1.96322508, 0.0130038857, 0.0947994795, 0.00788383295, -0.0148774149, -0.102261774, 0.003730539, 32678.2294, 126.137528],
            [16.7548389, 253.21582, 381.012756, 600.000027, 135.016464, 334.965149, 134.991257, 472.944641, 158.635803, 587.857422, 0.00535201401, -0.021324296, 0.0139256476, 0.0156336619, 0.0221618217, 4.55965008, 0.0, -0.000144539698, -0.00949019062, -0.0027661712, -0.000688329921, -0.000129926484, 32766.3267, 127.979381],
        ],
        "gel": [
            [85.5782776, 314.421722, 373.442291, 600.000027, 200.0, 324.637787, 200.0, 468.757172, 223.047363, 587.866516, 0.00756688655, 0.0349871608, 0.0205928234, 0.0180338362, 0.0359985271, 0.916666564, 0.00880710315, 0.0290838149, 0.00309686992, 0.00742490292, 0.00844532531, 0.00283307373, 32789.8728, 126.978212],
            [67.5531235, 332.446838, 464.358124, 600.000027, 200.000015, 373.160736, 200.0, 529.600159, 227.626984, 587.849976, 0.115677892, 0.0131145649, 0.127063303, 0.418917533, 0.802014272, 0.916666564, 1.14503813, 0.017951251, -0.00114871498, -0.0391056812, 0.720231533, 0.942885518, 34115.0108, 147.732596],
            [164.630341, 399.583527, 326.662292, 571.04031, 281.866119, 291.796021, 289.499786, 416.663635, 303.52417, 556.583008, 0.039385265, -0.0421770758, 0.0768831012, -0.00799451053, 0.350733503, 1.02331597, 1.25279891, -0.728987214, -0.00504566824, -0.021178736, 0.783506691, 1.02941871, 34274.1561, 123.989903],
            [141.459229, 399.512604, 318.833374, 553.661404, 287.800385, 272.913239, 284.891968, 412.907013, 285.109039, 540.606018, 0.0418826662, 0.175539464, 0.126649626, 0.0163681189, 0.471434302, 1.02331597, 1.24612677, 0.0121829128, -0.0390960872, 0.00693640624, 0.783816516, 1.02612734, 34335.838, 122.330747],
            [153.202316, 393.904541, 366.189362, 598.592434, 283.312653, 317.640289, 277.3685, 461.409088, 291.154968, 582.859436, 0.0325712183, -0.173070243, 0.102995977, 0.02829559, 0.254587209, 1.02331597, 0.0830542743, -1.31019822, -0.0200902214, 0.0146775082, 0.0000688446089, -0.0405905955, 32930.7852, 121.645871],
            [156.093307, 388.303558, 375.46875, 600.000027, 272.987549, 328.045807, 272.290253, 469.797241, 294.982574, 587.64856, 0.00278365319, 0.0175047383, 0.00789634912, 0.00445500581, 0.0332964786, 1.99910556, 0.000257987005, -0.000428539442, 0.00843542853, 0.0041738456, 0.0000767282909, 0.000223649666, 32767.7669, 127.071952],
            [218.979782, 400.0, 137.813004, 372.620144, 299.060791, 83.4501648, 351.689789, 230.319351, 353.075317, 358.197815, 0.090134215, -0.00534539874, 0.0601194757, 0.223347613, 0.696241263, 1.99910556, 0.76362282, 0.14386663, -0.00316996908, 0.0146607192, 0.731007099, 0.0437218286, 33706.3923, 158.785206],
            [31.0132122, 257.18454, 222.006332, 453.154782, 148.697342, 165.562103, 141.694077, 319.887268, 165.975281, 441.021454, 0.033144417, 0.0556544627, 0.0414300898, 0.0322034009, 0.0768441849, 1.99910556, 0.000963094993, -0.260221345, 0.0225560324, -0.0124727382, -0.0091650011, -0.0246475805, 32648.7534, 125.763843],
            [9.97588539, 250.180618, 384.098724, 600.000027, 129.831528, 338.333282, 130.041382, 474.640778, 154.291641, 587.673218, 0.0112346881, -0.0217030503, 0.0300263927, 0.0311468077, 0.0232848479, 4.76739932, 0.000188646591, 0.000460268112, -0.00874442402, -0.00344973184, 0.000184115372, 0.000101307647, 32768.4351, 127.814539],
        ],
        "mochi": [
            [85.6708984, 314.329102, 372.897675, 600.000027, 200.0, 324.595612, 200.0, 468.442688, 223.061111, 587.866699, 0.00820099541, 0.0207469947, 0.0233091857, 0.019334842, 0.0205199677, 0.825000015, 0.00026403385, -0.00278436923, 0.00282395529, 0.00605174012, 0.000255721447, 0.000110791159, 32768.5645, 126.981082],
            [61.6703835, 338.32959, 448.251831, 600.000027, 199.999985, 365.873383, 200.0, 522.951721, 227.26622, 587.653748, 0.100428417, 0.0174866061, 0.162011301, 0.323355494, 0.714270796, 0.825000015, 0.94591397, 0.0118203447, -0.000197693328, -0.0238161057, 0.398043543, 0.678409398, 33472.5273, 135.707408],
            [155.960739, 400.0, 331.906891, 586.727932, 282.256775, 302.75824, 289.516693, 416.944458, 295.017731, 571.739746, 0.0555725236, 0.0866525095, 0.14214489, -0.0178356604, 0.299163479, 1.04501272, 1.02901626, -0.4653855, -0.00436493908, -0.0194648258, 0.433013231, 0.738010287, 33536.1151, 125.325965],
            [132.649475, 399.424438, 317.63855, 564.621548, 290.831848, 277.008942, 289.379974, 411.992249, 284.659454, 546.608887, 0.0592054806, 0.17789704, 0.189289004, 0.0212711884, 0.349636371, 1.04501272, 1.02942312, 0.00284397743, -0.0292823456, 0.0000614384688, 0.433184475, 0.738302112, 33598.8852, 125.571155],
            [167.976532, 398.361572, 370.058319, 593.703518, 286.423492, 318.830383, 278.219055, 466.474243, 300.721863, 579.607422, 0.0204286058, -0.139689261, 0.0357535722, 0.0407344159, 0.250004584, 1.04501272, 0.00597581128, 0.238530125, -0.00471989643, 0.00473120063, -0.0690555871, -0.127492934, 32641.5046, 125.430864],
            [163.42778, 394.991333, 375.014587, 600.000027, 278.744751, 327.70285, 279.120209, 469.562744, 302.730255, 587.394836, 0.00367590195, 0.0205362991, 0.010945834, 0.00683617146, 0.0246352146, 1.77645536, 9.97243106e-8, -8.41988349e-7, 0.00977992921, 0.0039296562, -4.0093413e-9, -4.49053559e-8, 32767.8154, 127.082793],
            [196.320923, 400.0, 150.718643, 388.877041, 285.225586, 107.713417, 348.336914, 230.509216, 333.356201, 373.850067, 0.0883256895, -0.0711607851, 0.0690985018, 0.132180987, 0.5692728, 1.77645536, 0.629800618, 0.0931769281, -0.00133634204, 0.0123438406, 0.587017894, 0.00141167897, 33242.7821, 149.548624],
            [36.9870148, 265.198456, 167.178284, 397.246823, 153.318893, 114.485893, 153.677124, 262.982208, 174.638275, 384.945953, 0.0250285791, 0.056338984, 0.036966443, 0.021614598, 0.048576715, 1.77645536, 0.017054474, -0.0194626499, 0.0153868245, -0.00535926514, 0.0146525912, -0.00027496909, 32780.0519, 125.920502],
            [1.40095282, 239.232559, 382.12973, 600.000027, 120.408417, 336.069153, 120.334297, 473.560486, 144.16925, 587.843323, 0.00751606069, -0.018790008, 0.0199348894, 0.0211179524, 0.0202383774, 4.28192086, 4.79662496e-8, -4.12365513e-7, -0.00893044194, -0.00260799841, 4.68990713e-8, 2.7670719e-8, 32768.0, 127.783399],
        ],
    ]
}
