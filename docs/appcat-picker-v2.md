# AppCat Picker V2

## Product Direction

AppCat has two picker jobs:

1. Route an incoming link or file into a browser, browser profile, or native app.
2. Switch to an already running app or app window.

The two modes share visual metrics and picker plumbing, but keep separate ranking rules.

## Routing Picker

Used when AppCat receives a URL or file.

Content rules:

- Web URLs: visible browsers and profiles first, then native apps whose host rules match the URL.
- Web-readable files: browsers first, then LaunchServices/configured file apps.
- Native files: configured and LaunchServices-capable apps first.
- Developer/text files: editors and explicitly configured apps stay visible; view-only browsers reported only by LaunchServices are hidden unless the user pinned that browser through custom formats.
- Unknown files: capable LaunchServices apps and configured unknown-type apps are shown, except picker-hidden apps and apps that cannot meaningfully open links or files.
- When a chosen browser is still running but has no open windows, AppCat re-activates it after the URL handoff so a browser closed with the red window button can surface again.

The routing picker does not show window previews. Its private-mode hint appears only for link routing, not for app switching or file routing. The hint has a reserved footer below the shortcut badges; the routing panel includes that footer in its height instead of overlaying it on the item row.

## App Switcher

Used when the user invokes the picker manually with no pending URL or file.

Content rules:

- One centered horizontal row of app/window items using the same transient surface styling as the routing picker.
- Visible app windows are first-class items in the row.
- Running apps without windows are optional and appear dimmed when enabled.
- Background and menu-bar apps are optional and hidden by default.
- Settings -> Picker exclusions apply to both routing and switching pickers.
- Existing visibility, running, hidden, background, and windowless rules determine candidates first.
- Candidates are flattened into individual tiles and each tile is ranked on its own by when it was
  last frontmost. Windows of one app are therefore **not** adjacent — that is what makes the tile
  after the one you are in the exact window you were in before, rather than merely the right app.
- A tile whose window title was resolved outranks siblings that only inherit their app's recency.
- Tiles with no recency fall back to the previous contract: successful manual-picker selections from
  the trailing seven local calendar days, then localized display name, then bundle id. With no
  recency at all the ordering is identical to the pre-recency behaviour.
- Windowless apps remain dimmed but share the same order, so a recently or frequently used windowless
  app can appear before a windowed app.
- Each manual-picker session snapshots recency *and* counts before presentation and never re-reads
  them, so a background app stealing focus mid-session cannot reshuffle the row under the user's
  focused tile. A successful selection changes the next session's order, not the current one.
- Toggle-shortcut and service-key sessions publish a fresh Accessibility window snapshot before
  the panel appears, so newly opened windows do not arrive as a delayed in-place replacement.
- A live `NSRunningApplication` snapshot makes newly launched apps available before the slower
  installed-app rescan and supplies the current runtime icon in both picker jobs.

Browser/app identity is already visible through the icon, so app-switcher cells suppress redundant secondary app-name labels.

## Appearance

The picker is a borderless `KeyablePanel` created once with `.fullSizeContentView`, `.borderless`,
and `.nonactivatingPanel`. Every presentation reapplies an interactive overlay level (`.screenSaver - 1`),
`isFloatingPanel = true`, `hidesOnDeactivate = false`, and the cross-application fullscreen policy:
`.canJoinAllSpaces`, `.canJoinAllApplications`, `.fullScreenAuxiliary`, `.stationary`, and
`.ignoresCycle`.

AppCat switches to `.accessory` and presents with `orderFrontRegardless()` without calling
`NSApp.activate(...)`. Link/file, toggle, and service-key sessions then make the panel key and focus
an accepting SwiftUI hosting responder. Hold-to-switch stays non-key because its event tap owns input.
If LaunchServices activated AppCat first, presentation waits for deactivation to settle so a late
`windowDidResignKey` cannot flash and dismiss the picker.

On macOS 26 and newer, the panel surface uses `NSGlassEffectContainerView` with a child `NSGlassEffectView`:

- glass style: `.regular`
- tint: adaptive neutral (`8%` white in Dark appearance, `4%` black in Light appearance)
- shadow: disabled on the panel
- corner radius: scaled from the 48 pt base radius

Older macOS versions fall back to an `NSVisualEffectView` with `.hudWindow` material, the same adaptive tint overlay, no panel shadow, and no explicit border. This appearance is fixed and shared by routing and app-switcher sessions; there is no alternate background-style setting. Native glass still reacts to the content behind the panel.

The Settings -> Picker size slider scales the panel, app icons, labels, focus ring, and shortcut hints from 50% to 200%. At 100%, the current app-switcher metrics are:

- icon image: 88 pt
- focus chrome: 92 pt
- visual icon gap: 8 pt
- focus-frame gap: 4 pt
- title-to-shortcut and shortcut-to-routing-hint gaps: 4 pt
- panel corner radius: 48 pt

## Keyboard Model

Common picker keys:

- `Escape`: dismiss.
- `Return`: open the focused item.
- `Tab` / `Shift+Tab`: move focus forward/backward and clear hidden type-ahead.
- Arrow keys: navigate the row.
- Typed letters: hidden type-to-focus by app, browser, profile, or window name.

Toggle activation mode:

- Uses the configurable global shortcut, `Option+Tab` by default.
- Shows numeric positional direct-selection keys when direct selection is enabled.
- Direct-selection keys use `1...0`; letters are reserved for type-ahead by app/window name.

Hold-to-switch activation mode:

- Requires Input Monitoring.
- Hold `Option`, press `Tab` / `Shift+Tab` to cycle, release `Option` to open the focused item.
- Does not show indexed direct-selection key labels.

Service-key activation:

- Supports `Caps Lock` or `Escape`.
- Supports 1, 2, or 3 taps.
- Requires Input Monitoring.
- Shows and accepts numeric positional direct-selection keys, even when hold-to-switch is the configured global activation mode.
- Reserves letters for type-ahead so entering a name such as `chatgpt` cannot activate a positional item mid-query.

Invocation-source policy:

- Every source uses the same nonactivating fullscreen-safe panel.
- Link routing, toggle-shortcut, and service-key sessions require keyboard focus.
- Toggle-shortcut and service-key sessions open focused on index 1, the previous window, whenever
  index 0 is the window the user is currently in. Link routing stays on index 0: its list is
  destinations for a URL, not a history.
- Repeating the toggle shortcut steps focus forward instead of confirming; `Shift` steps backward.
  A press that lands while the session is still waiting on its window enumeration is banked and
  applied on arrival, so a fast double-tap reaches two windows back.
- A toggle session commits when the activation chord's modifiers are released, detected by polling
  `NSEvent.modifierFlags` — no Accessibility or Input Monitoring required. Releasing before the panel
  could be presented commits without ever ordering it front, so a quick tap switches with no flash.
  A shortcut rebound to a modifier-free chord simply stays a modal picker.
- Hold-`Option`+`Tab` stays non-key, cycles with `Tab` / `Shift+Tab`, opens on `Option` release, and omits all shortcut labels.
  It reaches index 1 by presenting at 0 and stepping forward once, so it is excluded from the
  initial-focus rule above to avoid double-advancing.
- Every picker item is clickable. A global hit-test fallback handles the first mouse-down only when
  AppKit did not deliver it locally to the SwiftUI button.
- Routing configured shortcuts take precedence; remaining routing items receive positional keys in `1...0`, then `QWERTY...` order.
- Manual toggle/service sessions expose only positional `1...0`; alphabetic input is type-ahead.
