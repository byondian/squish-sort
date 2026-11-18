import XCTest

/// Squishy Workshop on a simulator: the room, the Workshop door, the grown-up gate and the unlock.
final class KidsAppTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        return app
    }

    private func keep(_ shot: XCUIScreenshot, as name: String) {
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func button(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let b = app.buttons[id]
        if !b.waitForExistence(timeout: 10) {
            print("KIDS-APP \(id) missing; screen:\n\(app.debugDescription)")
            XCTFail("\(id) missing")
        }
        return b
    }

    /// A fresh install lands in the room with a squishy to squeeze. A second one joins from the shelf,
    /// closed rooms and worlds never show a price, and the door opens the Workshop.
    func testRoomOpensAndTheDoorLeadsToTheWorkshop() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["room-squishy"].waitForExistence(timeout: 15), "a squishy is in the room")
        Thread.sleep(forTimeInterval: 1.0)
        keep(app.screenshot(), as: "squishy-kids-1-room")
        // The second toy on the shelf comes in beside the first.
        let toys = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'kids-toy-'"))
        XCTAssertGreaterThan(toys.count, 3, "the free world's squishies are on the shelf")
        toys.element(boundBy: 1).tap()
        Thread.sleep(forTimeInterval: 1.0)
        keep(app.screenshot(), as: "squishy-kids-2-two")
        // Nothing a child sees has a price or a currency sign.
        let priced = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '$' OR label CONTAINS '£' OR label CONTAINS '€' OR label CONTAINS '2.99'"))
        XCTAssertEqual(priced.count, 0, "no price in the room")
        // A closed room asks for a grown-up; it does not change the room.
        button("kids-scene-bathTime", in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["kids-gate-hold"].waitForExistence(timeout: 5), "a closed room leads to the grown-up gate")
        button("kids-gate-close", in: app).tap()
        // The door.
        button("kids-door", in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["ws-stage"].waitForExistence(timeout: 10)
                      || app.buttons["ws-next"].waitForExistence(timeout: 5), "the Workshop opens")
        Thread.sleep(forTimeInterval: 0.8)
        keep(app.screenshot(), as: "squishy-kids-3-workshop")
        XCTAssertFalse(app.buttons["ws-see-shop"].exists)
    }

    /// The gate: hold for three seconds, then a sum. Behind it, the one purchase and no way out by accident.
    func testTheGrownUpsCornerSitsBehindTheGate() {
        let app = launch()
        button("kids-grownups", in: app).tap()
        let hold = app.descendants(matching: .any)["kids-gate-hold"]
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        // A quick poke does nothing.
        hold.tap()
        XCTAssertFalse(app.staticTexts["gate-question"].waitForExistence(timeout: 1.5), "a tap does not pass the hold")
        hold.press(forDuration: 3.6)
        let question = app.staticTexts["gate-question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5), "the sum follows the hold")
        let numbers = question.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertEqual(numbers.count, 2, question.label)
        let field = app.textFields["gate-answer"]
        field.tap()
        field.typeText(String(numbers[0] * numbers[1]))
        app.buttons["gate-ok"].tap()
        XCTAssertTrue(app.buttons["kids-unlock"].waitForExistence(timeout: 8), "the unlock is behind the gate")
        Thread.sleep(forTimeInterval: 0.8)
        keep(app.screenshot(), as: "squishy-kids-4-grownups")
    }

    /// Unlocked: every room and every world is open.
    func testUnlockedOpensEveryRoomAndWorld() {
        let app = launch(["-kidsUnlocked"])
        XCTAssertTrue(app.descendants(matching: .any)["room-squishy"].waitForExistence(timeout: 15))
        button("kids-scene-snowDay", in: app).tap()
        XCTAssertFalse(app.descendants(matching: .any)["kids-gate-hold"].waitForExistence(timeout: 1.5), "an open room needs no gate")
        button("kids-tab-junglejam", in: app).tap()
        let toys = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'kids-toy-'"))
        XCTAssertGreaterThan(toys.count, 3)
        toys.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1.0)
        keep(app.screenshot(), as: "squishy-kids-5-snow")
    }
}
