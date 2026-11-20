import XCTest

/// Gate 3: the golden path on a simulator, from a fresh install.
final class GoldenPathTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func play(_ moves: [(Int, Int)]) {
        for (from, to) in moves {
            tapJar(from)
            Thread.sleep(forTimeInterval: 0.3)
            tapJar(to)
            // Let the hop and squash finish.
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    private func tapJar(_ j: Int) {
        let button = app.buttons["jar-\(j)"]
        if !button.waitForExistence(timeout: 5) {
            XCTFail("jar-\(j) missing. Screen:\n\(app.debugDescription)")
        }
        button.tap()
        Thread.sleep(forTimeInterval: 0.2)
    }

    private func next(_ id: String = "win-next") {
        let next = app.buttons[id]
        if !next.waitForExistence(timeout: 8) {
            dump("\(id) missing")
            XCTFail("\(id) missing")
        }
        // A cover that is still sliding away can swallow the tap: wait until the button can be hit.
        let deadline = Date().addingTimeInterval(6)
        while !next.isHittable && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        next.tap()
    }

    /// Taps Next on the win card and waits for the level title. Next runs once in
    /// the app, so a second tap is safe if the first one landed on a closing cover.
    private func nextLevel(_ title: String) {
        next()
        let label = app.staticTexts[title]
        if label.waitForExistence(timeout: 3) { return }
        // Good news (a new place to play) may be up first: read it and carry on.
        let news = app.buttons["news-next"]
        let again = app.buttons["win-next"]
        if news.exists && news.isHittable { news.tap() } else if again.exists && again.isHittable { again.tap() }
        if !label.waitForExistence(timeout: 6) {
            dump("\(title) missing after Next")
            XCTFail("\(title) missing after Next")
        }
    }

    /// The birthday question has to be off screen before the win card can be used.
    private func waitForAgeQuestionToClose() {
        let skip = app.buttons["Skip"]
        let deadline = Date().addingTimeInterval(8)
        while skip.exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        if skip.exists {
            dump("birthday question still on screen")
            XCTFail("birthday question still on screen")
        }
    }

    private func dump(_ what: String) {
        let state = app.staticTexts["scene-state"]
        print("GOLDEN-PATH \(what); scene-state: \(state.exists ? state.label : "missing")")
        print("GOLDEN-PATH screen:\n\(app.debugDescription)")
    }

    /// Home's top bar on whatever phone the test runs on: the coin pill, the stamp pill and settings are
    /// one height on one centre line, the side margins match, the bar sits just under the status bar
    /// and the logo keeps clear of it.
    func testHomeTopBarLinesUp() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-storeShot", "home"]
        app.launch()
        let coins = app.buttons["home-coins"], stamps = app.buttons["stamp-card"], settings = app.buttons["gearshape.fill"]
        XCTAssertTrue(coins.waitForExistence(timeout: 20))
        XCTAssertTrue(stamps.exists && settings.exists)
        Thread.sleep(forTimeInterval: 1.5)
        let screen = app.windows.firstMatch.frame
        let c = coins.frame, s = stamps.frame, g = settings.frame
        for f in [s, g] {
            XCTAssertEqual(f.height, c.height, accuracy: 1, "one height")
            XCTAssertEqual(f.midY, c.midY, accuracy: 1, "one centre line")
        }
        XCTAssertEqual(c.minX, 16, accuracy: 1, "left margin")
        XCTAssertEqual(screen.maxX - g.maxX, 16, accuracy: 1, "right margin")
        XCTAssertEqual(s.minX - c.maxX, 8, accuracy: 1, "gap between the pills")
        XCTAssertLessThan(c.minY, 76, "the bar sits just under the status bar")
        XCTAssertGreaterThan(c.minY, 18, "the bar stays clear of the status bar")
        let logo = app.otherElements["home-logo"]
        if logo.exists { XCTAssertGreaterThanOrEqual(logo.frame.minY - c.maxY, 12, "the logo keeps clear of the bar") }
        keep(app.screenshot(), as: "squishy-home-top-bar")
        app.terminate()
    }

    /// The Buddy on Home with gifts on and its size meter: a picture, so where a hat sits is seen without a phone.
    func testBuddyWearsItsGifts() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-storeShot", "gifts"]
        app.launch()
        XCTAssertTrue(app.buttons["home-play"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["buddy-size"].waitForExistence(timeout: 5), "the size meter is on Home")
        Thread.sleep(forTimeInterval: 2.5)
        keep(app.screenshot(), as: "squishy-buddy-gifts")
        app.terminate()
    }

    /// Bubble Bath level 4, played to the end by its stored solution: floaters seal their jars and pop,
    /// and the golden bubble takes its ride. Pictures are kept of the start, the bubble lifted and after it lands.
    func testBubbleBathFloatersAndARide() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-storeShot", "bubbles:4"]
        app.launch()
        XCTAssertTrue(app.buttons["bubble-0"].waitForExistence(timeout: 20), "a Bubble Bath board has bubble buttons")
        Thread.sleep(forTimeInterval: 2.5)
        keep(app.screenshot(), as: "squishy-bubbles-1-start")
        let state = app.staticTexts["scene-state"]
        play([(2, 4)])
        // Jar 2 now has room, but its bubble seals it: the lifted squishy goes back.
        tapJar(1)
        Thread.sleep(forTimeInterval: 0.3)
        tapJar(2)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(state.label.contains("lifted=-"), "nothing pours into a sealed jar: \(state.label)")
        app.buttons["bubble-0"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(state.label.contains("riding=0"), "the golden bubble is up: \(state.label)")
        keep(app.screenshot(), as: "squishy-bubbles-2-riding")
        tapJar(4)
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertTrue(state.label.contains("riding=-"), "the golden bubble has landed: \(state.label)")
        keep(app.screenshot(), as: "squishy-bubbles-3-landed")
        play([(2, 0), (1, 5), (2, 5), (1, 2), (0, 1), (0, 2), (0, 4), (3, 2), (3, 4), (3, 5), (1, 3)])
        let won = NSPredicate(format: "label CONTAINS 'won'")
        expectation(for: won, evaluatedWith: state)
        waitForExpectations(timeout: 8)
        keep(app.screenshot(), as: "squishy-bubbles-4-won")
        app.terminate()
    }

    /// Squishies whose signature move brings its own part (a top, a hat, a lid): a picture of each at
    /// rest in the Squish Room, so a part that sits in the wrong place is seen without a phone.
    func testPartsSitOnTheirSquishies() {
        for id in ["cream-puff", "cupcake", "macaron", "capy", "mushie", "axo"] {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting", "-storeShot", "room:\(id)"]
            app.launch()
            XCTAssertTrue(app.otherElements["room-squishy"].waitForExistence(timeout: 20), id)
            Thread.sleep(forTimeInterval: 3)
            keep(app.screenshot(), as: "squishy-room-\(id)")
            app.terminate()
        }
    }

    /// Pictures of the soft squishy at rest, just after a squeeze and held down hard, kept with the test results so the
    /// light and the dent can be looked at without a phone. Nothing here can fail the test.
    private func squeezeForThePicture() {
        let squishy = app.otherElements["capsule-squishy"]
        guard squishy.waitForExistence(timeout: 3) else { return }
        Thread.sleep(forTimeInterval: 0.8)
        keep(app.screenshot(), as: "squishy-at-rest")
        squishy.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(forDuration: 0.9)
        keep(app.screenshot(), as: "squishy-just-squeezed")
        Thread.sleep(forTimeInterval: 2.5)
        // Pressed hard from the top and held: it should be a fat pancake with its face still a face.
        // The press blocks this thread, so the pictures are taken from another one while it lasts.
        let taken = DispatchGroup()
        let held = HeldShots()
        for (name, wait) in [("squishy-held-down-early", 1.3), ("squishy-held-down", 2.2)] {
            taken.enter()
            DispatchQueue.global().asyncAfter(deadline: .now() + wait) {
                let shot = XCUIScreen.main.screenshot()
                held.add(name, shot)
                taken.leave()
            }
        }
        let top = squishy.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let low = squishy.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        top.press(forDuration: 0.2, thenDragTo: low, withVelocity: .slow, thenHoldForDuration: 2.4)
        _ = taken.wait(timeout: .now() + 5)
        for (name, shot) in held.all() { keep(shot, as: name) }
        Thread.sleep(forTimeInterval: 2.0)
    }

    private func keep(_ shot: XCUIScreenshot, as name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func playFirstThreeAndOpenCapsule() {
        XCTAssertTrue(app.staticTexts["Level 1"].waitForExistence(timeout: 10), "Level 1 is the first screen")
        // Level 1 opens with the first squishy already lifted: one tap finishes a jar.
        tapJar(0)
        Thread.sleep(forTimeInterval: 1.0)
        play([(1, 2)])
        // The first two levels roll on by themselves after the celebration.
        XCTAssertTrue(app.staticTexts["Level 2"].waitForExistence(timeout: 10), "level 1 rolls on to level 2")
        play([(0, 2), (1, 0), (1, 2)])
        XCTAssertTrue(app.staticTexts["Level 3"].waitForExistence(timeout: 10), "level 2 rolls on to level 3")
        play([(0, 3), (2, 0), (1, 2), (1, 3), (0, 1), (2, 0), (2, 3)])
        // First capsule is always Peach Bun.
        let open = app.buttons["open-capsule"]
        XCTAssertTrue(open.waitForExistence(timeout: 8), "capsule after level 3")
        open.tap()
        XCTAssertTrue(app.staticTexts["Peach Bun"].waitForExistence(timeout: 5))
        squeezeForThePicture()
        next("capsule-next")
    }

    private func workshopButton(_ id: String, in app: XCUIApplication, _ what: String) -> XCUIElement {
        let button = app.buttons[id]
        if !button.waitForExistence(timeout: 8) {
            print("GOLDEN-PATH \(what): \(id) missing; screen:\n\(app.debugDescription)")
            XCTFail("\(what): \(id) missing")
        }
        return button
    }

    /// The Squishy Workshop from an empty mould to the shelf: mould, pour, bake, face, dress up,
    /// voice and name, the birthday card, then Surprise me. Also run by CI on an iPad.
    func testWorkshopMakesASquishy() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-storeShot", "workshop"]
        app.launch()
        workshopButton("ws-mould-egg", in: app, "mould station").tap()
        XCTAssertFalse(app.buttons["ws-station-3"].isEnabled, "no baking before the goo is poured")
        workshopButton("ws-next", in: app, "to the goo").tap()
        workshopButton("ws-goo-foam", in: app, "goo station").tap()
        XCTAssertFalse(app.buttons["ws-next"].isEnabled, "an empty mould cannot move on")
        // Hold a finger on the mould: the goo pours while it is held.
        let stage = app.descendants(matching: .any)["ws-stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        stage.press(forDuration: 1.0)
        keep(app.screenshot(), as: "squishy-workshop-1-half-poured")
        print("GOLDEN-PATH workshop poured after 1 s: \(stage.value ?? "?")")
        stage.press(forDuration: 3.0)
        print("GOLDEN-PATH workshop poured after 4 s: \(stage.value ?? "?")")
        for _ in 0..<3 where !app.buttons["ws-next"].isEnabled { stage.press(forDuration: 2.0) }
        XCTAssertTrue(app.buttons["ws-next"].isEnabled, "a full mould moves on")
        keep(app.screenshot(), as: "squishy-workshop-2-poured")
        app.buttons["ws-next"].tap()
        workshopButton("ws-bake", in: app, "oven").tap()
        // It pops out; then the belt moves on to the face.
        XCTAssertTrue(app.buttons["ws-redo"].waitForExistence(timeout: 8), "the squishy pops out of the oven")
        app.buttons["ws-next"].tap()
        workshopButton("ws-eyes-big-shine", in: app, "face station").tap()
        workshopButton("ws-face-mouths", in: app, "face station").tap()
        workshopButton("ws-mouths-big-smile", in: app, "mouths").tap()
        app.buttons["ws-next"].tap()
        workshopButton("ws-part-bear", in: app, "dress up").tap()
        XCTAssertTrue(app.descendants(matching: .any)["ws-placed-ears"].waitForExistence(timeout: 5), "the ears are on")
        keep(app.screenshot(), as: "squishy-workshop-3-dressed")
        // A part that is not open says how to get it, and the squishy is kept while the player looks.
        workshopButton("ws-tray-wings", in: app, "wings tray").tap()
        workshopButton("ws-part-angel", in: app, "wings").tap()
        XCTAssertTrue(app.buttons["ws-buy-part"].waitForExistence(timeout: 5), "from 13, a wearable can be bought with coins")
        app.buttons["ws-next"].tap()
        workshopButton("ws-voice-honk", in: app, "voices").tap()
        let wheel = workshopButton("ws-spin", in: app, "name wheel")
        if !wheel.isHittable { app.swipeUp() }
        wheel.tap()
        keep(app.screenshot(), as: "squishy-workshop-4-life")
        let done = workshopButton("ws-done", in: app, "done")
        if !done.isHittable { app.swipeUp() }
        done.tap()
        XCTAssertTrue(app.staticTexts["ws-card-name"].waitForExistence(timeout: 8), "the birthday card")
        Thread.sleep(forTimeInterval: 0.8)
        keep(app.screenshot(), as: "squishy-workshop-5-card")
        workshopButton("ws-another", in: app, "card").tap()
        // Surprise me lands at the oven.
        workshopButton("ws-surprise", in: app, "surprise").tap()
        workshopButton("ws-bake", in: app, "surprise oven").tap()
        XCTAssertTrue(app.buttons["ws-redo"].waitForExistence(timeout: 8))
        keep(app.screenshot(), as: "squishy-workshop-6-surprise")
        // The first one is on the shelf.
        app.buttons["ws-shelf"].tap()
        XCTAssertTrue(app.buttons["ws-edit"].waitForExistence(timeout: 5), "the saved squishy is on the shelf")
        app.terminate()
    }

    /// A child (or an unknown age) sees no price, no coin price and no way to the shop in the Workshop.
    func testWorkshopShowsAChildNoPricesAndNoShop() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-storeShot", "workshop-child"]
        app.launch()
        _ = workshopButton("ws-mould-bun", in: app, "mould station")
        XCTAssertFalse(app.buttons["ws-more"].exists, "the closed drawer cannot be tapped")
        XCTAssertFalse(app.buttons["ws-on-top"].exists, "no locked Pro tool")
        keep(app.screenshot(), as: "squishy-workshop-7-child")
        app.buttons["ws-next"].tap()
        let stage = app.descendants(matching: .any)["ws-stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        // A slow simulator starts pouring late: keep holding until the mould is full.
        for _ in 0..<4 where !app.buttons["ws-next"].isEnabled { stage.press(forDuration: 3.0) }
        XCTAssertFalse(app.buttons["ws-mix"].exists)
        app.buttons["ws-next"].tap()
        workshopButton("ws-bake", in: app, "oven").tap()
        XCTAssertTrue(app.buttons["ws-redo"].waitForExistence(timeout: 8))
        app.buttons["ws-next"].tap()
        app.buttons["ws-next"].tap()
        workshopButton("ws-tray-wings", in: app, "wings tray").tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(app.buttons["ws-part-angel"].exists, "parts that come with Remove Ads are not shown to a child")
        XCTAssertFalse(app.buttons["ws-see-shop"].exists)
        XCTAssertFalse(app.buttons["ws-buy-part"].exists)
        app.buttons["ws-next"].tap()
        XCTAssertFalse(app.buttons["ws-type-name"].exists, "a child has the name wheel only")
        XCTAssertTrue(app.buttons["ws-spin"].waitForExistence(timeout: 5))
        app.terminate()
    }

    /// Also run by CI on an older iOS, to catch a launch crash from newer frameworks.
    func testLaunchShowsLevelOne() {
        XCTAssertTrue(app.staticTexts["Level 1"].waitForExistence(timeout: 30), "Level 1 is the first screen")
    }

    /// How long a new player waits for the first squish: from tapping the icon to a jar that can be tapped.
    /// Nothing sits in front of level 1 (the birthday question comes after the first capsule).
    /// The simulator on a build machine is slower than a phone, so this prints the time and only
    /// fails when something has clearly been put in the way.
    func testFirstSquishIsQuick() {
        app.terminate()
        let started = Date()
        app.launch()
        let jar = app.buttons["jar-0"]
        XCTAssertTrue(jar.waitForExistence(timeout: 30), "the first board is the first screen")
        let ready = Date().timeIntervalSince(started)
        jar.tap()
        let squished = Date().timeIntervalSince(started)
        print("FIRST-SQUISH board ready after \(String(format: "%.1f", ready)) s, first tap done after \(String(format: "%.1f", squished)) s")
        XCTAssertLessThan(squished, 25, "nothing should sit between the icon and the first squish")
    }

    func testSkippingTheBirthdayQuestionMeansGentleMode() {
        playFirstThreeAndOpenCapsule()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8), "birthday question after the first capsule")
        skip.tap()
        waitForAgeQuestionToClose()
        nextLevel("Level 4")
        app.buttons["gearshape.fill"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Gentle mode is on"].waitForExistence(timeout: 5))
    }

    /// Leaving gentle mode needs the grown-up check, and then asks the birthday question again.
    func testLeavingGentleModeNeedsAGrownUpAndAsksTheAgeAgain() {
        playFirstThreeAndOpenCapsule()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        skip.tap()
        waitForAgeQuestionToClose()
        nextLevel("Level 4")
        app.buttons["gearshape.fill"].firstMatch.tap()
        let off = app.buttons["Turn off gentle mode"]
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        off.tap()
        let question = app.staticTexts["gate-question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5), "the grown-up check comes first")
        let numbers = question.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertEqual(numbers.count, 2, question.label)
        for digit in String(numbers[0] * numbers[1]) { app.buttons["gate-key-\(digit)"].tap() }
        app.buttons["gate-ok"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 8), "the birthday question follows the gate")
    }

    func testChoosingAnAdultYearLeavesGentleModeOff() {
        playFirstThreeAndOpenCapsule()
        let decade = app.buttons["decade-1990"]
        XCTAssertTrue(decade.waitForExistence(timeout: 8))
        decade.tap()
        let year = app.buttons["year-1990"]
        XCTAssertTrue(year.waitForExistence(timeout: 5))
        year.tap()
        app.buttons["Continue"].tap()
        waitForAgeQuestionToClose()
        nextLevel("Level 4")
        app.buttons["gearshape.fill"].firstMatch.tap()
        // Settings is a long list now: rows below the fold only exist once scrolled to.
        let child = app.buttons["Set up for a child"]
        if !child.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(child.waitForExistence(timeout: 5))
    }
}

/// Screenshots taken on another thread while a long press holds the test's own.
private final class HeldShots: @unchecked Sendable {
    private let lock = NSLock()
    private var shots: [(String, XCUIScreenshot)] = []

    func add(_ name: String, _ shot: XCUIScreenshot) {
        lock.lock()
        shots.append((name, shot))
        lock.unlock()
    }

    func all() -> [(String, XCUIScreenshot)] {
        lock.lock()
        defer { lock.unlock() }
        return shots
    }
}
