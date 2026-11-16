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
    // Depth (version 2).
    /// How deep a finger dents the surface (1 = about the toy's own puffiness), and the dent's radius in toy sizes.
    public var poke: Double
    public var pokeR: Double
    /// Spring that fills a dent back in, 1/s², and its damping, 1/s (high = slow fill, low = ripples).
    public var zk: Double
    public var zd: Double
    /// Speed at which ripples cross the surface, toy sizes per second.
    public var zc: Double
    /// How much a landing makes the belly ripple.
    public var zland: Double
    /// How much the whole toy swells while dented.
    public var puff: Double
    /// Spring and damping of the face sliding over the body, and how far the face turns towards a finger.
    public var tk: Double
    public var td: Double
    public var look: Double
    // Light.
    /// Strength of light and shade.
    public var kd: Double
    /// Size and tightness of the wet highlight.
    public var gloss: Double
    public var shin: Double
    /// How dark the inside of a dent gets.
    public var ao: Double

    public init(k: Double, beta: Double, c: Double, quad: Double, vp: Double, smin: Double, smax: Double, grav: Double,
                fric: Double, rest: Double, press: Double, grabR: Double, halo: Double, land: Double, grip: Double,
                poke: Double, pokeR: Double, zk: Double, zd: Double, zc: Double, zland: Double, puff: Double,
                tk: Double, td: Double, look: Double, kd: Double, gloss: Double, shin: Double, ao: Double) {
        self.poke = poke
        self.pokeR = pokeR
        self.zk = zk
        self.zd = zd
        self.zc = zc
        self.zland = zland
        self.puff = puff
        self.tk = tk
        self.td = td
        self.look = look
        self.kd = kd
        self.gloss = gloss
        self.shin = shin
        self.ao = ao
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
    /// One light tap when a released dent pops out past flat for the first time (jelly).
    public var hapticDentPop = false
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
    /// Continuous haptic while a finger is on the toy: min(1, hapticGain × D + hapticDentGain × Z).
    public var hapticGain = 3.0
    public var hapticDentGain = 0.4
    /// The light, shared by all four feels: how strongly the rest shape and the dent catch the light,
    /// how far the art is pulled into a dent, and where the light comes from (upper left, towards the viewer; y is down).
    public var restRelief = 0.2
    public var dentRelief = 0.3
    public var dentPinch = 0.004
    public var light = [-0.46, -0.62, 0.64]
    /// The most a tilt of the phone adds to the light and to the face slide.
    public var phoneTilt = 0.03
    /// Pressing harder (a bigger contact patch) adds up to this share to the dent depth.
    public var hardPressExtra = 0.5
    public var hapticGrainsPerSecond = 20.0
    public var hapticLandingGain = 0.25
    /// Reduce Motion: the press goes this share as deep.
    public var reducedPress = 0.5

    public func feel(_ feel: SquishFeel) -> SquishFeelTuning {
        feels[feel.rawValue] ?? SquishTuning.standard.feels[SquishFeel.foam.rawValue]!
    }

    public func material(_ feel: SquishFeel, reduceMotion: Bool = false) -> SquishMaterial {
        var m = self.feel(feel).material
        if reduceMotion {
            // Reduce Motion: half as deep, and the face stays put.
            m.press *= reducedPress
            m.poke *= reducedPress
            m.look = 0
        }
        return m
    }

    /// Second tuning (the depth version), 16 Nov 2026 (spec sections 5, 7 and 8).
    public static let standard = SquishTuning(feels: [
        "foam": SquishFeelTuning(
            material: SquishMaterial(k: 300, beta: 0.68, c: 62, quad: 0.55, vp: 0.9, smin: 0.40, smax: 1.7, grav: 9,
                                     fric: 0.9, rest: 0.05, press: 0.46, grabR: 0.20, halo: 0.35, land: 0.6, grip: 0.5,
                                     poke: 0.95, pokeR: 0.13, zk: 77, zd: 60, zc: 0.25, zland: 0, puff: 0.2,
                                     tk: 60, td: 14, look: 0.07, kd: 0.6, gloss: 0, shin: 20, ao: 0.42),
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
            material: SquishMaterial(k: 820, beta: 0.7, c: 7.5, quad: 0.6, vp: 1, smin: 0.45, smax: 1.9, grav: 9,
                                     fric: 0.55, rest: 0.22, press: 0.44, grabR: 0.20, halo: 0.35, land: 0.75, grip: 0.3,
                                     poke: 0.8, pokeR: 0.12, zk: 420, zd: 4.5, zc: 0.7, zland: 0.5, puff: 0.15,
                                     tk: 180, td: 5, look: 0.08, kd: 0.5, gloss: 0.55, shin: 26, ao: 0.3),
            loops: [
                SquishLoopRule("squelch_low", .change, gain: 0.17, cap: 0.22, blend: .shallow),
                SquishLoopRule("squelch_high", .change, gain: 0.17, cap: 0.22, blend: .deep),
                SquishLoopRule("hum", .speed, gain: 0.08, cap: 0.1),
            ],
            grains: [
                SquishGrainRule("bubble", .press, gain: 16, cap: 12, over: 0.05, volume: 0.03...0.08),
            ],
            landingBubbles: 3, popsOnRelease: false, hapticSharpness: 0.4, hapticGrainSet: nil, hapticDentPop: true),
        "gel": SquishFeelTuning(
            material: SquishMaterial(k: 300, beta: 0.8, c: 12, quad: 0.7, vp: 1, smin: 0.42, smax: 2.1, grav: 11,
                                     fric: 0.6, rest: 0.04, press: 0.5, grabR: 0.22, halo: 0.5, land: 1.0, grip: 0.35,
                                     poke: 1.15, pokeR: 0.16, zk: 90, zd: 8, zc: 0.45, zland: 0.8, puff: 0.25,
                                     tk: 50, td: 4, look: 0.09, kd: 0.5, gloss: 0.85, shin: 44, ao: 0.26),
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
                                     fric: 1, rest: 0, press: 0.46, grabR: 0.19, halo: 0.3, land: 0.65, grip: 0.9,
                                     poke: 0.95, pokeR: 0.13, zk: 250, zd: 16, zc: 0.3, zland: 0.2, puff: 0.3,
                                     tk: 80, td: 10, look: 0.07, kd: 0.6, gloss: 0.15, shin: 14, ao: 0.4),
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
