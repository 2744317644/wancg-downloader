# Review swarm — wnacg iOS v1.22.0

- Repo: `E:\Code\manga-downloader` · branch `main` · HEAD `f605732` (= `v1.22.0`, remote tag present)
- Scope: `git diff v1.21.4..HEAD -- ios/Sources ios/UITests ios/project.yml .github/workflows README.md WORKLOG.md`
  (14 files, +534/−132; `README.md` unchanged)
- Method: read-only static review from the diff plus full surrounding source. Four skill roles (intent/regression,
  security/privacy, performance/reliability, contracts/coverage) were executed by one reviewer because this session's
  delegation depth is 0; no files were edited, no builds or git writes were performed.
- Limits: no Xcode/Simulator on this Windows host, so nothing was compiled or run; no screenshot inspection. All
  findings below are source/CI-config evidence only. Visual-contrast claims were deliberately not made.

Intent packet used: v1.22.0 = UI polish (unified `AppBackground`, home skeleton, detail CTA hierarchy, paste button,
keyboard dismissal on parse, settings about link) + a full-app UI walkthrough test. Invariants: iOS 17 compatibility,
native iOS 26 Liquid Glass `TabView`, category infinite scroll + automatic load, reader close returns with the tab bar
already visible, downloads/favorites/history flows unchanged, Release build + all UI tests in CI.

## Summary

| # | Finding | Category | Severity | Confidence |
| - | ------- | -------- | -------- | ---------- |
| F1 | UI tests have no automatic trigger (stale branch + manual dispatch only) | contracts | medium | high |
| F2 | Network/sleep-driven walkthrough shares the release-gating suite with the category 429-stress test | reliability | medium | high |
| F3 | Headline v1.22.0 fix and new paste control have no assertion; walkthrough silently skips steps | contracts | medium | high |
| F4 | Simulator selection always picks the newest runtime — iOS 17/18 runtime coverage removed | contracts | medium | high |
| F5 | Paste button: silent no-op on empty/denied clipboard, ~30 pt tap target | reliability | low | high/med |
| F6 | Home “N 部” shows the preview count next to “更多”, reading as the category total | regression | low | high |
| F7 | Release notes / WORKLOG overstate what the new walkthrough covers | contracts | low | high |

## Findings

### F1 — The UI tests only run when someone remembers to dispatch them (`redesign/category-ui` is stale)

- **Where:** `.github/workflows/ui-preview.yml:6-10` (trigger), `:90-104` (`xcodebuild test`);
  `.github/workflows/ios.yml:3-6, 31-46` (Release build only, no test step);
  `ios/project.yml:147-150` (scheme test action correctly includes `WnacgDownloaderUITests`).
  `origin/redesign/category-ui` tip is `0eed7aa` (“bump to 1.21.0”), already merged into `main`.
- **Category / severity / confidence:** contracts · medium · high.
- **Why it matters:** the only workflow that runs UI tests is triggered by a push to a merged v1.21.0 branch (which
  will never fire again) or by `workflow_dispatch`. A commit can land on `main`, the Release IPA workflow can build and
  upload an artifact, and a tag can be cut without a single UI test executing. The new full-app walkthrough is presented
  as the v1.22.0 QA evidence, but nothing in the pipeline requires it to run. The stated invariant “CI … runs all UI
  tests” is therefore manual-only, not automatic.
- **Recommended follow-up:** add a `push: branches: [main]` and/or `push: tags: ['v*']` trigger to the UI workflow (or
  `workflow_run` after “Build iOS IPA”), and put “dispatch UI workflow from the release commit and attach its artifact”
  into the release checklist until then. Keep `workflow_dispatch` for ad-hoc screenshots.
- **Confidence:** high on the config facts; medium on whether the release checklist already assumes a manual dispatch
  (no such requirement is recorded in the repo).

### F2 — The new walkthrough burns the shared live-site budget in the same blocking suite as the 429 regression test

- **Where:** `ios/UITests/AppWalkthroughUITests.swift:16-113` (home load/refresh, real 解析 request, category, detail,
  search; `sleep(14)` at :48, `sleep(8)` at :82/:113, etc.); `ios/UITests/CategoryScreenUITests.swift:161-201`
  (three load-more stress rounds against the same site); `.github/workflows/ui-preview.yml:90-104` runs both in one
  `xcodebuild test` on one simulator.
- **Category / severity / confidence:** reliability · medium · high.
- **Why it matters:** v1.21.1/v1.21.2/v1.21.3 existed because this site rate-limits bursts (HTTP 429). The walkthrough
  now issues a rapid sequence of real requests (home, refresh, parse, category, detail, detail preview, search), and
  XCTest typically runs `AppWalkthroughUITests` before `CategoryScreenUITests` in the same job, so the category
  auto-load assertion — the regression that must never come back — runs against an IP that was just exercised. A 429 or
  slow page turns that release-gating test red, and the failure will look like an app regression. Fixed sleeps also
  make the new test the most timing-fragile part of the suite.
- **Recommended follow-up:** keep `CategoryScreenUITests` as the release gate and move the walkthrough to a separate
  scheme/target (manual or nightly, `continue-on-error`), or gate its network steps behind a launch argument. Where
  possible replace `sleep` with `waitForExistence`/polling on UI state.

### F3 — The release’s only behavioral fix is unasserted, and the walkthrough passes when its steps silently vanish

- **Where:** `ios/Sources/ContentView.swift:34-41` (keyboard “完成” toolbar), `:100-105` (focus drop before parse);
  `ios/UITests/AppWalkthroughUITests.swift:42-48` (`if linkField.waitForExistence` / `if parseButton.waitForExistence`
  guard the only keyboard/parse coverage), `:65, :79, :106` (same pattern for history/category/search),
  `:147-156` (`dismissKeyboard` taps the app’s own “完成”, so it works even if the app regressed).
- **Category / severity / confidence:** contracts · medium · high.
- **Why it matters:** the “keyboard dismissal on parse” fix is the one behavior change in v1.22.0, and the new QA test
  cannot detect its regression: after 解析作品 it calls `dismissKeyboard()`, which will tap the newly added “完成” if the
  keyboard is still up. Because each flow is wrapped in `if … waitForExistence`, the test also stays green if the parse
  button, history link, category chips, or search field disappear — only the home chip load is a hard `XCTAssertTrue`.
  The new paste button has no test at all. Confidence in the release therefore rests on the screenshots, not on the test
  result.
- **Recommended follow-up:** assert `XCTAssertFalse(app.keyboards.firstMatch.exists)` right after tapping 解析作品, add a
  paste-button step (not required to hit the site), and make presence of the controls under test hard assertions rather
  than `if` guards (leave optional/exploratory steps documented as such).

### F4 — The UI job now always runs the newest iOS runtime; iOS 17/18 is never exercised

- **Where:** `.github/workflows/ui-preview.yml:40-88` (picks the highest available iOS runtime, prefers a “Pro” device);
  `ios/project.yml:5-6, 17, 70` (deployment target `17.0`); same Xcode 26.3 selection in `ios.yml:19-22`.
- **Category / severity / confidence:** contracts/compatibility · medium · high (facts), medium (impact).
- **Why it matters:** the base version used whatever `simctl` listed first (the workflow’s own comment says that was
  iOS 18.5); after this change the only automated UI execution is on iOS 26.x. The stated invariant “iOS 17 compatibility
  unchanged” and the shipping deployment target `17.0` now have zero runtime coverage — exactly where
  `#available(iOS 26)` branches, the Liquid Glass `TabView` fallback, and older UIKit/swiftUI behaviors differ. A
  release can be green on 26.2 and broken on 17/18.
- **Recommended follow-up:** make the job a small matrix — newest runtime for screenshots (as now) plus the oldest
  available runtime running at least `CategoryScreenUITests`; if a matrix is too expensive, add a second job on the
  oldest available iPhone runtime with the category test only.

### F5 — Paste button can look dead and is below the project’s own 44 pt touch standard

- **Where:** `ios/Sources/ContentView.swift:59-80` — the `粘贴` button reads `UIPasteboard.general.string` directly,
  sets `model.input` only when the trimmed string is non-empty, then always focuses the field; the label is
  `.font(.caption.weight(.medium))` with `.padding(.vertical, 6)` (~30 pt tall).
  Reference for the project standard: `ios/Sources/CategoryView.swift:590` (`frame(minHeight: 44)`) and
  `ios/UITests/CategoryScreenUITests.swift:78-81, 102-105` (asserts ≥43.5 pt on filter chips).
- **Category / severity / confidence:** reliability (accessibility/UX) · low · high (tap target, empty/denied no-op),
  medium (system paste-confirmation details).
- **Why it matters:** on an empty clipboard, or if the user declines the system paste confirmation that iOS may show for
  a direct pasteboard read, the button does nothing — no haptic, message, or disabled state — so it reads as broken.
  The tap target is below the 44 pt rule the codebase enforces elsewhere.
- **Recommended follow-up:** use SwiftUI `PasteButton`/`UIPasteControl` for the system paste affordance, or check
  `UIPasteboard.general.hasStrings` and give feedback on the empty/denied path; raise the hit area to ≥44 pt. Treat
  “paste” as filling the link field only when the content looks like a URL/ID (optional).

### F6 — “N 部” in home section headers is the preview count, not the category size

- **Where:** `ios/Sources/HomeView.swift:416` (`Text("\(section.albums.count) 部")`), fed by
  `displaySections` at `:344-355`; `section.albums` is only the cards parsed from the home block
  (`ios/Sources/HomeParser.swift`, `HomeSection.albums` + `moreURL`).
- **Category / severity / confidence:** regression (UI content) · low · high.
- **Why it matters:** the number sits immediately before “更多”, so “最新上架 6 部 ›” reads as “this category has six
  works”, while the category behind 更多 has hundreds. It also silently changes when 屏蔽 AI filters the preview, so the
  same section can show different totals between light/dark walks. It is new copy added in this release, not a
  pre-existing label.
- **Recommended follow-up:** either drop the number or label it as a preview (e.g. “本栏 6 部 / 更多”), or parse a real
  total only where the source provides one.

### F7 — QA docs claim walkthrough coverage that lives in the other test (or nowhere)

- **Where:** `docs/release-notes-v1.22.0.md:7` (“分类（筛选/自动加载）→ 详情 → 阅读器 … 逐屏截图”) and `:24`
  (“新增 `AppWalkthroughUITests`：… 阅读器开关”); `WORKLOG.md:13` (“→ 阅读器 →”) and `:19` (“走查同时确认分类页自动加载、
  阅读器返回底栏”). `ios/UITests/AppWalkthroughUITests.swift` contains no `开始阅读` / `reader-close-button` tap, no
  filter-chip tap, and no category scrolling (verified by grep); those checks exist in
  `ios/UITests/CategoryScreenUITests.swift:115-141, 161-201`. Dark-mode screenshots are only home/category/detail.
- **Category / severity / confidence:** contracts · low · high.
- **Why it matters:** the release notes are the QA record for a release cut from a host that cannot run the tests. If a
  future change drops or weakens `CategoryScreenUITests`, the docs suggest the walkthrough still covers the reader and
  auto-load. It also means the “reader returns with the tab bar visible” invariant is not exercised by the new test at
  all.
- **Recommended follow-up:** correct the two documents, and consider adding the reader open/close step to the
  walkthrough (it would then re-guard the v1.21.4 tab-bar invariant). `:25` already attributes those checks correctly
  to the existing test.

## Role coverage — checked and found clean

- **Security / privacy:** no new network endpoints, auth, storage, or permission changes. The only new trust-boundary
  touch is the clipboard read in F5 (user-initiated, content only inserted into the local link field, not logged);
  the new `Link` target is the project’s own GitHub releases page; workflow permissions remain `contents: read`; no
  secrets in the new test or workflow output. No security findings.
- **iOS 17 API surface:** all new calls in the diff are ≤ iOS 17 (`ContentUnavailableView`, `@FocusState`,
  `ToolbarItemGroup(placement: .keyboard)`, `.foregroundStyle(.tertiary)`, `Link`); the only iOS 26 API is the
  pre-existing `#available(iOS 26.0)` in `RootView.swift:40-44`, untouched.
- **Liquid Glass `TabView`:** `RootView.swift:9-45` is untouched; the diff adds no `.toolbar(.hidden, for: .tabBar)` and
  no tab-bar styling.
- **Category infinite scroll / automatic load:** `CategoryView.swift` changes are limited to the skeleton struct rename
  (`:352-360`) and the background (`:679-681`); `requestMore`, the lazy sentinel and the 1.1 s throttle are unchanged.
- **Reader close → tab bar visible:** `AlbumDetailView.swift:130-139` (`fullScreenCover`) is unchanged from v1.21.4; the
  CTA stays a `Button` labelled “开始阅读”, so `CategoryScreenUITests` still finds it.
- **Downloads / favorites / history flows:** no store, queue, or history code touched. `FavoritesView` changes only the
  button style (`:176`) and background (`:81-83`); `FilesView`/`HistoryView` only add `.background`; `SettingsView` only
  reads `Bundle.main` version/build and adds a `Link`; `ContentView` paste writes only `model.input`.
- **Version contract:** `ios/project.yml` sets `1.22.0 / 259` in all three places (app Info.plist, app settings, widget);
  `docs/release-notes-v1.22.0.md:28` matches; remote tag `v1.22.0` = `f605732`. No stale version strings found.

## Open questions

1. Is manual `workflow_dispatch` of the UI job the accepted release gate? If yes, F1 becomes a documentation item; if no,
   it is the most important item in this report.
2. Is the home “N 部” meant as “shown in this row” or “total in the category”? That decides whether F6 is a wording fix
   or a data-source fix.

## Optional follow-ups (not findings)

- `FilesView.swift:63-72` and `HistoryView.swift:71-97` put `AppBackground()` behind a populated `.insetGrouped` `List`
  without `.scrollContentBackground(.hidden)`, so the new background is only visible on the empty states. Harmless, but
  the added code does not do what a reader would expect; either add the modifier or drop the background on those screens.
- `AlbumDetailView.swift:209-224` duplicates the gradient-bar section header from `HomeView.swift:402-414`; if a third
  use appears, lift it into `Theme.swift` like `AppBackground`.

## Path forward

- **Fix before the next release:** wire the UI job into `main`/tags (F1) and split the walkthrough off the release-gating
  suite (F2). These are process changes, not app changes, and are cheap.
- **Fix soon:** add the missing keyboard/parse assertion and paste step (F3); add an older-runtime job (F4); correct the
  release notes/WORKLOG claims (F7).
- **Optional:** paste-button feedback/tap target (F5), home count wording (F6), Files/History background cleanup.
- **Blocking another release?** No code defect in v1.22.0 warrants blocking a re-release. The release *process* should
  not be repeated as-is: as of today the ship/no-ship UI signal is manual and the walkthrough is unassertive, so a
  regression could be released with a green-looking pipeline.
