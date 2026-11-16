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
        return [bb.x0, bb.x1, bb.y0, bb.y1, Double(b.p[12]), Double(b.p[13]), Double(b.p[168]), Double(b.p[169]),
                Double(b.p[300]), Double(b.p[301]), m.D, m.rate, m.stretch, m.squash, m.speed, m.impact]
    }

    /// The same script as the design thread's page engine (squish-engine.js run in Node):
    /// settle, press the top, drag, add a second finger, let go, pick up, throw at a wall, land.
    private func script(_ feel: SquishFeel) -> [[Double]] {
        let b = body(feel)
        var marks: [[Double]] = []
        for _ in 0..<60 { b.step(h, world: world) }
        marks.append(mark(b))
        let top = b.bounds()
        XCTAssertTrue(b.grab(1, x: 200, y: top.y0 + 12))
        for _ in 0..<72 { b.step(h, world: world) }
        marks.append(mark(b))
        for i in 1...30 {
            b.move(1, x: 200 + Double(i) * 3, y: top.y0 + 12 - Double(i) * 2, dt: h)
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
                    // Positions in points, then the numbers behind sound and haptics.
                    let slack = column < 10 ? 0.5 : 0.02 + abs(w[column]) * 0.05
                    XCTAssertEqual(g[column], w[column], accuracy: slack, "\(feel) mark \(row) column \(column)")
                }
            }
        }
    }

    /// Spec section 4: press the top for 0.6 s, then let go.
    func testEachFeelLooksAsMeasured() {
        // Height and width when pressed, as a share of the resting size (the test's plain oval, run through the page engine).
        let expected: [SquishFeel: (height: ClosedRange<Double>, width: ClosedRange<Double>)] = [
            .foam: (0.48...0.62, 1.06...1.20), .jelly: (0.55...0.69, 1.20...1.38),
            .gel: (0.52...0.66, 1.20...1.38), .mochi: (0.50...0.64, 1.24...1.42),
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
            b.release(1)
            var tallest = 0.0
            var backAt: Double?
            for i in 1...480 {
                b.step(h, world: world)
                let now = b.bounds()
                let height = (now.y1 - now.y0) / restH
                tallest = max(tallest, height)
                if backAt == nil, height >= 0.9 { backAt = Double(i) * h }
            }
            if feel == .foam {
                XCTAssertLessThan(tallest, 1.02, "foam creeps back and never overshoots")
                XCTAssertGreaterThan(backAt ?? 0, 0.8, "foam is slow to rise")
            } else {
                XCTAssertLessThan(backAt ?? 9, 0.5, "\(feel) springs back")
            }
            if feel == .jelly { XCTAssertGreaterThan(tallest, 1.05, "jelly overshoots") }
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
                    b.move(1, x: Double.random(in: -200...600, using: &rng), y: Double.random(in: -300...900, using: &rng), dt: h * 2)
                    b.move(2, x: Double.random(in: -200...600, using: &rng), y: Double.random(in: -300...900, using: &rng), dt: h * 2)
                }
                b.step(h, world: world)
                XCTAssertLessThan(b.metric.D, 2.5)
            }
            b.releaseAll()
            for _ in 0..<600 { b.step(h, world: world) }
            let end = b.bounds()
            for value in b.p { XCTAssertTrue(value.isFinite) }
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
        let b = body(.foam)
        b.breathScale = 0
        for _ in 0..<240 { b.step(h, world: world) }
        let first = b.bounds()
        for _ in 0..<100 { b.step(h, world: world) }
        let later = b.bounds()
        XCTAssertEqual(first.y0, later.y0, accuracy: 0.5, "the breath alone would move it about 3 points")
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
        XCTAssertEqual(shallow.loops["squelch_low"] ?? 0, 0.12, accuracy: 1e-9)
        XCTAssertEqual(shallow.loops["squelch_high"] ?? 0, 0, accuracy: 1e-9)
        XCTAssertEqual(shallow.loops["hum"] ?? 0, 0.04, accuracy: 1e-9)
        let deep = mixer.frame(dt: 1.0 / 60, metric: metric(D: 0.5, rate: -3, speed: 9), feel: .jelly, rng: &rng)
        XCTAssertEqual(deep.loops["squelch_low"] ?? 0, 0, accuracy: 1e-9)
        XCTAssertEqual(deep.loops["squelch_high"] ?? 0, 0.3, accuracy: 1e-9)
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
            [83.3550491, 316.644928, 378.14502, 600.000027, 200.0, 329.976868, 200.0, 471.346832, 223.333557, 587.866455, 0.0006660582, -0.0100097497, -0.0000010324996, 0.00152934673, 0.0146214678, 0.824999978],
            [69.1552353, 330.844757, 477.22348, 600.000027, 200.0, 411.723785, 200.0, 524.251038, 227.021606, 587.77478, 0.122666043, 0.0121002621, 0.108788803, 0.461329094, 0.305928854, 0.824999978],
            [137.949692, 386.397552, 330.666992, 595.464749, 279.622955, 307.418488, 283.902496, 434.763153, 265.761444, 581.015015, 0.0736351354, 0.26288251, 0.212182053, 0.0115842901, 0.12484483, 0.824999978],
            [114.52597, 399.547394, 325.250671, 577.043301, 286.639984, 291.258362, 282.088928, 419.3479, 254.717789, 562.980408, 0.0912034649, 0.258059438, 0.314938995, 0.00931048727, 0.184345787, 0.824999978],
            [131.409302, 388.634247, 366.749939, 600.000027, 280.696625, 326.696991, 273.028656, 460.189728, 268.047241, 584.803284, 0.05584099, -0.196794344, 0.190045217, 0.0653426599, 0.149226861, 1.4252522],
            [138.386627, 373.963837, 378.656342, 600.000027, 256.78186, 331.386078, 256.298187, 471.544464, 278.78244, 587.095703, 0.00475554291, -0.0128111761, 0.0136864961, 0.0119589622, 0.0144373891, 1.4252522],
            [245.726898, 400.0, 149.198456, 376.091183, 343.691986, 95.4254684, 398.855774, 232.390961, 379.72525, 360.805786, 0.136414651, 0.395495906, 0.0106798627, 0.319613065, 0.281966279, 1.4252522],
            [192.234116, 400.0, 155.618378, 399.386441, 300.008148, 102.249809, 311.4617, 255.14537, 325.122437, 386.05542, 0.0489594771, -0.05436262, 0.0994577999, 0.111358508, 0.0907470483, 1.4252522],
            [162.921265, 399.931702, 381.951538, 600.000027, 281.454407, 335.691986, 281.459259, 473.460724, 305.078857, 587.843628, 0.00659053036, -0.00380959696, 0.0156561117, 0.019696025, 0.00458905085, 4.35027361],
        ],
        "jelly": [
            [85.404953, 314.595032, 371.389191, 600.000027, 200.0, 323.693604, 200.0, 467.582581, 222.80368, 587.866089, 0.00933018708, -0.0121114075, 0.0309955876, 0.0185926963, 0.018521054, 0.824999967],
            [53.3285141, 346.671417, 458.833466, 600.000027, 200.0, 399.271515, 200.0, 499.35141, 230.429337, 587.607727, 0.11453207, 0.00963562116, 0.230732929, 0.352245327, 1.20190976, 0.824999967],
            [157.084076, 376.942291, 323.72168, 596.941616, 281.185974, 294.055542, 279.552948, 431.261932, 272.478912, 580.195984, 0.0732484816, 0.345572455, 0.23961381, 0.0948936978, 0.616747511, 0.824999967],
            [128.198685, 392.518433, 318.245667, 570.386929, 291.876373, 280.388977, 279.541473, 417.900452, 274.985748, 545.775696, 0.0703373788, 0.201012395, 0.23911821, 0.0569157229, 0.498151025, 0.824999967],
            [154.013443, 399.989899, 375.607147, 600.000027, 260.608826, 324.932159, 273.441406, 465.12146, 307.322052, 587.866699, 0.0358814921, 0.186801811, 0.0837661945, 0.0465993213, 0.567300751, 1.59283141],
            [154.908051, 385.017303, 373.195038, 600.000027, 270.15332, 325.990753, 270.022095, 468.53183, 291.978912, 587.533325, 0.00623592223, 0.0194877339, 0.0177801069, 0.0143297367, 0.0319051638, 1.59283141],
            [219.332336, 400.0, 135.731049, 379.275387, 309.247833, 85.0473557, 389.190338, 229.255783, 343.24588, 365.6539, 0.127061455, 0.243109266, 0.0914597879, 0.246770495, 1.36262688, 1.59283141],
            [146.539642, 365.92337, 139.877167, 375.516262, 259.647705, 84.3246689, 244.659988, 240.629059, 274.075195, 363.242157, 0.0407254916, -0.099960021, 0.0588011285, 0.0779046569, 0.491516331, 1.59283141],
            [128.536346, 364.509399, 380.49704, 600.000027, 246.390579, 334.533508, 246.507706, 472.639435, 270.299774, 587.677856, 0.00463696135, -0.0193000363, 0.0116721846, 0.0139295622, 0.020248519, 4.48098648],
        ],
        "gel": [
            [87.6757202, 312.324249, 369.482056, 600.000027, 200.0, 321.021332, 200.0, 466.522919, 222.597351, 587.866028, 0.0145474189, 0.0155402806, 0.0386696929, 0.0386128314, 0.0480887722, 0.916666647],
            [56.0230026, 343.976959, 463.554901, 600.000027, 200.0, 409.296112, 200.0, 510.149017, 230.86142, 587.701294, 0.119427819, 0.0108971896, 0.197943696, 0.394957553, 0.962616203, 0.916666647],
            [156.587036, 388.347595, 321.566803, 597.364041, 281.93692, 292.979126, 285.631012, 422.95575, 273.057343, 580.417847, 0.0799028354, 0.350140206, 0.268718694, 0.0587421594, 0.499335016, 0.916666647],
            [128.279251, 395.055847, 316.199402, 575.114224, 290.218475, 278.906708, 280.42981, 413.232483, 263.0625, 554.141052, 0.0792163193, 0.208044447, 0.276641103, 0.0455460406, 0.394387756, 0.916666647],
            [174.262878, 395.040863, 382.530792, 599.923245, 283.461884, 328.259064, 278.435638, 478.358154, 309.434753, 584.891113, 0.0290616849, -0.268318017, -0.0224114829, 0.0845088671, 0.548969399, 0.916666647],
            [154.940399, 385.034149, 371.20874, 600.000027, 272.557678, 324.451599, 270.228699, 467.231934, 291.146576, 587.049316, 0.00724633338, 0.0243623724, 0.0210667053, 0.0158493012, 0.0447375791, 2.06035376],
            [255.82608, 400.0, 131.32019, 377.388485, 336.465149, 67.8447342, 394.454742, 227.720673, 370.751587, 362.366699, 0.146153297, 0.388143467, 0.100316625, 0.387011685, 1.05858242, 2.06035376],
            [145.057816, 380.95285, 220.451889, 453.438015, 259.756653, 169.470657, 270.617676, 316.426453, 286.555969, 441.083374, 0.0351868568, -0.209526462, 0.0517457928, -0.0306651838, 0.638537893, 2.06035376],
            [143.642975, 381.040741, 381.83194, 600.000027, 262.468079, 336.08075, 262.384583, 473.380524, 286.009491, 587.80481, 0.00703709643, -0.0245939043, 0.0186379954, 0.0200679806, 0.026439363, 4.77544232],
        ],
        "mochi": [
            [85.6773987, 314.322571, 372.911011, 600.000027, 199.999985, 324.879364, 200.0, 468.450073, 223.06044, 587.866638, 0.00820029329, 0.0207250021, 0.0232486435, 0.019385974, 0.0203031876, 0.825000002],
            [49.4824066, 350.517548, 471.439178, 600.000027, 199.999985, 407.938507, 200.0, 509.391693, 230.523605, 587.674866, 0.129134893, 0.0190994555, 0.251532457, 0.404891539, 0.739440953, 0.825000002],
            [126.127319, 371.861511, 325.49881, 599.814541, 277.321198, 303.77179, 274.45105, 435.052429, 247.743668, 583.99646, 0.0938480386, 0.352804808, 0.312849751, 0.0567775915, 0.4410675, 0.825000002],
            [103.054268, 385.823639, 319.920197, 577.287625, 288.961121, 286.530853, 276.551544, 420.120697, 245.487091, 559.081421, 0.107504292, 0.238840208, 0.372836437, 0.0691600016, 0.39637178, 0.825000002],
            [157.369568, 376.200226, 375.863708, 600.000027, 264.847931, 326.421265, 259.533417, 471.403015, 288.99118, 578.817932, 0.0274385575, -0.353239617, 0.0172718033, 0.0981061834, 0.35790058, 1.57215586],
            [151.261597, 382.816742, 375.091492, 600.000027, 267.052399, 327.789612, 267.027191, 469.615143, 290.800079, 587.464905, 0.00373068965, 0.0164802708, 0.0110346531, 0.00699831215, 0.0294354998, 1.57215586],
            [225.189957, 400.0, 150.187775, 389.40939, 320.212463, 99.4327774, 395.408325, 230.538696, 353.312531, 374.442871, 0.139918242, 0.257584622, 0.0700670193, 0.26134802, 0.739892463, 1.57215586],
            [163.456436, 393.52536, 167.600388, 396.969784, 277.894135, 115.383827, 282.070679, 263.091278, 302.399933, 384.714294, 0.0225981526, 0.0566493965, 0.0334854912, 0.0122348812, 0.0830139903, 1.57215586],
            [160.207153, 398.038757, 382.1604, 600.000027, 279.069641, 336.282013, 279.112885, 473.580994, 303.00412, 587.827332, 0.00751709579, -0.0187890211, 0.0199344377, 0.0211172194, 0.0201348331, 4.35692396],
        ]
    ]
}
