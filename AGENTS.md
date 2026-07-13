# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

AppCat is a macOS menu bar app that acts as the system default browser. When any link is clicked, AppCat intercepts the URL and either auto-routes it via URL rules or shows a floating picker to choose browser/profile/app.

- **Platform:** macOS 14.0+ (Sonoma), Swift 5.9+, SwiftUI
- **Bundle ID:** `ua.com.rmarinsky.appcat` (release) / `ua.com.rmarinsky.appcat.dev` (debug)
- **Sandbox:** Disabled (required for URL interception and launching other apps)
- **Localization:** Ukrainian (default) and English
- **Distribution:** notarized DMG via GitHub Releases + Sparkle auto-update (see Release process)

## Build Commands

```bash
# Prerequisites
brew install xcodegen        # Required
brew install create-dmg      # For release DMG only

# Generate and open project
./generate_project.sh        # Always run first — generates .xcodeproj from project.yml
open AppCat.xcodeproj    # Select "AppCat DEV" scheme → Run

# Dev install (build + install to /Applications)
./scripts/dev-install.sh                          # Fast incremental build/install
./scripts/dev-clean-install.sh                    # Clean build/install
./scripts/dev-reset-tcc.sh                        # Reset DEV privacy grants
./scripts/dev-install.sh --build-only             # Build only
./scripts/dev-install.sh --install-name my-name   # Custom app name

# Release
./release.sh                  # Build, sign, notarize, DMG
./release.sh --skip-notarize  # Without notarization
```

### Build Schemes

| Scheme | Config | App Name | Bundle ID |
|--------|--------|----------|-----------|
| AppCat DEV | Debug | AppCat DEV | ua.com.rmarinsky.appcat.dev |
| AppCat | Release | AppCat | ua.com.rmarinsky.appcat |

## Done criteria

If a prompt changes source code (`*.swift`, project config, resources, scripts used by the app), finish by installing the DEV app:

```bash
./scripts/dev-install.sh
```

Docs-only changes do not need a dev install.

## Release process

**NEVER push directly to `main`** — not commits, not tags. Everything goes through a PR.
**NEVER create or push `v*` tags by hand** — CI does that.
**NEVER hand-edit** `MARKETING_VERSION` in `project.yml` or the Sparkle `appcast.xml`.
**Every release must go through a PR and the release-label version flow.** No direct release without a version update/tag produced by CI.

To ship a release:

1. Open a PR into `main`.
2. Add exactly one label: `release:patch` (bug fix / internal), `release:minor`
   (new user-facing capability), `release:major` (breaking change), or
   `release:skip` (no release for this PR).
3. Merge the PR.

CI does the rest: `prepare-release.yml` computes the next version from the
latest tag, pushes tag `vX.Y.Z`, and dispatches `release.yml`, which builds,
notarizes, signs, creates the GitHub Release, and updates the Sparkle
`appcast.xml` on the **`gh-pages`** branch. The app version comes **from the
git tag** — `project.yml`'s `MARKETING_VERSION` is only a placeholder.

Workflows: `.github/workflows/release-label-check.yml` (PR gate),
`prepare-release.yml` (tag on merge), `release.yml` (build + publish).
Version math: `scripts/next-version.sh`.

## Task tracking

Tasks live in `backlog/` (Backlog.md CLI format). Use `backlog task list --plain`, `backlog board`, `backlog task create` — do not use any `mcp__vatra-*` tool, the hosted Vatra Ops service was decommissioned 2026-07.

## Ponytail rules

- Use the smallest change that preserves behavior: reuse existing managers/services before adding new layers.
- Prefer deleting stale docs or instructions over adding new explanatory pages.
- Documentation should describe shipped behavior, build/release commands, and real ownership boundaries only. Do not document "planned" features unless the user explicitly asks for a roadmap.
- When code changes user-facing behavior, update the nearest doc in the same PR; otherwise leave docs alone.
- After source-code changes, run the dev install before the final response.

## Architecture

### URL Interception Flow (End-to-End)

```
1. Link clicked anywhere on macOS
2. macOS routes to AppCat (registered for http/https via kAEGetURL)
3. AppDelegate.handleURLEvent → appState.pendingURL = url
4. LinkMetadataManager fetches page title in background
5. URLRulesManager.findMatch() scans enabled rules in sortOrder
   └── URLRuleMatcher: .host (exact/subdomain) | .hostContains | .regex
6a. Rule matches → PickerCoordinator.openURL() directly (no picker)
6b. No match → PickerCoordinator.showPicker()
    └── PickerWindowController shows NSPanel near cursor
7. User picks via click, hotkey, or keyboard navigation
8. BrowserLauncher.open() launches URL in chosen browser/profile/app
9. HistoryManager records entry, pendingURL cleared
```

### Key Components

**App layer** (`App/`):
- `AppCatApp.swift` — `@main` SwiftUI entry
- `AppDelegate.swift` — URL event handler, creates all managers
- `AppState.swift` — `@Observable @MainActor` single source of truth (pendingURL, browsers, apps, rules, history)
- `ManagerEnvironment.swift` — SwiftUI Environment keys for all managers

**Managers** (stateful, `@MainActor`):
- `PickerCoordinator` — orchestrates picker show/dismiss and URL open
- `BrowserManager` — detects browsers via NSWorkspace, merges with saved config
- `AppManager` — detects native apps from `AppDefinition` registry
- `DefaultBrowserManager` — check/set AppCat as system default
- `URLRulesManager` — loads/saves rules, finds first matching rule
- `HistoryManager` — records URL opens, max 500 entries
- `FaviconManager` (actor) — Google S2 favicons, memory+disk cache
- `LinkMetadataManager` (actor) — page title via partial HTML fetch

**Services** (stateless utilities):
- `BrowserDetector` — finds HTTP-capable apps via `NSWorkspace.urlsForApplications`
- `ProfileDetector` — reads Chromium `Local State` JSON / Firefox `profiles.ini`
- `AppDetector` — checks which `AppDefinition` apps are installed
- `BrowserLauncher` — opens URLs: normal, background, private mode, with profile
- `URLRuleMatcher` — host/hostContains/regex matching

**Storage** (all in `~/Library/Application Support/AppCat/`):
- `BrowserConfigStorage` — `browsers.json` (visibility, hotkeys, sort order, profile hotkeys)
- `AppConfigStorage` — `apps.json` (visibility, hotkey, sort order)
- `RulesStorage` — `rules.json` (URL routing rules)
- `HistoryStorage` — `history.json` (ISO8601 dates)
- `SettingsStorage` — UserDefaults (lastURL, recentLinksCount, picker scale/activation, appLanguage)

### Picker Window

- `KeyablePanel` (NSPanel subclass) — `canBecomeKey: true` for keyboard events on borderless panel
- Style: `.nonactivatingPanel`, `.screenSaver` level, cross-app fullscreen collection policy, native `NSGlassEffectView` `.regular` on macOS 26+, `.hudWindow` fallback on older macOS, no panel shadow
- Single compact horizontal row with adaptive width, clamped to the visible screen width
- Position: centered on cursor, shifted up 40pt, clamped to screen safe area

### Keyboard Navigation in Picker

| Key | Action |
|-----|--------|
| Escape | Dismiss |
| Return | Open focused item |
| Number keys | Open visible items 1...9,0 |
| Type letters | Hidden type-to-focus by app, browser, profile, or window name |
| Tab/Shift+Tab | Move focus forward/backward and clear hidden typing |
| Arrow keys | Navigate the compact row |
| Hotkey char | Link-routing only: open matching browser/profile |
| Option+Hotkey or Shift+Hotkey | Link-routing only: open browser/profile in private mode |

### Hotkey System

- `HotkeyRecorder` captures key press (character + keyCode)
- Stored per-browser/profile/app in `browsers.json` / `apps.json`
- `AppsSettingsView.clearDuplicateHotkey()` prevents conflicts across all items
- Matching uses `hotkeyKeyCode` (layout-independent) with fallback to character comparison
- Global picker activation has two modes in Settings → Shortcuts:
  - toggle shortcut mode uses `KeyboardShortcuts.Recorder` (`⌥Tab` by default)
  - hold-to-switch mode uses `PickerActivationListener` (`CGEventTap`): hold `⌥`, press `Tab` / `⇧Tab`, release `⌥` to open the focused item
- Optional service-key activation also uses `PickerActivationListener`: `Caps Lock` or `Escape`, with 1/2/3 taps. It requires Input Monitoring permission.

### Browser Detection

`BrowserDefinition` has a static registry of ~18 known browsers with:
- Private mode CLI args (e.g., `--incognito`, `-private-window`)
- Profile data paths for Chromium/Firefox profile enumeration
- Profile types: `.chromium` (reads `Local State` JSON) or `.firefox` (reads `profiles.ini`)

### Native App Routing

`AppDefinition` registry defines ~19 apps (Teams, Slack, Discord, Figma, Zoom, etc.) with:
- `hostPatterns` — web hosts this app handles
- `convertURL` — optional closure for deep link conversion (e.g., `https://teams.microsoft.com` → `msteams:`)
- Apps appear in picker only when pending URL's host matches their patterns

## Logging

`Log` enum with typed `os.Logger` instances: `.app`, `.browser`, `.picker`, `.settings`, `.profiles`, `.rules`, `.apps`, `.history`

## Patterns & Conventions

- **@MainActor** on all managers and AppDelegate; actors for `FaviconManager` and `LinkMetadataManager`
- **Environment-based DI** — managers passed via SwiftUI `EnvironmentValues`, not singletons from views
- **Storage singletons** — `.shared` pattern, called only from managers
- **Codable separation** — `InstalledBrowser` (has `NSImage`) separate from `BrowserConfig` (Codable)
- **`DEV_BUILD` compile condition** — available for debug-only code paths
- **SPM packages:** `Sparkle`, `LaunchAtLogin-Modern`, `KeyboardShortcuts`

## Key Files to Edit

| Task | Files |
|------|-------|
| Add new known browser | `BrowserDefinition.swift` (registry) |
| Add new native app | `AppDefinition.swift` (registry) |
| Change picker layout | `PickerView.swift`, `PickerWindowController.swift` |
| Modify URL rule matching | `URLRuleMatcher.swift` |
| Change browser launch behavior | `BrowserLauncher.swift` |
| Add settings | `SettingsStorage.swift` + relevant settings view |
| Modify menu bar content | `MenuBarContentView.swift` |
