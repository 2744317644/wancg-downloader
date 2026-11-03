import XCTest

/// Lightweight visual/functional harness for the second-level listing screen.
/// It runs on a GitHub Actions macOS simulator (there is no local Xcode on the
/// Windows dev box), taps into the 同人志 category from Home, scrolls the grid,
/// exercises the filter chips and leaves PNG screenshots in the runner's temp
/// directory so the workflow can collect them.
final class CategoryScreenUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testCategorySecondaryScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "app did not reach foreground"
        )

        // Home is network-backed; the category chips only appear after the
        // homepage HTML has been fetched and parsed.
        let categoryChip = app.buttons["同人志"].firstMatch
        let categoryText = app.staticTexts["同人志"].firstMatch
        if categoryChip.waitForExistence(timeout: 120) {
            capture(name: "ui-01-home")
            categoryChip.tap()
        } else if categoryText.waitForExistence(timeout: 10) {
            capture(name: "ui-01-home")
            categoryText.tap()
        } else {
            capture(name: "ui-00-home-not-loaded")
            print("=== HOME TREE (chip not found) ===")
            print(app.debugDescription)
            print("=== END HOME TREE ===")
            XCTFail("同人志 category chip never appeared")
            return
        }

        XCTAssertTrue(
            app.navigationBars["同人志"].waitForExistence(timeout: 40),
            "category screen did not push"
        )

        // Give the first site page + cover thumbnails time to land.
        sleep(12)
        capture(name: "ui-02-category-top")
        print("=== CATEGORY TREE (top) ===")
        print(app.debugDescription)
        print("=== END CATEGORY TREE ===")

        // Scroll far enough to trigger the bottom sentinel / cover reuse.
        app.swipeUp()
        sleep(3)
        app.swipeUp()
        sleep(4)
        capture(name: "ui-03-category-scrolled")

        // Filter chips: same screen must stay stable and never show a blank
        // "page"; switching back to 全部 must restore the grid.
        let translated = app.buttons["翻译"].firstMatch
        if translated.waitForExistence(timeout: 10) {
            translated.tap()
            sleep(4)
            capture(name: "ui-04-category-filtered")
            let all = app.buttons["全部"].firstMatch
            if all.exists {
                all.tap()
                sleep(3)
                capture(name: "ui-05-category-filter-cleared")
            }
        } else {
            capture(name: "ui-04-filter-chip-missing")
        }

        // AI filter toggle chip must be reachable on the same row.
        let aiChip = app.buttons["屏蔽 AI"].firstMatch
        if aiChip.waitForExistence(timeout: 5) {
            aiChip.tap()
            sleep(3)
            capture(name: "ui-06-category-ai-filter")
        }

        print("=== CATEGORY TREE (after interactions) ===")
        print(app.debugDescription)
        print("=== END CATEGORY TREE ===")
    }

    private func capture(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
        print("SCREENSHOT_PATH: \(url.path)")
    }
}
