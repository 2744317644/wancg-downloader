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
            dumpTree(app, label: "HOME TREE (chip not found)")
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
        dumpTree(app, label: "CATEGORY TREE (top)")

        // Only the native TabView bar may exist at the bottom. The old design
        // stacked a floating pager bar on top of it.
        XCTAssertEqual(app.tabBars.count, 1, "expected exactly one native tab bar")
        XCTAssertEqual(
            app.staticTexts.matching(
                NSPredicate(format: "label MATCHES '.*[0-9]+ / [0-9]+.*'")
            ).count,
            0,
            "old pager counter must be gone"
        )

        // Scroll far enough to trigger the bottom sentinel / cover reuse.
        app.swipeUp()
        sleep(3)
        app.swipeUp()
        sleep(4)
        capture(name: "ui-03-category-scrolled")
        let cardsAfterScroll = albumCardCount(app)
        print("ALBUM_CARDS_AFTER_SCROLL: \(cardsAfterScroll)")

        // Back to the top: the inline scope chips scroll away with the content.
        scrollToTop(app)
        sleep(2)

        // Filter chips: same screen must stay stable and never show a blank
        // "page"; switching back to 全部 must restore the grid.
        let translated = app.buttons["翻译"].firstMatch
        XCTAssertTrue(
            translated.waitForExistence(timeout: 10),
            "language filter chip missing"
        )
        if translated.exists {
            XCTAssertGreaterThanOrEqual(
                translated.frame.height, 44,
                "filter chip touch target must be at least 44pt"
            )
            translated.tap()
            sleep(4)
            capture(name: "ui-04-category-filtered")
            XCTAssertTrue(
                albumCardCount(app) > 0
                    || app.staticTexts["没有符合筛选的作品"].exists,
                "filtered state must show either matches or the explained empty state"
            )
            let all = app.buttons["全部"].firstMatch
            if all.exists {
                all.tap()
                sleep(3)
                capture(name: "ui-05-category-filter-cleared")
            }
        }

        // AI filter toggle chip must be reachable on the same row.
        let aiChip = app.buttons["屏蔽 AI"].firstMatch
        if aiChip.waitForExistence(timeout: 5) {
            XCTAssertGreaterThanOrEqual(
                aiChip.frame.height, 44,
                "AI filter chip touch target must be at least 44pt"
            )
            aiChip.tap()
            sleep(3)
            capture(name: "ui-06-category-ai-filter")
        }

        // Third level: a cover must still push the detail screen.
        if let firstCard = firstAlbumCard(app) {
            firstCard.tap()
            if app.navigationBars["详情"].waitForExistence(timeout: 30) {
                sleep(5)
                capture(name: "ui-07-detail")
                app.navigationBars.buttons.firstMatch.tap()
                sleep(2)
            }
        }

        dumpTree(app, label: "CATEGORY TREE (after interactions)")
    }

    // MARK: Helpers

    private func albumCardCount(_ app: XCUIApplication) -> Int {
        app.buttons.matching(albumCardPredicate).count
    }

    private func firstAlbumCard(_ app: XCUIApplication) -> XCUIElement? {
        let match = app.buttons.matching(albumCardPredicate).firstMatch
        return match.exists ? match : nil
    }

    /// Album cards expose a combined accessibility label like
    /// "<title>, 216P, 2026-11-03" (pages and date are optional).
    private var albumCardPredicate: NSPredicate {
        NSPredicate(
            format: "label MATCHES '.*[0-9]{4}-[0-9]{2}-[0-9]{2}.*'"
        )
    }

    private func scrollToTop(_ app: XCUIApplication) {
        // Tapping the status bar is the system gesture for scroll-to-top; a few
        // swipes are the fallback when the tap is swallowed by the simulator.
        let statusBar = app.statusBars.firstMatch
        if statusBar.exists {
            statusBar.tap()
            sleep(1)
        }
        for _ in 0..<4 where !app.buttons["翻译"].firstMatch.exists {
            app.swipeDown()
            sleep(1)
        }
    }

    private func dumpTree(_ app: XCUIApplication, label: String) {
        print("=== \(label) ===")
        print(app.debugDescription)
        print("=== END \(label) ===")
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
