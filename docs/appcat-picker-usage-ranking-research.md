# AppCat Picker Usage Ranking Research

## Decision

Rank only the manual app/window switcher by successful selections made through AppCat. Count click,
Return, positional shortcuts, service-key selection, and hold-Option-Tab after
`BrowserLauncher.activate` succeeds. Link/file routing and automatic rules are excluded.

Do not use `NSWorkspace.didActivateApplicationNotification` as the ranking signal. It reports
application activations across the system, including switches that did not originate in AppCat. The
notification remains useful for refreshing running-app and window state.

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
windowless-app rules. Historical counts never create candidates. Sort the remaining app groups by:

1. trailing-seven-day selection count, descending;
2. localized app name, ascending;
3. bundle ID, ascending, for deterministic equal-name ties.

Windowless apps remain dimmed but participate in the same frequency order. Multiple windows of one
app remain adjacent because the app group is ranked before it is expanded. Each manual-picker session
uses one count snapshot; a successful selection affects the next session, not the current keyboard
focus and ordering.

## Privacy assessment

The data stays on the device in AppCat's Application Support directory and is not transmitted.
Apple's App Privacy guidance says data processed only on-device is not considered collected for the
privacy-label questionnaire. If AppCat later sends, syncs, exports, or links these counts to a user or
device, the privacy assessment must be revisited.

## Primary sources

- Apple: [`CFBundleIdentifier`](https://developer.apple.com/documentation/BundleResources/Information-Property-List/CFBundleIdentifier)
- Apple: [`NSRunningApplication.bundleIdentifier`](https://developer.apple.com/documentation/appkit/nsrunningapplication/bundleidentifier)
- Apple: [`NSWorkspace.didActivateApplicationNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)
- Apple: [`URL.applicationSupportDirectory`](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory)
- Apple: [`NSData.WritingOptions.atomic`](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic)
- Apple: [`Calendar.startOfDay(for:)`](https://developer.apple.com/documentation/foundation/calendar/startofday%28for%3A%29)
- Apple: [`Calendar.date(byAdding:to:wrappingComponents:)`](https://developer.apple.com/documentation/foundation/calendar/date%28byadding%3Ato%3Awrappingcomponents%3A%29)
- Apple: [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
