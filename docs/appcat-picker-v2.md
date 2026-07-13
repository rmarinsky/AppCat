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

- One centered horizontal row of app/window items using the same floating surface styling as the routing picker.
- Visible app windows are first-class items in the row.
- Running apps without windows are optional and appear dimmed when enabled.
- Background and menu-bar apps are optional and hidden by default.
- Settings -> Picker exclusions apply to both routing and switching pickers.
- Sorting prefers recent app activation, then activation count, then display name.
- Toggle-shortcut and service-key sessions publish a fresh Accessibility window snapshot before
  the panel appears, so newly opened windows do not arrive as a delayed in-place replacement.
- A live `NSRunningApplication` snapshot makes newly launched apps available before the slower
  installed-app rescan and supplies the current runtime icon in both picker jobs.

Browser/app identity is already visible through the icon, so app-switcher cells suppress redundant secondary app-name labels.

## Appearance

The picker is a borderless `KeyablePanel` at `.floating` level. Link-routing, toggle-shortcut, and
service-key sessions use an activating `.fullSizeContentView`/`.borderless` panel so the first click
and keyboard event are delivered normally. Hold-to-switch alone adds `.nonactivatingPanel`.

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
- Shows configured hotkeys and positional direct-selection keys when direct selection is enabled.
- Direct-selection keys use `1...0`, then `Q...M`.

Hold-to-switch activation mode:

- Requires Input Monitoring.
- Hold `Option`, press `Tab` / `Shift+Tab` to cycle, release `Option` to open the focused item.
- Does not show indexed direct-selection key labels.

Service-key activation:

- Supports `Caps Lock` or `Escape`.
- Supports 1, 2, or 3 taps.
- Requires Input Monitoring.
- Shows and accepts configured and positional direct-selection keys, even when hold-to-switch is the configured global activation mode.

Invocation-source policy:

- Link routing, toggle-shortcut, and service-key sessions activate the panel and support direct selection.
- Hold-`Option`+`Tab` alone stays non-activating, cycles with `Tab` / `Shift+Tab`, opens on `Option` release, and omits all shortcut labels.
- Every picker item is clickable. A global hit-test fallback handles the first mouse-down only when
  AppKit did not deliver it locally to the SwiftUI button.
- Configured item shortcuts take precedence; remaining items receive positional keys in `1...0`, then `QWERTY...` order.
