import Foundation

/// Every number the design thread may retune lives in this file: the four
/// feels, the sound mapping and the haptics. Source of truth:
/// /mnt/project-files/content/squish-motion-spec.md and the Squish Room Test page.

public enum SquishFeel: String, Codable, CaseIterable, Sendable {
    case foam, jelly, gel, mochi

    /// Roster entries name their feel; anything missing or unknown is slow-rise foam.
    public init(named name: String?) {
        self = name.flatMap(SquishFeel.init(rawValue:)) ?? .foam
    }
}

public struct SquishMaterial: Codable, Equatable, Sendable {
    /// Spring towards the goal shape, 1/s² (higher = snappier).
    public var k: Double
    /// How much of a stretch or squash is allowed to linger (0 rigid, 1 floppy).
    public var beta: Double
    /// Damping of deformation, 1/s (high = slow rise, low = wobble).
    public var c: Double
    /// How much bending and bulging is allowed.
    public var quad: Double
    /// Volume kept when squashed (1 = sides bulge fully).
    public var vp: Double
    public var smin: Double
    public var smax: Double
    /// Gravity in body sizes per s².
    public var grav: Double
    public var fric: Double
    /// Bounce, 0...1.
    public var rest: Double
    /// How deep a press goes, as a share of the distance to the base.
    public var press: Double
    /// Radius of the firm patch under a finger, and the strength of the soft patch around it.
    public var grabR: Double
    public var halo: Double
    /// How much a landing squashes (0 none, 1 splat).
    public var land: Double
    /// How much the base sticks to the floor when pulled.
    public var grip: Double

    public init(k: Double, beta: Double, c: Double, quad: Double, vp: Double, smin: Double, smax: Double, grav: Double,
                fric: Double, rest: Double, press: Double, grabR: Double, halo: Double, land: Double, grip: Double) {
        self.k = k
        self.beta = beta
        self.c = c
        self.quad = quad
        self.vp = vp
        self.smin = smin
        self.smax = smax
        self.grav = grav
        self.fric = fric
        self.rest = rest
        self.press = press
        self.grabR = grabR
        self.halo = halo
        self.land = land
        self.grip = grip
    }
}

/// What a sound rule listens to. All come from `SquishBody.Metric`.
public enum SquishSignal: String, Codable, Sendable {
    /// How fast the toy is being pressed in (0 while rising).
    case press
    /// How fast it is rising back (0 while pressed).
    case rise
    /// Either of the two.
    case change
    /// How fast it is being stretched further.
    case stretch
    /// How fast the body is wobbling.
    case speed
}

public struct SquishLoopRule: Codable, Equatable, Sendable {
    public enum Blend: String, Codable, Sendable {
        /// Fades out as the squeeze gets deeper.
        case shallow
        /// Fades in as the squeeze gets deeper.
        case deep
    }

    public var loop: String
    public var signal: SquishSignal
    /// Volume = min(cap, gain × signal).
    public var gain: Double
    public var cap: Double
    public var blend: Blend?

    public init(_ loop: String, _ signal: SquishSignal, gain: Double, cap: Double, blend: Blend? = nil) {
        self.loop = loop
        self.signal = signal
        self.gain = gain
        self.cap = cap
        self.blend = blend
    }
}

public struct SquishGrainRule: Codable, Equatable, Sendable {
    public var set: String
    public var signal: SquishSignal
    /// Grains a second = min(cap, gain × signal), once the signal is over `over`.
    public var gain: Double
    public var cap: Double
    public var over: Double
    public var volumeMin: Double
    public var volumeMax: Double
    /// Extra grains a second for as long as the toy is still rising after it is
    /// let go: `tailBase + tailPerDepth × depth`.
    public var tailBase: Double
    public var tailPerDepth: Double
    /// Extra left-right scatter on top of the usual 0.25.
    public var scatter: Double

    public init(_ set: String, _ signal: SquishSignal, gain: Double, cap: Double, over: Double = 0,
                volume: ClosedRange<Double>, tailBase: Double = 0, tailPerDepth: Double = 0, scatter: Double = 0) {
        self.set = set
        self.signal = signal
        self.gain = gain
        self.cap = cap
        self.over = over
        volumeMin = volume.lowerBound
        volumeMax = volume.upperBound
        self.tailBase = tailBase
        self.tailPerDepth = tailPerDepth
        self.scatter = scatter
    }
}

public struct SquishFeelTuning: Codable, Equatable, Sendable {
    public var material: SquishMaterial
    public var loops: [SquishLoopRule]
    public var grains: [SquishGrainRule]
    /// Bubbles thrown in with a landing thud.
    public var landingBubbles: Int
    /// A pop when a deep squeeze is let go.
    public var popsOnRelease: Bool
    public var hapticSharpness: Double
    /// A very light tap with each grain of this set (foam crackle).
    public var hapticGrainSet: String?
}

public struct SquishTuning: Codable, Equatable, Sendable {
    public var feels: [String: SquishFeelTuning]
    /// Fixed step of the body, run twice a frame.
    public var stepSeconds = 1.0 / 120
    /// Every sound's volume is multiplied by this.
    public var masterVolume = 1.0
    /// `metric.D` is multiplied by this and capped at 1 to give the depth the sound rules use.
    public var depthScale = 3.0
    public var grainPanScatter = 0.25
    /// Most grains started in one frame, and the most that may be sounding at once.
    public var grainsPerFrame = 6
    public var grainVoices = 16
    public var thudOverImpact = 0.5
    public var thudGain = 0.11
    public var thudOffset = 0.3
    public var thudMin = 0.04
    public var thudMax = 0.34
    public var landingBubbleVolume = 0.03...0.07
    public var popOverDepth = 0.05
    public var popGain = 1.6
    public var popMax = 0.3
    /// Morph Squad squishies change when a squeeze deeper than this is let go.
    public var morphOverDepth = 0.08
    /// Continuous haptic while a finger is on the toy: min(1, hapticGain × D).
    public var hapticGain = 3.0
    public var hapticGrainsPerSecond = 20.0
    public var hapticLandingGain = 0.25
    /// Reduce Motion: the press goes this share as deep.
    public var reducedPress = 0.5

    public func feel(_ feel: SquishFeel) -> SquishFeelTuning {
        feels[feel.rawValue] ?? SquishTuning.standard.feels[SquishFeel.foam.rawValue]!
    }

    public func material(_ feel: SquishFeel, reduceMotion: Bool = false) -> SquishMaterial {
        var m = self.feel(feel).material
        if reduceMotion { m.press *= reducedPress }
        return m
    }

    /// First tuning, 16 Nov 2026 (spec sections 4, 6 and 7).
    public static let standard = SquishTuning(feels: [
        "foam": SquishFeelTuning(
            material: SquishMaterial(k: 300, beta: 0.68, c: 62, quad: 0.55, vp: 0.9, smin: 0.40, smax: 1.7, grav: 9,
                                     fric: 0.9, rest: 0.05, press: 0.46, grabR: 0.20, halo: 0.35, land: 0.6, grip: 0.5),
            loops: [
                SquishLoopRule("air_out", .press, gain: 0.55, cap: 0.5),
                SquishLoopRule("air_in", .rise, gain: 0.8, cap: 0.16),
            ],
            grains: [
                SquishGrainRule("crackle_press", .press, gain: 320, cap: 90, volume: 0.16...0.42),
                SquishGrainRule("crackle_rise", .rise, gain: 320, cap: 90, volume: 0.09...0.23, tailBase: 9, tailPerDepth: 40),
            ],
            landingBubbles: 0, popsOnRelease: false, hapticSharpness: 0.2, hapticGrainSet: "crackle_press"),
        "jelly": SquishFeelTuning(
            material: SquishMaterial(k: 700, beta: 0.72, c: 5.5, quad: 0.6, vp: 1, smin: 0.45, smax: 1.9, grav: 9,
                                     fric: 0.55, rest: 0.22, press: 0.44, grabR: 0.20, halo: 0.35, land: 0.75, grip: 0.3),
            loops: [
                SquishLoopRule("squelch_low", .change, gain: 0.24, cap: 0.3, blend: .shallow),
                SquishLoopRule("squelch_high", .change, gain: 0.24, cap: 0.3, blend: .deep),
                SquishLoopRule("hum", .speed, gain: 0.08, cap: 0.1),
            ],
            grains: [
                SquishGrainRule("bubble", .press, gain: 16, cap: 12, over: 0.05, volume: 0.03...0.08),
            ],
            landingBubbles: 3, popsOnRelease: false, hapticSharpness: 0.4, hapticGrainSet: nil),
        "gel": SquishFeelTuning(
            material: SquishMaterial(k: 440, beta: 0.78, c: 5.5, quad: 0.6, vp: 0.9, smin: 0.42, smax: 2.1, grav: 11,
                                     fric: 0.6, rest: 0.08, press: 0.44, grabR: 0.22, halo: 0.45, land: 1.0, grip: 0.35),
            loops: [
                SquishLoopRule("squelch_low", .change, gain: 0.2, cap: 0.26, blend: .shallow),
                SquishLoopRule("squelch_high", .change, gain: 0.2, cap: 0.26, blend: .deep),
                SquishLoopRule("hum", .speed, gain: 0.05, cap: 0.07),
            ],
            grains: [
                SquishGrainRule("bubble", .change, gain: 60, cap: 44, over: 0.02, volume: 0.05...0.14, scatter: 0.3),
            ],
            landingBubbles: 3, popsOnRelease: true, hapticSharpness: 0.1, hapticGrainSet: nil),
        "mochi": SquishFeelTuning(
            material: SquishMaterial(k: 380, beta: 0.74, c: 12, quad: 0.5, vp: 1, smin: 0.40, smax: 2.6, grav: 9,
                                     fric: 1, rest: 0, press: 0.46, grabR: 0.19, halo: 0.3, land: 0.65, grip: 0.9),
            loops: [
                SquishLoopRule("creak", .stretch, gain: 1.2, cap: 0.4),
                SquishLoopRule("air_out", .press, gain: 0.4, cap: 0.35),
            ],
            grains: [
                SquishGrainRule("tack_press", .press, gain: 45, cap: 24, over: 0.02, volume: 0.08...0.2),
                SquishGrainRule("tack_rise", .rise, gain: 70, cap: 30, over: 0.02, volume: 0.12...0.3),
            ],
            landingBubbles: 0, popsOnRelease: true, hapticSharpness: 0.3, hapticGrainSet: nil),
    ])
}
