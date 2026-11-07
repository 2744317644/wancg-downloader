import XCTest

/// Visual/functional + load-more stress harness for the second-level listing
/// screen. Runs on a GitHub Actions macOS simulator (there is no local Xcode
/// on the Windows dev box), leaves PNG screenshots in the runner's temp
/// directory and prints the accessibility tree for layout checks.
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

        XCTAssertEqual(app.tabBars.count, 1, "expected exactly one native tab bar")
        XCTAssertEqual(
            app.staticTexts.matching(
                NSPredicate(format: "label MATCHES '.*[0-9]+ / [0-9]+.*'")
            ).count,
            0,
            "old pager counter must be gone"
        )

        // Scroll far enough to trigger the first load-more.
        app.swipeUp()
        sleep(3)
        app.swipeUp()
        sleep(4)
        capture(name: "ui-03-category-scrolled")
        print("ALBUM_CARDS_AFTER_SCROLL: \(albumCardCount(app))")

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
                translated.frame.height, 43.5,
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
        var aiFilterOn = false
        if aiChip.waitForExistence(timeout: 5) {
            XCTAssertGreaterThanOrEqual(
                aiChip.frame.height, 43.5,
                "AI filter chip touch target must be at least 44pt"
            )
            aiChip.tap()
            aiFilterOn = true
            sleep(3)
            capture(name: "ui-06-category-ai-filter")
        }

        // Third level: a cover must still push the detail screen, and the
        // reader must come back with the tab bar already in place (regression:
        // pushing the reader hid the tab bar and it animated back late).
        if let firstCard = firstAlbumCard(app) {
            firstCard.tap()
            if app.navigationBars["详情"].waitForExistence(timeout: 30) {
                sleep(5)
                capture(name: "ui-07-detail")
                let startReading = app.buttons["开始阅读"].firstMatch
                if startReading.waitForExistence(timeout: 10) {
                    startReading.tap()
                    let closeReader = app.buttons["reader-close-button"].firstMatch
                    if closeReader.waitForExistence(timeout: 60) {
                        sleep(6)
                        let frame = closeReader.frame
                        print(
                            "READER_CLOSE_FRAME: x=\(frame.minX) " +
                            "y=\(frame.minY) w=\(frame.width) h=\(frame.height) " +
                            "screen=\(app.windows.firstMatch.frame)"
                        )
                        // The close button now exposes its full 44pt hit
                        // frame (not just the glass icon glyph), so its top
                        // edge should line up with the Dynamic Island bottom
                        // at about 48pt.
                        XCTAssertGreaterThanOrEqual(
                            frame.minY, 44,
                            "reader chrome should start below the Dynamic Island"
                        )
                        XCTAssertLessThan(
                            frame.minY, 60,
                            "reader chrome should align with the Dynamic Island bottom"
                        )
                        capture(name: "ui-10-reader")
                        closeReader.tap()
                        sleep(2)
                        XCTAssertTrue(
                            app.tabBars.firstMatch.exists,
                            "tab bar must be present right after closing the reader"
                        )
                        capture(name: "ui-11-after-reader")
                    } else {
                        XCTFail("reader screen did not present")
                    }
                }
                app.navigationBars.buttons.firstMatch.tap()
                sleep(2)
            }
        }

        // ---- load-more stress: this is the regression the user reported ----
        scrollToTop(app)
        sleep(1)
        // Reset the AI filter toggled above so it does not reduce the sample.
        if aiFilterOn, app.buttons["屏蔽 AI"].firstMatch.exists {
            app.buttons["屏蔽 AI"].firstMatch.tap()
            sleep(2)
        }

        // Count is exposed by the footer's accessibility label even when the
        // footer is off-screen (the outer VStack is non-lazy), so the test can
        // observe automatic loading without chasing an ever-moving footer.
        var counts: [Int] = []
        if let baseline = loadedAlbumCount(app) {
            counts.append(baseline)
            print("AUTO_BASELINE_COUNT \(baseline)")
        }
        var loadFailed = false
        for round in 0..<3 {
            if loadMoreErrorText(app) != nil {
                XCTFail("load-more error before round \(round)")
                loadFailed = true
                break
            }
            // Swipe down like a normal user. No footer button is tapped.
            for _ in 0..<4 {
                app.swipeUp()
                usleep(600_000)
            }
            var grew = false
            for attempt in 0..<10 {
                if let errorText = loadMoreErrorText(app) {
                    print("AUTO_LOAD_ERROR_ROUND \(round): \(errorText)")
                    capture(name: "ui-08-auto-load-error-round-\(round)")
                    XCTFail("load-more failed in round \(round): \(errorText)")
                    loadFailed = true
                    break
                }
                if let count = loadedAlbumCount(app),
                   let last = counts.last, count > last {
                    counts.append(count)
                    print("AUTO_LOAD_ROUND \(round) COUNT \(count) (attempt \(attempt))")
                    grew = true
                    break
                }
                if endReached(app) { break }
                app.swipeUp()
                usleep(700_000)
            }
            if loadFailed { break }
            if !grew, endReached(app) { break }
            XCTAssertTrue(
                grew,
                "scrolling to the end did NOT auto-load the next page in "
                    + "round \(round) (only the footer button works)"
            )
            if !grew { break }
            capture(name: "ui-08-auto-load-round-\(round)")
        }
        print("AUTO_LOAD_COUNTS: \(counts)")
        if !loadFailed, counts.count >= 2,
           let first = counts.first, let last = counts.last {
            XCTAssertGreaterThan(
                last, first,
                "album count should grow while scrolling without tapping "
                    + "the footer button"
            )
        }

        // ---- pull to refresh must recover without an error banner ----
        scrollToTop(app)
        sleep(1)
        app.swipeDown()
        sleep(6)
        XCTAssertNil(
            loadMoreErrorText(app),
            "pull-to-refresh left an error message on screen"
        )
        capture(name: "ui-09-refresh")

        dumpTree(app, label: "CATEGORY TREE (after interactions)")
    }

    // MARK: Load-more helpers

    private func scrollToFooter(_ app: XCUIApplication) -> Bool {
        for _ in 0..<20 {
            if footerOnScreen(app) != nil { return true }
            app.swipeUp()
            usleep(500_000)
        }
        return footerOnScreen(app) != nil
    }

    private func footerOnScreen(_ app: XCUIApplication) -> XCUIElement? {
        guard let footer = footerElement(app) else { return nil }
        return isOnScreen(footer, in: app) ? footer : nil
    }

    /// Off-screen SwiftUI content can still exist in the accessibility tree,
    /// so `exists` alone is not enough to decide we reached the footer.
    private func isOnScreen(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width > 0, frame.height > 0 else { return false }
        return frame.intersects(app.windows.firstMatch.frame)
    }

    private func footerElement(_ app: XCUIApplication) -> XCUIElement? {
        let loadMore = app.buttons["load-more-button"].firstMatch
        if loadMore.exists { return loadMore }
        let combined = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS '正在加载更多' OR "
                    + "label BEGINSWITH '已经到底了' OR "
                    + "label CONTAINS '加载失败'"
            )
        ).firstMatch
        return combined.exists ? combined : nil
    }

    private func endReached(_ app: XCUIApplication) -> Bool {
        app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH '已经到底了'")
        ).firstMatch.exists
    }

    private func footerIsLoading(_ app: XCUIApplication) -> Bool {
        app.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS '正在加载更多' OR label CONTAINS '正在筛选'"
            )
        ).firstMatch.exists
    }

    private func waitForFooterToSettle(_ app: XCUIApplication) {
        for _ in 0..<12 {
            if !footerIsLoading(app) { break }
            sleep(1)
        }
        sleep(1)
    }

    private func loadMoreErrorText(_ app: XCUIApplication) -> String? {
        let stack = app.staticTexts
        for index in 0..<stack.count {
            let label = stack.element(boundBy: index).label
            if label.contains("加载失败") || label.contains("HTTP 4")
                || label.contains("限流") || label.contains("超时") {
                return label
            }
        }
        if app.buttons["加载失败，点击重试"].exists {
            return "加载失败，点击重试"
        }
        return nil
    }

    private func loadedAlbumCount(_ app: XCUIApplication) -> Int? {
        // Read targeted firstMatch queries only; enumerating the whole tree
        // while a page is being appended invalidates snapshots mid-iteration.
        let button = app.buttons["load-more-button"].firstMatch
        if button.exists, let value = parseLoadedCount(button.label) {
            return value
        }
        let endText = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH '已经到底了'")
        ).firstMatch
        if endText.exists, let value = parseLoadedCount(endText.label) {
            return value
        }
        let loadingText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '已加载'")
        ).firstMatch
        if loadingText.exists, let value = parseLoadedCount(loadingText.label) {
            return value
        }
        return nil
    }

    private func parseLoadedCount(_ label: String) -> Int? {
        let pattern = "(?:已加载|共)\\s*([0-9]+)\\s*部"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(label.startIndex..<label.endIndex, in: label)
        guard let match = regex.firstMatch(in: label, range: range),
              let valueRange = Range(match.range(at: 1), in: label) else {
            return nil
        }
        return Int(label[valueRange])
    }

    // MARK: Generic helpers

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
        for _ in 0..<6 where !app.buttons["翻译"].firstMatch.exists {
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
