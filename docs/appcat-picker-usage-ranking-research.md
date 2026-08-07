# AppCat Picker Usage Ranking Research

## Decision

Rank the manual app/window switcher by **window-level recency first**, and fall back to selection
frequency only for targets with no recency at all.

`NSWorkspace.didActivateApplicationNotification` **is** the recency signal. An earlier revision of
this document rejected it, on the grounds that it reports activations across the system including
switches that did not originate in AppCat. That reasoning was correct for a *frequency* ranking,
where third-party switches are noise that distorts a histogram of the user's AppCat habits. It is
backwards for a *recency* ranking: a switcher exists to return you to where you just were, and where
you just were is defined by every activation, not only the ones AppCat performed. Excluding
third-party switches is precisely what made ⌥Tab unable to go back.

The frequency signal is retained, unchanged, as the fallback tier. Count click, Return, positional
shortcuts, service-key selection, and hold-Option-Tab after `BrowserLauncher.activate` succeeds.
Link/file routing and automatic rules are excluded.

## Recency identity and storage

- Recency is a monotonic tick, not a timestamp: deterministic under test and immune to clock changes.
- Two key namespaces. `app|<bundleID>` records when an app was last frontmost;
  `window-title|<bundleID>|<case- and diacritic-folded title>` records when one specific window was.
  The window key folds identically to `PickerItem.switcherDedupeKey` so a ledger entry and a rendered
  tile agree on identity. `AppWindowTarget.index` is a per-enumeration-pass position and is
  deliberately not part of any key.
- The window that was focused during an activation is resolved asynchronously through Accessibility
  (`kAXFocusedWindowAttribute`), stamped with the tick captured at activation time so a slow read
  cannot reorder anything. Without Accessibility the resolution returns nothing and the switcher
  degrades to app-level recency — which is also all it can render, since window tiles need
  Accessibility to exist at all.
- Window switches *inside* one app (⌘\`, clicking a sibling window) emit no workspace notification,
  so the running-app refresh re-resolves the frontmost window as a backstop.
- Held in memory only, never written to disk. At launch the order is seeded from the Core Graphics
  front-to-back window list; seeds occupy negative ticks so the first real activation outranks the
  entire seed, and seeding never overwrites a live record.
- Bounded at 250 entries, trimmed to the 200 most recent. Keys for closed windows are inert:
  recency never *creates* a candidate, exactly like a stale frequency entry.

`kCGWindowName` requires Screen Recording, which AppCat does not request, so Core Graphics supplies
the cross-application z-order for the seed while Accessibility supplies each app's own window order
and titles.

## Identity and storage

- Use the lowercased `CFBundleIdentifier` of the base app. Browser profiles and individual windows
  aggregate to that app identifier.
- Store one count per bundle ID per local calendar day in the existing `DailyStats` records and
  atomically written `stats.json` under Application Support.
- Keep app identities for today plus the six preceding local calendar days. On load and on the next
  manual selection, clear older per-app maps while preserving anonymous aggregate totals.
- Do not store app names, window titles, URLs, exact timestamps, or an event log. Do not add an
  analytics SDK, database, or separate manager.

`CFBundleIdentifier` is the platform identifier used to identify an app bundle. Foundation's
calendar-day APIs match the product requirement better than a rolling 168-hour interval because the
ranking is defined in local calendar days.

## Ranking contract

First build candidates using the existing visibility, running, hidden, background-app, and
windowless-app rules. Neither historical counts nor recency ever create candidates. Then flatten the
app groups into individual tiles and sort the **tiles**, not the groups, by:

1. recency, descending — the newer of the tile's window tick and its app tick. A tile whose window
   tick is at least its app tick is an *exact* window and wins ties against siblings that only
   inherit the app tick;
2. any recency at all, ahead of none;
3. trailing-seven-day selection count of the tile's app, descending;
4. localized app name, ascending;
5. bundle ID, ascending;
6. construction order, so the ordering is a total order.

Taking the *newer* of the two ticks matters when a title resolution fails: the app tick moves on
without its window, and preferring the window key unconditionally would sort unresolved siblings
above the window that was actually focused. Falling back to the app tick instead degrades honestly to
"somewhere in this app", where every window of the app ties.

**Multiple windows of one app are no longer adjacent.** Ranking tiles individually is what makes the
tile after the one you are in the exact window you were in before, rather than merely the right app.
Adjacency still emerges when neither window has recency, because tiers 3–5 tie and construction order
decides — which is also why an empty ledger reproduces the previous ordering exactly.

Windowless apps remain dimmed and participate in the same order. Each manual-picker session freezes
one snapshot of *both* ordering inputs before the panel exists and never re-reads them: a background
app stealing focus mid-session would otherwise reshuffle the row under the user's focused tile.

## Interaction contract

The switcher opens focused on index 1 — the previous window — whenever index 0 is the window the user
is currently in. If that target was filtered out of the list, index 0 already *is* the previous
window and focus stays there. Link routing is excluded: its list is destinations for a URL, not a
history. Hold-Option-Tab is excluded because it reaches index 1 itself, by presenting at 0 and
stepping forward once.

Repeating the activation shortcut steps focus forward rather than confirming; Shift steps backward.
The session commits when the activation chord's modifiers are released, or on Return, Space, a click,
or a positional shortcut. Escape cancels. A press that arrives while the session is still waiting on
its window enumeration is banked and applied when the session exists, so a fast double-tap lands two
windows back and a quick tap-and-release switches without the panel ever painting.

Modifier release is detected by polling `NSEvent.modifierFlags`, an ungated window-server query. A
`CGEvent` tap would require Input Monitoring; a global `NSEvent` monitor would require Accessibility
and would fail silently if it were revoked, leaving the picker stuck open with no diagnostic.

## Privacy assessment

Recency is held in memory only and is never written to disk; the frequency counts stay on the device
in AppCat's Application Support directory. Neither is transmitted.
Apple's App Privacy guidance says data processed only on-device is not considered collected for the
privacy-label questionnaire. If AppCat later sends, syncs, exports, or links these counts to a user or
device, the privacy assessment must be revisited.

## Primary sources

- Apple: [`CFBundleIdentifier`](https://developer.apple.com/documentation/BundleResources/Information-Property-List/CFBundleIdentifier)
- Apple: [`NSRunningApplication.bundleIdentifier`](https://developer.apple.com/documentation/appkit/nsrunningapplication/bundleidentifier)
- Apple: [`NSWorkspace.didActivateApplicationNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)
- Apple: [`CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo)
- Apple: [`kCGWindowName`](https://developer.apple.com/documentation/coregraphics/kcgwindowname) — withheld without Screen Recording
- Apple: [`kAXFocusedWindowAttribute`](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowattribute)
- Apple: [`NSEvent.modifierFlags`](https://developer.apple.com/documentation/appkit/nsevent/modifierflags-swift.type.property)
- Apple: [`URL.applicationSupportDirectory`](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory)
- Apple: [`NSData.WritingOptions.atomic`](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic)
- Apple: [`Calendar.startOfDay(for:)`](https://developer.apple.com/documentation/foundation/calendar/startofday%28for%3A%29)
- Apple: [`Calendar.date(byAdding:to:wrappingComponents:)`](https://developer.apple.com/documentation/foundation/calendar/date%28byadding%3Ato%3Awrappingcomponents%3A%29)
- Apple: [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
