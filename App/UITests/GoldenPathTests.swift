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

    private func next() {
        let next = app.buttons["Next"]
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
        next()
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
