import Foundation

/// Turns the body's numbers into what should sound this frame. It decides, the
/// app only plays: loops run silently all the time and only their volume
/// moves, and grains are fired at a rate that follows the squish.
public struct SquishSoundMixer {
    public struct Grain: Equatable, Sendable {
        public var set: String
        public var volume: Double
        /// Added to the toy's own left-right position.
        public var pan: Double
    }

    public struct Frame: Sendable {
        /// Volume by loop name. Loops not listed are silent.
        public var loops: [String: Double] = [:]
        public var grains: [Grain] = []
        /// Volume of the landing thud, if there is one.
        public var thud: Double?
    }

    public var tuning: SquishTuning
    private var carried: [String: Double] = [:]
    private var lastStretch = 0.0

    public init(tuning: SquishTuning = .standard) {
        self.tuning = tuning
    }

    public mutating func reset() {
        carried = [:]
        lastStretch = 0
    }

    /// Call once a frame, then clear the body's impact.
    public mutating func frame<R: RandomNumberGenerator>(dt: Double, metric: SquishBody.Metric, feel: SquishFeel, rng: inout R) -> Frame {
        let rules = tuning.feel(feel)
        let press = max(0, metric.rate), rise = max(0, -metric.rate)
        let depth = min(1, max(0, metric.D * tuning.depthScale))
        let stretchRate = max(0, (metric.stretch - lastStretch) / max(dt, 0.004))
        lastStretch = metric.stretch
        func value(_ signal: SquishSignal) -> Double {
            switch signal {
            case .press: return press
            case .rise: return rise
            case .change: return abs(metric.rate)
            case .stretch: return stretchRate
            case .speed: return metric.speed
            }
        }
        var out = Frame()
        for rule in rules.loops {
            var volume = min(rule.cap, rule.gain * value(rule.signal))
            switch rule.blend {
            case .shallow: volume *= 1 - depth
            case .deep: volume *= depth
            case nil: break
            }
            out.loops[rule.loop, default: 0] += volume * tuning.masterVolume
        }
        for rule in rules.grains {
            let signal = value(rule.signal)
            var perSecond = signal > rule.over ? min(rule.cap, rule.gain * signal) : 0
            // Still rising after being let go: sparse grains that thin out as it recovers.
            if rule.tailBase > 0, rise > 0.004, metric.D > 0.012, metric.held == 0 {
                perSecond += rule.tailBase + rule.tailPerDepth * depth
            }
            guard perSecond > 0.5 else { continue }
            var due = (carried[rule.set] ?? 0) + perSecond * dt
            var fired = 0
            while due >= 1 && fired < tuning.grainsPerFrame {
                let scatter = tuning.grainPanScatter + rule.scatter
                out.grains.append(Grain(set: rule.set,
                                        volume: Double.random(in: rule.volumeMin...rule.volumeMax, using: &rng) * tuning.masterVolume,
                                        pan: Double.random(in: -scatter...scatter, using: &rng)))
                due -= 1
                fired += 1
            }
            carried[rule.set] = due > Double(tuning.grainsPerFrame) ? 0 : due
        }
        if metric.impact > tuning.thudOverImpact {
            let volume = min(tuning.thudMax, max(tuning.thudMin, (metric.impact - tuning.thudOffset) * tuning.thudGain))
            out.thud = volume * tuning.masterVolume
            for _ in 0..<rules.landingBubbles {
                out.grains.append(Grain(set: "bubble",
                                        volume: Double.random(in: tuning.landingBubbleVolume, using: &rng) * tuning.masterVolume,
                                        pan: 0))
            }
        }
        return out
    }

    /// Volume of the pop when a squeeze of this depth is let go, if this feel pops.
    public func pop(depth D: Double, feel: SquishFeel) -> Double? {
        guard tuning.feel(feel).popsOnRelease, D > tuning.popOverDepth else { return nil }
        return min(tuning.popMax, D * tuning.popGain) * tuning.masterVolume
    }

    /// Continuous haptic strength while a finger is on the toy.
    public func hapticIntensity(metric: SquishBody.Metric) -> Double {
        metric.held > 0 ? min(1, tuning.hapticGain * metric.D + tuning.hapticDentGain * metric.Z) : 0
    }
}

/// Board pieces: two springs each instead of fixed scale sequences (spec section 8).
public struct PieceSpring: Sendable {
    public var value = 0.0
    public var velocity = 0.0
    public var target = 0.0

    public static let omega = 2 * Double.pi * 5
    public static let zeta = 0.35
    public static let step = 1.0 / 120
    /// A piece never squashes past this.
    public static let maxSquash = 0.3

    public init() {}

    public mutating func advance(_ dt: Double) {
        var left = min(dt, 0.1)
        while left > 1e-9 {
            let h = min(left, PieceSpring.step)
            let w = PieceSpring.omega
            velocity += (-w * w * (value - target) - 2 * PieceSpring.zeta * w * velocity) * h
            value += velocity * h
            left -= h
        }
    }

    public var isResting: Bool { abs(value - target) < 0.0005 && abs(velocity) < 0.005 }

    /// How far a spring at rest swings for a kick of 1, found by running it.
    private static let peakPerKick: Double = {
        var s = PieceSpring()
        s.velocity = 1
        var peak = 0.0
        for _ in 0..<60 {
            s.advance(step)
            peak = max(peak, s.value)
        }
        return peak
    }()

    /// The kick that makes a spring at rest peak at `peak`.
    public static func kick(forPeak peak: Double) -> Double { peak / peakPerKick }

    /// How far a spring at rest swings for this kick.
    public static func peak(forKick kick: Double) -> Double { kick * peakPerKick }

    /// Stack ripple: each piece under the one that landed gets this share of the squash of the piece above it...
    public static let rippleShare = 0.6
    /// ...this much later each.
    public static let rippleDelay = 0.04
    /// A lift is a quick stretch upwards.
    public static let liftKick = -3.0
    /// The lean aims at this many radians per piece width a second of sideways speed, up to `maxLean`.
    public static let leanPerSpeed = 0.02
    public static let maxLean = 12 * Double.pi / 180
    /// Rejected move: the lean kicks this far, twice.
    public static let rejectLean = 8 * Double.pi / 180
    /// Jar complete: all four squash to `maxSquash` together over this long, then let go at once.
    public static let completeSqueezeSeconds = 0.12

    /// Landing: velocity += 0.6 × landing speed (piece heights per second), capped so the squash never passes 0.3.
    public static func landingKick(speed: Double) -> Double {
        min(0.6 * speed, kick(forPeak: maxSquash))
    }
}
