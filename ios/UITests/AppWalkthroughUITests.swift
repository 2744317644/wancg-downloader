import XCTest

/// Exploratory walkthrough of every main screen and flow, used for QA and UI
/// review. It runs on the GitHub Actions macOS simulator (highest iOS runtime)
/// because the Windows dev box cannot host Simulator.app.
///
/// Every screen gets a screenshot (`ui-walk-*.png`, collected by the workflow)
/// and an accessibility-tree dump in the log, so layout / truncation /
/// missing-control bugs can be reviewed without a local Mac.
final class AppWalkthroughUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testFullAppWalkthrough() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "app did not reach foreground"
        )

        // Home is network-backed; wait for the category chips.
        XCTAssertTrue(
            app.buttons["同人志"].waitForExistence(timeout: 120),
            "home page did not finish loading"
        )
        sleep(3)
        capture(app, "ui-walk-01-home-light")
        dump(app, "WALK: HOME (light)")

        // Pull to refresh the home feed.
        app.swipeDown()
        sleep(5)
        capture(app, "ui-walk-02-home-refreshed")

        // ---- Tabs ----
        visitTab(app, label: "下载", name: "download")
        // Try the download-link parser with the sample album used in the smoke test.
        let linkField = app.textFields.firstMatch
        if linkField.waitForExistence(timeout: 6) {
            linkField.tap()
            linkField.typeText("https://www.wnacg.com/photos-index-aid-383877.html")
            let parseButton = app.buttons["解析作品"].firstMatch
            if parseButton.waitForExistence(timeout: 5) {
                parseButton.tap()
                sleep(14)
                dismissKeyboard(app)
                capture(app, "ui-walk-03-download-parsed")
                dump(app, "WALK: DOWNLOAD parsed")
            }
        }

        visitTab(app, label: "收藏", name: "favorites")
        visitTab(app, label: "文件", name: "files")

        visitTab(app, label: "设置", name: "settings")
        dump(app, "WALK: SETTINGS")

        // History sub-screen.
        let historyLink = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '历史记录'")
        ).firstMatch
        if historyLink.waitForExistence(timeout: 6) {
            historyLink.tap()
            sleep(3)
            capture(app, "ui-walk-04-history")
            dump(app, "WALK: HISTORY")
            goBack(app)
        }

        // ---- Dark appearance pass ----
        setAppearance(app, option: "深色")
        visitTab(app, label: "首页", name: "home-dark")
        sleep(2)
        capture(app, "ui-walk-05-home-dark")

        if app.buttons["同人志"].waitForExistence(timeout: 10) {
            app.buttons["同人志"].tap()
            _ = app.navigationBars["同人志"].waitForExistence(timeout: 30)
            sleep(8)
            capture(app, "ui-walk-06-category-dark")
            dump(app, "WALK: CATEGORY (dark)")

            if let card = firstAlbumCard(app) {
                card.tap()
                _ = app.navigationBars["详情"].waitForExistence(timeout: 30)
                sleep(5)
                capture(app, "ui-walk-07-detail-dark")
                dump(app, "WALK: DETAIL (dark)")
                goBack(app)
                sleep(2)
            }
            goBack(app)
            sleep(2)
        }

        // Restore appearance.
        visitTab(app, label: "设置", name: "settings-restore")
        setAppearance(app, option: "跟随系统")

        // ---- Search ----
        visitTab(app, label: "首页", name: "home-before-search")
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 6) {
            searchField.tap()
            searchField.typeText("love\n")
            let searchNav = app.navigationBars.matching(
                NSPredicate(format: "identifier CONTAINS '搜索'")
            ).firstMatch
            _ = searchNav.waitForExistence(timeout: 25)
            sleep(8)
            capture(app, "ui-walk-08-search")
            dump(app, "WALK: SEARCH RESULTS")
            goBack(app)
        }

        dump(app, "WALK: FINAL STATE")
    }

    // MARK: - Steps

    private func visitTab(
        _ app: XCUIApplication,
        label: String,
        name: String
    ) {
        dismissKeyboard(app)
        let tab = app.tabBars.buttons[label].firstMatch
        XCTAssertTrue(
            tab.waitForExistence(timeout: 10),
            "tab \(label) is missing"
        )
        tab.tap()
        sleep(2)
        XCTAssertTrue(
            tab.isSelected,
            "tab \(label) did not become selected (tap was swallowed)"
        )
        capture(app, "ui-walk-tab-\(name)")
        dump(app, "WALK: TAB \(label)")
    }

    /// The keyboard covers the native tab bar on iOS 26; dismiss it before
    /// tapping another tab (the app itself also drops focus when parsing).
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons["完成"].firstMatch
        if done.exists {
            done.tap()
        } else {
            app.scrollViews.firstMatch.swipeDown()
        }
        sleep(1)
    }

    private func setAppearance(
        _ app: XCUIApplication,
        option: String
    ) {
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '深色模式'")
        ).firstMatch
        if row.waitForExistence(timeout: 6) {
            row.tap()
            sleep(1)
        } else {
            let textRow = app.staticTexts["深色模式"].firstMatch
            if textRow.exists {
                textRow.tap()
                sleep(1)
            }
        }
        let optionButton = app.buttons[option].firstMatch
        if optionButton.waitForExistence(timeout: 3) {
            optionButton.tap()
        } else {
            let optionText = app.staticTexts[option].firstMatch
            if optionText.exists {
                optionText.tap()
            }
        }
        sleep(2)
    }

    private func firstAlbumCard(_ app: XCUIApplication) -> XCUIElement? {
        let match = app.buttons.matching(
            NSPredicate(format: "label MATCHES '.*[0-9]{4}-[0-9]{2}-[0-9]{2}.*'")
        ).firstMatch
        return match.exists ? match : nil
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists {
            back.tap()
            sleep(2)
        }
    }

    // MARK: - Capture / dump

    private func capture(_ app: XCUIApplication, _ name: String) {
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

    private func dump(_ app: XCUIApplication, _ label: String) {
        print("=== \(label) ===")
        print(app.debugDescription)
        print("=== END \(label) ===")
    }
}
