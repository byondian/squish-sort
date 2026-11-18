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
            [83.2498398, 316.750183, 378.511078, 600.000027, 200.0, 329.085022, 200.0, 471.549683, 223.352417, 587.866394, 0.00094095284, -0.0141232468, 0.000893942949, 0.00326810551, 0.0171962136, 0.825000012, 0.0, 0.0, 0.00208414009, 0.00491910721, 0.0, 0.0, 32768.0, 127.052397],
            [74.2300644, 325.769989, 460.135529, 596.492581, 200.0, 371.435211, 200.0, 527.129761, 225.807327, 584.357727, 0.110494597, 0.0155545747, 0.0760812638, 0.416022517, 0.314551754, 0.825000012, 0.944824636, 0.0122197159, 0.0000652085031, -0.0216715199, 0.446378291, 0.649104714, 33479.2758, 154.933149],
            [161.064545, 398.860046, 334.666138, 566.366543, 282.30307, 300.981934, 288.952332, 418.999268, 300.566284, 552.93988, 0.0391126224, -0.200056147, 0.0370534754, 0.022865993, 0.16716292, 1.02432253, 1.11142325, -0.398769124, -0.00374468957, -0.0203213329, 0.521946967, 0.750240922, 33615.1674, 127.938888],
            [136.547913, 399.924866, 323.424957, 551.605618, 287.316223, 278.595703, 287.467529, 415.332916, 283.150726, 538.017212, 0.0444695904, 0.206129179, 0.125900218, 0.0398368968, 0.229015729, 1.02432253, 1.02823758, -0.000472620028, -0.0206351176, -0.00435631638, 0.485786378, 0.706410289, 33592.852, 128.452545],
            [144.67514, 396.799316, 363.539398, 590.039151, 285.444733, 315.370697, 282.790344, 456.071716, 286.452942, 577.183167, 0.0355272156, -0.0501164091, 0.10659309, 0.034580944, 0.0805800805, 1.02432253, 0.788802385, -0.286979448, -0.00837447125, 0.00167900487, 0.370546132, 0.530791163, 33414.9557, 124.342013],
            [154.406616, 390.819397, 378.852234, 600.000027, 272.835968, 330.713501, 272.690735, 471.690857, 295.950256, 587.426147, 0.0044047512, -0.0130448282, 0.0146210436, 0.00810791428, 0.0151093195, 1.7942016, 0.0531441048, -0.0203902851, 0.0101706388, 0.0041174169, 0.028782906, 0.0365784056, 32826.0095, 126.74907],
            [215.113251, 400.0, 149.37999, 376.137905, 297.090088, 102.117088, 348.778717, 232.552475, 349.46344, 361.387543, 0.085972148, -0.0158342222, 0.0139764613, 0.208432901, 0.315723057, 1.7942016, 0.629796624, 0.0928320627, 0.00134840583, 0.0106037914, 0.587033331, 0.0226289202, 33260.328, 157.295037],
            [40.9169579, 259.839935, 158.671402, 397.460263, 154.860687, 105.800873, 159.131805, 255.930527, 178.490173, 383.762665, 0.0365103433, -0.00508961268, 0.073751533, 0.0639166871, 0.0548731663, 1.7942016, 0.30983606, -0.112071296, 0.0135977664, 0.000433820865, 0.282963812, 0.0119748274, 33028.0756, 125.640026],
            [36.0967064, 274.062073, 382.404694, 600.000027, 155.104675, 335.736786, 155.099899, 473.705902, 178.794098, 587.774902, 0.00783060755, -0.00571663702, 0.019959614, 0.0222321885, 0.00683697651, 4.35171307, 0.0153669771, -0.00610593146, -0.00831583593, -0.00235392693, 0.0140912058, 0.00149689149, 32786.2577, 127.686789],
        ],
        "jelly": [
            [85.7904892, 314.209503, 370.826691, 600.000027, 200.0, 323.093567, 200.0, 467.275574, 222.780197, 587.865967, 0.0103766464, -0.000112075833, 0.033273564, 0.0217800587, 0.00746215039, 0.880000498, 0.0, 0.0273863599, 0.00369664104, 0.00481511275, -0.00745315803, -0.00301352027, 32745.9028, 126.734084],
            [62.2733307, 337.726685, 447.764496, 600.000027, 200.0, 367.093231, 200.0, 521.337891, 228.39917, 587.566223, 0.100183535, 0.00326327177, 0.162382178, 0.32558005, 1.04275049, 0.880000498, 0.896128714, 0.0104039223, 0.000905026298, -0.0167016088, 0.361695588, 0.651515961, 33470.5093, 136.380806],
            [167.867661, 395.655731, 325.866089, 578.483731, 284.154816, 294.381958, 289.159241, 415.214691, 303.208832, 563.743042, 0.0423180901, 0.152867454, 0.112129827, 0.0186482571, 0.33046149, 1.07574222, 0.974857092, -0.45496894, -0.0107643943, -0.0281022824, 0.393471956, 0.708754182, 33514.0936, 127.790945],
            [143.30101, 398.988403, 315.977448, 556.300442, 289.730896, 274.107758, 287.293213, 411.033722, 289.837738, 538.679871, 0.0424548383, 0.149512433, 0.137307263, 0.0213560001, 0.349730045, 1.07574222, 0.975242555, -0.00776857974, -0.0550492105, 0.0211473807, 0.393627524, 0.709034443, 33560.5802, 124.87225],
            [161.996887, 399.072906, 363.67627, 585.374661, 274.633148, 312.476654, 275.467438, 459.703827, 306.42572, 572.383911, 0.0174876642, 0.0324996591, 0.0072153654, 0.0165792928, 0.272973181, 1.07574222, 0.0214275289, -0.529255134, 0.0314373682, -0.00211275286, -0.21799393, -0.29003951, 32325.7092, 126.743118],
            [159.823013, 390.269836, 373.51062, 600.000027, 276.393341, 326.414917, 275.184967, 468.690216, 297.563965, 587.597778, 0.00577410045, 0.0209970483, 0.0164383505, 0.0128734022, 0.0260888036, 1.960819, 0.00102908933, -0.00250662894, 0.00987995422, 0.00355614743, -0.00111462944, 0.000927256711, 32764.7613, 127.07716],
            [196.628433, 400.0, 137.544937, 374.118344, 285.66037, 92.8662796, 341.995789, 229.348083, 333.431671, 360.461639, 0.0737142667, -0.0178633426, 0.0646855801, 0.133088947, 0.727492, 1.960819, 0.59678632, 0.0873099098, -0.00323055125, 0.0213885194, 0.555474281, 0.00558074191, 33242.6198, 147.783399],
            [26.9702015, 251.416306, 166.756241, 396.841854, 141.10434, 111.517319, 136.080566, 264.427185, 160.25148, 384.580475, 0.0281951923, 0.0478111423, 0.0373278801, 0.0403004565, 0.108705388, 1.960819, 0.0130614555, 0.0944941339, 0.00787042105, -0.0148998656, -0.102218866, 0.00374799827, 32678.9377, 126.135721],
            [125.332901, 361.78479, 380.809906, 600.000027, 243.58638, 334.855682, 243.565186, 472.8237, 267.137085, 587.827942, 0.00526920155, -0.0211863701, 0.0139177024, 0.0150926312, 0.0220926088, 4.55973889, 0.00188383285, 0.0064627639, -0.010205298, -0.00249084103, 0.00171816919, 0.000715712551, 32772.7805, 128.0],
        ],
        "gel": [
            [85.5643463, 314.43573, 373.464752, 600.000027, 200.0, 324.665283, 200.0, 468.766418, 223.052765, 587.866394, 0.00752619405, 0.0351020176, 0.0204734262, 0.0179037988, 0.0361481858, 0.916666564, 0.00880710315, 0.0290838149, 0.00309686982, 0.00743869413, 0.00844532531, 0.00283307373, 32789.8728, 126.980551],
            [67.5384674, 332.461609, 464.368713, 600.000027, 200.0, 373.173798, 200.0, 529.606201, 227.629852, 587.850098, 0.115699531, 0.0131145083, 0.127185581, 0.418962429, 0.801977972, 0.916666564, 1.14503634, 0.0179546297, -0.00114870845, -0.0390671728, 0.720462084, 0.942773163, 34115.0436, 147.732065],
            [162.954056, 397.966736, 326.68338, 571.021389, 281.908173, 291.812866, 289.585663, 416.672852, 301.549591, 556.579651, 0.0403000617, -0.0200358452, 0.0784846133, -0.00647208686, 0.411221185, 1.02326411, 1.25279689, -0.72898548, -0.00498638506, -0.021164394, 0.783757508, 1.02929521, 34274.2103, 124.038049],
            [140.358795, 399.410431, 318.860962, 553.657254, 287.227692, 272.981384, 285.264435, 412.915802, 283.99884, 540.581482, 0.0432499923, 0.186579953, 0.130358663, 0.0183200093, 0.46917668, 1.02326411, 1.24612486, 0.0127256278, -0.0386079793, 0.0070137381, 0.784067452, 1.02600503, 34343.6029, 122.581677],
            [153.351852, 394.024231, 366.069855, 598.701565, 283.357452, 317.605377, 277.24585, 461.353088, 291.3685, 582.707581, 0.0329590384, -0.176737127, 0.104490202, 0.0293583357, 0.257153836, 1.02326411, 0.0832876489, -1.30638799, -0.0199025708, 0.0147540625, 0.0000244600069, -0.0405741371, 32930.7124, 121.611648],
            [159.46582, 391.706879, 375.317688, 600.000027, 276.580688, 327.977631, 275.694397, 469.695984, 298.236603, 587.59491, 0.00283733611, 0.0158589943, 0.00799570768, 0.0045829448, 0.0340448264, 1.998456, 0.000215927546, -0.00089674536, 0.00844826011, 0.00410557819, 0.0000292038058, 0.000183593322, 32767.5231, 127.072484],
            [218.989334, 400.0, 137.660858, 372.627804, 299.193085, 83.3739777, 351.673676, 230.21759, 353.030823, 358.15155, 0.0900483204, -0.00696180545, 0.0602665343, 0.223353941, 0.694253452, 1.998456, 0.763609231, 0.145431087, -0.00268581744, 0.0146856295, 0.731062293, 0.0439235084, 33703.2312, 158.7868],
            [31.4959888, 257.693329, 221.903824, 453.116085, 149.265945, 165.479965, 142.213989, 319.807526, 166.369415, 440.962677, 0.0331320482, 0.0557689021, 0.0414364693, 0.0321826147, 0.0765650803, 1.998456, 0.00119718735, -0.259412736, 0.0223622453, -0.012474438, -0.00911534671, -0.0248098113, 32647.5387, 125.760867],
            [99.52948, 339.79129, 383.968414, 600.000027, 220.147186, 338.300232, 219.728958, 474.555023, 243.568558, 587.762024, 0.0112393766, -0.0216399843, 0.0300740372, 0.0310949303, 0.0232621738, 4.76752645, 0.0000230500646, -0.000690667759, -0.0086459246, -0.00341014293, -0.0000364288389, 0.00000130424951, 32767.8327, 127.826018],
        ],
        "mochi": [
            [85.6968689, 314.303192, 372.919922, 600.000027, 200.0, 324.58194, 200.0, 468.455597, 223.06749, 587.866699, 0.00823275091, 0.0209525495, 0.0232191203, 0.0195584541, 0.0207512473, 0.825000015, 0.00026403385, -0.00278436923, 0.00282395549, 0.00605656071, 0.000255721447, 0.000110791159, 32768.5645, 127.014879],
            [61.6800766, 338.319916, 448.265015, 600.000027, 200.0, 365.872406, 200.0, 522.961548, 227.269379, 587.65387, 0.100435446, 0.017488058, 0.161880187, 0.323441188, 0.714659595, 0.825000015, 0.945913076, 0.011820406, -0.000197695647, -0.0238086566, 0.398192346, 0.67832303, 33472.5314, 135.719843],
            [156.288727, 400.0, 331.923065, 586.72311, 282.262085, 302.752472, 289.660492, 416.954529, 295.163147, 571.734314, 0.0555512259, 0.086600728, 0.142079399, -0.0177468823, 0.29913894, 1.04504373, 1.0290153, -0.465386288, -0.00436549301, -0.0194591386, 0.433175117, 0.73791641, 33536.1182, 125.365182],
            [132.93132, 399.421021, 317.656158, 564.642605, 290.827179, 277.027344, 289.395203, 412.004211, 284.772675, 546.683838, 0.0590124401, 0.175177277, 0.18875778, 0.0208074719, 0.349728994, 1.04504373, 1.02942216, 0.00278683083, -0.0292453852, 0.0000439419171, 0.433346391, 0.738208175, 33598.1208, 125.518121],
            [167.750488, 398.216736, 370.063904, 593.658596, 286.218079, 318.827179, 278.063965, 466.464539, 300.565399, 579.565186, 0.0203875584, -0.138752089, 0.0356285257, 0.0406599705, 0.249236362, 1.04504373, 0.00597512769, 0.238540852, -0.00471253023, 0.00472565725, -0.0690868497, -0.127475217, 32641.6365, 125.438091],
            [163.459137, 395.040375, 374.93924, 600.000027, 278.698669, 327.671753, 279.151367, 469.512207, 302.800903, 587.318726, 0.00369465075, 0.0203744868, 0.0109936474, 0.00687831067, 0.0247587127, 1.77571176, 9.95599549e-8, -8.4209655e-7, 0.00978092256, 0.003929758, -3.95599775e-9, -4.49203945e-8, 32767.8158, 127.082368],
            [196.328018, 400.0, 150.654892, 388.803677, 285.225189, 107.651527, 348.333588, 230.458786, 333.354248, 373.791443, 0.0883263969, -0.0710546963, 0.0692410546, 0.13217107, 0.568948389, 1.77571176, 0.62980032, 0.0931769187, -0.00130943784, 0.0123440236, 0.587017536, 0.00141266792, 33242.7822, 149.535126],
            [36.9824753, 265.200012, 167.116455, 397.197506, 153.285477, 114.423454, 153.671448, 262.920624, 174.670334, 384.877319, 0.025028667, 0.0563506773, 0.0369642492, 0.0216238696, 0.0485678809, 1.77571176, 0.0170544591, -0.0194626386, 0.015387669, -0.00535887759, 0.0146525754, -0.00027489377, 32780.0523, 125.921458],
            [13.5668373, 251.398438, 382.111206, 600.000027, 132.383911, 336.059875, 132.463516, 473.548157, 156.385391, 587.777893, 0.00751676907, -0.0187942643, 0.0199363887, 0.0211200777, 0.0202410314, 4.28185399, 4.79654432e-8, -4.12359721e-7, -0.00893205701, -0.00260751667, 4.68982755e-8, 2.76701524e-8, 32768.0, 127.783718],
        ],
    ]
}
