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
            let state = app.staticTexts["scene-state"]
            print("GOLDEN-PATH scene-state: \(state.exists ? state.label : "missing")")
            print("GOLDEN-PATH screen:\n\(app.debugDescription)")
            XCTFail("Next missing; scene-state: \(state.exists ? state.label : "missing")")
        }
        next.tap()
    }

    private func playFirstThreeAndOpenCapsule() {
        XCTAssertTrue(app.staticTexts["Level 1"].waitForExistence(timeout: 10), "Level 1 is the first screen")
        play([(1, 0), (1, 2)])
        next()
        XCTAssertTrue(app.staticTexts["Level 2"].waitForExistence(timeout: 5))
        play([(0, 2), (1, 0), (1, 2)])
        next()
        XCTAssertTrue(app.staticTexts["Level 3"].waitForExistence(timeout: 5))
        play([(0, 3), (2, 0), (1, 2), (1, 3), (0, 1), (2, 0), (2, 3)])
        // First capsule is always Peach Bun.
        let open = app.buttons["open-capsule"]
        XCTAssertTrue(open.waitForExistence(timeout: 8), "capsule after level 3")
        open.tap()
        XCTAssertTrue(app.staticTexts["Peach Bun"].waitForExistence(timeout: 5))
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
        next()
        XCTAssertTrue(app.staticTexts["Level 4"].waitForExistence(timeout: 5))
        app.buttons["gearshape.fill"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Gentle mode is on"].waitForExistence(timeout: 5))
    }

    /// Leaving gentle mode needs the grown-up check, and then asks the birthday question again.
    func testLeavingGentleModeNeedsAGrownUpAndAsksTheAgeAgain() {
        playFirstThreeAndOpenCapsule()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        skip.tap()
        next()
        XCTAssertTrue(app.staticTexts["Level 4"].waitForExistence(timeout: 5))
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
        next()
        XCTAssertTrue(app.staticTexts["Level 4"].waitForExistence(timeout: 5))
        app.buttons["gearshape.fill"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Set up for a child"].waitForExistence(timeout: 5))
    }
}
