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
        XCTAssertEqual(d.parts.map(\.part), ["bunny"])
        // And a design with fields missing takes the defaults.
        let thin = try JSONDecoder().decode(WorkshopDesign.self, from: Data(#"{"mould":"bear"}"#.utf8))
        XCTAssertEqual(thin.mould, "bear")
        XCTAssertEqual(thin.goo, .jelly)
        XCTAssertEqual(thin.layers.count, 1)
        // A new save goes round.
        var full = MadeSquishy(id: "b2", name: "Mimi", design: thin)
        full.design?.parts = [Placed(id: "p", category: "wings", part: "angel")]
        let back = try JSONDecoder().decode(MadeSquishy.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(back, full)
    }

    func testColourMixing() {
        func hue(_ a: UInt32, _ b: UInt32) -> Double { GooMix.hue(GooMix.mix(a, b)) ?? -1 }
        // Blue and yellow make green.
        XCTAssertTrue((80...170).contains(hue(0x4A9FE8, 0xFFD86B)))
        XCTAssertTrue((80...170).contains(hue(0x7CC8FF, 0xFFD86B)))
        // Red and yellow make orange; blue and red make purple.
        XCTAssertTrue((8...45).contains(hue(0xFF5A6E, 0xFFD86B)))
        XCTAssertTrue((255...320).contains(hue(0x4A9FE8, 0xFF5A6E)))
        // Red and white make pink: still red-ish, and lighter than the red.
        let pink = GooMix.rgb(GooMix.mix(0xFF5A6E, 0xFFFFFF))
        XCTAssertTrue(pink[0] > 0.95 && pink[1] > 0.5 && pink[2] > 0.5 && pink[0] > pink[1])
        // A colour mixed with itself stays itself, and a share of nothing changes nothing.
        XCTAssertEqual(GooMix.mix(0x7FE0C4, 0x7FE0C4), 0x7FE0C4)
        XCTAssertEqual(GooMix.mix(0x4A9FE8, 0xFFD86B, share: 0), 0x4A9FE8)
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
        d = WorkshopDesign(); d.drawnFace = [[WorkshopPoint(x: 0, y: 0)]]; cases.append(d)
        d = WorkshopDesign(); d.dance = "spinner"; cases.append(d)
        for design in cases {
            XCTAssertFalse(WorkshopGate.allowed(design, palette: c.colours, free), "\(design)")
            XCTAssertTrue(WorkshopGate.allowed(design, palette: c.colours, pro))
            // With Pro gone the look can still be edited, from a copy that is free all through.
            XCTAssertTrue(WorkshopGate.allowed(WorkshopGate.freeCopy(of: design, palette: c.colours, free), palette: c.colours, free))
        }
        // Today's unlock rule still holds for the classic moulds.
        XCTAssertFalse(WorkshopGate.mouldOpen("cloud", WorkshopAccess(pro: false, classicMoulds: 2)))
        XCTAssertTrue(WorkshopGate.mouldOpen("egg", WorkshopAccess(pro: false, classicMoulds: 2)))
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
        a.parts = (0..<4).map { Placed(id: "a\($0)", category: "ears", part: "cat") }
        var b = WorkshopDesign(mould: "star")
        b.layers = [GooLayer(colour: 0x4A9FE8), GooLayer(colour: 0xFFD86B, pattern: "stripes")]
        b.parts = (0..<4).map { Placed(id: "b\($0)", category: "wings", part: "bee") }
        let out = SquishyMixer.mix(.made(a), .made(b), seed: 1)
        XCTAssertEqual(out.mould, "cat")
        XCTAssertEqual(out.layers, b.layers)
        XCTAssertEqual(out.parts.map(\.part), ["cat", "cat", "bee", "bee"])
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
                d.parts = (0..<6).map { Placed(id: "\($0)", category: "ears", part: "cat") }
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
}
