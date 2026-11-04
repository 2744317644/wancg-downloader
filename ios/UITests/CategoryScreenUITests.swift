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

        // ---- load-more stress: this is the regression the user reported ----
        scrollToTop(app)
        sleep(1)
        // Reset the AI filter toggled above so it does not reduce the sample.
        if aiFilterOn, app.buttons["屏蔽 AI"].firstMatch.exists {
            app.buttons["屏蔽 AI"].firstMatch.tap()
            sleep(2)
        }

        var counts: [Int] = []
        var hitEnd = false
        var loadFailed = false
        for round in 0..<3 {
            let reachedFooter = scrollToFooter(app)
            XCTAssertTrue(reachedFooter, "footer not reachable in load-more round \(round)")
            if !reachedFooter { break }
            if let count = loadedAlbumCount(app) {
                counts.append(count)
                print("AUTO_LOAD_ROUND \(round) BEFORE COUNT \(count)")
            }
            if endReached(app) {
                hitEnd = true
                break
            }
            // IMPORTANT: never tap the footer button here. Scrolling to the
            // last row itself must trigger the next page automatically; that
            // is exactly the regression the user reported.
            var grew = false
            for attempt in 0..<10 {
                waitForFooterToSettle(app)
                if let errorText = loadMoreErrorText(app) {
                    print("LOAD_MORE_ERROR_ROUND \(round): \(errorText)")
                    capture(name: "ui-08-load-error-round-\(round)")
                    XCTFail("load-more failed in round \(round): \(errorText)")
                    loadFailed = true
                    break
                }
                _ = scrollToFooter(app)
                if let count = loadedAlbumCount(app),
                   let last = counts.last, count > last {
                    counts.append(count)
                    print("AUTO_LOAD_ROUND \(round) AFTER COUNT \(count) (attempt \(attempt))")
                    grew = true
                    break
                }
                if endReached(app) {
                    hitEnd = true
                    break
                }
                // Nudge the list so the last-row cells enter the lazy grid's
                // render window; this is the user's normal swipe-down gesture.
                app.swipeUp()
                sleep(1)
            }
            if loadFailed || hitEnd { break }
            XCTAssertTrue(
                grew,
                "scrolling to the last row did NOT auto-load the next page "
                    + "in round \(round) (only the footer button works)"
            )
            if !grew { break }
            capture(name: "ui-08-auto-load-round-\(round)")
        }
        print("AUTO_LOAD_COUNTS: \(counts) hitEnd=\(hitEnd)")
        if !hitEnd, !loadFailed, counts.count >= 2,
           let first = counts.first, let last = counts.last {
            XCTAssertGreaterThan(
                last, first,
                "album count should grow across automatic load-more rounds"
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
        let matches = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label MATCHES '.*(已加载|共) [0-9]+ 部.*'"
            )
        ).allElementsBoundByIndex
        for element in matches {
            if let value = parseLoadedCount(element.label) {
                return value
            }
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
