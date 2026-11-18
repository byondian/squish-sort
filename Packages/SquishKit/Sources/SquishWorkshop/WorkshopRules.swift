import Foundation

/// What the host app lets this player use.
public struct WorkshopAccess: Equatable, Sendable {
    /// Workshop Pro (in Squish Sort: comes with Remove Ads).
    public var pro: Bool
    /// Story worlds finished: more of the free parts open with each one.
    public var worlds: Int
    /// Single wearables bought with coins, as "category/part".
    public var owned: Set<String>

    public init(pro: Bool, worlds: Int = 99, owned: Set<String> = []) {
        self.pro = pro
        self.worlds = max(0, worlds)
        self.owned = owned
    }
}

/// The parts list (Content/workshop-parts.json).
public struct WorkshopCatalog: Sendable {
    public var moulds: [String]
    public var eyes: [String]
    public var brows: [String]
    public var noses: [String]
    public var mouths: [String]
    public var cheeks: [String]
    public var colours: [UInt32]
    public var patterns: [String]
    public var effects: [String]
    /// Category slug to part slugs, in the order of the file. Voices and dances are kept apart.
    public var parts: [(category: String, title: String, items: [String])]
    public var voices: [String]
    public var dances: [String]

    public static let voiceIDs = ["squeak", "honk", "purr", "boing", "giggle", "chirp", "moo", "tiny-roar", "beep-boop", "yodel"]
    public static let stickerCategory = "stickers-and-patterns"

    private struct File: Decodable {
        var moulds, eyes, brows, noses, mouths, cheeks, colours, patterns, effects: [String]
        var features_and_accessories: [String: [String]]
    }

    /// The order the trays are shown in.
    public static let categoryOrder = ["Ears", "Horns and antlers", "Wings", "Tails", "Antennae and hair", "Hats and headwear",
                                       "Glasses and face wear", "Neck and body", "Held items", "Arms and feet", "Stickers and patterns"]

    public init(json: Data) throws {
        let f = try JSONDecoder().decode(File.self, from: json)
        moulds = f.moulds.map(workshopSlug)
        eyes = f.eyes.map(workshopSlug)
        brows = f.brows.map(workshopSlug)
        noses = f.noses.map(workshopSlug)
        mouths = f.mouths.map(workshopSlug)
        cheeks = f.cheeks.map(workshopSlug)
        colours = f.colours.compactMap { UInt32($0.replacingOccurrences(of: "#", with: ""), radix: 16) }
        patterns = f.patterns.map(workshopSlug)
        effects = f.effects.map(workshopSlug)
        parts = WorkshopCatalog.categoryOrder.compactMap { title in
            guard let items = f.features_and_accessories[title] else { return nil }
            return (workshopSlug(title), title, items.map(workshopSlug))
        }
        let sound = (f.features_and_accessories["Voices and dances"] ?? []).map(workshopSlug)
        voices = sound.filter { WorkshopCatalog.voiceIDs.contains($0) }
        dances = sound.filter { !WorkshopCatalog.voiceIDs.contains($0) }
    }

    public func items(in category: String) -> [String] { parts.first { $0.category == category }?.items ?? [] }
}

/// Free against Pro (workshop-spec.md section 6). Free parts are fixed lists, so a save can be
/// checked without the catalogue file.
public enum WorkshopGate {
    public static let freeMoulds = ["bun", "egg", "bean", "drop", "dome", "cloud"]
    public static let freeEyes = ["dots", "big-shine", "sparkle", "happy", "sleepy", "wink"]
    public static let freeMouths = ["smile", "big-smile", "cat-w", "open-o", "tongue", "fangs"]
    public static let freeNoses = ["none", "dot", "button", "triangle-cat"]
    public static let freeBrows = ["none", "soft", "straight"]
    public static let freeCheeks = ["none", "blush", "freckles"]
    public static let freePatterns = ["plain", "stripes"]
    /// Free players get ears and horns; the first few of each.
    public static let freeParts: [String: [String]] = [
        "ears": ["cat", "bear", "bunny", "mouse"],
        "horns-and-antlers": ["little-horns", "devil"],
    ]
    public static let freeVoices = WorkshopCatalog.voiceIDs
    public static let freeDances = ["bouncer", "wiggler"]
    public static let freeLayers = 2
    /// The 12 palette colours the Maker always had come first in the catalogue.
    public static let freeColourCount = 12
    /// Shelf places: three free, more for coins up to eight, fifty with Pro.
    public static let freeSlots = 3
    public static let coinSlots = 8
    public static let proSlots = 50
    /// Won, never bought, by everyone: the crown after three worlds, the unicorn horn after four.
    public static let winOnly: [String: Int] = ["hats-and-headwear/crown": 3, "horns-and-antlers/unicorn": 4]

    /// How many of a free list are open: two to start, one more with each world finished.
    static func open(_ total: Int, _ a: WorkshopAccess, base: Int = 2, perWorld: Int = 1) -> Int {
        min(total, base + a.worlds * perWorld)
    }

    private static func listed(_ id: String, _ list: [String], _ a: WorkshopAccess) -> Bool {
        if a.pro { return true }
        guard let i = list.firstIndex(of: id) else { return false }
        return i < open(list.count, a)
    }

    public static func mouldOpen(_ id: String, _ a: WorkshopAccess) -> Bool { listed(id, freeMoulds, a) }
    public static func eyesOpen(_ id: String, _ a: WorkshopAccess) -> Bool { listed(id, freeEyes, a) }
    public static func mouthOpen(_ id: String, _ a: WorkshopAccess) -> Bool { listed(id, freeMouths, a) }
    public static func noseOpen(_ id: String, _ a: WorkshopAccess) -> Bool { listed(id, freeNoses, a) }
    public static func browsOpen(_ id: String, _ a: WorkshopAccess) -> Bool { listed(id, freeBrows, a) }
    public static func cheeksOpen(_ id: String, _ a: WorkshopAccess) -> Bool { listed(id, freeCheeks, a) }
    public static func patternOpen(_ id: String, _ a: WorkshopAccess) -> Bool { a.pro || freePatterns.contains(id) }
    public static func danceOpen(_ id: String, _ a: WorkshopAccess) -> Bool { a.pro || freeDances.contains(id) }

    public static func partOpen(category: String, part: String, _ a: WorkshopAccess) -> Bool {
        let key = category + "/" + part
        if let worlds = winOnly[key] { return a.worlds >= worlds }
        if a.pro || a.owned.contains(key) { return true }
        guard let list = freeParts[category], let i = list.firstIndex(of: part) else { return false }
        return i < open(list.count, a)
    }

    /// What one wearable costs a free player in coins. Nil when it is not sold (won only, or open already).
    public static func coinPrice(category: String, part: String, _ a: WorkshopAccess) -> Int? {
        guard !partOpen(category: category, part: part, a), winOnly[category + "/" + part] == nil else { return nil }
        switch category {
        case "wings": return 800
        case "hats-and-headwear", "antennae-and-hair", "tails", "arms-and-feet", "held-items": return 500
        default: return 300
        }
    }

    public static func colourOpen(_ colour: UInt32, palette: [UInt32], _ a: WorkshopAccess) -> Bool {
        if a.pro { return true }
        guard let i = palette.firstIndex(of: colour & 0xFFFFFF) else { return false }
        return i < open(min(freeColourCount, palette.count), a, base: 5, perWorld: 2)
    }

    public static func slots(bought: Int, _ a: WorkshopAccess) -> Int {
        a.pro ? proSlots : min(coinSlots, max(freeSlots, bought))
    }

    /// True when a free player could have made every bit of this design. Used on save: a design
    /// with a Pro part is never saved by a player without Pro.
    public static func allowed(_ d: WorkshopDesign, palette: [UInt32], _ a: WorkshopAccess) -> Bool {
        if a.pro { return true }
        guard mouldOpen(d.mould, a), d.mould2 == nil, d.fx.isEmpty, d.drawnFace == nil, d.drawnOutline == nil else { return false }
        guard d.layers.count <= freeLayers,
              d.layers.allSatisfy({ freePatterns.contains($0.pattern) && colourOpen($0.colour, palette: palette, a) }) else { return false }
        guard eyesOpen(d.face.eyes, a), mouthOpen(d.face.mouth, a), noseOpen(d.face.nose, a),
              browsOpen(d.face.brows, a), cheeksOpen(d.face.cheeks, a) else { return false }
        guard (d.parts + d.stickers).allSatisfy({ partOpen(category: $0.category, part: $0.part, a) }) else { return false }
        return freeVoices.contains(d.voice) && freeDances.contains(d.dance)
    }

    /// A look made with Pro stays when Pro is lost (a refund), but it can only be changed with
    /// free tools: editing starts from this free copy of it.
    public static func freeCopy(of d: WorkshopDesign, palette: [UInt32], _ a: WorkshopAccess) -> WorkshopDesign {
        var out = d
        if !mouldOpen(out.mould, a) { out.mould = freeMoulds[0] }
        out.mould2 = nil
        out.fx = []
        out.drawnFace = nil
        out.drawnOutline = nil
        out.layers = out.layers.prefix(freeLayers).map { layer in
            var l = layer
            if !freePatterns.contains(l.pattern) { l.pattern = "plain" }
            if !colourOpen(l.colour, palette: palette, a) { l.colour = palette.first ?? 0xFF9EB5 }
            return l
        }
        if !eyesOpen(out.face.eyes, a) { out.face.eyes = freeEyes[0] }
        if !mouthOpen(out.face.mouth, a) { out.face.mouth = freeMouths[0] }
        if !noseOpen(out.face.nose, a) { out.face.nose = "none" }
        if !browsOpen(out.face.brows, a) { out.face.brows = "none" }
        if !cheeksOpen(out.face.cheeks, a) { out.face.cheeks = "none" }
        out.stickers = out.stickers.filter { partOpen(category: $0.category, part: $0.part, a) }
        out.parts = out.parts.filter { partOpen(category: $0.category, part: $0.part, a) }
        if !freeDances.contains(out.dance) { out.dance = freeDances[0] }
        out.tidy()
        return out
    }
}

/// Goo mixes like paint: blue and yellow make green. A line-for-line port of the design side's
/// reference (content/workshop-colour-mix.py); its printed table is the test table.
/// Hue is mixed on the painter's wheel (red, yellow, blue), lightness is averaged, and hue and
/// saturation are weighted by how much colour is really there, so white, grey and near-black only tint.
public enum GooMix {
    /// RGB hue to painter's-wheel hue: red 0 to 0, orange 30 to 60, yellow 60 to 120, green 120 to 180,
    /// blue 240 to 240, purple 280 to 300.
    private static let wheel: [(Double, Double)] = [(0, 0), (30, 60), (60, 120), (120, 180), (240, 240), (280, 300), (360, 360)]

    private static func mod(_ a: Double, _ n: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: n)
        return r < 0 ? r + n : r
    }

    private static func map(_ hue: Double, _ pts: [(Double, Double)]) -> Double {
        let h = mod(hue, 360)
        for k in 0..<(pts.count - 1) {
            let (a, b) = pts[k], (c, d) = pts[k + 1]
            if a <= h, h <= c { return b + (h - a) / (c - a) * (d - b) }
        }
        return h
    }

    private static func toWheel(_ h: Double) -> Double { map(h, wheel) }
    private static func fromWheel(_ h: Double) -> Double { map(h, wheel.map { ($0.1, $0.0) }) }

    /// Hue in degrees, lightness and saturation 0...1 (Python's colorsys.rgb_to_hls).
    static func hls(_ c: UInt32) -> (h: Double, l: Double, s: Double) {
        let v = rgb(c)
        let r = v[0], g = v[1], b = v[2]
        let maxc = max(r, g, b), minc = min(r, g, b)
        let sumc = maxc + minc, rangec = maxc - minc
        let l = sumc / 2
        if minc == maxc { return (0, l, 0) }
        let s = l <= 0.5 ? rangec / sumc : rangec / (2 - maxc - minc)
        let rc = (maxc - r) / rangec, gc = (maxc - g) / rangec, bc = (maxc - b) / rangec
        let h: Double
        if r == maxc { h = bc - gc } else if g == maxc { h = 2 + rc - bc } else { h = 4 + gc - rc }
        return (mod(h / 6, 1) * 360, l, s)
    }

    /// Python's colorsys.hls_to_rgb, with the hue in degrees.
    static func fromHLS(h: Double, l: Double, s: Double) -> [Double] {
        if s == 0 { return [l, l, l] }
        let m2 = l <= 0.5 ? l * (1 + s) : l + s - l * s
        let m1 = 2 * l - m2
        func v(_ raw: Double) -> Double {
            let hue = mod(raw, 1)
            if hue < 1.0 / 6 { return m1 + (m2 - m1) * hue * 6 }
            if hue < 0.5 { return m2 }
            if hue < 2.0 / 3 { return m1 + (m2 - m1) * (2.0 / 3 - hue) * 6 }
            return m1
        }
        let hue = h / 360
        return [v(hue + 1.0 / 3), v(hue), v(hue - 1.0 / 3)]
    }

    /// `share` is how much of the mix is `b`: 0.5 for equal pours.
    public static func mix(_ a: UInt32, _ b: UInt32, share: Double = 0.5) -> UInt32 {
        let t = min(1, max(0, share))
        // The reference takes two amounts; equal pours are 1 and 1.
        let wa = 2 * (1 - t), wb = 2 * t
        let (h1, l1, s1) = hls(a), (h2, l2, s2) = hls(b)
        // Chroma: white, grey and near-black barely pull the hue.
        let c1 = s1 * (1 - abs(2 * l1 - 1)) * wa + 1e-4
        let c2 = s2 * (1 - abs(2 * l2 - 1)) * wb + 1e-4
        let tc = c2 / (c1 + c2)
        let p1 = toWheel(h1), p2 = toWheel(h2)
        var d = mod(p2 - p1 + 180, 360) - 180
        let h = fromWheel(mod(p1 + d * tc, 360))
        let l = l1 + (l2 - l1) * t
        var s = s1 + (s2 - s1) * tc
        d *= min(tc, 1 - tc) * 2
        // Opposite hues make mud, like paint: saturation drops as the hues get further apart.
        s *= 1 - 0.6 * pow(abs(d) / 180, 2)
        return hex(fromHLS(h: h, l: l, s: s))
    }

    public static func rgb(_ c: UInt32) -> [Double] {
        [Double((c >> 16) & 0xFF) / 255, Double((c >> 8) & 0xFF) / 255, Double(c & 0xFF) / 255]
    }

    public static func hex(_ v: [Double]) -> UInt32 {
        let r = UInt32((min(1, max(0, v[0])) * 255).rounded())
        let g = UInt32((min(1, max(0, v[1])) * 255).rounded())
        let b = UInt32((min(1, max(0, v[2])) * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}

/// The four stats on a made squishy's birthday card, each 1...10, from what it is made of.
public struct WorkshopStats: Equatable, Sendable {
    public var squish: Int
    public var bounce: Int
    public var stretch: Int
    public var charm: Int
    public var total: Int { squish + bounce + stretch + charm }

    /// A rare collectible's stats add up to more than this, so a made squishy never outclasses one.
    public static let cap = 24

    public init(_ d: WorkshopDesign) {
        var s: Int, b: Int, t: Int
        switch d.goo {
        case .jelly: (s, b, t) = (5, 8, 4)
        case .foam: (s, b, t) = (8, 4, 4)
        case .gel: (s, b, t) = (5, 4, 8)
        case .mochi: (s, b, t) = (7, 3, 7)
        }
        // Big, long moulds stretch further.
        if ["long-cat", "bean", "pear", "dino", "fish", "moon"].contains(d.mould) { t += 1 }
        if d.mould2 != nil { t += 1 }
        var c = 2 + min(6, d.parts.count) + (d.stickers.isEmpty ? 0 : 1) + (d.fx.isEmpty ? 0 : 1)
        s = min(10, s); b = min(10, b); t = min(10, t); c = min(10, c)
        // Over the cap: charm gives way first, then the rest in turn.
        var over = s + b + t + c - WorkshopStats.cap
        while over > 0 {
            if c > 1 { c -= 1 } else if t > 1 { t -= 1 } else if b > 1 { b -= 1 } else if s > 1 { s -= 1 } else { break }
            over -= 1
        }
        squish = s; bounce = b; stretch = t; charm = c
    }
}

/// Two squishies in, one new made design out. The originals are never changed.
public enum SquishyMixer {
    /// What a squishy lends to the mix. A collectible only lends a look (a colour): it has no
    /// design, and the result is always a made design, never a collectible.
    public enum Ingredient: Equatable, Sendable {
        case made(WorkshopDesign)
        case collectible(colour: UInt32)
    }

    /// Mould and face from the first, colours from the second, up to two parts from each.
    public static func mix(_ first: Ingredient, _ second: Ingredient, seed: Int) -> WorkshopDesign {
        var out = WorkshopDesign()
        if case .made(let a) = first {
            out.mould = a.mould
            out.mould2 = a.mould2
            out.drawnOutline = a.drawnOutline
            out.goo = a.goo
            out.face = a.face
            out.drawnFace = a.drawnFace
            out.parts = Array(a.parts.prefix(2))
            out.voice = a.voice
        }
        switch second {
        case .made(let b):
            out.layers = b.layers
            out.fx = b.fx
            out.parts += b.parts.prefix(2).map { p in
                var q = p
                q.id = UUID().uuidString
                return q
            }
            out.stickers = b.stickers
            out.dance = b.dance
        case .collectible(let colour):
            out.layers = [GooLayer(colour: colour, seed: seed)]
        }
        if case .collectible(let colour) = first, case .made = second {
            // A collectible dropped in first tints the top of the other's colours.
            out.layers = Array(out.layers.prefix(WorkshopDesign.maxLayers - 1)) + [GooLayer(colour: colour, pattern: "ombre", seed: seed)]
        }
        out.source = "game"
        out.tidy()
        return out
    }
}

/// Two reels of syllables that stop on a name (Content/name-wheel.json).
public struct NameWheel: Sendable {
    public var first: [String]
    public var second: [String]

    private struct File: Decodable {
        struct Reels: Decodable {
            var first: [String]
            var second: [String]
        }
        var reels: [String: Reels]
    }

    /// `language` is "en", "ja", "ko" or "zh-Hant"; anything else gets English.
    public init(json: Data, language: String) throws {
        let f = try JSONDecoder().decode(File.self, from: json)
        let reels = f.reels[language] ?? f.reels["en"] ?? File.Reels(first: ["Blop"], second: ["po"])
        first = reels.first
        second = reels.second
    }

    public func name(_ a: Int, _ b: Int) -> String {
        guard !first.isEmpty, !second.isEmpty else { return "" }
        return first[((a % first.count) + first.count) % first.count] + second[((b % second.count) + second.count) % second.count]
    }

    /// A spin: a name the host's filter accepts. It spins on past any it refuses.
    public func spin<R: RandomNumberGenerator>(using rng: inout R, accepts: (String) -> Bool) -> String {
        for _ in 0..<40 {
            let n = name(Int(rng.next() % 4096), Int(rng.next() % 4096))
            if !n.isEmpty, accepts(n) { return n }
        }
        return name(0, 0)
    }
}

/// "Surprise me": a random design from the parts this player has open.
public enum WorkshopSurprise {
    public static func make<R: RandomNumberGenerator>(catalog: WorkshopCatalog, access a: WorkshopAccess, using rng: inout R) -> WorkshopDesign {
        func pick(_ list: [String], fallback: String) -> String {
            list.isEmpty ? fallback : list[Int(rng.next() % UInt64(list.count))]
        }
        var d = WorkshopDesign()
        d.mould = pick(catalog.moulds.filter { $0 != "draw-it" && WorkshopGate.mouldOpen($0, a) }, fallback: "bun")
        d.goo = Goo.allCases[Int(rng.next() % UInt64(Goo.allCases.count))]
        let colours = catalog.colours.filter { WorkshopGate.colourOpen($0, palette: catalog.colours, a) }
        let patterns = a.pro ? catalog.patterns : WorkshopGate.freePatterns
        let count = 1 + Int(rng.next() % 2)
        d.layers = (0..<count).map { i in
            GooLayer(colour: colours.isEmpty ? 0xFF9EB5 : colours[Int(rng.next() % UInt64(colours.count))],
                     pattern: i == 0 ? "plain" : pick(patterns, fallback: "plain"), seed: Int(rng.next() % 1000))
        }
        d.face.eyes = pick(catalog.eyes.filter { WorkshopGate.eyesOpen($0, a) }, fallback: "dots")
        d.face.mouth = pick(catalog.mouths.filter { WorkshopGate.mouthOpen($0, a) }, fallback: "smile")
        d.face.cheeks = pick(catalog.cheeks.filter { WorkshopGate.cheeksOpen($0, a) }, fallback: "none")
        // One part on top of the head, from a tray this player has open.
        let trays = ["ears", "horns-and-antlers"].flatMap { cat in
            catalog.items(in: cat).filter { WorkshopGate.partOpen(category: cat, part: $0, a) }.map { (cat, $0) }
        }
        if !trays.isEmpty {
            let (cat, part) = trays[Int(rng.next() % UInt64(trays.count))]
            d.parts = [Placed(category: cat, part: part, x: 0.5, y: 0.24)]
        }
        d.voice = pick(catalog.voices.filter { a.pro || WorkshopGate.freeVoices.contains($0) }, fallback: "squeak")
        d.dance = pick(a.pro ? catalog.dances : WorkshopGate.freeDances, fallback: "bouncer")
        d.pitch = 0.8 + Double(rng.next() % 46) / 100
        d.tidy()
        return d
    }
}

/// A finger-drawn outline, made fit to be a mould.
public enum DrawnShape {
    /// Closes the line, smooths it and spreads the points evenly. Nil when it is not a shape
    /// (too few points, or too small to squish).
    public static func mould(from raw: [WorkshopPoint], points count: Int = 64) -> [WorkshopPoint]? {
        guard raw.count >= 8 else { return nil }
        var pts = raw
        // Smooth twice: each point moves to the middle of its neighbours.
        for _ in 0..<2 {
            var next = pts
            for i in pts.indices {
                let a = pts[(i + pts.count - 1) % pts.count], b = pts[(i + 1) % pts.count]
                next[i] = WorkshopPoint(x: (a.x + 2 * pts[i].x + b.x) / 4, y: (a.y + 2 * pts[i].y + b.y) / 4)
            }
            pts = next
        }
        // Walk the closed line and drop a point every equal step.
        var lengths: [Double] = []
        var total = 0.0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let len = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
            lengths.append(len)
            total += len
        }
        guard total > 0.6 else { return nil }
        var out: [WorkshopPoint] = []
        var seg = 0, walked = 0.0
        for k in 0..<count {
            let target = total * Double(k) / Double(count)
            while seg < lengths.count - 1, walked + lengths[seg] < target {
                walked += lengths[seg]
                seg += 1
            }
            let a = pts[seg], b = pts[(seg + 1) % pts.count]
            let t = lengths[seg] > 0 ? (target - walked) / lengths[seg] : 0
            out.append(WorkshopPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        // Too thin to squish: grow it about its middle until it is at least a quarter of the pad wide and tall.
        let xs = out.map(\.x), ys = out.map(\.y)
        let w = (xs.max() ?? 0) - (xs.min() ?? 0), h = (ys.max() ?? 0) - (ys.min() ?? 0)
        guard w > 0.02, h > 0.02 else { return nil }
        let cx = ((xs.max() ?? 0) + (xs.min() ?? 0)) / 2, cy = ((ys.max() ?? 0) + (ys.min() ?? 0)) / 2
        let kx = max(1, 0.25 / w), ky = max(1, 0.25 / h)
        return out.map { WorkshopPoint(x: min(1, max(0, cx + ($0.x - cx) * kx)), y: min(1, max(0, cy + ($0.y - cy) * ky))) }
    }
}
