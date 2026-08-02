# AppCat runtime, correctness, and efficiency audit

Date: 2026-08-02
Source reviewed: `fix/picker-audit-followups` at `efc13fe23e41999ab138a9e21835bdfb048f77a7`; its tracked tree is identical to fetched `origin/main` at `8fafb0aad8ff07300968aa13e8738330343f204f`
Runtime inspected: `/Applications/appcat-dev.app`, PID `97903`, version `1.7.2 (46)`, macOS `26.5.2 (25F84)`

## Executive summary

The audit found three high-severity correctness/data-loss/side-effect defects and several material sources of avoidable idle work:

1. **P1 — toggle/service picker presentations can be stranded until another activation clears them.** A background window refresh can supersede the user-initiated refresh, suppress its completion, and leave `pendingManualPickerPresentationID` set. The first trigger shows nothing; the next trigger only cancels the stuck pending state.
2. **P1 — one malformed or forward-incompatible config file is overwritten with detected defaults at startup.** A decode error is indistinguishable from first launch, so AppCat can irreversibly discard hotkeys, ordering, visibility, profile, and custom file-routing settings.
3. **P1 — AppCat sends a side-effecting `GET` before the user chooses a destination.** It can consume a one-time login/unsubscribe/approval URL even if the user cancels; the same helper also has no reliable response-byte ceiling.
4. **P2 — AppCat reloads icons for every running app on the main actor every five seconds.** An independent 15-second idle sample reproduced `8.1–8.8%` CPU spikes at the five-second cadence; the stack sample attributes most of one poll to `NSWorkspace.icon(forFile:)`.
5. **P2 — canceled AX enumeration tasks continue doing synchronous cross-process IPC and can overlap.** Swift task cancellation is cooperative, but `WindowEnumerator.runningWindows()` never checks it. The captured sample contains two simultaneous detached enumeration stacks.
6. **P2 — the intended 250 ms AX timeout does not cover the per-window attribute reads.** The timeout is installed on the application AX element, while title/role/minimized/modal reads are performed on distinct window AX elements. Apple documents the timeout as element-specific.
7. **P2 — Core Graphics fallback work is repeated per app, and the fallback cannot satisfy its stated off-Space purpose.** Apple calls full window-dictionary generation relatively expensive; AppCat may regenerate the system list for each fallback app, then rejects every window whose `kCGWindowIsOnscreen` value is false.
8. **P2 — shortcut files are read in full on the main actor.** A large file renamed to `.webloc`, `.inetloc`, or `.url` can allocate its full size and freeze routing before the picker appears.
9. **P2 — routing history and usage are recorded before launch success is known.** Failed `NSWorkspace` opens can still become history, stats, suggestions, and app-usage signals after the fixed 750 ms delay.

There is **no runtime evidence of an AppCat-origin heap leak or a permanent CPU spin** in this capture. Footprint stayed around `101–102 MB`; `leaks` found only `17.8 KB` in Apple Link/AppIntents XPC cycles and no leaked root containing an AppCat frame. The process nevertheless performs recurring work that is expensive for an otherwise idle menu-bar utility.

## Scope and method

The review covered:

- app lifecycle, detached/unstructured tasks, cancellation, observers, event taps, and event monitors;
- five-second running-app/window polling and Accessibility/Core Graphics enumeration;
- icon, favicon, metadata, and avatar caches;
- asynchronous persistence and termination behavior;
- the picker presentation state machine and background-refresh interleavings;
- live `top`, `sample`, `ps`, and `leaks` evidence from the running DEV app;
- existing unit tests and the Clang static analyzer result supplied from the same checkout.

Severity used here:

- **P1:** user-visible core flow failure, severe hang, unrecoverable user-data loss, or unintended external side effect with a credible trigger;
- **P2:** material correctness, battery, CPU, I/O, or bounded data-loss risk;
- **P3:** low-frequency, bounded, or defensive lifecycle issue.

Runtime attribution limitation: the running DEV bundle does not expose a source commit SHA. Its symbols and source line mappings match this checkout, but runtime measurements are not exact-SHA proof.

## Findings

### F-01 — P1: background refresh can strand a manual picker presentation

**Trigger**

1. Toggle shortcut or service-key activation starts a user-initiated window snapshot and stores a `pendingManualPickerPresentationID`.
2. Before AX enumeration finishes, either the five-second poll or a workspace notification schedules another snapshot.
3. The second request increments the shared `windowSnapshotRequestID` and cancels the first task.
4. Cancellation does not stop the first synchronous AX pass. When it returns, its request-ID guard fails, so it returns without invoking the presentation completion.

**Impact**

The picker remains logically pending but never appears. The next activation takes `.cancelPendingPresentation`, clears the token, and also presents nothing. This directly explains an intermittent “shortcut did nothing” symptom.

**Evidence**

- The picker is presented only from the snapshot completion: [`AppCat/App/AppDelegate.swift:277-287`](../AppCat/App/AppDelegate.swift#L277).
- A pending presentation changes the next trigger into cancellation: [`AppCat/App/AppDelegate.swift:234-244`](../AppCat/App/AppDelegate.swift#L234).
- The user-initiated path delegates to the shared request mechanism: [`AppCat/Services/AppActivityMonitor.swift:108-112`](../AppCat/Services/AppActivityMonitor.swift#L108).
- Every request increments the same generation, cancels the prior task, and invokes completion only when the generation still matches: [`AppCat/Services/AppActivityMonitor.swift:199-228`](../AppCat/Services/AppActivityMonitor.swift#L199).
- The independent poll requests work every five seconds: [`AppCat/Services/AppActivityMonitor.swift:165-173`](../AppCat/Services/AppActivityMonitor.swift#L165). Workspace changes can request the same work: [`AppCat/Services/AppActivityMonitor.swift:138-152`](../AppCat/Services/AppActivityMonitor.swift#L138).
- No test currently references `AppActivityMonitor`, `refreshWindowsForPickerPresentation`, or `windowSnapshotRequestID`.

**Smallest fix direction**

Make snapshot enumeration single-flight and priority-aware at `AppActivityMonitor`: a utility refresh must never supersede an in-flight user-initiated request. Attach picker completions to the current pass, or promote/coalesce that pass, and guarantee every completion is resolved exactly once even when a request is canceled. A timeout in `AppDelegate` would mask the shared-state bug rather than fix it.

**Validation plan**

Inject a controllable window-enumerator closure. Start a picker request, fire a utility poll before releasing the first enumeration, then assert:

- picker completion fires exactly once;
- the newest snapshot publishes once;
- `pendingManualPickerPresentationID` clears;
- one activation presents the picker rather than requiring a second/third trigger.

### F-02 — P2: idle polling reloads every running-app icon on the main actor

**Trigger and impact**

Every five seconds, the main-actor polling task calls `refreshRunningApplications()`. That method rebuilds `runningAppsByBundleID` and obtains an icon for every running app, falling back to `NSWorkspace.icon(forFile:)`. This creates recurring AppKit/file-icon work, image churn, observation comparisons, and UI-thread latency while AppCat is idle.

**Evidence**

- Fixed five-second cadence and main-actor task: [`AppCat/Services/AppActivityMonitor.swift:14-15`](../AppCat/Services/AppActivityMonitor.swift#L14), [`AppCat/Services/AppActivityMonitor.swift:165-173`](../AppCat/Services/AppActivityMonitor.swift#L165).
- Full running-app model and icon rebuilt each pass: [`AppCat/Services/AppActivityMonitor.swift:53-94`](../AppCat/Services/AppActivityMonitor.swift#L53), especially line 67.
- The repo already has a downsampling helper specifically because retaining full icon representations costs memory: [`AppCat/Services/AppIconLoader.swift:3-10`](../AppCat/Services/AppIconLoader.swift#L3).
- Apple documents that `icon(forFile:)` returns the file icon and is safe to call off the main thread: [Apple `NSWorkspace.icon(forFile:)`](https://developer.apple.com/documentation/appkit/nsworkspace/icon%28forfile%3A%29).
- The 1 ms stack sample (`/tmp/appcat-runtime-audit.sample.txt`) contains 338 samples in one `refreshRunningApplications()` pass; 249 are below `NSWorkspace iconForFile:`.
- Independent 15-second `top` sampling at 16:55 showed three poll-aligned spikes: `8.7%`, `8.1%`, and `8.8%`, with near-zero CPU between them. Arithmetic mean across the 15 one-second observations was about `1.7%` of one core. An earlier 30-second capture saw `7–12%` spikes and roughly `3%` average.

This is recurring CPU/I/O work, not a runaway loop: thread count returned to 4–5 and CPU returned to ~0% between polls.

**Smallest fix direction**

Reuse the prior `InstalledApp`/icon for unchanged `(bundleID, bundleURL)` pairs. Running-set, activation-policy, and frontmost fields can still refresh cheaply. Load a new icon only for a newly seen or relocated app, using the existing `AppIconLoader` rather than adding another cache layer. Apple explicitly permits icon loading off-main if a miss still needs I/O.

**Validation plan**

- Inject/count icon loads: after one warm refresh, ten unchanged polls must perform zero icon loads.
- Capture 60 seconds of idle `top` plus `sample`; the five-second `iconForFile:` stacks should disappear.
- Verify launch/terminate notifications still add/remove apps and that an app whose bundle URL changes gets a fresh icon.

### F-03 — P2: cancellation does not stop AX enumeration, so refreshes overlap

**Trigger and impact**

Each new snapshot cancels the stored detached task, but the task immediately enters synchronous `WindowEnumerator.runningWindows()`. That function loops through every regular app without checking cancellation. A slow pass therefore continues while a new pass starts. Under an unresponsive target or a burst of workspace changes this multiplies Accessibility/Core Graphics IPC, CPU, and temporary allocations; it also widens F-01’s race window.

**Evidence**

- Cancel-and-replace task logic: [`AppCat/Services/AppActivityMonitor.swift:205-213`](../AppCat/Services/AppActivityMonitor.swift#L205).
- Enumeration loops through all regular apps without `Task.isCancelled`/`checkCancellation()`: [`AppCat/Services/WindowEnumerator.swift:159-168`](../AppCat/Services/WindowEnumerator.swift#L159).
- Swift documents cancellation as cooperative and puts responsibility on running code to check it: [Swift `Task` cancellation](https://developer.apple.com/documentation/swift/task/), [The Swift Programming Language — Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html#ID645).
- The captured sample contains two distinct live detached-task groups in `AppActivityMonitor.requestWindowSnapshot`: one with 157 samples and another with 118 samples, both inside `WindowEnumerator.runningWindows()`.

**Smallest fix direction**

Use one in-flight enumeration, coalesce demand, and check cancellation between apps and before expensive fallbacks. Do not rely on `Task.cancel()` to preempt synchronous AX calls. This should be implemented together with F-01 so there is one owner for request priority, completion delivery, and publication.

**Validation plan**

Use a blocking fake enumerator and issue 20 poll/workspace/picker requests. Assert maximum concurrent enumerations is one, the picker completion is not lost, and the final published snapshot corresponds to the newest demand.

### F-04 — P2: the 250 ms AX timeout does not cover window attribute calls

**Trigger and impact**

AppCat sets `AXUIElementSetMessagingTimeout` on the application element before reading `kAXWindowsAttribute`, but then performs title, role, subrole, minimized, and modal queries on each returned **window element** without setting a timeout on those elements. A target app that stops responding can therefore stall those cross-process calls longer than the code’s intended 250 ms cap. Window activation also reads/actions window elements without applying the timeout.

**Evidence**

- Intended timeout constant and claim: [`AppCat/Services/WindowEnumerator.swift:83-85`](../AppCat/Services/WindowEnumerator.swift#L83).
- Timeout applied only to `axApp`: [`AppCat/Services/WindowEnumerator.swift:280-289`](../AppCat/Services/WindowEnumerator.swift#L280).
- Attribute reads occur on each distinct `window`: [`AppCat/Services/WindowEnumerator.swift:292-303`](../AppCat/Services/WindowEnumerator.swift#L292), via helpers at [`AppCat/Services/WindowEnumerator.swift:431-440`](../AppCat/Services/WindowEnumerator.swift#L431).
- Apple documents that setting a timeout on a non-system-wide AX element sets it only for that element, not other AX objects: [Apple `AXUIElementSetMessagingTimeout`](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout).

**Smallest fix direction**

Apply the existing timeout to every window AX element before reading or mutating its attributes. Keep the value local rather than changing the process-wide Accessibility timeout.

**Validation plan**

Exercise enumeration and activation against a controlled Accessibility test app that deliberately delays window attribute replies. Measure a bounded per-window duration and verify a later app still enumerates after the delayed target.

### F-05 — P2: full Core Graphics window snapshots can be regenerated once per fallback app

**Trigger and impact**

`runningWindows()` iterates apps, and each app whose AX/menu targets are empty calls `CGWindowListCopyWindowInfo` for the entire session before filtering to one PID. Several such apps turn one system-wide snapshot into N snapshots per five-second pass.

**Evidence**

- Per-app loop: [`AppCat/Services/WindowEnumerator.swift:159-168`](../AppCat/Services/WindowEnumerator.swift#L159).
- Per-app fallback: [`AppCat/Services/WindowEnumerator.swift:241-265`](../AppCat/Services/WindowEnumerator.swift#L241).
- System-wide copy inside that fallback: [`AppCat/Services/WindowEnumerator.swift:350-372`](../AppCat/Services/WindowEnumerator.swift#L350).
- Apple explicitly says generating these dictionaries for system windows is relatively expensive and recommends profiling/adjusting usage: [Apple `CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo%28_%3A_%3A%29).
- The live sample includes `cgWindowCandidates` stacks in both overlapping enumeration tasks.

**Smallest fix direction**

Take at most one Core Graphics snapshot per `runningWindows()` pass, group entries by owner PID, and pass the grouped candidates into each app fallback. No new cache or long-lived invalidation policy is needed.

**Validation plan**

Inject/count the Core Graphics snapshot provider. A pass with ten fallback apps must call it once and produce the same per-PID targets as today.

### F-06 — P2 contract contradiction: the stated off-Space fallback rejects offscreen windows

**Trigger and impact**

The source says Core Graphics is the last resort when an app has windows that are off-Space or empty-titled and has no usable Window menu. However, Core Graphics candidates are accepted only when `isOnscreen == true`. Apple defines `kCGWindowIsOnscreen` as whether the window is currently onscreen, so the stated off-Space case cannot pass this filter. This is a confirmed code/comment/test contract contradiction; whether it is a product defect depends on the intended balance between cross-Space coverage and phantom-window suppression.

**Evidence**

- Stated fallback purpose and call: [`AppCat/Services/WindowEnumerator.swift:244-265`](../AppCat/Services/WindowEnumerator.swift#L244).
- Filter requires `candidate.isOnscreen == true`: [`AppCat/Services/WindowEnumerator.swift:490-500`](../AppCat/Services/WindowEnumerator.swift#L490).
- Apple’s key definition: [Apple `kCGWindowIsOnscreen`](https://developer.apple.com/documentation/coregraphics/kcgwindowisonscreen).
- The current test explicitly classifies `isOnscreen: false` as invalid: [`AppCatTests/SmokeTests.swift:1034-1099`](../AppCatTests/SmokeTests.swift#L1034). This locks in the contradiction rather than testing the claimed cross-Space behavior.

**Smallest fix direction**

First decide the contract explicitly: if cross-Space Core Graphics fallback is required, accept carefully filtered offscreen layer-0/shared/content-sized windows and add a real cross-Space installed-app test. If phantom-window avoidance is more important, remove the unsupported fallback claim and rely only on the Window-menu path. Do not simply drop every filter.

**Validation plan**

Use a controlled app with one named document window on another Space and no usable Window menu. Verify whether the product contract expects a tile, then encode that decision in the filter test and an installed DEV UI check.

### F-07 — P2: queued history/stats/usage writes are not flushed before termination

**Trigger and impact**

History, daily stats, and app-usage writes are queued asynchronously. `applicationWillTerminate` stops listeners but does not wait for those queues. If the user quits immediately after selecting a target, the last history/stat/usage update can be lost. Sudden termination remains a separate, larger durability boundary.

**Evidence**

- Async history writes: [`AppCat/Services/HistoryStorage.swift:8-23`](../AppCat/Services/HistoryStorage.swift#L8).
- Async stats writes: [`AppCat/Services/StatsStorage.swift:12-26`](../AppCat/Services/StatsStorage.swift#L12).
- Async app-usage writes: [`AppCat/Services/AppUsageStorage.swift:17-27`](../AppCat/Services/AppUsageStorage.swift#L17).
- Termination performs no persistence drain: [`AppCat/App/AppDelegate.swift:153-162`](../AppCat/App/AppDelegate.swift#L153).
- Apple says the app terminates after `applicationWillTerminate(_:)` returns and notes that the callback is absent during sudden termination: [Apple `applicationWillTerminate(_:)`](https://developer.apple.com/documentation/AppKit/NSApplicationDelegate/applicationWillTerminate%28_%3A%29).

**Smallest fix direction**

Expose a queue-drain/`flush()` on the three asynchronous stores and invoke it during normal termination. Keep atomic writes; do not introduce a database for three bounded JSON files.

**Validation plan**

Record one selection, immediately terminate normally, relaunch, and assert the history row, daily counters, and app-use count all advanced. Repeat in a loop to widen the race before and after the fix.

### F-08 — P3: `AppActivityMonitor.stop()` is not a terminal state

**Trigger and impact**

Canceling the polling task causes `Task.sleep` to throw, but `try?` suppresses the error and execution continues to one final `refreshRunningApplications()` and `scheduleWindowRefresh(after: 0)`. Because `stop()` has already canceled and nilled the stored refresh tasks, this final iteration can create a new detached enumeration. An already-running enumeration can also publish after `stop()` because stopping does not invalidate its request ID or guard publication with a running flag.

**Evidence**

- Stop ordering: [`AppCat/Services/AppActivityMonitor.swift:38-50`](../AppCat/Services/AppActivityMonitor.swift#L38).
- Poll body has no cancellation guard after sleep: [`AppCat/Services/AppActivityMonitor.swift:165-173`](../AppCat/Services/AppActivityMonitor.swift#L165).
- Detached result publication checks only request ID and `appState`, not lifecycle state/cancellation: [`AppCat/Services/AppActivityMonitor.swift:212-228`](../AppCat/Services/AppActivityMonitor.swift#L212).
- Swift documents that cancellation must be cooperatively observed: [Swift `Task`](https://developer.apple.com/documentation/swift/task/).

Production impact is currently low because `stop()` is called during process termination, but the method’s contract is unsafe for tests, restarts, or future sleep/pause lifecycle use.

**Smallest fix direction**

Guard immediately after the sleep, mark the monitor stopped, increment/invalidate the snapshot generation in `stop()`, and reject publication while stopped.

**Validation plan**

Start with a blocking fake enumeration, call `stop()`, release the fake, advance the polling clock, and assert no new enumeration, state mutation, or callback occurs.

### F-09 — P1: pre-choice metadata GET can trigger external side effects; response bytes are also unbounded

**Trigger and impact**

For every incoming HTTPS URL, AppCat immediately performs a metadata `GET` before the user chooses a destination. One-time login, unsubscribe, approval, payment, tracking, or local-host endpoints can therefore be consumed or mutated even when the user cancels the picker; the selected browser may then request the URL a second time. A byte cap would not fix this correctness/privacy boundary.

Separately, the helper asks for the first 16 KiB using `Range`, but `URLSession.shared.data(for:)` still buffers the complete response that the server sends. HTTP permits a server to ignore `Range`, so a fast, very large response can create a large temporary allocation. The redirect-history resolver normally sends `HEAD`, but on `405` it retries with an unrestricted `GET` and also waits for the body through `data(for:)`.

**Evidence**

- Automatic fetch for every incoming URL: [`AppCat/App/AppDelegate.swift:329-337`](../AppCat/App/AppDelegate.swift#L329), [`AppCat/App/AppDelegate.swift:389-398`](../AppCat/App/AppDelegate.swift#L389).
- Advisory `Range` header followed by whole-response `data(for:)` and whole-body UTF-8 conversion: [`AppCat/Managers/LinkMetadataManager.swift:46-65`](../AppCat/Managers/LinkMetadataManager.swift#L46).
- `HEAD` to unrestricted `GET` fallback: [`AppCat/Services/URLResolver.swift:24-47`](../AppCat/Services/URLResolver.swift#L24).
- Apple describes data tasks as returning response data in memory and provides incremental bytes/delegate APIs: [Apple `URLSession`](https://developer.apple.com/documentation/foundation/urlsession).
- RFC 9110 says a server may ignore a `Range` field and a client cannot assume future partial responses: [RFC 9110, Range Requests](https://www.rfc-editor.org/rfc/rfc9110.html#section-14).

The five-second timeout limits duration, not bytes transferred during that duration. The 500-entry metadata cache limits retained entry count, not the peak response allocation.

**Smallest fix direction**

Remove automatic dereferencing of the destination URL for title enrichment; host-only display data is already available without a request. If an explicitly user-authorized metadata fetch remains, use an ephemeral `URLSession`, consume bytes incrementally, and cancel at a small hard cap. For redirect resolution, use a task/delegate that stops after headers/redirect completion instead of downloading a fallback body.

**Validation plan**

First assert that receiving and then canceling routing for a one-time URL sends no request at all. Then, for any retained explicit-fetch seam, serve a local HTTPS fixture that ignores `Range` and streams a large body; assert AppCat cancels at the cap. Repeat with a `HEAD 405` endpoint and assert the redirect resolver does not consume its full `GET` body.

### F-10 — P2: shortcut parsing reads arbitrary files in full on the main actor

**Trigger and impact**

AppCat registers a broad file-routing path and normalizes incoming URLs synchronously in `AppDelegate`. Files ending in `.webloc`, `.inetloc`, or `.url` are loaded with `Data(contentsOf:)` before parsing, with no size check. A user can therefore open a large or maliciously renamed file and make the main actor allocate/read the entire file before routing continues.

**Evidence**

- Both shortcut formats use whole-file `Data(contentsOf:)`: [`AppCat/Services/FileShortcutResolver.swift:18-57`](../AppCat/Services/FileShortcutResolver.swift#L18).
- Normalization maps every incoming URL synchronously: [`AppCat/App/AppDelegate.swift:329-336`](../AppCat/App/AppDelegate.swift#L329), [`AppCat/App/AppDelegate.swift:373-386`](../AppCat/App/AppDelegate.swift#L373).

**Smallest fix direction**

Read resource values first and reject shortcut files above a small configuration-file ceiling. Keep parsing synchronous only for accepted small files; no streaming parser or new dependency is necessary.

**Validation plan**

Pass a valid small shortcut and an oversized sparse fixture through the real normalization seam. Assert the small file resolves and the oversized file is rejected/falls back without reading its body or blocking the main actor.

### F-11 — P2: failed launches can still be recorded as successful behavior

**Trigger and impact**

For link routing, `PickerCoordinator` starts the browser/app open and immediately schedules history, stats, suggestion, and app-usage work. The normal browser launcher receives `NSWorkspace` success or failure asynchronously, but does not report it back to the coordinator. Native-app candidates also complete asynchronously and may all fail before falling back to activation. Regardless, the fixed 750 ms task records the selection as a success.

This corrupts user-visible history and the data used for stats/ranking/suggestions. It also adds a second loss window: quitting or crashing during the untracked 750 ms delay drops all post-selection work even before the storage queues in F-07 are reached.

**Evidence**

- Coordinator launches and records without awaiting a result: [`AppCat/Managers/PickerCoordinator.swift:132-175`](../AppCat/Managers/PickerCoordinator.swift#L132), [`AppCat/Managers/PickerCoordinator.swift:177-207`](../AppCat/Managers/PickerCoordinator.swift#L177).
- History/stats/app usage run after an untracked 750 ms sleep: [`AppCat/Managers/PickerCoordinator.swift:232-307`](../AppCat/Managers/PickerCoordinator.swift#L232).
- `BrowserLauncher` logs the asynchronous normal-open error but exposes no result to its caller: [`AppCat/Services/BrowserLauncher.swift:137-157`](../AppCat/Services/BrowserLauncher.swift#L137).
- Native-app open failures recurse/fallback internally after the coordinator has already scheduled success recording: [`AppCat/Services/BrowserLauncher.swift:219-263`](../AppCat/Services/BrowserLauncher.swift#L219).
- The manual app/window switch path already demonstrates the correct local contract by recording only when synchronous activation returns `true`: [`AppCat/Managers/PickerCoordinator.swift:140-150`](../AppCat/Managers/PickerCoordinator.swift#L140), [`AppCat/Managers/PickerCoordinator.swift:183-193`](../AppCat/Managers/PickerCoordinator.swift#L183).

**Smallest fix direction**

Propagate one final success/failure completion from the existing `BrowserLauncher` operations and record only the first confirmed success. Persist critical history/stats immediately after confirmation; defer only suggestion recomputation and the visual handoff overlay.

**Validation plan**

Inject the existing launcher dependencies so every candidate fails, wait beyond 750 ms, and assert history, stats, app usage, and suggestions are unchanged. Add the mirror success case and a multi-candidate case that records exactly once.

### F-12 — current-runtime unverified: hold-Option-Tab source conflicts with its non-key fullscreen contract

The current source distinguishes hold-to-switch behavior, but panel presentation always calls `makeKey()` and key resignation either refocuses or dismisses. That conflicts with the already documented design in which the event tap owns Tab cycling and Option-release selection while the hold picker remains non-key.

- Hold mode is distinct but has no focus policy: [`AppCat/Features/Picker/PickerInvocationSource.swift:1-28`](../AppCat/Features/Picker/PickerInvocationSource.swift#L1).
- Every presentation focuses the panel: [`AppCat/Features/Picker/PickerWindowController.swift:249-265`](../AppCat/Features/Picker/PickerWindowController.swift#L249), [`AppCat/Features/Picker/PickerWindowController.swift:342-345`](../AppCat/Features/Picker/PickerWindowController.swift#L342).
- Resigning key refocuses or closes it: [`AppCat/Features/Picker/PickerWindowController.swift:1080-1101`](../AppCat/Features/Picker/PickerWindowController.swift#L1080).
- The repo’s fullscreen research defines hold mode as non-key and requires real WindowServer verification: [`docs/appcat-fullscreen-picker-research.md`](appcat-fullscreen-picker-research.md).

A prior live run reproduced an invisible hold picker over fullscreen Slack while Option-release still activated the selected app, which is consistent with this path. The exact fullscreen Slack case was **not rerun against this process/HEAD**, so this audit treats the source-contract violation as confirmed but the current live symptom as unverified. The smallest fix is source-specific focus policy, not Slack-specific code; validation requires a native fullscreen host plus WindowServer overlap/layer assertions because the existing flag-only tests are false-green for visibility.

### F-13 — P1: config decode failure is treated as first launch and overwrites user settings

**Trigger and impact**

Both config loaders return `nil` for two materially different states: “file does not exist” and “existing file could not be read or decoded.” Startup treats either as first launch, reconstructs detected defaults, then immediately saves them over the existing file. One partial/corrupt write, manual edit, or config produced by a newer AppCat version can therefore irreversibly erase browser/app order, visibility, hotkeys, profile settings, display names, custom formats, and universal-file routing choices.

**Evidence**

- Existing-file read/decode errors collapse to `nil`: [`AppCat/Services/BrowserConfigStorage.swift:24-34`](../AppCat/Services/BrowserConfigStorage.swift#L24), [`AppCat/Services/AppConfigStorage.swift:24-34`](../AppCat/Services/AppConfigStorage.swift#L24).
- Browser startup uses defaults when `nil` and always saves afterward: [`AppCat/Managers/BrowserManager.swift:9-29`](../AppCat/Managers/BrowserManager.swift#L9), [`AppCat/Managers/BrowserManager.swift:57-62`](../AppCat/Managers/BrowserManager.swift#L57).
- App startup follows the same pattern: [`AppCat/Managers/AppManager.swift:27-53`](../AppCat/Managers/AppManager.swift#L27).
- Existing tests cover legacy field decoding but not whole-file corruption followed by manager startup.

**Smallest fix direction**

Distinguish `.missing`, `.loaded(config)`, and `.failed(error)` at the storage boundary. Only `.missing` may seed and save defaults. Preserve or quarantine a failed file and surface recovery/reset explicitly; do not add a migration framework until the schema actually requires one.

**Validation plan**

Start each manager with a pre-existing malformed file and a forward-incompatible fixture. Assert the bytes remain unchanged and no default save occurs. Keep the current missing-file case to prove first-launch seeding still works.

### F-14 — P2: a live picker preserves stale targets when the authoritative list becomes empty

During a toggle/service session, `refreshSnapshotForVisibleSession()` rebuilds the authoritative snapshot but restores `oldItems` whenever the new result is empty: [`AppCat/Features/Picker/PickerWindowController.swift:631-649`](../AppCat/Features/Picker/PickerWindowController.swift#L631). This prevents visible churn during a transient refresh, but it also means that if all displayed apps/windows really close, dead targets remain selectable indefinitely. The current test removes only part of a non-empty list and does not cover non-empty → empty: [`AppCatTests/PickerSessionTests.swift:329-341`](../AppCatTests/PickerSessionTests.swift#L329).

The smallest correction is to publish the genuine empty state (or dismiss with a clear empty-state policy) after an authoritative refresh; do not silently reinstate stale targets. Validate a real session that transitions from one target to zero and assert the closed target can no longer be opened.

## Confirmed lower-priority lifecycle and ordering risks

### R-01 — P3: detached installed-app rescans can overlap and publish stale results

`AppManager.refreshAppsInBackground()` creates an untracked detached scan on every call and applies whichever result finishes last; it has no generation token or single-flight guard: [`AppCat/Managers/AppManager.swift:17-25`](../AppCat/Managers/AppManager.swift#L17). The caller debounces launch/termination bursts by two seconds, but a slow directory/icon scan can still overlap a later scan: [`AppCat/Services/AppActivityMonitor.swift:145-160`](../AppCat/Services/AppActivityMonitor.swift#L145).

Impact was not reproduced in this runtime capture. The credible failure is an older scan overwriting a newer installed-app set/config after launch/install/uninstall churn. Store the task plus generation, or coalesce scans; validate by making scan A finish after scan B and asserting only B publishes/saves.

### R-02 — P3: one bounded ARC cycle retains the picker controller/coordinator pair

`PickerCoordinator` strongly owns `pickerController`: [`AppCat/Managers/PickerCoordinator.swift:13-16`](../AppCat/Managers/PickerCoordinator.swift#L13), [`AppCat/Managers/PickerCoordinator.swift:28-34`](../AppCat/Managers/PickerCoordinator.swift#L28). `PickerWindowController` strongly owns the coordinator: [`AppCat/Features/Picker/PickerWindowController.swift:136-156`](../AppCat/Features/Picker/PickerWindowController.swift#L136).

This is **not a current runaway leak**: production creates one pair intended to live for the process, and the pair remains reachable from `AppDelegate`. It does prevent reclamation in tests or if picker infrastructure is recreated later. Making the controller’s coordinator reference `unowned` (or weak with guards) removes the cycle without a new abstraction.

### R-03 — P3: the cold hold-Option-Tab path can enumerate all windows on the main actor

If no background snapshot has landed, hold-Option-Tab calls `refreshWindowSnapshotForPicker()` synchronously before showing: [`AppCat/App/AppDelegate.swift:291-296`](../AppCat/App/AppDelegate.swift#L291). That method directly calls `WindowEnumerator.runningWindows()` from its `@MainActor` owner: [`AppCat/Services/AppActivityMonitor.swift:96-104`](../AppCat/Services/AppActivityMonitor.swift#L96). This contradicts the enumerator’s own off-main rationale: [`AppCat/Services/WindowEnumerator.swift:20-23`](../AppCat/Services/WindowEnumerator.swift#L20).

The window is narrow (startup before the initial background snapshot) and was not observed in the warm process. Avoid synchronous IPC: present an empty/current cached snapshot immediately and refresh asynchronously, or guarantee prewarming completes before enabling the chord.

### R-04 — P3: Accessibility permission UI can remain stale after returning from Settings

`ShortcutsSettingsView` reads global permission functions directly, so granting Accessibility creates no observable state change: [`AppCat/Features/Settings/ShortcutsSettingsView.swift:101-123`](../AppCat/Features/Settings/ShortcutsSettingsView.swift#L101). `applicationDidBecomeActive` refreshes the listener but does not mutate view state: [`AppCat/App/AppDelegate.swift:143-150`](../AppCat/App/AppDelegate.swift#L143). The banner can remain until another unrelated render. Recheck permissions into observable state on app activation; verify a Settings round trip rather than only section navigation.

### R-05 — P3: the documented WKWebView “one AX window” fallback is not implemented

`WindowEnumerator` says WKWebView wrappers are handled by a `≤1-window` symptom path, but `shouldMergeWindowMenu` consults the Window menu for a normal non-Electron app only when the AX count is exactly zero: [`AppCat/Services/WindowEnumerator.swift:509-527`](../AppCat/Services/WindowEnumerator.swift#L509). A multi-window WKWebView wrapper exposing one AX window can therefore remain under-reported. Existing tests intentionally assert `false` for one normal AX window and cover Electron separately: [`AppCatTests/SmokeTests.swift:1203-1218`](../AppCatTests/SmokeTests.swift#L1203). Confirm with a real wrapper before changing the heuristic because broad menu merging can create phantom Chrome-style duplicates.

## Potential optimizations, not confirmed bugs

1. **Profile avatar cache:** `ProfileAvatarBadge.avatarCache` is process-wide and has no explicit count/cost limit; it stores images loaded from profile paths without downsampling: [`AppCat/Features/Picker/BrowserCell.swift:313-330`](../AppCat/Features/Picker/BrowserCell.swift#L313). `NSCache` has automatic eviction under memory pressure, so this is not an unbounded dictionary or a proven leak. A modest `countLimit` plus the existing downsampler is reasonable only if Instruments shows profile-image growth. [Apple `NSCache`](https://developer.apple.com/documentation/foundation/nscache).
2. **Negative favicon caching:** failed favicon fetches are removed from `inFlight` and not cached, so repeatedly recreated views can retry the same missing favicon: [`AppCat/Managers/FaviconManager.swift:39-50`](../AppCat/Managers/FaviconManager.swift#L39), [`AppCat/Managers/FaviconManager.swift:71-96`](../AppCat/Managers/FaviconManager.swift#L71). Add a short negative TTL only if network traces show repeated failures; the current request timeout is bounded.
3. **Installed-app rescans:** a launch/termination causes a complete Applications-directory walk, bundle parsing, format inspection, and icon decode. It is already debounced and off-main. Optimize only after F-02/F-03, which are recurring and measured.

## Runtime evidence

### CPU and thread behavior

- At 16:54, `ps` showed PID `97903` at `0.1%` CPU, `59,632 KiB` RSS, sleeping, after about two days of uptime.
- A 15-second one-second-interval `top` sample held memory at about `102 MB` and threads at 4–5. CPU spikes of `8.7%`, `8.1%`, and `8.8%` appeared roughly five seconds apart; intervening observations were `0–0.2%`.
- The 1 ms `sample` capture reports `101.0 MB` footprint and `158.5 MB` peak. The main thread had 11,803 samples total; 11,426 were in the event-loop subtree and 11,383 were blocked in normal AppKit/CoreFoundation waiting, so there is no evidence of a main-thread busy loop.
- The meaningful sampled work was the five-second `refreshRunningApplications` icon pass and two overlapping detached `WindowEnumerator` passes.

### Heap behavior

`/usr/bin/leaks 97903` at 16:54 reported:

```text
Physical footprint: 101.7M
Physical footprint (peak): 158.5M
Process 97903: 367 leaks for 18256 total leaked bytes.
367 (17.8K) << TOTAL >>
```

All displayed roots were Apple `NSXPCConnection`/`com.apple.linkd.autoShortcut`/AppIntents cycles. No leaked root included `AppCat DEV.debug.dylib`. This is a point-in-time leak scan, not a growth test; it rules out an obvious leaked allocation family in this capture but cannot prove long-term heap stability.

## Clean checks and existing safeguards

- `xcodebuild analyze -project AppCat.xcodeproj -scheme 'AppCat DEV' -destination 'platform=macOS' -quiet` exited 0 with no analyzer diagnostics.
- Unit result: **233 passed, 0 failed, 0 skipped** in the captured `.xcresult`.
- `PickerActivationListener.stop()` disables its event tap and removes its run-loop source: [`AppCat/Services/PickerActivationListener.swift:75-86`](../AppCat/Services/PickerActivationListener.swift#L75).
- `PickerWindowController.close()` removes global/local mouse and key monitors; the scroll bridge also removes its monitor on removal/deinit: [`AppCat/Features/Picker/PickerWindowController.swift:320-405`](../AppCat/Features/Picker/PickerWindowController.swift#L320), [`AppCat/Features/Picker/PickerView.swift:930-969`](../AppCat/Features/Picker/PickerView.swift#L930).
- Workspace notification tokens are removed in `AppActivityMonitor.stop()`: [`AppCat/Services/AppActivityMonitor.swift:38-42`](../AppCat/Services/AppActivityMonitor.swift#L38).
- Favicon memory cache is explicitly limited to 256 entries and disk-backed: [`AppCat/Managers/FaviconManager.swift:7-20`](../AppCat/Managers/FaviconManager.swift#L7).
- Link metadata cache is explicitly limited to 500 entries and in-flight requests are deduplicated: [`AppCat/Managers/LinkMetadataManager.swift:11-44`](../AppCat/Managers/LinkMetadataManager.swift#L11).
- Network metadata/favicon requests use five-second request timeouts: [`AppCat/Managers/LinkMetadataManager.swift:46-68`](../AppCat/Managers/LinkMetadataManager.swift#L46), [`AppCat/Managers/FaviconManager.swift:71-96`](../AppCat/Managers/FaviconManager.swift#L71).
- Window enumeration already runs off-main for normal polling and uses generation checks to prevent stale result publication; the defect is request/completion ownership and non-cooperative work, not absence of any stale-result defense.

Passing tests and a clean analyzer do not cover the request interleavings, process-exit durability, real Accessibility IPC, or idle resource cadence identified above.

## Recommended order

1. **Prevent config destruction (F-13)** by distinguishing missing from unreadable/invalid files before any startup save.
2. **Fix F-01 and F-03 together** with one priority-aware, single-flight snapshot owner and a deterministic interleaving test.
3. **Fix F-02** by reusing unchanged running-app models/icons; this is the clearest measured idle-energy win.
4. **Remove the pre-choice metadata GET and bound retained network/file reads (F-09/F-10)** at the existing seams.
5. **Record only confirmed launch success (F-11)** and remove the 750 ms durability window.
6. **Apply per-window AX timeouts (F-04)** and share one Core Graphics snapshot per pass (F-05).
7. **Decide and test the cross-Space/empty-snapshot contract (F-06/F-14)** before changing filters, and rerun the fullscreen hold path with real WindowServer assertions before changing F-12.
8. Add normal-termination persistence drains (F-07), then close the lower-priority lifecycle gaps when touching those modules.

No new dependency or architecture layer is needed for these changes; the smallest fixes belong in the existing monitor, enumerator, and storage seams.

## Primary platform sources

- [Swift `Task` and cooperative cancellation](https://developer.apple.com/documentation/swift/task/)
- [The Swift Programming Language — Concurrency and cancellation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html#ID645)
- [Apple `AXUIElementSetMessagingTimeout`](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)
- [Apple `CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo%28_%3A_%3A%29)
- [Apple `kCGWindowIsOnscreen`](https://developer.apple.com/documentation/coregraphics/kcgwindowisonscreen)
- [Apple `NSWorkspace.icon(forFile:)`](https://developer.apple.com/documentation/appkit/nsworkspace/icon%28forfile%3A%29)
- [Apple `NSCache`](https://developer.apple.com/documentation/foundation/nscache)
- [Apple `applicationWillTerminate(_:)`](https://developer.apple.com/documentation/AppKit/NSApplicationDelegate/applicationWillTerminate%28_%3A%29)
- [Apple `URLSession`](https://developer.apple.com/documentation/foundation/urlsession)
- [RFC 9110 — HTTP Range Requests](https://www.rfc-editor.org/rfc/rfc9110.html#section-14)
