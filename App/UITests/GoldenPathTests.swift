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
        let again = app.buttons["win-next"]
        if again.exists && again.isHittable { again.tap() }
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

    /// Also run by CI on an older iOS, to catch a launch crash from newer frameworks.
    func testLaunchShowsLevelOne() {
        XCTAssertTrue(app.staticTexts["Level 1"].waitForExistence(timeout: 30), "Level 1 is the first screen")
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
        let field = app.textFields["gate-answer"]
        field.tap()
        field.typeText(String(numbers[0] * numbers[1]))
        app.buttons["gate-ok"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 8), "the birthday question follows the gate")
    }

    func testChoosingAnAdultYearLeavesGentleModeOff() {
        playFirstThreeAndOpenCapsule()
        let picker = app.pickerWheels.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.adjust(toPickerWheelValue: "1990")
        app.buttons["Continue"].tap()
        waitForAgeQuestionToClose()
        nextLevel("Level 4")
        app.buttons["gearshape.fill"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Set up for a child"].waitForExistence(timeout: 5))
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
