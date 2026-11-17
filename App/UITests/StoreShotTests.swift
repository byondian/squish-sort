import XCTest

/// Takes the App Store pictures: six staged screens in each of the four languages.
/// Run by .github/workflows/screenshots.yml only (the everyday checks skip it).
final class StoreShotTests: XCTestCase {
    private let languages: [(code: String, locale: String)] = [
        ("en", "en_GB"), ("ja", "ja_JP"), ("ko", "ko_KR"), ("zh-Hant", "zh_TW"),
    ]

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ shot: String, _ language: (code: String, locale: String)) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-storeShot", shot, "-AppleLanguages", "(\(language.code))", "-AppleLocale", language.locale]
        app.launch()
        return app
    }

    private func keep(_ app: XCUIApplication, _ number: Int, _ name: String, _ language: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "store-\(language)-\(number)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }

    func testStorePictures() {
        for language in languages {
            // 1. The puzzle, with a squishy lifted.
            var app = launch("puzzle", language)
            let jar = app.buttons["jar-0"]
            if jar.waitForExistence(timeout: 20) {
                Thread.sleep(forTimeInterval: 1.5)
                jar.tap()
                Thread.sleep(forTimeInterval: 0.6)
            }
            keep(app, 1, "puzzle", language.code)

            // 2. An ultra rare out of its capsule.
            app = launch("reveal", language)
            let open = app.buttons["open-capsule"]
            if open.waitForExistence(timeout: 20) {
                open.tap()
                Thread.sleep(forTimeInterval: 1.0)
                // The capsule opens on the second tap.
                if open.exists && open.isHittable { open.tap() }
                _ = app.buttons["capsule-next"].waitForExistence(timeout: 12)
                Thread.sleep(forTimeInterval: 1.5)
            }
            keep(app, 2, "reveal", language.code)

            // 3. The Squish Room, with Taffy Snake pulled out.
            app = launch("room", language)
            Thread.sleep(forTimeInterval: 3.0)
            let window = app.windows.firstMatch
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.42))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3))
            from.press(forDuration: 0.3, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.4)
            keep(app, 3, "room", language.code)

            // 4. Home, with the Buddy.
            app = launch("home", language)
            _ = app.buttons["home-play"].waitForExistence(timeout: 20)
            Thread.sleep(forTimeInterval: 2.0)
            keep(app, 4, "home", language.code)

            // 5. The Collection.
            app = launch("book", language)
            Thread.sleep(forTimeInterval: 3.5)
            keep(app, 5, "book", language.code)

            // 6. The map: hundreds of levels, and Keep Squishing.
            app = launch("map", language)
            _ = app.buttons["map-current"].waitForExistence(timeout: 20)
            Thread.sleep(forTimeInterval: 2.0)
            keep(app, 6, "map", language.code)
        }
    }
}
