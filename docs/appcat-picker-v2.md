# AppCat Picker V2

## Product Direction

AppCat already does two related but different jobs:

1. Route a link or file into the right browser/app.
2. Switch to an already open app/window.

These should become two picker modes that share visual language and data plumbing, but not ranking rules.

AppCat is the product name for browser, file, and app routing.

## Picker Modes

### 1. Routing Picker

Used when AppCat receives a URL or file.

Primary task: choose where to open the incoming item.

Content rules:

- Web URLs: browsers and browser profiles first, then app matches by host.
- Web-readable files: browsers first, then LaunchServices file apps.
- Native files: LaunchServices/configured apps first.
- Unknown files: show every capable LaunchServices app, then configured "opens unknown types" apps.

Layout:

```text
┌──────────────────────────────────────────────────────────────┐
│  figma.com/file/W7x2...                                      │
│  [Chrome Work] [Safari] [Firefox] [Figma] [Cursor] [VS Code] │
└──────────────────────────────────────────────────────────────┘
```

No window previews in this mode by default. The user is routing, not browsing open state.

### 2. App Switcher

Used when the user invokes the picker manually with no pending URL/file.

Primary task: jump to a running app or a specific window/project fast.

Content rules:

- Only running apps.
- If an app has multiple visible windows, show the windows as first-class items in one flat list.
- No app-group split view. The user chooses "what is open", not "which app group".
- Browser windows should eventually use active tab title/favicon if available; until then use AX window title + browser icon.

Layout option A: Cmd-Tab style.

```text
┌────────────────────────────────────────────────────────────────────────┐
│ [Icon] [Icon] [Icon] [Icon] [Icon] [Icon] [Icon] [Icon] [Icon]        │
│ Cursor    Cursor    Chrome   Chrome   Slack    Figma    Finder        │
│ ofa       mac apps  YouTube  GitHub   Threads  Design   Downloads     │
└────────────────────────────────────────────────────────────────────────┘
```

Layout option B: Cmd-Tab plus focused preview.

```text
┌────────────────────────────────────────────────────────────────────────┐
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ focused window preview                                           │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│ [Cursor/ofa] [Cursor/mac apps] [Chrome/YouTube] [Chrome/GitHub]       │
└────────────────────────────────────────────────────────────────────────┘
```

Option A should ship first. Option B is better, but needs Screen Recording permission and careful caching.

## Name Normalization

Never mutate raw AX/window titles. Store raw values for activation and matching, then render normalized display fields.

Suggested display model:

```swift
struct PickerDisplayItem {
    let id: String
    let rawTitle: String
    let primaryTitle: String
    let secondaryTitle: String?
    let appName: String
    let projectName: String?
    let documentName: String?
    let bundleID: String
    let icon: NSImage?
    let preview: NSImage?
}
```

Normalization rules:

- Strip app suffixes: ` - Cursor`, ` — Cursor`, ` - Visual Studio Code`, ` - Google Chrome`.
- Split common title patterns:
  - `file.ext — project` -> primary `project`, secondary `file.ext · Cursor`
  - `project — Cursor` -> primary `project`, secondary `Cursor`
  - `page title - Google Chrome` -> primary `page title`, secondary `Chrome`
- Prefer project/folder title for IDEs/editors.
- Prefer page title/domain for browsers.
- Prefer filename for documents.
- Keep app name visible, but secondary. In switcher mode the window/project is the object.

Examples:

| Raw title | Primary | Secondary |
| --- | --- | --- |
| `ui-playwright-report-server-steps.yml — ofa` | `ofa` | `ui-playwright-report-server-steps.yml · Cursor` |
| `pipeline_report_audit_9ebba7b2.plan.md — opportunities-manager-app-ui` | `opportunities-manager-app-ui` | `pipeline_report_audit_9ebba7b2.plan.md · Cursor` |
| `YouTube - Google Chrome` | `YouTube` | `Chrome` |
| `AppCat — mac apps` | `mac apps` | `AppCat` |

## Keyboard Model

Current `KeyboardShortcuts.onKeyUp` is enough for "show picker", but not enough for a true Cmd-Tab replacement.

For App Switcher mode:

- `Tab`: next item.
- `Shift+Tab`: previous item.
- Arrow keys: move focus.
- Number keys: direct selection for first 9 visible items.
- `Return`: activate selected app/window.
- `Esc`: close.

For real Cmd-Tab-like behavior:

- Show on key down.
- Cycle while modifier is held.
- Activate selected item on modifier release.

That likely needs a lower-level keyboard event path, not only `KeyboardShortcuts.onKeyUp`.

## Cmd-Tab Replacement Feasibility

Do not make Cmd-Tab override the default path immediately.

Safer plan:

1. Ship a configurable App Switcher activation mode.
2. Keep the default toggle shortcut path for users who do not want Input Monitoring.
3. Offer hold-to-switch mode: hold `⌥`, press `Tab` / `⇧Tab`, release `⌥` to open.
4. Offer service-key trigger mode for `Caps Lock` / `Escape` with 1/2/3 taps.
5. Keep full Cmd-Tab replacement out of the default path.

Risks:

- Cmd-Tab is system-owned behavior and may win before our app gets a reliable chance to suppress it.
- Event taps can be disabled by macOS if the callback is slow.
- Requires Input Monitoring/Accessibility-style permission flows and careful failure UI.
- This feature needs real-device testing across current macOS versions.

## Window Preview Feasibility

Preview is worth doing, but should be phase two.

Possible implementation:

- Use Accessibility to enumerate and activate windows.
- Use ScreenCaptureKit to retrieve shareable windows and capture snapshots.
- Cache previews per window and refresh lazily.
- Show previews only for focused item and nearby items, not all items at once.

Permission behavior:

- Without Accessibility: show app-level items only.
- Without Screen Recording: show icons and normalized titles only.
- With both permissions: show specific windows + previews.

Performance budget:

- Picker visible within 60 ms.
- Window list from cache; refresh async after showing.
- Snapshot for focused item within 150-250 ms.
- Never block picker open on preview capture.

## Implementation Phases

### Phase 1: Solid App Switcher Without Previews

- Add `PickerPurpose`: `.routing` and `.switching`.
- Add normalized `PickerDisplayItem`.
- Fix all open paths to pass `windowTarget`.
- Sort switcher by last activation/usage first, then app name/title.
- Make hidden/minimized app activation robust.
- Add a Settings -> Picker exclusion list for apps that should never appear in routing or switching pickers.

### Phase 2: Cmd-Tab Style UI

- Horizontal centered panel, no URL header in switcher mode.
- One flat row of app/window items, without a visual split between windowed and windowless apps.
- Focus ring, icon, normalized primary title, secondary app/context. Keep AppCat orange for the focused item.
- Settings -> Picker size slider scales the panel, icons, labels, and key hints from 50% to 200%.
- Fast keyboard navigation and wraparound.

### Phase 3: Preview Layer

- Add `WindowPreviewService` using ScreenCaptureKit.
- Lazy focused preview only.
- Add degraded state for missing Screen Recording permission.

### Phase 4: Advanced Activation

- Toggle shortcut mode stays the default path.
- Hold-to-switch mode uses `⌥Tab` / `⌥⇧Tab` plus release-to-open.
- Service-key activation supports `Caps Lock` / `Escape` with 1/2/3 taps.
- Full `Cmd+Tab` replacement remains out of scope until real-device latency and permission failures are measured.
