import Foundation

/// The Squishy Workshop's model and rules. No ads, analytics or coins in here: the same code is
/// used by Squish Sort and, later, by the standalone Squishy Workshop app. The host app passes in
/// a `WorkshopAccess` (what is open) and gets saved designs back.

/// How a part's name is written in file names and saves: lower case, anything else a dash.
public func workshopSlug(_ name: String) -> String {
    var out = ""
    for ch in name.lowercased() {
        if ch.isASCII, ch.isLetter || ch.isNumber { out.append(ch) } else if out.last != "-" { out.append("-") }
    }
    return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

public enum Goo: String, Codable, CaseIterable, Sendable {
    case jelly, foam, gel, mochi
    /// Foam and mochi are baked; jelly and gel are frozen.
    public var baked: Bool { self == .foam || self == .mochi }
}

/// One pour of goo: a colour and how it sits in the mould.
public struct GooLayer: Codable, Equatable, Sendable {
    /// RGB, 0xRRGGBB. Any mixed colour is allowed.
    public var colour: UInt32
    /// A pattern id from the catalogue ("plain", "stripes", "ombre", "marble", ...).
    public var pattern: String
    public var seed: Int

    public init(colour: UInt32, pattern: String = "plain", seed: Int = 0) {
        self.colour = colour & 0xFFFFFF
        self.pattern = pattern
        self.seed = seed
    }
}

/// A made squishy's saved designs, one file each (Application Support/made in the app). The
/// player's progress keeps only the ids and their order.
public protocol MadeStore {
    func load(id: String) -> WorkshopDesign?
    func save(_ design: WorkshopDesign, id: String)
    func delete(id: String)
}

/// A part or sticker put on the body.
public struct Placed: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// Category slug ("ears", "hats-and-headwear", ...).
    public var category: String
    /// Part slug inside the category.
    public var part: String
    /// Centre on the body, 0...1 across the picture.
    public var x: Double
    public var y: Double
    public var scale: Double
    /// Radians.
    public var angle: Double

    public init(id: String = UUID().uuidString, category: String, part: String, x: Double = 0.5, y: Double = 0.3,
                scale: Double = 1, angle: Double = 0) {
        self.id = id
        self.category = category
        self.part = part
        self.x = x
        self.y = y
        self.scale = min(Placed.maxScale, max(Placed.minScale, scale))
        self.angle = angle
    }

    public static let minScale = 0.5
    public static let maxScale = 1.6
}

public struct WorkshopFace: Codable, Equatable, Sendable {
    public var eyes: String
    public var mouth: String
    public var nose: String
    public var brows: String
    public var cheeks: String

    public init(eyes: String = "dots", mouth: String = "smile", nose: String = "none", brows: String = "none", cheeks: String = "none") {
        self.eyes = eyes
        self.mouth = mouth
        self.nose = nose
        self.brows = brows
        self.cheeks = cheeks
    }
}

public struct WorkshopPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Everything the Workshop adds to a made squishy. Every field has a default, so an older save
/// with fewer fields still opens.
public struct WorkshopDesign: Codable, Equatable, Sendable {
    public var mould: String
    /// Pro: a second mould snapped on top (a head on a body).
    public var mould2: String?
    public var goo: Goo
    /// Bottom layer first. At most `maxLayers`.
    public var layers: [GooLayer]
    /// Effect ids from the catalogue (Pro).
    public var fx: [String]
    public var face: WorkshopFace
    /// Pro: a face or an outline drawn with a finger. Points are 0...1 across the picture.
    public var drawnFace: [[WorkshopPoint]]?
    /// Pro: the body's own outline, drawn with a finger (the "draw-it" mould).
    public var drawnOutline: [WorkshopPoint]?
    public var parts: [Placed]
    public var stickers: [Placed]
    public var voice: String
    public var pitch: Double
    public var dance: String
    public var food: String?
    /// Seconds since 1970, printed on the birthday card.
    public var born: Double
    /// "game" or "workshop-app".
    public var source: String
    /// Schema number of the save.
    public var v: Int = 2

    public static let maxLayers = 3
    /// One from each of the eleven trays.
    public static let maxParts = 11
    public static let maxStickers = 8
    public static let maxStrokes = 12
    public static let maxStrokePoints = 64

    public init(mould: String = "bun", mould2: String? = nil, goo: Goo = .jelly, layers: [GooLayer] = [GooLayer(colour: 0xFF9EB5)],
                fx: [String] = [], face: WorkshopFace = WorkshopFace(), drawnFace: [[WorkshopPoint]]? = nil,
                drawnOutline: [WorkshopPoint]? = nil, parts: [Placed] = [], stickers: [Placed] = [], voice: String = "squeak",
                pitch: Double = 1, dance: String = "bouncer", food: String? = nil, born: Double = 0, source: String = "game") {
        self.mould = mould
        self.mould2 = mould2
        self.goo = goo
        self.layers = layers
        self.fx = fx
        self.face = face
        self.drawnFace = drawnFace
        self.drawnOutline = drawnOutline
        self.parts = parts
        self.stickers = stickers
        self.voice = voice
        self.pitch = pitch
        self.dance = dance
        self.food = food
        self.born = born
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WorkshopDesign()
        mould = (try? c.decodeIfPresent(String.self, forKey: .mould)) ?? d.mould
        mould2 = (try? c.decodeIfPresent(String.self, forKey: .mould2)) ?? nil
        goo = (try? c.decodeIfPresent(Goo.self, forKey: .goo)) ?? d.goo
        layers = (try? c.decodeIfPresent([GooLayer].self, forKey: .layers)) ?? d.layers
        fx = (try? c.decodeIfPresent([String].self, forKey: .fx)) ?? []
        face = (try? c.decodeIfPresent(WorkshopFace.self, forKey: .face)) ?? d.face
        drawnFace = (try? c.decodeIfPresent([[WorkshopPoint]].self, forKey: .drawnFace)) ?? nil
        drawnOutline = (try? c.decodeIfPresent([WorkshopPoint].self, forKey: .drawnOutline)) ?? nil
        parts = (try? c.decodeIfPresent([Placed].self, forKey: .parts)) ?? []
        stickers = (try? c.decodeIfPresent([Placed].self, forKey: .stickers)) ?? []
        voice = (try? c.decodeIfPresent(String.self, forKey: .voice)) ?? d.voice
        pitch = (try? c.decodeIfPresent(Double.self, forKey: .pitch)) ?? 1
        dance = (try? c.decodeIfPresent(String.self, forKey: .dance)) ?? d.dance
        food = (try? c.decodeIfPresent(String.self, forKey: .food)) ?? nil
        born = (try? c.decodeIfPresent(Double.self, forKey: .born)) ?? 0
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "game"
        v = max(2, (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? 2)
        tidy()
    }

    /// Keeps every list inside its limit and every number inside its range.
    public mutating func tidy() {
        if layers.isEmpty { layers = [GooLayer(colour: 0xFF9EB5)] }
        layers = Array(layers.prefix(WorkshopDesign.maxLayers))
        // One wearable from each tray: a newer one takes the place of the one before it.
        var seen = Set<String>()
        parts = Array(parts.reversed().filter { seen.insert($0.category).inserted }.reversed())
        stickers = Array(stickers.prefix(WorkshopDesign.maxStickers))
        parts = parts.map(WorkshopDesign.clamped)
        stickers = stickers.map(WorkshopDesign.clamped)
        pitch = min(1.25, max(0.8, pitch))
        if let strokes = drawnFace {
            drawnFace = strokes.prefix(WorkshopDesign.maxStrokes).map { Array($0.prefix(WorkshopDesign.maxStrokePoints)) }
        }
    }

    /// A part's centre stays on the body box grown by a fifth, and its size inside its range.
    public static func clamped(_ p: Placed) -> Placed {
        var q = p
        let lo = 0.5 - bodyShare / 2 * 1.2, hi = 0.5 + bodyShare / 2 * 1.2
        q.x = min(hi, max(lo, p.x))
        q.y = min(hi, max(lo, p.y))
        q.scale = min(Placed.maxScale, max(Placed.minScale, p.scale))
        return q
    }

    /// The body fills the middle of the picture; the rest is room for ears, hats and wings.
    public static let bodyShare = 0.64

    /// The colour the body mostly is: its top layer.
    public var mainColour: UInt32 { layers.last?.colour ?? 0xFF9EB5 }
}
