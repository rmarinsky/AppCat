# AppCat Fullscreen Picker Research

## Question

How should AppCat present an interactive picker in the active macOS Space, including a native
fullscreen Space owned by another application, without switching Spaces or requiring a preliminary
focus click?

This document records the Apple guidance, the controlled fixture, and the behavior verified by the
implementation in PR #21.

## Apple DTS Model

Apple DTS documents this cross-application fullscreen overlay configuration:

- an accessory application activation policy, or an `LSUIElement` agent;
- an `NSPanel` created with `.nonactivatingPanel`;
- `isFloatingPanel = true` and `hidesOnDeactivate = false`;
- `.screenSaver` window level;
- `.canJoinAllSpaces`, `.canJoinAllApplications`, `.fullScreenAuxiliary`, and `.stationary`;
- presentation through `orderFrontRegardless()`.

DTS explicitly notes that `.floating` and `.statusBar` remain below fullscreen content. See the
[accepted Apple DTS answer](https://developer.apple.com/forums/thread/826308).

`canJoinAllApplications` is available from macOS 13. The AppKit header in the installed Xcode 26.5
SDK declares:

```objc
NSWindowCollectionBehaviorCanJoinAllApplications API_AVAILABLE(macos(13.0))
```

AppCat supports macOS 14+, so every supported OS uses the same collection policy:

```swift
[
    .canJoinAllSpaces,
    .canJoinAllApplications,
    .fullScreenAuxiliary,
    .stationary,
    .ignoresCycle,
]
```

Apple's [`canJoinAllApplications`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)
contract covers joining other applications' fullscreen Spaces when eligible.
[`fullScreenAuxiliary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)
allows a window to display in the same Space as a fullscreen window. DTS uses both flags together.

## Controlled Fixture Result

A temporary bundled AppKit fixture was built before the production patch. It contains a native
fullscreen host, a candidate overlay, a WindowServer probe, and injected keyboard events.

The accepted candidate used the complete DTS policy plus:

1. `orderFrontRegardless()`;
2. `makeKey()`;
3. `makeFirstResponder(...)` on a content view whose `acceptsFirstResponder` is `true`.

On the current macOS 26 machine the host remained frontmost, the overlay was visible above the
fullscreen host at WindowServer layer 1000, and the fixture received Arrow Down (`125`) and Escape
(`53`) before any mouse click. This resolved the previously undocumented interaction requirement:
a nonactivating panel can remain a cross-app fullscreen overlay and still accept programmatic
keyboard focus when its responder chain is valid.

Hold-Option-Tab does not make the panel key. Its existing event-tap flow owns cycling and
open-on-Option-release.

## Implemented Design

### One panel contract

Every invocation source creates the panel with `.borderless`, `.fullSizeContentView`, and
`.nonactivatingPanel`. The prewarmed/reused panel is never converted between activating and
nonactivating styles.

Every `show()` reapplies:

- `.screenSaver` level;
- the shared five-flag collection policy;
- `isFloatingPanel = true`;
- `hidesOnDeactivate = false`.

Presentation uses `orderFrontRegardless()` and does not call `NSApp.activate(...)`.

The invocation-source semantic is `requiresKeyboardFocus`:

- `true`: link/file, toggle shortcut, service key;
- `false`: hold Option-Tab.

The SwiftUI root uses a hosting-view subclass that accepts first responder. This is required for
Escape, Return, arrows, type-ahead, and direct-selection events to reach the local monitor.

### Activation lifecycle and LaunchServices settling

AppCat switches to `.accessory` before presentation. If LaunchServices activated AppCat to deliver
a URL/file, presentation waits for `NSApplication.didResignActiveNotification` and a 150 ms settling
interval before ordering and focusing the panel.

The settling interval is not a cosmetic delay. A controlled link test showed that ordering
immediately after the first inactive observation still left a pending AppKit deactivation. Roughly
0.3 seconds later it produced `windowDidResignKey` and closed the picker. Waiting for the resign event
and the same interval proven by the isolated fixture removes that race.

Pending presentation work is cancelled on a replacement `show()` or `close()`. A second URL received
while the panel is reused therefore starts a fresh snapshot and presentation lifecycle.
If LaunchServices reactivates AppCat during the settling interval, the controller re-arms the
deactivation observer and repeats the cycle instead of leaving the picker session visible in state
but unordered on screen.

On dismissal AppCat restores `.regular` only when Settings is visible on the active Space. Otherwise
it remains `.accessory`. Activating visible Settings later restores `.regular`. `LSUIElement` was not
added.

## Runtime Verification

Verified on the current macOS 26 machine:

| Scenario | Result |
| --- | --- |
| Isolated DTS fixture over native fullscreen | Host frontmost, overlay visible, Arrow Down and Escape received |
| Cold `open -b` link into AppCat DEV over fullscreen host | Picker stayed visible for the full 3 s probe; host remained frontmost |
| Reused panel with a second link | Picker stayed visible for the full 2 s probe; host remained frontmost |
| Escape after cold and reused presentation | Picker ordered out; fullscreen host remained frontmost |
| Link picker while Settings existed in another Space | No jump to the Settings Space |
| ChatGPT manual selection after keyboard-policy fix | Native ChatGPT became frontmost in 3/3 runs |

The cold fullscreen probe first observed the panel at 1.170 s. The reused probe first observed it at
0.336 s. Both panels were at WindowServer layer 1000 and overlapped the fullscreen host.

The complete interactive matrix for all four invocation sources still needs manual execution on
macOS 14 and 15. Compilation and unit tests are not evidence of cross-application fullscreen behavior
on those OS versions.

## Automated Coverage

Policy and behavior tests cover:

- `.nonactivatingPanel` for all four invocation sources;
- `.screenSaver` level and the common collection flags;
- focus policy for link/file, toggle, service key, and hold Option-Tab;
- an accepting SwiftUI hosting responder;
- active-application deactivation planning, the interrupted-settling retry decision, and the
  settling interval;
- reused hold-Option-Tab panels remaining visible without taking key focus;
- `.regular` restoration only for visible Settings on the active Space;
- reapplying policy to a reused panel;
- first-click hit testing, direct Escape dismissal, Return policy, number direct-selection, routing
  hotkeys, type-ahead matching, and Option-release policy.

Repository verification completed on the current checkout: `./generate_project.sh`, 97 targeted
smoke tests plus a direct Escape regression, the full 209-test suite, `./scripts/dev-install.sh`, and
the controlled fullscreen fixture. The remaining external acceptance boundary is the interactive
four-source Spaces matrix on macOS 14 and 15; those OS versions are not available on the current
machine.

## Risks and Boundaries

- `.screenSaver` is intentionally high. The picker must remain transient and be ordered out on every
  completion path.
- Protected system surfaces such as the login window are outside the supported behavior.
- macOS 14–15 runtime behavior remains unverified until exercised in an interactive session or VM.
- File routing, editor ranking, universal-editor configuration, LaunchServices declarations, and
  bundle schema are outside this picker fix.

## Release Scope

This fix is part of PR #21. Keep its existing `release:minor` label because the PR also contains the
unknown-file and universal-editor capability. Do not merge or deploy without a separate command.
