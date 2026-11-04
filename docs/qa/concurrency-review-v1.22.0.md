# Concurrency & async review — wancg (iOS) v1.22.0

- **Repo / baseline:** `main` @ `f605732` (tag `v1.22.0`, build 259), working dir `E:\Code\manga-downloader`.
- **Build context:** `SWIFT_VERSION = 5.0` (no Swift 6 strict-concurrency mode), deployment target iOS 17.0,
  CI builds/runs on Xcode 26.3 / iOS 26.2 simulator (`.github/workflows/*.yml`), no local Xcode in this review.
- **Review mode:** read-only static review (no builds, no edits to app sources). Method follows
  `E:\Code\Skills\swift-concurrency-expert\SKILL.md` (triage isolation → smallest safe fix → verify), with
  judgement applied for a Swift 5 / iOS 17 project: language-mode violations that are *compile-time only*
  are separated from issues that can misbehave **at runtime under Swift 5**.
- **Scope:** `CategoryView.swift`, `HomeView.swift`, `ReaderView.swift`, `WnacgClient.swift`,
  `LocalProxy.swift`, `AppModel.swift`, `DownloadQueue.swift`, `DownloadLiveActivityManager.swift`,
  `HistoryStore.swift` / `LibraryStore.swift` / `FavoritesExporter.swift`, plus the supporting
  `AlbumCardView.swift`, `AlbumDetailView.swift`, `ReaderScrollController.swift`, `DoHResolver.swift`,
  `PDFBuilder.swift`, `ZipExtractor.swift`, `ContentView.swift`, `RootView.swift`, `WnacgApp.swift`.

## Verdict

**No P0.** I found no double-resume of a `CheckedContinuation`, no unsynchronized `@Published` write off the
main actor, no un-awaited main-actor crossing, and no permanent feed/reader state wedge. The generation-token
pattern in `CategoryFeedModel` / `HomeFeedModel` / `ReaderModel` is correct: every `generation += 1` is paired
with a load that owns the `isLoading` reset, so stale loads cannot leave the UI stuck.

Two P1s are worth fixing in a 1.22.x patch (both are small, local changes):

1. **`CategoryFeedModel`'s auto-retry cancels its own task** and therefore never succeeds — the v1.22
   "self-healing feed" feature is effectively dead and replaces the original transient error with a bogus
   "cancelled" message (`CategoryView.swift:166-179`).
2. **The local-proxy (re)start path blocks whatever thread calls it for up to 5 s** via
   `DispatchSemaphore.wait` — including the main thread at launch, on every return-to-foreground, on reader
   reload and on the Settings toggle (`LocalProxy.swift:51-84` + call sites).

Neither is a crash or data-loss bug, so **v1.22.0 is not blocked** on them; F3/F4 below are the same class of
"transient network failure becomes a stuck/duplicated request" and are cheap to fix together.

| ID | Severity | File | One-line |
|----|----------|------|----------|
| F1 | **P1** | `CategoryView.swift:83-86,166-179` | Auto-retry task cancels itself before its request → retry always fails |
| F2 | **P1** | `LocalProxy.swift:51-84` (+`WnacgApp:24`, `RootView:52`, `ReaderView:48`, `SettingsView:36`) | Blocking proxy (re)start on main / cooperative threads, 5 s cap |
| F3 | **P1** | `WnacgClient.swift:87-93` + `LocalProxy.swift:375` | Per-request proxy restart `invalidateAndCancel()`s every sibling request; `-999` not retried |
| F4 | **P1** | `LocalProxy.swift:377-389` + `WnacgClient.swift:6-10,59-61` | Sticky `startupError` wedges all networking with no in-app recovery |
| F5 | P2 | `HomeView.swift:142-204` | `CoverImageStore` has no in-flight coalescing → duplicate cover downloads |
| F6 | P2 | `LocalProxy.swift:292-299,301-311,319-371` | `ProxySession`/`LocalProxy` state read/written from several threads; restarts dropped, not coalesced |
| F7 | P2 | `WnacgClient.swift:336-384,426-445` | `FileDownloader`: cancel-before-handle is ignored; continuation/task handle unsynchronized |
| F8 | P2 | `CategoryView.swift:83-92`, `HomeView.swift:16-21` | Force refresh does not cancel the previous in-flight feed request (duplicate requests, 429 exposure) |
| F9 | P2 | `ReaderView.swift:127-143,192-219` | Failed prefetch URLs are retried by every page within 10 pages (no failure memo) |
| F10 | P2 | `AppModel.swift:179-209,245-250,257-379` | Queue items silently dropped on async parse/download failure |
| F11 | P2 (theoretical) | `ReaderScrollController.swift:21-35,55-71` | One `Task { @MainActor }` hop + 4 `@Published` writes per scroll frame |
| F12 | P2 (theoretical) | `DownloadLiveActivityManager.swift:51-78` | Fire-and-forget Live Activity updates can land out of order |

---

## P1 findings

### F1 — `CategoryFeedModel` recovery retry cancels its own `Task`, so the retry can never run

**Where:** `ios/Sources/CategoryView.swift:166-179` (`scheduleRecovery()`), `:83-86` (`load(reset:force:)`),
`:147-155` (fail path).

**Trigger:** any transient failure of an ordinary "load more" — HTTP 429/5xx, timeout, connection reset,
or a proxy restart. This is the exact path the feature was added for (commit `b6ccdae`, "Improve auto-load
reliability … self-recovery"), so it is on the hot path for category/search screens.

**What happens:**

```
catch { … error = …; scheduleRecovery() }        // load() line 152-153
recoveryTask = Task { @MainActor [weak self] in   // :170
    try? await Task.sleep(2.5 s)
    guard let self, !Task.isCancelled else { return }
    guard self.error != nil, self.hasMore, !self.isLoading else { return }
    self.error = nil
    await self.load(reset: false)                 // :177  ← this cancels recoveryTask (`recoveryTask` is *this* task)
}
load():  recoveryTask?.cancel(); recoveryTask = nil   // :85-86
         … isLoading = true
         let html = try await client.fetchHTML(…)      // :112  runs in the task that was just cancelled
```

`load()` unconditionally cancels `recoveryTask`, and when `load()` is called *from* `recoveryTask`, that
cancel targets the executing task itself. The request is then issued from a cancelled task: `URLSession`'s
async `data(for:)` is cancellation-aware, so the underlying `URLSessionTask` is cancelled and the await
throws `URLError(.cancelled)` (NSURLErrorCancelled, **-999**). The `catch` checks only
`if !(err is CancellationError)` (`:151`) — a `URLError` is not a `CancellationError` — so it:

1. shows a misleading error: "The operation couldn't be completed. (NSURLErrorDomain error -999.)",
2. burns the next recovery attempt (`recoveryAttempts` → 2), and
3. stops `fillFilteredPages()` (its loop exits on `model.error != nil`).

Net result: automatic recovery is a two-shot loop that always fails; a one-off 429 turns into a persistent
error banner until the user taps "加载更多 / 重试" manually (manual retry works, because that path calls
`load()` from a non-cancelled task).

**Why Swift 5 runtime makes it possible:** nothing here is rejected at compile time — `Task.cancel()` on the
current task is legal, and a cancelled task may still call an async function; only `URLSession` (and any
`Task.sleep`/`checkCancellation` *inside*) observes it. So this is a real Swift-5 behaviour bug, not a
Swift-6 diagnostic.

**Minimal safe fix (behaviour-preserving):** detach the recovery task from the cancel path before calling
`load`:

```swift
guard self.error != nil, self.hasMore, !self.isLoading else { return }
self.recoveryTask = nil          // ← load() will now have nothing to cancel
self.error = nil
await self.load(reset: false)
```

(Equivalently: give `load` a `cancelRecovery: Bool = true` parameter and pass `false` here.) Also consider
treating `NSURLErrorCancelled` with `Task.isCancelled == true` as silent (no user-facing error) in `:151`.

**Confidence:** 0.85 that the retry request is cancelled (-999) and 0.98 that the retry is at best
unreliable because it runs in a cancelled task. **Real, not theoretical.**

**CI verification without a Mac:** in the existing UITest, force a "load more" failure (e.g. point the feed
at a category URL and toggle airplane-mode-equivalent via the test host is not available; simplest is a
temporary unit-level check of `CategoryFeedModel` with an injected failing client — the model would need a
`init(startURL:clientFactory:)` seam). Cheapest non-invasive verification: add `os_log` on
`scheduleRecovery`/catch error domain and read it from the iOS 26.2 simulator run.

---

### F2 — Local-proxy (re)start blocks the calling thread on a `DispatchSemaphore` for up to 5 s

**Where:** `ios/Sources/LocalProxy.swift:51-84` — `start()` creates a `DispatchSemaphore(value: 0)` and calls
`semaphore.wait(timeout: .now() + 5)` on the caller's thread while `NWListener` reports state from
`queue` (`:8`, `:79`). It is reached synchronously from:

| Call site | Thread | Frequency |
|---|---|---|
| `WnacgApp.swift:21-25` (`_ = try? LocalProxy.shared.start()`) | **main** | every cold launch |
| `RootView.swift:46-54` → `ProxySession.restart()` (`LocalProxy.swift:364-365`) | **main** | every return from background without an active download |
| `ReaderView.swift:45-50` (`reload()` → `ProxySession.shared.restart()`) | **main** (`ReaderModel` is `@MainActor`) | every reader reload / per-page "重新加载" |
| `SettingsView.swift:34-37` → `ProxySession.setUseSystemNetwork` (`LocalProxy.swift:319-346`) | **main** | network-mode toggle |
| `WnacgClient.swift:93` (`load` proxy-failure retry) | Swift global executor (nonisolated async) | any request that hits the retry list |

**Why it can happen under Swift 5:** `ProxySession`, `LocalProxy` and `WnacgClient` are plain non-`Sendable`
classes; there is no isolation and no compiler/runtime guard. In an `async` function a blocking
`DispatchSemaphore.wait` does not suspend the task — it parks the thread. On the main thread that is a UI
freeze; on the cooperative pool it blocks one of the runtime's worker threads (the runtime does not
compensate for blocked threads), which is exactly the pattern Xcode's Thread Performance Checker flags.

**Worst case:** `NWListener` never reaches `.ready`/`.failed` (background launch, simulator CI, port/state
churn, local-network permission) → `wait` times out after 5 s → `start()` throws → `rebuild()` installs a
proxy-less session and sets `startupError` (see F4). On the main thread this is a 5 s unresponsive window
(scene-update watchdog / "app is not responding" territory); the common case is single-digit ms but still a
thread hop on every foreground.

**Minimal safe fix:** keep the synchronous `start()` (the macOS `WnacgProxyCheck` target compiles
`LocalProxy.swift`), and add an async path used by the main-actor callers:

```swift
// LocalProxy.swift — same body, but suspend instead of blocking
func startAsync() async throws -> UInt16 {
    try await withCheckedThrowingContinuation { cont in
        queue.async { /* stateUpdateHandler resumes cont exactly once (guard !signaled) */ }
    }
}
```

and make `ProxySession.restart()` / `setUseSystemNetwork` `async` (or execute their bodies on a private
serial queue and let main-actor callers `Task { await … }`). Remove the direct `LocalProxy.shared.start()`
from `WnacgApp.init` and let `ProxySession`'s lazy `rebuild` own startup (it already does at
`LocalProxy.swift:301-311`). While there, reduce the 5 s cap to ~1.5–2 s.

**Confidence:** 0.95 for the mechanism (blocking call on main); probability of a full 5 s stall is low but
non-zero. **Real, not theoretical.**

---

### F3 — A proxy restart triggered by one request cancels every other in-flight request, and that cancellation is not retried

**Where:** `ios/Sources/WnacgClient.swift:83-99` (retry classification + `ProxySession.shared.restart()`),
`ios/Sources/LocalProxy.swift:356-361` / `:373-390` (`session.invalidateAndCancel()`).

**Trigger:** one request fails with a proxy-ish error (`310`/`-310`, `-1001`, `-1004`, `-1005`, `-1009`,
`-1200`). `load()` restarts the singleton session: `rebuild(invalidate: true)` calls
`session.invalidateAndCancel()` — that is the **shared** `URLSession` used by all `WnacgClient`s
(`WnacgClient.swift:4`). All sibling requests that happen to be in flight (3–6 cover downloads, prefetch
images, a category page fetch, an `AppModel` preview) are cancelled by the session, and each receives
`URLError(.cancelled)` = **-999**. `-999` is *not* in the retry list at `:87-90`, and `Task.isCancelled` is
false for those tasks (the *task* was not cancelled, the session was), so `:91` rethrows immediately:

- `CoverImageStore.loadImage` swallows it → cover silently stays a placeholder (no retry until the cell is
  recreated),
- `ReaderImageStore.loadImage` swallows it → reader page shows the failed-state UI,
- `CategoryFeedModel`/`HomeFeedModel`/`AlbumDetailModel` show an error banner.

The restarting request itself retries after 300 ms on the new session and usually succeeds — so the failure
looks random and intermittent, and the "burst of restarts" also stops/starts the `NWListener` and creates a
fresh `URLSession` each time (up to 2 restarts per failing request, serialized only by the `isRestarting`
flag in F6).

**Why Swift 5 runtime:** no isolation prevents a request-independent global side effect; `invalidateAndCancel`
semantics are the same in every language mode. This is a real concurrency-design bug (global resource
replaced by a per-request error handler), not a Swift-6 warning.

**Minimal safe fix:** after the existing `if Task.isCancelled { throw error }` guard, treat a cancelled
`URLError` as a *consequence of a restart* and retry once against the new session:

```swift
let wasCancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
let proxyFailure = wasCancelled || code == 310 || code == -310 || […]
```

Because real user/structured cancellation is already filtered by `Task.isCancelled` above, this does not
retry work the user cancelled. (Optional follow-up: have `ProxySession` expose a generation counter and only
retry when the generation changed, and coalesce restart requests — see F6.)

**Confidence:** 0.9. **Real.**

---

### F4 — A single failed proxy start sets a sticky `startupError` that blocks all networking with no in-app recovery

**Where:** `ios/Sources/LocalProxy.swift:377-389` (on `start()` failure sets `startupError` and installs a
proxy-less `URLSession`), `:292` (`private(set) var startupError`), `WnacgClient.swift:6-10`
(`init()` throws if `startupError != nil`), `:59-61` (`load()` throws the same error *before* the retry loop).

**Trigger:** `LocalProxy.start()` fails once — 5 s timeout, `NWListener` creation failure, listener
`.failed` — e.g. while the app is launched/restarted from a background or restricted state, or under
simulator CI. From then on:

- every `try WnacgClient()` throws → `AppModel.init:52-56`, `AppModel.parse:116-118`,
  `CategoryFeedModel:104-107`, `HomeFeedModel:23`, `ReaderModel:59`, `AlbumDetailModel:23`,
  `CoverImageStore/ReaderImageStore:177/150` all fail immediately;
- every `WnacgClient.load` throws at `:59-61` before it can ever reach the restart branch at `:93`.

`startupError` is cleared only by `rebuild()` succeeding (`:380`), i.e. by `restart()`, and `restart()` is
reached from: return-from-background (`RootView`), settings toggle, reader reload, and the `WnacgClient`
retry path — **the last one is unreachable** because of the early throw. So after one failed start the app
can be "offline" until the user backgrounds and re-opens it (or opens a reader and taps reload). The
`CategoryFeedModel` recovery (even once F1 is fixed) cannot heal it either, because it too constructs a
`WnacgClient`.

**Why Swift 5 runtime:** sticky error state + a lazy-init failure, no isolation involved; it is a
state-machine/recovery defect exposed only when startup fails, so it never shows in normal builds/CI.

**Minimal safe fix:**
1. In `WnacgClient.load`, if `startupError != nil`, attempt one `ProxySession.shared.restart()` and retry
   before throwing (guard it with a timestamp so it does not restart on every call — e.g.
   `startupErrorAt` + `attemptedRecovery`).
2. In `WnacgClient.init`, do not hard-fail on `startupError`; keep the throw only when the proxy is
   *required* and recovery already failed.
3. Record the failure time in `ProxySession` and let the first request after N seconds trigger the rebuild.

**Confidence:** 0.9 for the sticky-state mechanics; probability of hitting it is low. **Real.**

---

## P2 findings

### F5 — `CoverImageStore` has no in-flight request coalescing (duplicate downloads)

**Where:** `ios/Sources/HomeView.swift:142-160` (`image(for:)`) and `:162-204` (`loadImage`). Only the
`NSCache` is consulted (`:143`, `:163`, `:173`); unlike `ReaderImageStore` (`ReaderView.swift:131-141`)
there is no `inFlight: [URL: Task<…>]` map.

**Trigger:** the same cover URL requested concurrently — the same album appearing in two home sections
(`HomeParser.parse` de-dupes within a section, not across sections), a cell whose `.task` restarts while the
first request is still running (identity change after a filter/parent update), or cover + detail header in
quick succession. Two views → two disk probes → two `limiter.acquire()` permits → **two network requests for
the same image**. Each duplicate consumes a slot from the cover limiter (default 3) and adds to the site's
429 budget that the category feed work is explicitly trying to protect.

**Why it matters now:** the codebase already has the correct pattern one file over (`ReaderImageStore`), so
this is a missing mirror, not a new design.

**Minimal safe fix:** add `private var inFlight: [URL: Task<UIImage?, Never>] = [:]` to `CoverImageStore`
(main-actor only), return the existing task's value, and clear the entry after completion — exactly the
`ReaderImageStore.image(for:)` shape.

**Confidence:** 0.85 real; frequency low-to-medium. **P2.**

---

### F6 — `ProxySession`/`LocalProxy` shared state is read and written without a common lock, and restarts are dropped instead of coalesced

**Where:** `ios/Sources/LocalProxy.swift:292-299` (`startupError`, `proxyPort`, `useSystemNetwork`,
`isRestarting`), `:301-311` (init calls `rebuild`), `:319-346` (`setUseSystemNetwork`), `:349-371`
(`restart`), `:373-390` (`rebuild`); `ios/Sources/LocalProxy.swift:9-11` (`listener`, `port`, `started`).

**What is unsynchronized:**
- `startupError` is written in `rebuild()` (called from `init`/`restart`/`setUseSystemNetwork`, i.e. main
  *or* a global-executor thread via `WnacgClient.load`) and read from any thread in
  `WnacgClient.init`/`load` — never under a lock.
- `useSystemNetwork` is written under `restartLock` in `setUseSystemNetwork` (`:327`) but read **outside**
  the lock in `setUseSystemNetwork:320` and `restart():358`.
- `LocalProxy.listener/port/started` have no lock; `stop()` (`:31-38`) can run on main while `start()`
  runs from a global-executor thread. Only `ProxySession.isRestarting` serializes the common path, and it
  **drops** a concurrent restart request (`:351-354`, `:322-325`) instead of coalescing it: a request that
  needed the *new* session may then retry against the session that is being replaced (interacts with F3).

**Swift 5 judgement:** the compiler cannot see any of this (all types are non-`Sendable`, all calls are
synchronous). Consequence today is not a crash — word-sized pointer/bool loads don't tear in practice — but
it is a genuine data race (TSan will flag it if CI ever enables it) and the dropped-restart window produces
the intermittent request failures described in F3. Under Swift 6 these fields would have to be isolated.

**Minimal safe fix:** move `startupError`/`proxyPort`/`useSystemNetwork` access under the existing
`stateLock` (or add one small `stateLock` around all three), and make `restart()` wait for an in-progress
restart (semaphore/continuation) rather than early-return. Keep `LocalProxy`'s own `started/port/listener`
access on its existing private `queue` (or a lock) for the direct `start()` call at launch.

**Confidence:** race is certain by inspection (1.0); runtime impact is theoretical-to-low (0.4). **P2.**

---

### F7 — `FileDownloader`: cancellation before the task handle exists is ignored; continuation/task state is unsynchronized

**Where:** `ios/Sources/WnacgClient.swift:336-384` (`download(_:destination:referer:progress:)`,
`withTaskCancellationHandler`, `onCancel: { self.downloadTask?.cancel() }`), `:386-445` (delegate callbacks
mutating `destination`, `finished`, `failure`, `continuation`).

**Two issues:**
1. **Cancel-before-handle window:** `onCancel` reads `self.downloadTask`, which is only assigned inside the
   continuation body (`:378`). If the awaiting task is cancelled before that line runs, `onCancel` sees
   `nil`, nothing is cancelled, and the ZIP download proceeds to completion (up to
   `timeoutIntervalForResource = 1200`) while the caller believes it cancelled. There is no cancel UI today,
   so this is latent — but it is exactly the failure mode that appears when someone adds "取消下载".
2. **Unsynchronized state:** `downloadTask` is written by the async task and read by the cancellation
   handler on another thread; `continuation`/`destination`/`finished`/`failure` are written on the
   URLSession delegate queue and read when resuming from that same queue (mostly ordered via the resume),
   but the handle/flag sharing has no lock. `session.finishTasksAndInvalidate()` at `:431` is fine.

**Minimal safe fix:** check cancellation right after resuming and guard state with a small `NSLock`:

```swift
let task = session.downloadTask(with: request)
lock.lock(); self.downloadTask = task; lock.unlock()
task.resume()
if Task.isCancelled { task.cancel() }
```

and have `onCancel` take the lock before reading the handle. (Do not switch to `Task.detached` etc.; the
continuation shape itself is sound — exactly one resume path.)

**Confidence:** 0.8. **Real but latent** (no user-visible cancellation path exists yet).

---

### F8 — Feed force-refresh does not cancel the previous in-flight request

**Where:** `ios/Sources/CategoryView.swift:83-92` (`load(reset:force:)` increments `generation` but never
cancels the running `fetchHTML`), `ios/Sources/HomeView.swift:16-21` (same shape).

**Trigger:** pull-to-refresh (`.refreshable` is **not** disabled while a page load is in flight —
`CategoryView.swift:244-249`), the toolbar refresh button, or two quick refreshes. Each starts a new site
request while the previous one is still running; only the newest result is applied (`guard token ==
generation`), so the extra requests are pure waste and extra 429 budget on a site that is already
rate-limiting (see the 429 backoff in `WnacgClient.swift:68-81`).

**Minimal safe fix:** keep a `private var loadTask: Task<Void, Never>?` per model (or store the
`URLSessionTask`), `cancel()` it before a forced/reset load, and have `load()` run the fetch inside it.
Simpler variant: gate refresh on `!isLoading` for the *refresh* entry points too (cheapest, slightly worse
UX).

**Confidence:** 0.9 real, low impact. **P2.**

---

### F9 — Failed reader prefetch URLs are retried by every page within the next 10 pages

**Where:** `ios/Sources/ReaderView.swift:192-202` (`prefetch` de-dupes only via `prefetching`),
`:221-225` (`finishPrefetch` removes the URL from `prefetching`), `:127-143` (`image(for:)` caches only
successes), `:440-447` (each `ReaderPageView` calls `prefetch(next 10)` on appear).

**Trigger:** one image fails (img5 timeout, proxy restart — see F3/F4). The URL is removed from
`prefetching`, not cached, so the next 9–10 page appearances each re-enqueue it, and each retry also runs
the img4 mirror fallback (`:159-173`) → up to ~20 requests for one broken page plus the page view's own
foreground attempt.

**Minimal safe fix:** keep a `failedUntil: [URL: Date]` (short TTL, e.g. 20 s) and skip those URLs in
`prefetch`; or keep the URL in `prefetching` on failure and only clear it when the foreground page request
succeeds.

**Confidence:** 0.8. **P2.**

---

### F10 — Download queue drops items on async parse failure

**Where:** `ios/Sources/AppModel.swift:179-209` (`startQueued`), `:245-250` (`processNext` removes the item
before starting), `:257-379` (`download` returns `true` even after its `catch`).

**Trigger:** a queued album whose `parse` step fails (429/proxy hiccup): the `guard let preview,
errorMessage == nil else { activeAid = nil; setInflight(nil); processNext(); return }` branch
(`:188-193`) never re-inserts `item`, so the queued download silently disappears (only a global error
message remains). Similarly `download()` returns `true` on failure (`:372-378`), so `startQueued` treats it
as handled. This is a state-machine/async-failure issue rather than a data race, but it is data loss for the
user's queue.

**Minimal safe fix:** re-insert the item with a `retryCount` (cap it) in both failure branches, and return
`false` from `download()`'s catch path so `startQueued` re-queues.

**Confidence:** 0.9. **P2.**

---

### F11 — `ReaderScrollController` spawns a `Task` per KVO change and publishes four properties (theoretical perf)

**Where:** `ios/Sources/ReaderScrollController.swift:21-35` (three `scrollView.observe` closures each doing
`Task { @MainActor in self?.update() }`), `:55-71` (writes `contentHeight`, `viewportHeight`,
`isScrollable`, `progress`).

**Trigger:** continuous scrolling — KVO fires for `contentOffset` on every frame, each hop allocates a Task
and triggers 4 `objectWillChange` publishes, on top of SwiftUI's own scroll path. Not a correctness bug; a
plausible contributor to the scroll hitching the project already instruments with `PerformanceMonitor`.

**Minimal safe fix:** coalesce the callbacks instead of allocating a `Task` each time — e.g. call
`update()` through `MainActor.assumeIsolated` (iOS 17 / Swift 5.9, which this project targets; the KVO
callbacks for `contentOffset`/`bounds` are delivered on the main thread) guarded by a "pending" flag, or
drive `update()` from one `CADisplayLink`; publish a single derived value.

**Confidence:** 0.6 (not measured). **Theoretical/low.**

---

### F12 — Live Activity updates are fire-and-forget and can be applied out of order (theoretical)

**Where:** `ios/Sources/DownloadLiveActivityManager.swift:51-63` (`update` creates a new `Task { await
activity.update(content) }` per progress callback), `:65-78` (`end` nils `activity` before awaiting `end`).

**Trigger:** progress callbacks arrive faster than ActivityKit completes updates; independent tasks can
complete out of order, so the Live Activity progress can step backwards. `end()` followed immediately by a
new download's `start()` can also request a new activity while the old one is still ending.

**Minimal safe fix:** serialize updates through one stored task / latest-value mailbox (skip intermediate
frames), and keep a single "ending" activity until `end` completes.

**Confidence:** 0.6. **Theoretical.**

---

## Checked and found sound (so the Lead knows the coverage)

- **Generation-token guards** in `CategoryFeedModel.load` (`:90-113`, `:147-159`), `HomeFeedModel.load`
  (`:16-41`) and `ReaderModel.load` (`:52-95`) are correct: stale results are dropped *before* any mutation,
  the newest token always owns the `isLoading` reset, and no path can wedge `isLoading` (verified by
  induction over the token-issuing paths). `CategoryFeedModel`'s `catch` deliberately falls through to the
  reset (`:149-160`) — the earlier "cancellation stall" bug (`cb3dbe0`) is genuinely fixed.
- **`CoverLimiter` continuation discipline** (`HomeView.swift:44-103`): every `CheckedContinuation` is
  resumed exactly once; waiters are removed from `waiters` atomically under the actor; `cancel` on an
  already-granted permit is a no-op and the caller releases via `defer`
  (`HomeView.swift:169-171,172-174`). No double-resume or lost-permit path found — including the
  `Task { await self.cancel(id) }` ordering (the continuation store is synchronous inside the actor job,
  the cancel job cannot interleave).
- **Reader image dedupe + cache** (`ReaderView.swift:127-143`) is right; prefetch generation reset on
  `cancelPrefetch` (`:182-189`) cannot underflow `activePrefetch` because old generation tasks return before
  `finishPrefetch`.
- **Main-actor stores** (`HistoryStore`, `FavoritesStore`, `DownloadHistory`, `AppModel`,
  `DownloadLiveActivityManager`, `CoverImageStore`, `ReaderImageStore`, `ReaderScrollController`,
  `PerformanceMonitor`, `HighRefreshRateController`) are all `@MainActor`; I found no `@Published` write
  from a non-main thread and no `.detached` closure touching UI state.
- **Off-main heavy work** is correctly placed: thumbnail downsampling (`HomeView.swift:148-150,185-187`),
  reader decode (`ReaderView.swift:176-180`), ZIP extraction and PDF generation
  (`AppModel.swift:319-356` via `Task.detached`), PDF progress marshalled to main
  (`PDFBuilder.swift:45-47`).
- **`DoHResolver`** (`DoHResolver.swift:23-24,128-139`) guards its cache with `NSLock`; the recursive
  `query` is bounded and cancellation-propagating.
- **No retain cycles** in the long-lived paths: feed recovery uses `[weak self]` (`CategoryView.swift:170`),
  proxy connection handlers use `[weak self]` (`LocalProxy.swift:76,197,227`), KVO in
  `ReaderScrollController` uses `[weak self]`, `PerformanceMonitor` invalidates its display link on
  `onDisappear`. `FileDownloader` is retained by its session only until completion/invalidation.
- **No `@unchecked Sendable`**, no global mutable `static var` (only computed statics in
  `DownloadFolders`), no `DispatchQueue.main.sync`.

## Swift 6 / future-proofing appendix (not runtime risks today)

If `SWIFT_VERSION` is ever raised, the following will become *compile* errors, not runtime bugs — they should
not be "fixed" in a 1.22 patch unless the version bump is planned, and any fix must keep the macOS
`WnacgProxyCheck` target compiling (`ios/project.yml` compiles `LocalProxy.swift`, `WnacgClient.swift`,
`DoHResolver.swift` into a macOS tool):

- `WnacgClient`, `ProxySession`, `LocalProxy`, `FileDownloader`, `DoHResolver` are non-`Sendable` and cross
  `Task`/thread boundaries (`WnacgClient.swift:93`, `WnacgClient.swift:367` reads a URLSession config across
  threads).
- `LocalProxy`'s `startup`/`signaled` locals are mutated from the `NWListener` handler and read after
  `semaphore.wait` (safe by semaphore ordering, but a Swift 6 closure-capture warning).
- `ReaderScrollController`'s KVO closures and `ReaderScrollObserver`'s `asyncAfter` retry capture
  non-`Sendable` view/controller types (`ReaderScrollController.swift:22-33,99-101`).
- `ReaderScrollController` is created as `@State` in `ReaderView` (`ReaderView.swift:239`) though it is an
  `ObservableObject`; Swift 6/`@Observable` migration aside, this only re-allocates on view init (the
  first instance is kept) — harmless today.

## Recommended patch order

1. **F1** (3 lines, `CategoryView.swift`) — restores the advertised auto-recovery.
2. **F3** (1 line in the retry classification) + **F4** (recovery attempt in `WnacgClient.load`) — removes
   the two ways a transient network event becomes a persistent failure.
3. **F2** (async proxy start; drop the blocking call from `WnacgApp.init`) — removes the only main-thread
   stall with a hard 5 s cap.
4. F5/F8/F9 (dedupe/coalesce/cancel) — lowers duplicate request volume and 429 pressure.
5. F6/F7/F10 — hardening; schedule with the next refactor of the proxy/session and downloader.
