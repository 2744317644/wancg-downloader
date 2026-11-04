# SwiftUI runtime performance audit — wnacg iOS 1.22.0

| | |
| --- | --- |
| Repository | `E:\Code\manga-downloader` |
| Commit | `f605732e279b54a91234990294c4b5882f164f27` (`main`), v1.22.0 / build 259 |
| Audit date | 2026-11-04 |
| Scope | `HomeView`, `AlbumCardView`/`HomeCover`, `CategoryView` (feed model, grid, chips, sentinel/prefetch), `AlbumDetailView`, `ReaderView`/`ReaderImageStore`/`ReaderScrollController`, `FilesView`, `ContentView`, `HistoryView`, `FavoritesView`, `CoverImageStore`+`CoverLimiter`, `AppModel`/`DownloadQueue`, Live Activity managers, plus `HTMLParser`/`HomeParser`/`LibraryStore` where they sit in the same hot paths |
| Method | Code-first review following `swiftui-performance-audit` (`references/code-smells.md`, `references/optimizing-swiftui-performance-instruments.md`, WWDC23 "Demystify SwiftUI performance"). Read-only: no edits, no build, no Instruments, no simulator capture on this host. |
| Confidence model | **High** = the code path and its cost are proven by reading, only the magnitude is inferred. **Medium** = the mechanism is likely but depends on runtime conditions (cache state, library size, device). **Low** = hypothesis that needs a trace. |

## Summary

The user-visible "hitch when a page of covers is appended while scrolling" is best explained by two main-thread mechanisms that both fire at append time:

1. **The whole feed page is parsed on the MainActor**, and `HTMLParser` constructs a brand-new `NSRegularExpression` for every `first`/`all`/`matches`/`clean` call — roughly a dozen regex compilations per album card. The parse runs in `CategoryFeedModel.load` / `HomeFeedModel.load` *after* the `await` returns, i.e. inside a frame, right before the new covers appear.
2. **On the warm path, cover thumbnails are decoded lazily on the render path.** The network path already downsamples on a background queue with `kCGImageSourceShouldCacheImmediately`, but the disk-cache path (`readThumbnail`) returns `UIImage(contentsOfFile:)`, so a page of 20 disk hits can decode 20 JPEGs in one frame instead of on the worker that read the files.

A separate class of cost sits in downloads: every URLSession chunk publishes `downloadProgress`/`downloadSpeed`/`downloadETA` on `AppModel`, which the entire download screen and the album detail screen observe, and every chunk also schedules a Live Activity update. Favorites and Files have main-thread O(favorites × files) work with regex-based filename normalization, plus `FileManager` stat calls inside a sort comparator.

List identity is largely fixed (see *Verified landed fixes*); the remaining invalidation cost is derived collections rebuilt in `body` and broad `@ObservedObject`/`@EnvironmentObject` reads. All findings below are code-backed; none is trace-backed, so magnitudes are hypotheses and each finding states what evidence would confirm it.

## Top issues (ordered by impact)

| # | Finding | Location (file:line) | Likely cause | Proposed fix | Effort | Confidence |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Feed page append runs HTML parsing + per-call regex compilation on the MainActor | `ios/Sources/CategoryView.swift:115`, `ios/Sources/HomeView.swift:29`, `ios/Sources/HomeParser.swift:86-146`, `ios/Sources/HTMLParser.swift:4-60` | `@MainActor` model parses fetched HTML in-line; every `HTMLParser` call compiles a fresh `NSRegularExpression` (~13 per card) | Cache compiled regexes; move `HomeParser.parse/parseCards` to `Task.detached` and assign results on the MainActor | S–M | High (path) / Medium (ms) |
| 2 | Disk-cached cover thumbnails decode lazily on the main/render path | `ios/Sources/HomeView.swift:142-160`, `ios/Sources/HomeView.swift:212-221` | `UIImage(contentsOfFile:)` is not force-decoded, unlike the network path which uses `kCGImageSourceShouldCacheImmediately` | Reuse the `CGImageSource` + `CreateThumbnailAtIndex` + `ShouldCacheImmediately` approach in `readThumbnail` | S | Medium-High |
| 3 | Download progress fan-out: per-chunk `@Published` storms, whole-screen invalidation, Live Activity update per chunk | `ios/Sources/WnacgClient.swift:386-398`, `ios/Sources/AppModel.swift:211-243`, `ios/Sources/AppModel.swift:296-309`, `ios/Sources/ContentView.swift:5`, `ios/Sources/AlbumDetailView.swift:377-430`, `ios/Sources/DownloadLiveActivityManager.swift:51-63` | No throttling between URLSession progress and `@Published` UI state; Live Activity `update` builds a `Task` per callback; detail/download screens observe the whole `AppModel` | Throttle progress publishing to ~4–5 Hz (and on ≥0.5 % change); throttle Live Activity to ~1 Hz/1 %; extract progress into a small observable so big bodies stop depending on it; move zip validate/temp-dir cleanup off the MainActor | M | Medium-High |
| 4 | Favorites tab: `reconcile` is O(favorites × files) with regex normalization per file, on the MainActor, every appearance | `ios/Sources/LibraryStore.swift:139-151`, `ios/Sources/LibraryStore.swift:112-123`, `ios/Sources/FavoritesView.swift:107-109`, `ios/Sources/AlbumDetailView.swift:469-471` | `file(_:matches:)` calls `HTMLParser.safeFilename` for the *title* inside a per-file loop; `allFiles()` enumerates Documents on main; same helper used by the download tap path | Normalize the title once per favorite and compare against a pre-built `Set` of normalized base names; run once per launch/favorites change; build the set off-main | S | High (path) / Medium (magnitude) |
| 5 | Files tab: `stat` inside the sort comparator, directory enumeration on main, `PDFDocument(url:)` on main | `ios/Sources/FilesView.swift:8-25`, `ios/Sources/FilesView.swift:155-159`, `ios/Sources/FilesView.swift:180-185` | `size`/`date` are computed properties that call `attributesOfItem`; `load()` sorts by `date` → O(n log n) stats; PDF is parsed synchronously when the sheet's `StateObject` initializes | Capture size/date once during enumeration; sort on stored values; cache `ByteCountFormatter`; load `PDFDocument` asynchronously with a progress state | S–M | High (stats) / Medium-High (PDF) |
| 6 | Reader: one `Task` + 4 `@Published` writes per scroll tick (slider re-render), and a 12-image cache against a 10-page prefetch window | `ios/Sources/ReaderScrollController.swift:14-36`, `ios/Sources/ReaderScrollController.swift:55-71`, `ios/Sources/ReaderView.swift:343-383`, `ios/Sources/ReaderView.swift:118`, `ios/Sources/ReaderView.swift:192-219` | KVO handlers hop to `@MainActor` with a new `Task` per event; `update()` writes `contentHeight`/`viewportHeight`/`isScrollable`/`progress` unconditionally; `countLimit = 12` vs 10 prefetched pages + current + previous | Compare before assigning, coalesce to at most one update per frame, drop the `Task` hop; raise `countLimit` to ≥24 (or budget by cost) | M | Medium |
| 7 | A 120 Hz `CADisplayLink` runs permanently by default and does nothing | `ios/Sources/HighRefreshRateController.swift:15-48`, `ios/Sources/SettingsView.swift:15`, `ios/Sources/WnacgApp.swift:26-29` | `applySavedSetting()` turns it on when unset; an empty 120 Hz display link keeps the main run loop awake and prevents display/CPU idle on ProMotion devices | Remove it (Info.plist already has `CADisableMinimumFrameDurationOnPhone`) or only run it while scrolling; default the toggle off | S | High (mechanism) / Medium (impact) |
| 8 | History/Favorites rebuild derived collections in `body` (grouping + sort + 2–4 filter passes) on every keystroke | `ios/Sources/HistoryView.swift:20-43`, `ios/Sources/FavoritesView.swift:26-40` | `sections`, `filteredItems`, `downloaded`, `pending` are computed properties; `noMatches` recomputes the same filters; search text is `@State` so each keystroke re-evaluates the body | Compute once per body (or derive in the store on data change, debounced), pass values down; keep `filteredItems` to one pass | M | High (work) / Low-Medium (impact) |

## Findings

### 1. Feed HTML is parsed on the MainActor and `HTMLParser` compiles a regex per call

- **Symptom**: a visible hitch (1–3 dropped frames, more on older devices) when the next category page is appended while scrolling; the skeleton shimmer on first load stalls while the home page is being parsed.
- **Likely cause**: `CategoryFeedModel.load` is `@MainActor` and calls `HomeParser.parseCards(html)` directly after the `await` at `ios/Sources/CategoryView.swift:115`; `HomeFeedModel.load` does the same at `ios/Sources/HomeView.swift:29`. `HTMLParser.first`/`all`/`matches` each do `try? NSRegularExpression(pattern:options:)` for every call (`ios/Sources/HTMLParser.swift:5-8`, `:19-22`, `:38-41`), and `clean` does two `replacingOccurrences(options: .regularExpression)` calls plus `decodeEntities`'s own regex (`ios/Sources/HTMLParser.swift:51-60`, `:72`). Per album card, `parseCards` makes 7 `first` calls and 2 `clean` calls (each `clean` = 2 regex replaces + 1 entity regex) → **≈13 regex constructions per card**, with the same patterns repeated for every card (and `HomeParser.parse` repeats the same block pattern for every section). A 20-card category page is ~260 compilations; the home page is easily 1,000+. Compilation dominates the matching cost for these small patterns.
- **Evidence**: `ios/Sources/HomeParser.swift:86-146` (card loop), `ios/Sources/HTMLParser.swift:4-60` (no cache of any kind), `ios/Sources/CategoryView.swift:112-146` (parse + several `@Published` writes — `albums`, `loadedPageCount`, `hasMore`, `didLoadOnce`, `visibleAlbums` — on the MainActor in the same synchronous block). This is also the moment the grid changes, which is why the cost is attributed to the append rather than to layout.
- **Fix**: (a) cache compiled `NSRegularExpression` instances keyed by pattern (a lock-guarded dictionary, or hoist the fixed patterns into `static let`s); replace `clean`'s two regex replaces with those cached instances, and make `safeFilename`'s two patterns static. This alone collapses ~260 compilations to ~8 per page. (b) Parse off the MainActor:
  ```swift
  let parsed = await Task.detached(priority: .userInitiated) {
      HomeParser.parseCards(html)
  }.value
  guard token == generation else { return }
  ```
  For the home feed the same pattern with `HomeParser.parse(html)`. Effort S for (a), S for (b).
- **Confidence**: High that the work is on the main thread and that regexes are recompiled; Medium on the absolute milliseconds — stated as "one to a few frames per append, likely worse in Debug".
- **What would confirm it**: Instruments Time Profiler during a category scroll-to-append, inspection range set on the hitch; expect samples in `NSRegularExpression`/ICU init and `HomeParser.parseCards`/`HTMLParser.clean` on the main thread, with no corresponding "Long View Body Update" (this is not body work — it is a main-thread block between frames). Add a temporary `os_signpost` around the parse, or compare hitch count with (a) applied only.
- **Validation**: see plan steps 2 and 3.

### 2. Disk-cached cover thumbnails are decoded lazily on the render path

- **Symptom**: the second visit to a category (or any feed whose thumbnails are already on disk) hitches in a burst right when the appended covers appear; first visit (network path) is smoother.
- **Likely cause**: `CoverImageStore.image(for:)` checks `NSCache`, then always spawns a detached utility task that calls `readThumbnail` (`ios/Sources/HomeView.swift:147-157`). `readThumbnail` does `fileExists` + `UIImage(contentsOfFile:)` (`ios/Sources/HomeView.swift:212-221`). `UIImage(contentsOfFile:)` returns an image backed by an `ImageIO` source whose pixels are decoded at first draw, not at load; the network path (`prepareThumbnail` → `downsample`) sets `kCGImageSourceShouldCacheImmediately: true` (`ios/Sources/HomeView.swift:234-239`), so it is forced-decoded on the worker. The disk path is the one that lost that flag. When 20 covers are appended, their detached tasks complete within a few ms of each other, the MainActor receives 20 cache inserts and 20 `HomeCover` state updates, and the JPEG decode lands in the same frame(s) as the grid's first render.
- **Evidence**: `ios/Sources/HomeView.swift:212-221` vs `ios/Sources/HomeView.swift:230-246`; `ios/Sources/AlbumCardView.swift:95-108` (each card's `.task` awaits the store); `ios/Sources/HomeView.swift:129-130` (`countLimit = 120`, `totalCostLimit = 48 MB` — so disk hits are expected after memory eviction or a relaunch).
- **Fix**: make `readThumbnail` produce a decoded image, mirroring `downsample`:
  ```swift
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: 360,
  ]
  guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  else { return nil }
  return UIImage(cgImage: cg, scale: 1, orientation: .up)
  ```
  This also removes the extra `fileExists` stat (a missing file makes `CGImageSourceCreateWithURL` return nil). Second-order improvement: don't spawn the detached read at all for cards that disappear before the 80 ms debounce — already handled by `.task` cancellation, but the read itself is not cancelled; the forced-decode fix makes each read cheap either way. Effort S, low risk.
- **Confidence**: Medium-High. The inconsistency between the two paths is proven; whether iOS decodes at `Image(uiImage:)` layout time or at CA commit time depends on the OS, and either way it is not on the worker that read the file.
- **What would confirm it**: record a warm-thumbnail category append (scroll through the category once, pop, re-enter, scroll to the bottom) with Time Profiler + the SwiftUI instrument; look for `CGImageSourceCreateImageAtIndex`/ImageIO frames on the main thread (or inside `CA::Transaction::commit`) aligned with the append, and for 20 cover updates in one `Update Group`.
- **Validation**: plan step 3, second pass.

### 3. Download progress fan-out dominates CPU during downloads

- **Symptom**: while a ZIP/PDF download runs, the download screen and (if the user started from an album) the detail screen re-render continuously; the app heats up on long downloads. On the detail screen the progress card usually shows nothing because of the visibility gate (see below), so the cost buys no UI.
- **Likely cause**: `FileDownloader`'s `didWriteData` dispatches every chunk to main (`ios/Sources/WnacgClient.swift:386-398`). `AppModel`'s handler then creates a `Task { @MainActor }` per chunk and calls `updateDownloadMetrics`, which writes `downloadProgress`, then `downloadSpeed` and `downloadETA` unconditionally (`ios/Sources/AppModel.swift:211-243`, `:300-309`). The same callback calls `DownloadLiveActivityManager.update` (`ios/Sources/AppModel.swift:305-307`), which builds new `ActivityContent` and starts another `Task` for `activity.update` per chunk (`ios/Sources/DownloadLiveActivityManager.swift:51-63`). `ContentView` observes the whole `AppModel` (`@ObservedObject var model: AppModel`, `ios/Sources/ContentView.swift:5`) and its body reads `preview`, `isBusy`, `status`, `queue`, `downloadProgress`, `pdfProgress`, `downloadSpeed`, `downloadETA`, `zipURL`, `pdfURL` — so every chunk invalidates the entire screen. `AlbumDetailView` observes the same object plus three other stores (`ios/Sources/AlbumDetailView.swift:38-41`) and reads `downloadModel.downloadProgress`/`status` inside `downloadStatus` (`:377-430`). PDF generation adds one main-queue hop and one Live Activity update **per page** (`ios/Sources/PDFBuilder.swift:44-47` → `ios/Sources/AppModel.swift:346-355`), i.e. hundreds for a long album. Also on the MainActor: `ZipExtractor.validate(downloaded)` (`ios/Sources/AppModel.swift:311`) parses the zip central directory, and the `defer` cleanup removes the whole extracted temp directory (one file per page) at `ios/Sources/AppModel.swift:324-330`.
- **Evidence**: no throttling exists anywhere between the delegate callback and `@Published`/ActivityKit; the 0.35 s window in `updateDownloadMetrics` only gates the *speed math*, not the assignments. The detail progress card's condition `downloadModel.input == album.pageURL.absoluteString` is false when the download was started from the detail screen, because `enqueue` → `startQueued` → `parse(value:)` never assigns `input` (`ios/Sources/AppModel.swift:166-209`, `:107-115`) — so the detail body pays for progress updates it does not display.
- **Fix**: (a) throttle at the source: in `updateDownloadMetrics`, keep a `lastPublishedAt`/`lastPublishedValue` and only assign `downloadProgress` when the change is ≥0.5 % or 250 ms have passed; publish `downloadSpeed`/`downloadETA` at most every 0.5 s. (b) Throttle the Live Activity: skip `update` unless progress moved ≥1 % or the status string changed, and let `DownloadLiveActivityManager` coalesce (one pending update at a time) instead of a `Task` per call. (c) Low-risk structural: extract `downloadProgressCard` into a child view that takes the model, then stop reading progress values in `ContentView.body` (pass a bool/status instead), so progress updates invalidate only the small card. (d) Run `ZipExtractor.validate` and the temp-directory cleanup in `Task.detached` (validate is a cheap parse but scales with the archive; cleanup scales with page count). (e) Fix the detail gate to use `downloadModel.activeAid == album.aid || downloadModel.preview?.aid == album.aid`, so the visible card and the invalidation agree. Effort S for (a)+(b)+(d)+(e), M for (c).
- **Confidence**: High for the fan-out and the per-chunk Task/ActivityKit calls; Medium for the visible-jank magnitude (a large part of the cost is off-screen body evaluation, which is measurable but not always user-visible).
- **What would confirm it**: Instruments Time Profiler + "Update Groups" during a 30–60 s ZIP download: count ContentView body evaluations per second and correlate with `URLSessionDownloadDelegate.didWriteData`; count `activity.update` calls per second in Console (`ActivityKit` subsystem) or via a temporary counter. On the album detail screen, confirm the progress card is absent while the updates still happen.
- **Validation**: plan step 4.

### 4. Favorites tab does O(favorites × files) regex work on the MainActor, every appearance

- **Symptom**: switching to the Favorites tab hangs for a noticeable fraction of a second (worse with more favorites/files); tapping "download" on a detail page can also stall before the queue responds.
- **Likely cause**: `FavoritesView.onAppear` calls `downloads.reconcile(with: favorites.items)` on every appearance (`ios/Sources/FavoritesView.swift:107-109`). `reconcile` enumerates Documents (`DownloadFolders.allFiles()` → recursive `FileManager.enumerator` on main, `ios/Sources/DownloadFolders.swift:29-48`), then for each favorite not in `downloadedAids` runs `files.contains(where: { file($0, matches: favorite.title) })` (`ios/Sources/LibraryStore.swift:139-151`). `file(_:matches:)` calls `normalizedTitle(title)` — `HTMLParser.safeFilename` → two `replacingOccurrences(..., .regularExpression)` plus trimming (`ios/Sources/LibraryStore.swift:112-123`, `ios/Sources/HTMLParser.swift:116-130`) — **once per file**, although it only depends on the favorite. Undownloaded favorites never match, so a library with e.g. 200 favorites and 200 files does ~80,000 regex compilations per visit (200 × 200 × 2), or roughly 0.5–2 s of main-thread work. `DownloadHistory.hasDownloadedFile(matching:)`, used by the download tap (`ios/Sources/AlbumDetailView.swift:469-471`), repeats the same per-file normalization.
- **Evidence**: as above. There is no `didReconcile` guard, no off-main work, and no memoized normalized-name set.
- **Fix**: normalize once per query and compare with a set:
  ```swift
  private func normalizedNames() -> Set<String> {
      Set(DownloadFolders.allFiles().map {
          $0.deletingPathExtension().lastPathComponent.lowercased()
      })
  }

  func reconcile(with favorites: [FavoriteManga]) {
      guard !favorites.isEmpty else { return }
      let names = normalizedNames()                    // one enumeration
      var changed = false
      for favorite in favorites where !downloadedAids.contains(favorite.aid) {
          let target = normalizedTitle(favorite.title) // once per favorite
          if !target.isEmpty, names.contains(target) {
              downloadedAids.insert(favorite.aid)
              changed = true
          }
      }
      if changed { save() }
  }
  ```
  and reuse `names` for `hasDownloadedFile`. Only reconcile once per launch or when `favorites.items` changes (a `didReconcile` flag or a `favoritesRevision`), and consider building `names` in a detached task. Effort S.
- **Confidence**: High that the loop is quadratic with a regex per iteration and runs on main; Medium on how many favorites the affected users have.
- **What would confirm it**: seed ~200 favorites and ~200 files in the simulator container (plan step 1), record the Favorites tab selection with the Hangs instrument (default threshold 250 ms) and Time Profiler; expect a hang whose heaviest frames are `HTMLParser.safeFilename`/`NSRegularExpression` and `FileManager` enumeration.
- **Validation**: plan step 5.

### 5. Files tab: `stat` inside the sort comparator, main-thread enumeration, synchronous `PDFDocument` load

- **Symptom**: the Files tab takes a moment to populate with a large Downloads folder; rows can stutter while scrolling; opening a large PDF sheet freezes the UI while the file is parsed.
- **Likely cause**: `DownloadedFile` stores only the URL; `size` and `date` are computed properties that call `attributesOfItem` each time (`ios/Sources/FilesView.swift:8-25`). `load()` maps then `.sorted { $0.date > $1.date }` (`ios/Sources/FilesView.swift:155-159`) → each sort comparison performs two `attributesOfItem` calls, i.e. O(n log n) stats for n files, plus two more per visible row in `row(_:)` (`:113-153`). `load()` runs on `.onAppear` every time the tab appears, on every `.downloadsChanged` notification, and on the `hideZIP` toggle even though that only needs a re-filter (`:98-109`). `PDFEditorModel.init` creates `PDFDocument(url:)` synchronously on the MainActor (`ios/Sources/FilesView.swift:180-185`), so a 300 DPI album PDF (tens to hundreds of MB) is opened inside the sheet presentation. `ByteCountFormatter.string(fromByteCount:countStyle:)` is invoked for every row (`:125-127`) with no shared formatter instance to configure once.
- **Evidence**: as above; `DownloadFolders.allFiles()` returns only URLs, so nothing is cached between the enumeration and the sort/row rendering.
- **Fix**: capture the metadata once while enumerating (`resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])`) and store `size`/`date` as `let`s; sort the stored values; skip the reload for `hideZIP` (just re-filter `files`); hoist a static `ByteCountFormatter`; load the PDF with a loading state, e.g. `Task.detached { PDFDocument(url: url) }` and assign on the MainActor (PDFKit object creation is safe off-main; keep all later mutations on main). Optionally cache the file list in a store and refresh on `.downloadsChanged` only. Effort S–M.
- **Confidence**: High for the stat-in-comparator cost (pure code); Medium-High for the PDF cost (depends on file size; the previous audit cycle already targets 300 DPI output, so these files are large).
- **What would confirm it**: seed 300 files in `Documents/ZIP` + `Documents/PDF`, open the Files tab with the Hangs instrument + Time Profiler; expect a hang in `load()`/`sorted` with `attributesOfItem` samples, and a separate hang in `PDFDocument.init` when presenting a >100-page PDF.
- **Validation**: plan step 6.

### 6. Reader: per-tick scroll-controller churn and an undersized image cache

- **Symptom**: fast reader scrolling shows occasional hitches; scrolling back up a few pages re-shows placeholders and re-downloads images even though they were just prefetched.
- **Likely cause**: `ReaderScrollController.attach` installs three KVO observations that each hop to the MainActor with `Task { @MainActor in self?.update() }` (`ios/Sources/ReaderScrollController.swift:21-34`); `update()` then assigns `contentHeight`, `viewportHeight`, `isScrollable` and `progress` unconditionally (`:55-71`). Because `@Published` sends on every assignment, **four** object changes are emitted per scroll tick even when only `progress` moved, invalidating `ReaderPageSlider` (~120 times/s on ProMotion) — including its `GeometryReader` and `DragGesture` (`ios/Sources/ReaderView.swift:343-383`). The slider is only 24 pt wide, but this is work scheduled at the worst time (during scrolling). Separately, `ReaderImageStore` caps at 12 images (`ios/Sources/ReaderView.swift:118`) while `prefetch` queues the next 10 (`:192-202`, driven from `ReaderPageView`'s `.task` at `:440-447`). At 1200 px max dimension a decoded page is ~4–6 MB (portrait ~4 MB, square ~5.8 MB), so the 84 MB cost limit allows roughly 14–20 images and **`countLimit = 12` is the binding limit**: current + the 10 ahead already fills it, and scrolling up two pages evicts the page the user just left. `ReaderImageStore.image(for:)` then refetches it over the network.
- **Evidence**: `ios/Sources/ReaderScrollController.swift:14-71`, `ios/Sources/ReaderView.swift:118`, `:192-219`, `:440-447`, `:343-383`. The reader's image path itself is already good (downsample + force-decode in a detached task, `ios/Sources/ReaderView.swift:176-180`).
- **Fix**: (a) in `update()`, compare before assigning (`guard value != progress else { return }` etc.) and skip `contentHeight`/`viewportHeight` assignments when unchanged; (b) coalesce KVO into one update per frame (a `pending` flag consumed on the next `CADisplayLink` tick, or a `DispatchQueue.main.async` that is only scheduled when not already pending) and drop the `Task` hop — UIScrollView KVO is already on the main thread, so `MainActor.assumeIsolated` is enough on iOS 17+; (c) raise `countLimit` to ≥24 and/or teach prefetch to keep the previous 2 pages (prefetch a window `index-2...index+10` only when missing) so scroll-back hits the cache. Effort S for (a)+(c), M for (b).
- **Confidence**: Medium. The mechanism is clear from code; the per-frame cost is small relative to image decode, so the slider may be a second-order contributor. The cache arithmetic is high confidence: `12` images vs a 10-page forward window + current + previous.
- **What would confirm it**: record a fast reader scroll in the SwiftUI instrument; count Update Groups per second and check whether they come almost entirely from `ReaderScrollController` (cause graph). For the cache, scroll down 15 pages then up 5 and watch the Network instrument / proxy logs for re-fetches, or add a temporary miss counter in `ReaderImageStore.image(for:)`.
- **Validation**: plan step 7.

### 7. The 120 Hz display link is always on by default and does no work

- **Symptom**: none directly visible; higher idle/warm CPU and battery drain on ProMotion devices, worse during long reading/downloading, and it can feed thermal throttling that later shows up as jank.
- **Likely cause**: `HighRefreshRateController.applySavedSetting()` writes `true` when the key is absent (`ios/Sources/HighRefreshRateController.swift:15-21`), `WnacgApp.init` applies it (`ios/Sources/WnacgApp.swift:26-29`), and `SettingsView` defaults the toggle to `true` (`ios/Sources/SettingsView.swift:15`). `start()` registers a `CADisplayLink` with `minimum/maximum: 120` in `.common` mode and an empty `tick()` (`ios/Sources/HighRefreshRateController.swift:28-48`). A 120 Hz display link requests a 120 Hz main-thread wake-up and frame budget for the life of the app, including static screens. It does not raise the actual render rate beyond what the system allows, and SwiftUI already gets ProMotion while scrolling/animating.
- **Evidence**: as above; `Info.plist` already sets `CADisableMinimumFrameDurationOnPhone: true` (`ios/project.yml:39`), so the controller is redundant.
- **Fix**: delete the controller and its Settings section (or keep the key only to migrate users), leaving `CADisableMinimumFrameDurationOnPhone` in place. Effort S.
- **Confidence**: High that the link runs at 120 Hz by default with an empty tick; Medium on the power delta (no Energy Log was available).
- **What would confirm it**: Xcode Energy report / Time Profiler on an idle Home screen for 60 s with the toggle on vs off (or with the controller removed); compare main-thread wake-ups, CPU and energy impact. Needs a physical ProMotion iPhone — the simulator does not model the device's frame-rate policy.
- **Validation**: plan step 8.

### 8. History and Favorites rebuild derived collections in `body`

- **Symptom**: typing in the History/Favorites search field can feel heavy with a large library; large lists re-sort/group on unrelated state changes.
- **Likely cause**: `HistoryView.sections` groups by `Calendar.current.startOfDay`, sorts each group and then sorts the groups, on every body evaluation (`ios/Sources/HistoryView.swift:32-43`); `filteredItems` is computed twice per body (once via `noMatches` at `:28-30`, once via `sections`) and `searchText` is `@State`, so every keystroke pays for it. `FavoritesView` computes `downloaded` and `pending` by filtering `favorites.items` twice each (`ios/Sources/FavoritesView.swift:26-36`) and `noMatches` filters both again (`:38-40`) → four full passes per body. `HistoryEntry.homeAlbum` and `FavoriteManga.homeAlbum` also rebuild a `HomeAlbum` (and re-run language/AI classification) on every row render (`ios/Sources/HistoryStore.swift:20-30`, `ios/Sources/LibraryStore.swift:20-30`).
- **Evidence**: as above. For libraries of a few dozen items this is sub-millisecond; the finding is about the shape, not the current size.
- **Fix**: compute once per body into locals and pass them to the branches (cheap, keeps structure), or derive in the store: `@Published var sections` recomputed only when `items` changes, and a debounced query in the model. Cache `homeAlbum` on the entry (computed lazily once) so `HistoryEntry`/`FavoriteManga` don't re-classify on each row. Effort M.
- **Confidence**: High for the duplicated work; Low-Medium for user impact until the lists get large.
- **What would confirm it**: SwiftUI Update Groups + Time Profiler while typing a query with 500+ seeded history rows; compare body-update duration before/after local caching.
- **Validation**: plan step 9 (optional).

## Smaller / opportunistic findings

- **Preview cover decode on the MainActor** — `AppModel.parse` loads the album cover with `UIImage(data:)` inside the MainActor task (`ios/Sources/AppModel.swift:137-148`) and keeps the full-size image for a 104×138 view. One-off hitch + memory waste; reuse the downsample helper (maxPixel ~600) in a detached task.
- **`ZipExtractor.validate` and temp-dir cleanup on the MainActor** — `ios/Sources/AppModel.swift:311`, `:324-330`; move both to a detached task alongside the existing extract/PDF detached work.
- **Detail body does per-tick derived work during downloads** — `recommendationsSection` filters and `tagGrid` rebuilds `HomeParser.searchURL(tag)` (URLComponents + query items) for every tag on every body evaluation (`ios/Sources/AlbumDetailView.swift:432-464`, `:312-346`); with progress fan-out (finding 3) that is per chunk. Precompute tag search URLs when the preview is parsed, and derive the filtered recommendation list once.
- **Home recomputes `displaySections` twice per body** — used by `categoryChips` and the section list (`ios/Sources/HomeView.swift:271`, `:370`); with `hideAI` on it filters and rebuilds every section each time (`:344-355`). Compute once and cache in `HomeFeedModel` (it only changes when hidden state or sections change).
- **Category filter changes are double-handled and gated behind up to 6 network loads** — `onChange` of `languageFilter` and `hideAI` both call `handleFilterChange` (`ios/Sources/CategoryView.swift:269-274`, `:624-630`), so clearing filters runs two `fillFilteredPages(limit: 6)` loops and two scroll animations; with the 0.7 s request throttle a chip tap can look unresponsive for seconds while pages append. Coalesce the two onChange handlers and scroll to top immediately, then fill in the background.
- **`Array(visibleAlbums.enumerated())` per body pass** — `ios/Sources/CategoryView.swift:313-316`; allocates an array of 400+ tuples and a new view value per row on each update. Minor; `ForEach(visibleAlbums)` plus a suffix check for the prefetch trigger would avoid the array (index is only used for the prefetch distance).
- **`ReaderView` uses index identity** — `ForEach(Array(model.pageURLs.enumerated()), id: \.offset)` (`ios/Sources/ReaderView.swift:254`); identity is stable across reload only by accident, and a reload can leave row-local state (image/failed) attached to a different URL. Use the URL as id (dedupe first) or include a generation in the id.
- **Reader placeholder height** — `UIScreen.main.bounds.width * 1.4` (`ios/Sources/ReaderView.swift:396-398`) does not match the true aspect of every page, so row heights change when images arrive (layout shift, more visible when several placeholders are in view); on iPad (and iOS 26 multi-window sizes) `UIScreen.main` is not the window width. Use a container-relative width and, if available from the response, a per-page aspect hint.
- **`PDFPreviewView` rebuilds the whole `PDFView` after deleting pages** — `.id(model.pageCount)` (`ios/Sources/FilesView.swift:256`) recreates the representable and re-renders the document; acceptable for correctness, but measure because a 300 DPI PDF re-parse is expensive. Mutating the document in place and letting `PDFView` observe the change would avoid the rebuild.
- **`LocalProxy.start()` blocks the main thread at launch** — `WnacgApp.init` calls it synchronously (`ios/Sources/WnacgApp.swift:21-25`) and `start()` waits on a semaphore up to 5 s (`ios/Sources/LocalProxy.swift:40-98`); normally a few ms, but it is in the launch critical path. Measure with the App Launch template.
- **`ByteCountFormatter` convenience per call** — `ios/Sources/ContentView.swift:305-310`, `ios/Sources/FilesView.swift:125-127`; cache a static formatter.
- **Typing in the download URL field invalidates the whole `ContentView`** — `model.input` is `@Published` and `previewCard`/`statusBar` are rebuilt per keystroke (`ios/Sources/ContentView.swift:17-23`, `:82-90`); if it ever feels laggy with a large tag list, move the input into a child view.

## Verified landed fixes (what is already good, and the residual risk)

| Claimed fix | Verdict | Residual risk |
| --- | --- | --- |
| Equatable album cards | **Verified.** `AlbumCardView: Equatable` compares `HomeAlbum` (`ios/Sources/AlbumCardView.swift:33-37`) and `.equatable()` is applied in the home grid and the category grid (`ios/Sources/HomeView.swift:453`, `ios/Sources/CategoryView.swift:322`). `HomeCover`'s `.task(id: album.coverURL)` therefore does not refire when the parent re-renders. | The enclosing `NavigationLink`/row still re-evaluates; the win is skipping the card subtree, not the row. Detail/recommendation covers are not equatable but are in a non-lazy `HStack`, so it does not matter. |
| Cached filters / classification | **Verified.** `language` and `isAI` are computed once in `HomeAlbum.init` (`ios/Sources/HomeParser.swift:12-17`, `:35-36`) using a shared static regex (`ios/Sources/MangaFilter.swift:63-79`); `CategoryFeedModel.visibleAlbums` is maintained incrementally (`ios/Sources/CategoryView.swift:64-73`, `:146`). | `HomeView.displaySections` still filters/rebuilds sections in `body` when `hideAI` is on (smaller findings), and `homeAlbum` rebuilds on every History/Favorites row. |
| Background JPEG encode | **Verified.** `prepareThumbnail` and the `.jpegData` call run in `Task.detached(priority: .background)` (`ios/Sources/HomeView.swift:182-199`, `:223-228`); the disk write is also detached (`:193-199`). | The disk read path is the remaining gap (finding 2). |
| Off-main downsample | **Verified for covers and the reader.** Covers: `downsample` inside the detached task with `kCGImageSourceShouldCacheImmediately` (`ios/Sources/HomeView.swift:185-187`, `:230-246`). Reader: `ReaderImageDecoder` run via `Task.detached` (`ios/Sources/ReaderView.swift:5-25`, `:176-180`). | Not applied to the download-page preview cover (`ios/Sources/AppModel.swift:137-148`) and not to the cover disk cache (finding 2). |
| Skeleton loading | **Verified.** Home shows 9 skeleton cards while the first sections load (`ios/Sources/HomeView.swift:265-266`, `:462-480`); Category shows 12 (`ios/Sources/CategoryView.swift:288-296`, `:352-360`). | The skeleton animation is driven by `withAnimation(.repeatForever)` per card (`ios/Sources/AlbumCardView.swift:59-66`); a main-thread parse block (finding 1) freezes that shimmer, which is itself a visible symptom of finding 1. |
| List identity | **Verified stable** for feed grids (`id: \.element.id` → `aid`), home sections (`title`), Files (`URL`), History (`aid`), Favorites (`aid`). The sentinel's `.id("lazy-end-…")` is an intentional one-shot identity change per page. | `ReaderView` still uses index identity (smaller findings); `HistoryView.sections` rebuilds wrapper structs but keeps stable dates as ids. |

## iOS 26 / Liquid Glass notes (lower confidence, no trace)

- **Tab bar never minimizes** — `RootView` forces `.tabBarMinimizeBehavior(.never)` on iOS 26 (`ios/Sources/RootView.swift:39-45`), so the floating glass tab bar and its backdrop stay over scrolling content on every feed screen. That keeps one of the more expensive Liquid Glass elements on screen during scroll; the default (minimize on scroll) both saves space and may reduce per-frame backdrop work. Consider not forcing `.never` and measuring GPU/Animation Hitches during a long category scroll. Confidence Low; confirm with the Animation Hitches/GPU trace.
- **Materials over a full-screen gradient** — `AppBackground` is a full-screen `LinearGradient` on every screen (`ios/Sources/Theme.swift:22-41`), with `.ultraThinMaterial` chips (home chip bar, `ios/Sources/HomeView.swift:394`), the detail download button (`ios/Sources/AlbumDetailView.swift:276`), the PDF edit bar and the optional FPS HUD. Materials sample the background behind them; a gradient behind several materials means real blur work during scroll, and iOS 26's glass effects are heavier than previous materials. Prefer a solid/`Color(.secondarySystemBackground)` fill for small chips if GPU time shows up. Confidence Low.
- **No `ScrollView`/`List` glass-specific code was found**, so nothing else needs to be gated by availability; the iOS 26 availability check is confined to the tab bar behavior.

## Validation plan — iOS 26 simulator

The audit host has no Xcode/Instruments, so these steps must run on a Mac with Xcode 26.x and an iOS 26.x simulator (iPhone 17 Pro recommended; use a Release/Profile build, because Debug exaggerates body work and allocation).

**0. Build & baseline harness**
- `xcodegen generate` in `ios/`, open the workspace, Profile (Release) on the iOS 26 simulator.
- Use the **SwiftUI** Instruments template (SwiftUI instrument + Time Profiler + Hangs/Hitches lanes) and, for each scenario, set an Inspection Range on the suspected interval.
- Optional: add temporary `os_signpost` intervals around `HomeParser.parse`/`parseCards` and around `readThumbnail` so the trace can attribute the parse/decode directly; remove before release. (Read-only audit — not applied here.)

**1. Seed a large library in the simulator** (for findings 4, 5, 8)
- Container: `xcrun simctl get_app_container booted com.wancg.downloader data`.
- Files: copy ~200 dummy `.zip` + ~100 dummy `.pdf` into `Documents/ZIP` and `Documents/PDF` (small files, or real files for the PDF-load test — one >100-page 300 DPI PDF).
- Favorites/history: write `Library/Preferences/com.wancg.downloader.plist` keys `wnacg.favorites.v1` and `wnacg.history.v1` with 200 entries each (JSON `Data` as in `FavoritesStore`/`HistoryStore`). Use titles that do **not** match the seeded files to exercise the worst case in `reconcile` (no early match).
- Relaunch the app after writing the plist.

**2. Home first load (finding 1)**
- Cold launch → record until the first grid is fully populated.
- Look for: one long main-thread block after the HTML fetch, with Time Profiler samples in `HomeParser`/`NSRegularExpression`; the skeleton's repeating animation stalling during that block; the App Launch template's first-frame time.

**3. Category append, cold and warm (findings 1, 2)**
- Open a category, scroll to the last row, let two pages append while the recorder runs.
- Cold pass: thumbnails fetched over the network.
- Warm pass: pop the category, re-enter, scroll to the bottom again (thumbnails now on disk).
- Look for: Hitches lane spikes aligned with `parseCards` (finding 1); in the warm pass, main-thread ImageIO/`CGImageSourceCreateImageAtIndex` or `CA::Transaction::commit` samples and a burst of ~20 cover updates in one Update Group (finding 2). Compare hitch count per append before/after the regex cache + forced-decode fixes.

**4. Download + PDF (finding 3)**
- Download a real album with PDF generation on. Record 30–60 s of the ZIP phase and the PDF phase separately.
- Look for: ContentView (and AlbumDetailView, if started there) body update count per second vs the `didWriteData` rate; ActivityKit `update` call rate in Console; the detail-screen progress card being absent despite the updates; main-thread samples in `ZipExtractor.validate` and the temp-dir cleanup after the PDF completes.

**5. Favorites tab (finding 4)**
- With the seeded library, switch to Favorites (Hangs instrument, 250 ms default; also set a 100 ms threshold for one run).
- Look for: a hang in `reconcile` with `HTMLParser.safeFilename`/`NSRegularExpression`/`FileManager` frames. Re-run after the normalized-set fix and expect no hang.

**6. Files tab and PDF sheet (finding 5)**
- Open Files with the seeded library; record.
- Look for: hang in `load()` with `attributesOfItem` samples inside `sorted`; then open the large PDF and look for a main-thread `PDFDocument.init` hang.
- Also check scroll smoothness through the file rows (two stats per visible row).

**7. Reader (finding 6)**
- Open a gallery; fast-fling down 15 pages, then fling back up 5.
- Look for: Update Groups per second from the slider/controller during scrolling; the Network instrument (or the local proxy log) showing re-fetches when scrolling back up; placeholders reappearing. Re-run after the cache/countLimit change and expect no re-fetch for pages already prefetched.

**8. Power / 120 Hz (finding 7)**
- On a physical ProMotion iPhone (the simulator cannot reproduce the frame-rate policy): Energy Log or Time Profiler on an idle Home screen for 60 s with Settings → 锁定 120Hz on, then off (or with the controller removed). Compare CPU wake-ups and energy impact; confirm scrolling FPS is unchanged (PerformanceHUD already reports FPS and the worst frame, `ios/Sources/PerformanceMonitor.swift`).

**9. Optional: History/Favorites typing (finding 8)**
- With 500+ seeded history rows, type a query letter by letter; compare Update Groups/body duration before/after computing the sections locally.

**Acceptance targets** (no baseline exists yet; record the "before" column from the current build):
- Category append: no hitch > 1 frame attributable to parse; main-thread parse block ≤ 4 ms after the regex cache; no ImageIO decode on main in the warm pass.
- Downloads: `@Published` progress writes ≤ 5/s; Live Activity updates ≤ 1/s; no body evaluation of the full download/detail screen per network chunk.
- Favorites switch with 200 favorites/300 files: no hang > 100 ms.
- Files open with 300 files: < 100 ms; PDF sheet: first frame < 1 s, no hang while loading.
- Reader: 0 re-fetches for pages already prefetched after a scroll-back of ≤ 5 pages; slider updates ≤ 1 per frame.
- Idle Home CPU/energy measurably lower with the 120 Hz controller removed.

## Metrics

No measurements are available from this host, and the skill's template says not to invent them. Capture the before/after pair in the plan above and fill this table in the next QA cycle:

| Metric | Before | After | Notes |
| --- | --- | --- | --- |
| Hitches per category page append (Hitches lane) | TBD | TBD | Cold and warm thumbnail cache passes separately |
| Main-thread time in `parseCards` (signpost / Time Profiler) | TBD | TBD | iOS 26 simulator, Release |
| Cover disk-read + decode on main (warm pass) | TBD | TBD | ImageIO samples in the append window |
| Full-screen body updates during a ZIP download (per s) | TBD | TBD | SwiftUI Update Groups |
| Live Activity updates per s during download/PDF | TBD | TBD | Console ActivityKit |
| Favorites tab hang duration (200 favorites / 300 files) | TBD | TBD | Hangs instrument |
| Files tab open time / PDF sheet hang (300 files) | TBD | TBD | Hangs instrument |
| Reader Update Groups per s while scrolling; re-fetches on scroll-back | TBD | TBD | SwiftUI instrument + Network |
| Idle Home CPU / energy, 120 Hz link on vs off | TBD | TBD | Physical ProMotion device |

## Next step

Land the two S-effort, code-only fixes that target the reported append jank first — **cache the compiled regexes and parse off the MainActor (finding 1)** and **force-decode the disk-cached thumbnails (finding 2)** — then re-record the warm category append on the iOS 26 simulator before touching anything else. The Favorites/Files main-thread work (findings 4 and 5) and the download throttling (finding 3) are also small, contained changes and should follow in the same cycle; the reader scroll-controller work, the derived-state cleanup, and the 120 Hz default are better sized for the cycle after the trace confirms their share.
