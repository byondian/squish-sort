import Foundation
import XCTest
import SquishPolicy
@testable import SquishWorkshop

/// Repo root, found from this file's path (Packages/SquishKit/Tests/SquishWorkshopTests/).
private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

final class WorkshopTests: XCTestCase {
    func catalog() throws -> WorkshopCatalog {
        try WorkshopCatalog(json: Data(contentsOf: root.appendingPathComponent("Content/workshop-parts.json")))
    }

    func testCatalogueHasEveryTrayAndEveryPartHasItsPicture() throws {
        let c = try catalog()
        XCTAssertEqual(c.moulds.count, 24)
        XCTAssertEqual(c.colours.count, 36)
        XCTAssertEqual(c.eyes.count + c.mouths.count + c.noses.count + c.brows.count + c.cheeks.count, 88)
        XCTAssertEqual(c.parts.count, 11)
        XCTAssertEqual(c.voices.count, 10)
        XCTAssertEqual(c.dances.count, 6)
        let art = root.appendingPathComponent("Content/workshop")
        func has(_ name: String) -> Bool { FileManager.default.fileExists(atPath: art.appendingPathComponent(name + ".png").path) }
        for m in c.moulds where m != "draw-it" { XCTAssertTrue(has("mould-\(m)"), m) }
        for (kind, list) in [("eyes", c.eyes), ("mouths", c.mouths), ("noses", c.noses), ("brows", c.brows), ("cheeks", c.cheeks)] {
            for item in list where item != "none" { XCTAssertTrue(has("face-\(kind)-\(item)"), "\(kind) \(item)") }
        }
        for tray in c.parts {
            for item in tray.items { XCTAssertTrue(has("part-\(tray.category)-\(item)"), "\(tray.category) \(item)") }
        }
        // Every free part is a real part.
        for m in WorkshopGate.freeMoulds { XCTAssertTrue(c.moulds.contains(m), m) }
        for e in WorkshopGate.freeEyes { XCTAssertTrue(c.eyes.contains(e), e) }
        for e in WorkshopGate.freeMouths { XCTAssertTrue(c.mouths.contains(e), e) }
        for e in WorkshopGate.freeNoses { XCTAssertTrue(c.noses.contains(e), e) }
        for e in WorkshopGate.freeBrows { XCTAssertTrue(c.brows.contains(e), e) }
        for e in WorkshopGate.freeCheeks { XCTAssertTrue(c.cheeks.contains(e), e) }
        for e in WorkshopGate.freePatterns { XCTAssertTrue(c.patterns.contains(e), e) }
        for e in WorkshopGate.freeDances { XCTAssertTrue(c.dances.contains(e), e) }
        for (cat, items) in WorkshopGate.freeParts { for i in items { XCTAssertTrue(c.items(in: cat).contains(i), "\(cat) \(i)") } }
        // The Maker's twelve colours come first, in the Maker's order.
        XCTAssertEqual(Array(c.colours.prefix(12)), MakerParts.palette)
    }

    func testAnOldMakerSaveOpensUnchanged() throws {
        let old = #"{"id":"a1","name":"Bobo","shape":"egg","color":3,"eyes":"wink","mouth":"cat","ears":"bunny","accessory":"bow"}"#
        let made = try JSONDecoder().decode(MadeSquishy.self, from: Data(old.utf8))
        XCTAssertEqual(made, MadeSquishy(id: "a1", name: "Bobo", shape: .egg, color: 3, eyes: .wink, mouth: .cat, ears: .bunny, accessory: .bow))
        XCTAssertNil(made.design)
        let d = made.workshopDesign
        XCTAssertEqual(d.mould, "egg")
        XCTAssertEqual(d.layers, [GooLayer(colour: MakerParts.palette[3])])
        XCTAssertEqual(d.face.eyes, "wink")
        XCTAssertEqual(d.face.mouth, "cat-w")
        XCTAssertEqual(d.parts.map(\.part), ["bunny", "bow-headband"])
        // And a design with fields missing takes the defaults.
        let thin = try JSONDecoder().decode(WorkshopDesign.self, from: Data(#"{"mould":"bear"}"#.utf8))
        XCTAssertEqual(thin.mould, "bear")
        XCTAssertEqual(thin.goo, .jelly)
        XCTAssertEqual(thin.layers.count, 1)
        // A design goes round on its own, unknown part ids and all; the progress save leaves it out.
        var design = thin
        design.parts = [Placed(id: "p", category: "wings", part: "a-part-from-a-newer-build")]
        design.tidy()
        XCTAssertEqual(try JSONDecoder().decode(WorkshopDesign.self, from: JSONEncoder().encode(design)), design)
        XCTAssertEqual(design.v, 2)
        let full = MadeSquishy(id: "b2", name: "Mimi", design: design)
        let back = try JSONDecoder().decode(MadeSquishy.self, from: JSONEncoder().encode(full))
        XCTAssertNil(back.design)
        XCTAssertEqual(back.name, "Mimi")
        // One wearable from each tray, and a part never leaves the body's reach.
        var crowded = WorkshopDesign()
        crowded.parts = [Placed(id: "1", category: "ears", part: "cat"), Placed(id: "2", category: "ears", part: "bear", x: 5, y: -3, scale: 9),
                         Placed(id: "3", category: "wings", part: "bee")]
        crowded.tidy()
        XCTAssertEqual(crowded.parts.map(\.id), ["2", "3"])
        XCTAssertTrue((0...1).contains(crowded.parts[0].x) && (0...1).contains(crowded.parts[0].y))
        XCTAssertEqual(crowded.parts[0].scale, Placed.maxScale)
    }

    func testColourMixingMatchesTheReferenceTable() {
        // content/workshop-colour-mix.py prints this table. One step of rounding either way is allowed.
        let table: [(UInt32, UInt32, UInt32)] = [
            (0x7CC8FF, 0xFFD86B, 0xB7EA88), // blue + yellow = green
            (0x4A9FE8, 0xFFD86B, 0x98DC72), // strong blue + yellow = green
            (0xFF5A6E, 0xFFFFFF, 0xFFADB7), // red + white = pink
            (0xFF5A6E, 0x4A9FE8, 0xAA6ADC), // red + blue = purple
            (0xFF5A6E, 0xFFD86B, 0xF4996E), // red + yellow = orange
            (0xFF9EB5, 0x7CC8FF, 0xBE99F3), // pink + blue = lilac
            (0xFFD86B, 0x2E2E3A, 0xE0BC09), // yellow + dark = olive
            (0xFFFFFF, 0x2E2E3A, 0x8E8EA5), // white + dark = grey
            (0xFFA25C, 0x7FE0C4, 0xE3D87A), // orange + mint = muddy yellow-green
            (0x9ED67F, 0xFF5A6E, 0xE0A477), // green + red = brown
        ]
        func close(_ x: UInt32, _ y: UInt32) -> Bool {
            let a = GooMix.rgb(x), b = GooMix.rgb(y)
            return zip(a, b).allSatisfy { abs($0 - $1) <= 1.01 / 255 }
        }
        for (a, b, want) in table {
            let got = GooMix.mix(a, b)
            XCTAssertTrue(close(got, want), String(format: "%06X + %06X = %06X, want %06X", a, b, got, want))
        }
        // A colour mixed with itself stays itself.
        XCTAssertTrue(close(GooMix.mix(0x7FE0C4, 0x7FE0C4), 0x7FE0C4))
    }

    func testAFreeSaveNeverHoldsAProPart() throws {
        let c = try catalog()
        let free = WorkshopAccess(pro: false)
        let pro = WorkshopAccess(pro: true)
        XCTAssertTrue(WorkshopGate.allowed(WorkshopDesign(), palette: c.colours, free))
        var cases: [WorkshopDesign] = []
        var d = WorkshopDesign(); d.mould = "bear"; cases.append(d)
        d = WorkshopDesign(); d.mould2 = "bun"; cases.append(d)
        d = WorkshopDesign(); d.fx = ["glitter"]; cases.append(d)
        d = WorkshopDesign(); d.layers = [GooLayer(colour: 0xFF9EB5, pattern: "marble")]; cases.append(d)
        d = WorkshopDesign(); d.layers = [GooLayer(colour: 0x123456)]; cases.append(d)
        d = WorkshopDesign(); d.layers = Array(repeating: GooLayer(colour: 0xFF9EB5), count: 3); cases.append(d)
        d = WorkshopDesign(); d.face.eyes = "anime"; cases.append(d)
        d = WorkshopDesign(); d.parts = [Placed(category: "wings", part: "angel")]; cases.append(d)
        d = WorkshopDesign(); d.stickers = [Placed(category: "stickers-and-patterns", part: "star")]; cases.append(d)
        d = WorkshopDesign(); d.parts = [Placed(category: "ears", part: "dragon-fin")]; cases.append(d)
        d = WorkshopDesign(); d.drawnFace = [[WorkshopPoint(x: 0, y: 0)]]; cases.append(d)
        d = WorkshopDesign(); d.dance = "spinner"; cases.append(d)
        for design in cases {
            XCTAssertFalse(WorkshopGate.allowed(design, palette: c.colours, free), "\(design)")
            XCTAssertTrue(WorkshopGate.allowed(design, palette: c.colours, pro))
            // With Pro gone the look can still be edited, from a copy that is free all through.
            XCTAssertTrue(WorkshopGate.allowed(WorkshopGate.freeCopy(of: design, palette: c.colours, free), palette: c.colours, free))
        }
        // Free parts open with the worlds finished, as the Maker's did: two to start, one more each world.
        let start = WorkshopAccess(pro: false, worlds: 0)
        XCTAssertTrue(WorkshopGate.mouldOpen("egg", start))
        XCTAssertFalse(WorkshopGate.mouldOpen("cloud", start))
        XCTAssertTrue(WorkshopGate.mouldOpen("cloud", WorkshopAccess(pro: false, worlds: 4)))
        XCTAssertTrue(WorkshopGate.allowed(WorkshopDesign(), palette: c.colours, start))
        // One wearable bought with coins is open; a Pro owner is never asked for coins; the crown is won, never sold.
        XCTAssertEqual(WorkshopGate.coinPrice(category: "wings", part: "angel", free), 800)
        XCTAssertEqual(WorkshopGate.coinPrice(category: "hats-and-headwear", part: "party-hat", free), 500)
        XCTAssertEqual(WorkshopGate.coinPrice(category: "glasses-and-face-wear", part: "round", free), 300)
        XCTAssertNil(WorkshopGate.coinPrice(category: "wings", part: "angel", pro))
        let bought = WorkshopAccess(pro: false, owned: ["wings/angel"])
        XCTAssertTrue(WorkshopGate.partOpen(category: "wings", part: "angel", bought))
        XCTAssertNil(WorkshopGate.coinPrice(category: "wings", part: "angel", bought))
        XCTAssertNil(WorkshopGate.coinPrice(category: "hats-and-headwear", part: "crown", start))
        XCTAssertFalse(WorkshopGate.partOpen(category: "hats-and-headwear", part: "crown", WorkshopAccess(pro: true, worlds: 2)))
        XCTAssertTrue(WorkshopGate.partOpen(category: "hats-and-headwear", part: "crown", WorkshopAccess(pro: false, worlds: 3)))
        XCTAssertEqual(WorkshopGate.slots(bought: 1, free), 3)
        XCTAssertEqual(WorkshopGate.slots(bought: 20, free), 8)
        XCTAssertEqual(WorkshopGate.slots(bought: 1, pro), 50)
        // Surprise me only ever uses open parts.
        var rng = SplitMix64(seed: 7)
        for _ in 0..<200 {
            let s = WorkshopSurprise.make(catalog: c, access: free, using: &rng)
            XCTAssertTrue(WorkshopGate.allowed(s, palette: c.colours, free), "\(s)")
            XCTAssertNotEqual(s.mould, "draw-it")
        }
        for _ in 0..<200 { XCTAssertNotEqual(WorkshopSurprise.make(catalog: c, access: pro, using: &rng).mould, "draw-it") }
    }

    func testTheMixerOnlyEverMakesAMadeDesign() {
        var a = WorkshopDesign(mould: "cat")
        a.parts = [Placed(id: "a0", category: "hats-and-headwear", part: "hat"), Placed(id: "a1", category: "ears", part: "cat"),
                   Placed(id: "a2", category: "tails", part: "fox")]
        var b = WorkshopDesign(mould: "star")
        b.layers = [GooLayer(colour: 0x4A9FE8), GooLayer(colour: 0xFFD86B, pattern: "stripes")]
        b.parts = [Placed(id: "b0", category: "wings", part: "bee"), Placed(id: "b1", category: "neck-and-body", part: "bow"),
                   Placed(id: "b2", category: "held-items", part: "balloon")]
        let out = SquishyMixer.mix(.made(a), .made(b), seed: 1)
        XCTAssertEqual(out.mould, "cat")
        XCTAssertEqual(out.layers, b.layers)
        XCTAssertEqual(out.parts.map(\.part), ["hat", "cat", "bee", "bow"])
        XCTAssertEqual(Set(out.parts.map(\.id)).count, 4)
        XCTAssertEqual(out.source, "game")
        // A collectible only lends its colour.
        let lent = SquishyMixer.mix(.made(a), .collectible(colour: 0x7FE0C4), seed: 2)
        XCTAssertEqual(lent.mould, "cat")
        XCTAssertEqual(lent.layers.map(\.colour), [0x7FE0C4])
        let other = SquishyMixer.mix(.collectible(colour: 0x7FE0C4), .made(b), seed: 3)
        XCTAssertEqual(other.layers.last?.colour, 0x7FE0C4)
        XCTAssertTrue(other.layers.count <= WorkshopDesign.maxLayers)
        // The originals are untouched (values), and the result is a design, which has no collectible id at all.
        XCTAssertEqual(a.mould, "cat")
        XCTAssertEqual(b.mould, "star")
    }

    func testStatsStayUnderARare() throws {
        let c = try catalog()
        for goo in Goo.allCases {
            for mould in c.moulds {
                var d = WorkshopDesign(mould: mould, mould2: "bun", goo: goo)
                d.parts = c.parts.map { Placed(id: $0.category, category: $0.category, part: $0.items[0]) }
                d.stickers = [Placed(category: "stickers-and-patterns", part: "star")]
                d.fx = ["glitter"]
                let s = WorkshopStats(d)
                XCTAssertTrue(s.total <= WorkshopStats.cap, "\(goo) \(mould) \(s)")
                for v in [s.squish, s.bounce, s.stretch, s.charm] { XCTAssertTrue((1...10).contains(v)) }
            }
        }
        XCTAssertTrue(WorkshopStats(WorkshopDesign(goo: .jelly)).bounce > WorkshopStats(WorkshopDesign(goo: .foam)).bounce)
        XCTAssertTrue(WorkshopStats(WorkshopDesign(goo: .foam)).squish > WorkshopStats(WorkshopDesign(goo: .jelly)).squish)
    }

    func testTheNameWheelNeverLandsOnARudeName() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Content/name-wheel.json"))
        for language in ["en", "ja", "ko", "zh-Hant"] {
            let wheel = try NameWheel(json: data, language: language)
            XCTAssertEqual(wheel.first.count, 40, language)
            XCTAssertEqual(wheel.second.count, 40, language)
            var rng = SplitMix64(seed: 11)
            for _ in 0..<400 {
                let name = wheel.spin(using: &rng) { NameFilter.clean($0) == $0 }
                XCTAssertFalse(name.isEmpty)
                XCTAssertFalse(NameFilter.isRude(name), name)
                XCTAssertTrue(name.count <= NameFilter.maxLength, name)
            }
        }
        // An unknown language gets the English reels.
        XCTAssertEqual(try NameWheel(json: data, language: "fr").first, try NameWheel(json: data, language: "en").first)
    }

    func testADrawnOutlineBecomesAMould() {
        // A rough circle with a gap: closed, smoothed and evenly spaced.
        let circle = (0..<40).map { i -> WorkshopPoint in
            let a = Double(i) / 44 * 2 * Double.pi
            return WorkshopPoint(x: 0.5 + 0.3 * cos(a), y: 0.5 + 0.3 * sin(a))
        }
        let mould = DrawnShape.mould(from: circle)
        XCTAssertEqual(mould?.count, 64)
        // A dot or a scribble of three points is not a shape.
        XCTAssertNil(DrawnShape.mould(from: Array(circle.prefix(3))))
        XCTAssertNil(DrawnShape.mould(from: Array(repeating: WorkshopPoint(x: 0.5, y: 0.5), count: 20)))
        // A thin sliver is thickened until it can be squished.
        let sliver = (0..<40).map { i -> WorkshopPoint in
            let a = Double(i) / 40 * 2 * Double.pi
            return WorkshopPoint(x: 0.5 + 0.35 * cos(a), y: 0.5 + 0.03 * sin(a))
        }
        let thick = DrawnShape.mould(from: sliver) ?? []
        let ys = thick.map(\.y)
        XCTAssertTrue((ys.max() ?? 0) - (ys.min() ?? 0) >= 0.24)
    }

    func testGooLayersShareTheMouldByHowMuchWasPoured() throws {
        var d = WorkshopDesign()
        d.layers = [GooLayer(colour: 0xFF0000, amount: 0.75), GooLayer(colour: 0x0000FF, amount: 0.25)]
        XCTAssertEqual(d.bands.map(\.to), [0.75, 1.0])
        d.layers = [GooLayer(colour: 1), GooLayer(colour: 2), GooLayer(colour: 3)]
        XCTAssertEqual(d.bands[1].from, 1.0 / 3, accuracy: 0.0001)
        // A layer saved before amounts existed counts as one share.
        let old = try JSONDecoder().decode(GooLayer.self, from: Data(#"{"colour":255,"pattern":"plain","seed":4}"#.utf8))
        XCTAssertEqual(old, GooLayer(colour: 255, seed: 4))
    }
}
