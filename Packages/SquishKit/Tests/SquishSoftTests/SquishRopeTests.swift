import XCTest
@testable import SquishSoft

/// The Swift rope must move like the design thread's squish-rope.js. The numbers below come from
/// running that file in Node with the same script: settle, pull the head up and away, hold, let go.
final class SquishRopeTests: XCTestCase {
    private let cubics: [[Double]] = [[38, 35.2, 66, 27.2, 94, 37.2, 84, 57.2], [84, 57.2, 74, 77.2, 30, 65.2, 34, 85.2],
                                      [34, 85.2, 36, 97.2, 70, 99.2, 98, 89.2]]
    private let world = SquishRope.World(floor: 400, left: 6, right: 394)
    private let h = 1.0 / 240

    private func snap(_ rope: SquishRope) -> [Double] {
        [rope.p[0], rope.p[1], rope.p[58], rope.p[59], rope.metric.unravel, rope.angle]
    }

    private func check(_ got: [Double], _ want: [Double], _ what: String, accuracy: Double = 0.02) {
        XCTAssertEqual(got.count, want.count)
        for (g, w) in zip(got, want) { XCTAssertEqual(g, w, accuracy: accuracy, what) }
    }

    func testTaffySnakeUncoilsAndCoilsBackLikeTheReference() {
        let rope = SquishRope(cubics: cubics, n: 30, size: 240, x: 200, y: 300, radius: 15.5, headR: 22, material: .taffy)
        for _ in 0..<240 { rope.step(h, world: world) }
        check(snap(rope), [148.473781, 268.950762, 270.528895, 368.573756, 0, 0], "settled")
        let hx = rope.p[0], hy = rope.p[1]
        XCTAssertTrue(rope.grab(1, x: hx, y: hy))
        for i in 1...120 {
            rope.move(1, x: hx + 120 * Double(i) / 120, y: hy - 150 * Double(i) / 120)
            rope.step(h, world: world)
        }
        check(snap(rope), [268.473781, 118.950762, 271.290508, 368.974663, 0.3862, 0.214347], "pulled")
        for _ in 0..<240 { rope.step(h, world: world) }
        check(snap(rope), [268.473781, 118.950762, 275.340419, 368.974683, 0.386542, 0.291045], "held")
        rope.release(1)
        XCTAssertEqual(rope.metric.recoil, 0.386542, accuracy: 0.001, "a good pull springs back")
        for _ in 0..<480 { rope.step(h, world: world) }
        check(snap(rope), [153.270677, 275.292429, 275.7151, 368.654888, 0, 0.000695], "coiled back", accuracy: 0.3)
        XCTAssertFalse(rope.grab(2, x: 0, y: 0), "a touch far away misses")
    }

    func testALimbRidesOnTheBodyAndSwings() {
        var t = 0.0
        let tail = SquishRope.Material(k: 700, heldK: 0.05, curl: 0.1, smax: 1.8, damp: 2.0, grav: 4)
        let limb = SquishRope(points: [[94, 94], [108, 88], [114, 70], [106, 56]], n: 8, size: 240, radius: 8, headR: 8,
                              material: tail, root: { SquishRope.Root(x: 200 + 40 * sin(t * 6), y: 300, a: 0.3 * sin(t * 4)) })
        for _ in 0..<300 {
            t += h
            limb.step(h, world: world)
        }
        check([limb.p[0], limb.p[1], limb.p[14], limb.p[15]], [237.519999, 300, 240.896226, 220.90463], "limb", accuracy: 0.05)
    }
}
