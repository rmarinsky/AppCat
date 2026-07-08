@testable import AppCat
import AppKit
import ApplicationServices
import XCTest

final class SmokeTests: XCTestCase {
    func testTargetLoads() {
        XCTAssertTrue(true)
    }

    func testCustomFileFormatsArePickerAppMatches() throws {
        let app = makeApp(id: "test.editor.yaml", customFormats: ["yaml"])
        let url = try makeTempFile(named: "config.yaml")

        let matches = PickerItem.matchingApps(for: url, in: [app])

        XCTAssertEqual(matches.map(\.id), ["test.editor.yaml"])
    }

    func testCustomFileFormatsOverrideDetectedFormats() throws {
        let app = makeApp(
            id: "test.editor.override",
            customFormats: ["yaml"],
            detectedFormats: ["md"]
        )
        let url = try makeTempFile(named: "README.md")

        let matches = PickerItem.matchingApps(for: url, in: [app])

        XCTAssertFalse(matches.contains(where: { $0.id == "test.editor.override" }))
    }

    func testUnknownFileTypesCanRouteToConfiguredApp() throws {
        let app = makeApp(id: "test.editor.unknown", opensUnknownTypes: true)
        let url = try makeTempFile(named: "payload.romanunknownformat")

        let matches = PickerItem.matchingApps(for: url, in: [app])

        XCTAssertEqual(matches.map(\.id), ["test.editor.unknown"])
    }

    func testFormatNormalizationPreservesServiceFileTokens() {
        XCTAssertEqual(InstalledApp.normalizedFileFormat(".env.local"), "env.local")
        XCTAssertEqual(InstalledApp.normalizedFileFormat("docker-compose.yml"), "docker-compose.yml")
        XCTAssertEqual(InstalledApp.normalizedFileFormat(" YAML "), "yaml")
    }

    func testCanOpenTargetDropsAppsThatOpenNeitherFilesNorLinks() {
        XCTAssertFalse(makeApp(id: "test.inert").canOpenTarget)
        XCTAssertTrue(makeApp(id: "test.file", detectedFormats: ["txt"]).canOpenTarget)
        XCTAssertTrue(makeApp(id: "test.host", hostPatterns: ["slack.com"]).canOpenTarget)
        XCTAssertTrue(makeApp(id: "test.scheme", urlSchemes: ["slack"]).canOpenTarget)
    }

    func testDeveloperFilesHideLaunchServicesBrowsersButKeepEditors() throws {
        let yamlURL = try makeTempFile(named: "config.yaml")
        let editor = makeApp(id: "test.editor", customFormats: ["yaml"])
        let browser = makeApp(id: "com.apple.Safari", displayName: "Safari")

        let ranked = InstalledApp.rankedFileApps(
            candidates: [editor, browser],
            url: yamlURL,
            capableIDs: ["test.editor", "com.apple.Safari"],
            hiddenBrowserIDs: ["com.apple.Safari"]
        )

        XCTAssertEqual(ranked.map(\.id), ["test.editor"])
    }

    func testWebMarkupFilesKeepBrowsersAsCandidates() throws {
        // For html (not a developer file) the caller passes an empty hidden-browser set, so a
        // browser that LaunchServices reports as capable still appears alongside the editor.
        let htmlURL = try makeTempFile(named: "index.html")
        let editor = makeApp(id: "test.editor", customFormats: ["html"])
        let browser = makeApp(id: "com.apple.Safari", displayName: "Safari")

        let ranked = InstalledApp.rankedFileApps(
            candidates: [editor, browser],
            url: htmlURL,
            capableIDs: ["test.editor", "com.apple.Safari"],
            hiddenBrowserIDs: []
        )

        XCTAssertEqual(Set(ranked.map(\.id)), ["test.editor", "com.apple.Safari"])
    }

    func testPinnedBrowserStillMatchesDeveloperFileViaCustomFormats() throws {
        // The escape hatch: a user who added "json" to a browser's formats keeps it (Rank 0/1),
        // even though the same browser would otherwise be hidden for developer files.
        let jsonURL = try makeTempFile(named: "data.json")
        let pinnedBrowser = makeApp(id: "com.apple.Safari", displayName: "Safari", customFormats: ["json"])

        let ranked = InstalledApp.rankedFileApps(
            candidates: [pinnedBrowser],
            url: jsonURL,
            capableIDs: ["com.apple.Safari"],
            hiddenBrowserIDs: ["com.apple.Safari"]
        )

        XCTAssertEqual(ranked.map(\.id), ["com.apple.Safari"])
    }

    func testPickerShortcutAssignerUsesDigitsThenQwertyLetters() {
        let items = (0 ..< 12).map { index in
            PickerItem(app: makeApp(id: "test.app.\(index)"))
        }

        let assignments = PickerShortcutAssigner.assignments(for: items, positionalEnabled: true)

        XCTAssertEqual(assignments[items[0].id]?.key, "1")
        XCTAssertEqual(assignments[items[8].id]?.key, "9")
        XCTAssertEqual(assignments[items[9].id]?.key, "0")
        XCTAssertEqual(assignments[items[10].id]?.key, "q")
        XCTAssertEqual(assignments[items[11].id]?.key, "w")
    }

    func testPickerShortcutAssignerMatchesByKeyCode() throws {
        let items = (0 ..< 11).map { index in
            PickerItem(app: makeApp(id: "test.app.\(index)"))
        }
        let qKeyCode = try XCTUnwrap(KeyCodeMap.keyCode(for: "q"))

        let item = PickerShortcutAssigner.item(forKeyCode: qKeyCode, in: items, positionalEnabled: true)

        XCTAssertEqual(item?.id, items[10].id)
    }

    func testRoutingPickerShortcutPolicyShowsDirectKeysInAnyActivationMode() throws {
        let configuredKeyCode = try XCTUnwrap(KeyCodeMap.keyCode(for: "f"))
        let configured = PickerItem(app: makeApp(
            id: "test.figma",
            hotkey: "f",
            hotkeyKeyCode: configuredKeyCode
        ))
        let positional = PickerItem(app: makeApp(id: "test.cursor"))
        let items = [configured, positional]

        let toggleAssignments = PickerShortcutPolicy.assignments(
            for: items,
            activationMode: .toggleShortcut,
            isManualPickerPresentation: false,
            selectWithNumberKeys: true
        )
        let holdAssignments = PickerShortcutPolicy.assignments(
            for: items,
            activationMode: .holdOptionTab,
            isManualPickerPresentation: false,
            selectWithNumberKeys: true
        )

        XCTAssertEqual(toggleAssignments[configured.id]?.source, .configured)
        XCTAssertEqual(toggleAssignments[positional.id]?.source, .positional)
        XCTAssertEqual(holdAssignments[configured.id]?.source, .configured)
        XCTAssertEqual(holdAssignments[positional.id]?.source, .positional)
    }

    func testManualPickerShortcutPolicyDoesNotOpenItemsByKeyInHoldMode() throws {
        let configuredKeyCode = try XCTUnwrap(KeyCodeMap.keyCode(for: "f"))
        let configured = PickerItem(app: makeApp(
            id: "test.figma",
            hotkey: "f",
            hotkeyKeyCode: configuredKeyCode
        ))

        let item = PickerShortcutPolicy.item(
            forKeyCode: configuredKeyCode,
            in: [configured],
            activationMode: .holdOptionTab,
            isManualPickerPresentation: true,
            selectWithNumberKeys: true
        )

        XCTAssertNil(item)
    }

    func testRoutingPickerShortcutPolicyOpensItemsByKeyInHoldMode() throws {
        let configuredKeyCode = try XCTUnwrap(KeyCodeMap.keyCode(for: "f"))
        let configured = PickerItem(app: makeApp(
            id: "test.figma",
            hotkey: "f",
            hotkeyKeyCode: configuredKeyCode
        ))

        let item = PickerShortcutPolicy.item(
            forKeyCode: configuredKeyCode,
            in: [configured],
            activationMode: .holdOptionTab,
            isManualPickerPresentation: false,
            selectWithNumberKeys: true
        )

        XCTAssertEqual(item?.id, configured.id)
    }

    func testPickerPanelWidthUsesContentWidthForSmallItemCounts() {
        let expected: CGFloat = 342

        let width = PickerMetrics.panelWidth(itemCount: 3, availableWidth: 1200)

        XCTAssertEqual(width, expected, accuracy: 0.001)
    }

    func testPickerMetricsScaleTogether() {
        let scale: CGFloat = 1.35

        XCTAssertEqual(PickerMetrics.iconSize(scale: scale), 118.8, accuracy: 0.001)
        XCTAssertEqual(PickerMetrics.itemWidth(scale: scale), 126.9, accuracy: 0.001)
        XCTAssertEqual(PickerMetrics.panelWidth(itemCount: 3, availableWidth: 1200, scale: scale), 461.7, accuracy: 0.001)
    }

    func testPrivateModeHintStaysInsideStandardPickerHeight() {
        XCTAssertEqual(PickerMetrics.panelHeight(), PickerMetrics.scrollHeight(), accuracy: 0.001)
        XCTAssertEqual(PickerMetrics.hintBottomInset(), 5, accuracy: 0.001)
    }

    func testPickerIconGapUsesCompactAppSwitcherSpacing() {
        let iconGap = PickerMetrics.itemWidth()
            - PickerMetrics.iconSize()
            + PickerMetrics.itemSpacing()
        let focusGap = PickerMetrics.itemWidth()
            - PickerMetrics.iconChromeSize()
            + PickerMetrics.itemSpacing()

        XCTAssertEqual(iconGap, 8, accuracy: 0.001)
        XCTAssertEqual(focusGap, 4, accuracy: 0.001)
    }

    func testPickerPanelWidthClampsToAvailableScreenWidth() {
        let width = PickerMetrics.panelWidth(itemCount: 40, availableWidth: 700)

        XCTAssertEqual(width, 684, accuracy: 0.001)
    }

    func testManualPickerPanelCentersInVisibleFrame() {
        let origin = PickerPanelPositioning.centeredOrigin(
            panelSize: NSSize(width: 352, height: 162),
            visibleFrame: NSRect(x: 100, y: 50, width: 1200, height: 800)
        )

        XCTAssertEqual(origin.x, 524, accuracy: 0.001)
        XCTAssertEqual(origin.y, 369, accuracy: 0.001)
    }

    func testRoutingPickerPanelPositionsNearCursor() {
        let origin = PickerPanelPositioning.nearCursorOrigin(
            mouseLocation: NSPoint(x: 700, y: 500),
            panelSize: NSSize(width: 352, height: 162),
            visibleFrame: NSRect(x: 100, y: 50, width: 1200, height: 800),
            scale: 1
        )

        XCTAssertEqual(origin.x, 524, accuracy: 0.001)
        XCTAssertEqual(origin.y, 459, accuracy: 0.001)
    }

    func testRoutingPickerPanelPositionClampsToVisibleFrame() {
        let origin = PickerPanelPositioning.nearCursorOrigin(
            mouseLocation: NSPoint(x: 40, y: 30),
            panelSize: NSSize(width: 352, height: 162),
            visibleFrame: NSRect(x: 100, y: 50, width: 1200, height: 800),
            scale: 1
        )

        XCTAssertEqual(origin.x, 108, accuracy: 0.001)
        XCTAssertEqual(origin.y, 58, accuracy: 0.001)
    }

    func testTypeAheadFocusesAppByName() {
        let items = [
            PickerItem(app: makeApp(id: "test.cursor", displayName: "Cursor")),
            PickerItem(app: makeApp(id: "test.figma", displayName: "Figma")),
        ]

        XCTAssertEqual(PickerTypeAheadMatcher.firstMatchIndex(in: items, query: "fig"), 1)
    }

    func testTypeAheadFocusesWindowByTitle() {
        let app = makeApp(id: "test.cursor", displayName: "Cursor")
        let items = [
            PickerItem(app: makeApp(id: "test.figma", displayName: "Figma")),
            PickerItem(app: app, windowTarget: AppWindowTarget(bundleID: app.id, title: "mac apps", index: 0)),
        ]

        XCTAssertEqual(PickerTypeAheadMatcher.firstMatchIndex(in: items, query: "mac"), 1)
    }

    func testTypeAheadFocusesBrowserProfile() {
        let profile = BrowserProfile(directoryName: "Default", displayName: "Work", email: "work@example.com")
        let items = [
            PickerItem(app: makeApp(id: "test.figma", displayName: "Figma")),
            PickerItem(browser: makeBrowser(profiles: [profile]), profile: profile),
        ]

        XCTAssertEqual(PickerTypeAheadMatcher.firstMatchIndex(in: items, query: "wor"), 1)
        XCTAssertEqual(PickerTypeAheadMatcher.firstMatchIndex(in: items, query: "edge"), nil)
        XCTAssertEqual(PickerTypeAheadMatcher.firstMatchIndex(in: items, query: "chrome"), 1)
    }

    func testPickerShortcutAssignerUsesAppHotkeys() throws {
        let item = PickerItem(app: makeApp(id: "test.figma", displayName: "Figma", hotkey: "f", hotkeyKeyCode: 3))
        let fKeyCode = try XCTUnwrap(KeyCodeMap.keyCode(for: "f"))

        let match = PickerShortcutAssigner.item(forKeyCode: fKeyCode, in: [item], positionalEnabled: true)

        XCTAssertEqual(match?.id, item.id)
    }

    func testPickerShortcutAssignerMatchesBrowserAndProfileHotkeysByKeyCode() throws {
        var browser = makeBrowser()
        browser.hotkey = "b"
        browser.hotkeyKeyCode = try XCTUnwrap(KeyCodeMap.keyCode(for: "b"))
        let profile = BrowserProfile(
            directoryName: "Default",
            displayName: "Work",
            email: nil,
            hotkey: "w",
            hotkeyKeyCode: try XCTUnwrap(KeyCodeMap.keyCode(for: "w"))
        )
        let profileBrowser = makeBrowser(profiles: [profile])
        let items = [
            PickerItem(browser: browser),
            PickerItem(browser: profileBrowser, profile: profile),
        ]

        XCTAssertEqual(
            PickerShortcutAssigner.item(
                forKeyCode: try XCTUnwrap(KeyCodeMap.keyCode(for: "b")),
                in: items,
                positionalEnabled: true
            )?.id,
            browser.id
        )
        XCTAssertEqual(
            PickerShortcutAssigner.item(
                forKeyCode: try XCTUnwrap(KeyCodeMap.keyCode(for: "w")),
                in: items,
                positionalEnabled: true
            )?.id,
            "\(profileBrowser.id):\(profile.directoryName)"
        )
    }

    func testPickerShortcutAssignerSkipsConfiguredKeyForPositionalPool() throws {
        let appWithCustomKey = PickerItem(app: makeApp(
            id: "test.custom",
            hotkey: "q",
            hotkeyKeyCode: try XCTUnwrap(KeyCodeMap.keyCode(for: "q"))
        ))
        let positionalItems = (0 ..< 11).map { index in
            PickerItem(app: makeApp(id: "test.positional.\(index)"))
        }
        let items = [appWithCustomKey] + positionalItems

        let assignments = PickerShortcutAssigner.assignments(for: items, positionalEnabled: true)

        XCTAssertEqual(assignments[appWithCustomKey.id]?.key, "q")
        XCTAssertEqual(assignments[positionalItems[0].id]?.key, "1")
        XCTAssertEqual(assignments[positionalItems[9].id]?.key, "0")
        XCTAssertEqual(assignments[positionalItems[10].id]?.key, "w")
    }

    func testPickerShortcutAssignerShowsConfiguredKeyOnOnlyFirstWindowItem() throws {
        let app = makeApp(
            id: "test.cursor",
            displayName: "Cursor",
            hotkey: "c",
            hotkeyKeyCode: try XCTUnwrap(KeyCodeMap.keyCode(for: "c"))
        )
        let items = [
            PickerItem(app: app, windowTarget: AppWindowTarget(bundleID: app.id, title: "One", index: 0)),
            PickerItem(app: app, windowTarget: AppWindowTarget(bundleID: app.id, title: "Two", index: 1)),
        ]

        let assignments = PickerShortcutAssigner.assignments(for: items, positionalEnabled: true)

        XCTAssertEqual(assignments[items[0].id]?.key, "c")
        XCTAssertEqual(assignments[items[0].id]?.source, .configured)
        XCTAssertEqual(assignments[items[1].id]?.key, "1")
        XCTAssertEqual(assignments[items[1].id]?.source, .positional)
    }

    func testBrowserConfigPreservesBrowserAndProfileHotkeySymbols() throws {
        let profile = BrowserProfile(
            directoryName: "Default",
            displayName: "Work",
            email: nil,
            hotkey: ".",
            hotkeyKeyCode: 47
        )
        var browser = makeBrowser(profiles: [profile])
        browser.hotkey = "/"
        browser.hotkeyKeyCode = 44

        let config = BrowserConfig(from: browser)

        XCTAssertEqual(config.hotkey, "/")
        XCTAssertEqual(config.hotkeyKeyCode, 44)
        XCTAssertEqual(config.profileHotkeys?["Default"], ".")
        XCTAssertEqual(config.profileHotkeyKeyCodes?["Default"], 47)
    }

    func testWindowFilterRejectsKnownMenuCommandTitles() {
        let commandTitles = [
            "Show Next Tab",
            "Merge All Windows",
            "Move Tab to New Window",
            "Close All",
            "New Group",
            "Add Contact",
            "Toggle Full Screen",
        ]
        let candidates = commandTitles.enumerated().map { index, title in
            WindowEnumerator.WindowCandidate(
                bundleID: "test.app",
                title: title,
                index: index,
                source: .ax,
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String,
                isMinimized: false,
                isModal: false
            )
        }

        XCTAssertTrue(WindowEnumerator.filteredWindowCandidates(candidates).isEmpty)
    }

    func testWindowFilterRejectsInvalidCoreGraphicsCandidates() {
        let invalidCandidates = [
            WindowEnumerator.WindowCandidate(
                bundleID: "test.app",
                title: "Offscreen",
                index: 0,
                source: .coreGraphics,
                ownerPID: pid_t(123),
                layer: 0,
                alpha: 1,
                isOnscreen: false,
                sharingState: 1,
                bounds: CGSize(width: 640, height: 480)
            ),
            WindowEnumerator.WindowCandidate(
                bundleID: "test.app",
                title: "Overlay",
                index: 1,
                source: .coreGraphics,
                ownerPID: pid_t(123),
                layer: 1,
                alpha: 1,
                isOnscreen: true,
                sharingState: 1,
                bounds: CGSize(width: 640, height: 480)
            ),
            WindowEnumerator.WindowCandidate(
                bundleID: "test.app",
                title: "Transparent",
                index: 2,
                source: .coreGraphics,
                ownerPID: pid_t(123),
                layer: 0,
                alpha: 0,
                isOnscreen: true,
                sharingState: 1,
                bounds: CGSize(width: 640, height: 480)
            ),
            WindowEnumerator.WindowCandidate(
                bundleID: "test.app",
                title: "Tiny",
                index: 3,
                source: .coreGraphics,
                ownerPID: pid_t(123),
                layer: 0,
                alpha: 1,
                isOnscreen: true,
                sharingState: 1,
                bounds: CGSize(width: 80, height: 80)
            ),
            WindowEnumerator.WindowCandidate(
                bundleID: "test.app",
                title: "",
                index: 4,
                source: .coreGraphics,
                ownerPID: pid_t(123),
                layer: 0,
                alpha: 1,
                isOnscreen: true,
                sharingState: 1,
                bounds: CGSize(width: 640, height: 480)
            ),
        ]

        XCTAssertTrue(WindowEnumerator.filteredWindowCandidates(invalidCandidates).isEmpty)
    }

    func testWindowFilterAcceptsStandardAXWindowsAndDedupeTitles() {
        let candidates = [
            WindowEnumerator.WindowCandidate(
                bundleID: "test.app",
                title: " Project ",
                index: 4,
                source: .ax,
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String,
                isMinimized: false,
                isModal: false
            ),
            WindowEnumerator.WindowCandidate(
                bundleID: "test.app",
                title: "project",
                index: 5,
                source: .ax,
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String,
                isMinimized: false,
                isModal: false
            ),
        ]

        let targets = WindowEnumerator.windowTargets(from: candidates)

        XCTAssertEqual(targets.map(\.title), ["Project"])
        XCTAssertEqual(targets.map(\.index), [4])
    }

    func testWindowFilterAcceptsValidCoreGraphicsWindow() {
        let candidate = WindowEnumerator.WindowCandidate(
            bundleID: "test.app",
            title: "Visible Document",
            index: 0,
            source: .coreGraphics,
            ownerPID: pid_t(123),
            layer: 0,
            alpha: 1,
            isOnscreen: true,
            sharingState: 1,
            bounds: CGSize(width: 640, height: 480)
        )

        XCTAssertEqual(WindowEnumerator.windowTargets(from: [candidate]).map(\.title), ["Visible Document"])
    }

    func testWindowFilterAcceptsMenuWindowTitlesAndRejectsMenuCommands() {
        let candidates = [
            WindowEnumerator.WindowCandidate(bundleID: "com.microsoft.VSCode", title: "Minimize", index: 0, source: .menu),
            WindowEnumerator.WindowCandidate(bundleID: "com.microsoft.VSCode", title: "alli-e2e-test", index: 1, source: .menu),
            WindowEnumerator.WindowCandidate(bundleID: "com.microsoft.VSCode", title: "apex-design-system", index: 2, source: .menu),
        ]

        XCTAssertEqual(
            WindowEnumerator.windowTargets(from: candidates).map(\.title),
            ["alli-e2e-test", "apex-design-system"]
        )
    }

    func testWindowMenuExtractionMatchesRealVSCodeLayout() {
        // Exact "Window" menu layout captured from a live VS Code with three open windows
        // (separators are empty strings). Only the trailing window group should survive.
        let menuItemTitles = [
            "Minimize", "Minimise All", "Zoom", "Zoom All", "Fill", "Centre",
            "", "Move & Resize", "Full-Screen Tile",
            "", "Remove Window from Set",
            "", "Switch Window…",
            "", "Bring All to Front", "Arrange in Front",
            "", "AlliChatSelection.test.ts — alli-e2e-test", "apex-design-system", "settings.test.ts — ofa",
        ]

        let windowTitles = WindowEnumerator.windowListTitles(fromMenuItemTitles: menuItemTitles)
        XCTAssertEqual(
            windowTitles,
            ["AlliChatSelection.test.ts — alli-e2e-test", "apex-design-system", "settings.test.ts — ofa"]
        )

        // Full pipeline: menu candidates → filtered targets.
        let candidates = windowTitles.enumerated().map { index, title in
            WindowEnumerator.WindowCandidate(bundleID: "com.microsoft.VSCode", title: title, index: index, source: .menu)
        }
        XCTAssertEqual(WindowEnumerator.windowTargets(from: candidates).count, 3)
    }

    func testMergeWindowTargetsPrefersPrimaryOrderAndDedupesByTitle() {
        // VS Code repro: the Window menu lists all three windows; AX surfaces only the focused one.
        let menuTargets = [
            AppWindowTarget(bundleID: "com.microsoft.VSCode", title: "alli-e2e-test", index: 0),
            AppWindowTarget(bundleID: "com.microsoft.VSCode", title: "apex-design-system", index: 1),
            AppWindowTarget(bundleID: "com.microsoft.VSCode", title: "ofa", index: 2),
        ]
        let axTargets = [
            AppWindowTarget(bundleID: "com.microsoft.VSCode", title: "Apex-Design-System", index: 1),
        ]

        let merged = WindowEnumerator.mergeWindowTargets(menuTargets, axTargets)

        XCTAssertEqual(merged.map(\.title), ["alli-e2e-test", "apex-design-system", "ofa"])
    }

    func testShouldMergeWindowMenuTriggersWhenAXReturnsNothing() {
        // AX==0 means the app's windows are all off-Space/empty-titled: consult the Window menu (and
        // there's no AX window to accidentally duplicate against), regardless of bundle type.
        XCTAssertTrue(WindowEnumerator.shouldMergeWindowMenu(axWindowCount: 0, isWebContentApp: false))
    }

    func testShouldMergeWindowMenuTrustsAppsThatReportAtLeastOneAXWindow() {
        // A normal app reporting ≥1 window via AX is trusted verbatim — no menu read, so Chrome/Edge
        // can't gain a phantom tile from a menu entry whose title differs from the AX window's.
        XCTAssertFalse(WindowEnumerator.shouldMergeWindowMenu(axWindowCount: 1, isWebContentApp: false))
        XCTAssertFalse(WindowEnumerator.shouldMergeWindowMenu(axWindowCount: 5, isWebContentApp: false))
    }

    func testShouldMergeWindowMenuAlwaysMergesElectronEvenWithManyAXWindows() {
        // Electron/CEF bundles under-report off-Space windows even when ≥1 shows on the current Space,
        // so always cross-check their Window menu.
        XCTAssertTrue(WindowEnumerator.shouldMergeWindowMenu(axWindowCount: 3, isWebContentApp: true))
    }

    func testShouldMergeWindowMenuSkipsBundleInspectionWhenAXReturnsNothing() {
        // The autoclosure must NOT be evaluated on the AX==0 fast path — it short-circuits to true
        // before the filesystem bundle probe.
        var probed = false
        let result = WindowEnumerator.shouldMergeWindowMenu(
            axWindowCount: 0,
            isWebContentApp: { probed = true; return false }()
        )
        XCTAssertTrue(result)
        XCTAssertFalse(probed, "bundle inspection should be skipped on the AX==0 fast path")
    }

    func testShouldMergeWindowMenuProbesBundleWhenAXReportsWindows() {
        // With ≥1 AX window the symptom path is false, so the bundle type decides — the probe runs.
        var probed = false
        let result = WindowEnumerator.shouldMergeWindowMenu(
            axWindowCount: 2,
            isWebContentApp: { probed = true; return true }()
        )
        XCTAssertTrue(result)
        XCTAssertTrue(probed, "bundle inspection must run when AX already reports windows")
    }

    func testBundleContainsWebContentFrameworkDetectsElectronAndChromium() throws {
        let electron = try makeAppBundle(named: "Electronic", frameworks: ["Electron Framework.framework"])
        let cef = try makeAppBundle(named: "Embedded", frameworks: ["Chromium Embedded Framework.framework"])
        let native = try makeAppBundle(named: "Cocoa", frameworks: ["Sparkle.framework"])

        XCTAssertTrue(WindowEnumerator.bundleContainsWebContentFramework(in: electron))
        XCTAssertTrue(WindowEnumerator.bundleContainsWebContentFramework(in: cef))
        XCTAssertFalse(WindowEnumerator.bundleContainsWebContentFramework(in: native))
    }

    func testPickerBrowserProfileDisplayNameIncludesBrowserAndProfile() {
        let profile = BrowserProfile(directoryName: "Default", displayName: "Work", email: nil)
        let item = PickerItem(browser: makeBrowser(profiles: [profile]), profile: profile)

        XCTAssertEqual(item.displayName, "Chrome - Work")
    }

    @MainActor
    func testManualPickerShowsRunningBrowserAsAppTileInsteadOfProfileAction() {
        let profile = BrowserProfile(directoryName: "Default", displayName: "Work", email: nil)
        var browser = makeBrowser(profiles: [profile], profileType: .chromium)
        browser.isVisible = false

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [browser],
            allBrowsers: [browser],
            apps: [],
            appUsage: [:],
            runningBundleIDs: [browser.id],
            windowsByAppID: [:],
            regularBundleIDs: [browser.id]
        )

        XCTAssertEqual(items.map(\.id), [browser.id])
        XCTAssertNil(items[0].profile)
    }

    func testWebFilesPutBrowsersBeforeAppsInPickerOrder() throws {
        let htmlURL = try makeTempFile(named: "index.html")
        let yamlURL = try makeTempFile(named: "config.yaml")
        let app = makeApp(id: "test.editor.html", customFormats: ["html"])
        let browser = makeBrowser()

        XCTAssertTrue(PickerItem.shouldShowBrowsersFirst(for: htmlURL))
        XCTAssertFalse(PickerItem.shouldShowBrowsersFirst(for: yamlURL))

        let items = PickerItem.buildItems(
            browsers: [browser],
            apps: [app],
            browsersFirst: PickerItem.shouldShowBrowsersFirst(for: htmlURL)
        )

        XCTAssertEqual(items.map(\.id), ["com.google.Chrome", "app:test.editor.html"])
    }

    @MainActor
    func testPickerItemsRankMatchingAppsByRecentUseThenFrequency() throws {
        let url = try XCTUnwrap(URL(string: "https://app.slack.com/client"))
        let rarelyUsed = makeApp(
            id: "test.app.rare",
            displayName: "Recent",
            hostPatterns: ["slack.com", "app.slack.com"],
            sortOrder: 0
        )
        let frequentlyUsed = makeApp(
            id: "test.app.frequent",
            displayName: "Frequent",
            hostPatterns: ["slack.com", "app.slack.com"],
            sortOrder: 1
        )

        let items = PickerItem.items(
            for: url,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [rarelyUsed, frequentlyUsed],
            appUsage: [
                frequentlyUsed.id: AppUsage(count: 10, lastUsed: Date(timeIntervalSince1970: 1_000)),
                rarelyUsed.id: AppUsage(count: 1, lastUsed: Date(timeIntervalSince1970: 2_000)),
            ]
        )

        XCTAssertEqual(items.map(\.id), ["app:test.app.rare", "app:test.app.frequent"])
    }

    @MainActor
    func testManualPickerIncludesRunningAppsWithoutPendingURL() throws {
        let bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let runningApp = makeApp(id: bundleID, displayName: "AppCat Tests")
        let stoppedApp = makeApp(id: "test.not.running", displayName: "Not Running")

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [stoppedApp, runningApp],
            appUsage: [:],
            runningBundleIDs: [bundleID],
            windowsByAppID: [:]
        )

        XCTAssertEqual(items.map(\.id), ["app:\(bundleID)"])
    }

    @MainActor
    func testManualPickerIncludesOnlyRunningBrowsersWithoutPendingURL() {
        let runningBrowser = makeBrowser()
        let stoppedBrowser = InstalledBrowser(
            id: "test.browser.stopped",
            displayName: "Stopped",
            appURL: URL(fileURLWithPath: "/Applications/Stopped.app"),
            isVisible: true,
            sortOrder: 1,
            supportsPrivateMode: false
        )

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [stoppedBrowser, runningBrowser],
            allBrowsers: [stoppedBrowser, runningBrowser],
            apps: [],
            appUsage: [:],
            runningBundleIDs: [runningBrowser.id],
            windowsByAppID: [:]
        )

        XCTAssertEqual(items.map { $0.id }, [runningBrowser.id])
    }

    @MainActor
    func testManualPickerKeepsSingleRunningAppWindowAsAppTile() {
        let app = makeApp(id: "test.cursor", displayName: "Cursor")
        let windows = [
            AppWindowTarget(bundleID: app.id, title: "AppCat", index: 0),
        ]

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [app],
            appUsage: [:],
            runningBundleIDs: [app.id],
            windowsByAppID: [app.id: windows]
        )

        XCTAssertEqual(items.map(\.id), ["app:test.cursor"])
        XCTAssertEqual(items.map(\.displayName), ["Cursor"])
        XCTAssertTrue(items.allSatisfy { $0.windowTarget == nil })
    }

    @MainActor
    func testManualPickerKeepsSingleRunningBrowserWindowAsBrowserTile() {
        let browser = makeBrowser()
        let windows = [
            AppWindowTarget(bundleID: browser.id, title: "Chrome", index: 0),
        ]

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [browser],
            allBrowsers: [browser],
            apps: [],
            appUsage: [:],
            runningBundleIDs: [browser.id],
            windowsByAppID: [browser.id: windows]
        )

        XCTAssertEqual(items.map(\.id), [browser.id])
        XCTAssertEqual(items.map(\.displayName), [browser.displayName])
        XCTAssertTrue(items.allSatisfy { $0.windowTarget == nil })
    }

    @MainActor
    func testManualPickerExpandsRunningBrowserWindowsWithoutPendingURL() {
        let browser = makeBrowser()
        let windows = [
            AppWindowTarget(bundleID: browser.id, title: "Client Portal", index: 0),
            AppWindowTarget(bundleID: browser.id, title: "AppCat", index: 1),
        ]

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [browser],
            allBrowsers: [browser],
            apps: [],
            appUsage: [:],
            runningBundleIDs: [browser.id],
            windowsByAppID: [browser.id: windows]
        )

        XCTAssertEqual(items.map(\.id), [
            "window:\(browser.id):0:Client Portal",
            "window:\(browser.id):1:AppCat",
        ])
        XCTAssertEqual(items.map(\.displayName), ["Client Portal", "AppCat"])
        XCTAssertEqual(items.compactMap(\.secondaryDisplayName), [browser.displayName, browser.displayName])
    }

    @MainActor
    func testManualPickerExpandsRunningAppWindowsWithoutPendingURL() {
        let app = makeApp(id: "test.cursor", displayName: "Cursor")
        let windows = [
            AppWindowTarget(bundleID: app.id, title: "AppCat", index: 0),
            AppWindowTarget(bundleID: app.id, title: "mac apps", index: 1),
        ]

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [app],
            appUsage: [:],
            runningBundleIDs: [app.id],
            windowsByAppID: [app.id: windows]
        )

        XCTAssertEqual(items.map(\.id), [
            "window:test.cursor:0:AppCat",
            "window:test.cursor:1:mac apps",
        ])
        XCTAssertEqual(items.map(\.displayName), ["AppCat", "mac apps"])
        XCTAssertEqual(items.compactMap(\.secondaryDisplayName), ["Cursor", "Cursor"])
    }

    @MainActor
    func testManualPickerHidesBackgroundAppsByDefault() {
        let regularApp = makeApp(id: "test.regular", displayName: "Regular")
        let menuBarApp = makeApp(id: "test.menubar", displayName: "Brightness")

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [regularApp, menuBarApp],
            appUsage: [:],
            runningBundleIDs: [regularApp.id, menuBarApp.id],
            windowsByAppID: [:],
            regularBundleIDs: [regularApp.id]
        )

        XCTAssertEqual(items.map(\.id), ["app:test.regular"])
    }

    @MainActor
    func testManualPickerShowsBackgroundAppsWhenEnabled() {
        let regularApp = makeApp(id: "test.regular", displayName: "Regular")
        let menuBarApp = makeApp(id: "test.menubar", displayName: "Brightness")

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [regularApp, menuBarApp],
            appUsage: [:],
            runningBundleIDs: [regularApp.id, menuBarApp.id],
            windowsByAppID: [:],
            regularBundleIDs: [regularApp.id],
            showBackgroundApps: true
        )

        XCTAssertEqual(Set(items.map(\.id)), ["app:test.regular", "app:test.menubar"])
    }

    @MainActor
    func testPickerHiddenAppsAreExcludedFromURLPicker() throws {
        let hiddenApp = makeApp(id: "test.hidden", displayName: "Hidden", hostPatterns: ["example.com"])
        let shownApp = makeApp(id: "test.shown", displayName: "Shown", hostPatterns: ["example.com"])
        let url = try XCTUnwrap(URL(string: "https://example.com/path"))

        let items = PickerItem.items(
            for: url,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [hiddenApp, shownApp],
            appUsage: [:],
            hiddenAppIDs: [hiddenApp.id]
        )

        XCTAssertEqual(items.map(\.id), ["app:test.shown"])
    }

    @MainActor
    func testPickerHiddenAppsAreExcludedFromManualSwitcher() {
        let hiddenApp = makeApp(id: "test.hidden", displayName: "Hidden")
        let shownApp = makeApp(id: "test.shown", displayName: "Shown")

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [hiddenApp, shownApp],
            appUsage: [:],
            runningBundleIDs: [hiddenApp.id, shownApp.id],
            windowsByAppID: [:],
            regularBundleIDs: [hiddenApp.id, shownApp.id],
            hiddenAppIDs: [hiddenApp.id]
        )

        XCTAssertEqual(items.map(\.id), ["app:test.shown"])
    }

    @MainActor
    func testManualPickerGroupsWindowedBeforeWindowlessAndTagsThem() {
        let windowedApp = makeApp(id: "test.win", displayName: "Windowed")
        let idleApp = makeApp(id: "test.idle", displayName: "Idle")
        let windows = [AppWindowTarget(bundleID: windowedApp.id, title: "Project", index: 0)]

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [idleApp, windowedApp],
            appUsage: [:],
            runningBundleIDs: [windowedApp.id, idleApp.id],
            windowsByAppID: [windowedApp.id: windows],
            regularBundleIDs: [windowedApp.id, idleApp.id]
        )

        XCTAssertEqual(items.map(\.id), ["app:test.win", "app:test.idle"])
        XCTAssertTrue(items[0].hasOpenWindows)
        XCTAssertFalse(items[0].isBackgroundRunning)
        XCTAssertFalse(items[1].hasOpenWindows)
        XCTAssertTrue(items[1].isBackgroundRunning)
    }

    @MainActor
    func testManualPickerHidesWindowlessAppsWhenDisabled() {
        let windowedApp = makeApp(id: "test.win", displayName: "Windowed")
        let idleApp = makeApp(id: "test.idle", displayName: "Idle")
        let windows = [AppWindowTarget(bundleID: windowedApp.id, title: "Project", index: 0)]

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [idleApp, windowedApp],
            appUsage: [:],
            runningBundleIDs: [windowedApp.id, idleApp.id],
            windowsByAppID: [windowedApp.id: windows],
            regularBundleIDs: [windowedApp.id, idleApp.id],
            showWindowlessApps: false
        )

        XCTAssertEqual(items.map(\.id), ["app:test.win"])
    }

    @MainActor
    func testManualPickerSortsByActivationRecencyThenFrequency() {
        let a = makeApp(id: "test.a", displayName: "A")
        let b = makeApp(id: "test.b", displayName: "B")
        let c = makeApp(id: "test.c", displayName: "C")
        func window(_ id: String) -> [AppWindowTarget] {
            [AppWindowTarget(bundleID: id, title: "w", index: 0)]
        }

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [a, b, c],
            appUsage: [:],
            runningBundleIDs: [a.id, b.id, c.id],
            windowsByAppID: [a.id: window(a.id), b.id: window(b.id), c.id: window(c.id)],
            activations: [
                a.id: AppUsage(count: 5, lastUsed: Date(timeIntervalSince1970: 9_000)),
                b.id: AppUsage(count: 10, lastUsed: Date(timeIntervalSince1970: 1_000)),
                c.id: AppUsage(count: 10, lastUsed: Date(timeIntervalSince1970: 2_000)),
            ],
            regularBundleIDs: [a.id, b.id, c.id]
        )

        // recency desc first (a newest), then count desc (c before b when both are older).
        XCTAssertEqual(items.map(\.id), ["app:test.a", "app:test.c", "app:test.b"])
    }

    @MainActor
    func testManualPickerCollapsesIdenticallyTitledWindowsOfSameApp() {
        // Defense-in-depth: even if two windows of one app carry the same title, the switcher renders
        // one tile (they'd be indistinguishable in the row anyway).
        let app = makeApp(id: "test.cursor", displayName: "Cursor")
        let windows = [
            AppWindowTarget(bundleID: app.id, title: "Project", index: 0),
            AppWindowTarget(bundleID: app.id, title: "Project", index: 1),
        ]

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [app],
            appUsage: [:],
            runningBundleIDs: [app.id],
            windowsByAppID: [app.id: windows],
            regularBundleIDs: [app.id]
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.displayName, "Project")
    }

    @MainActor
    func testManualPickerKeepsDistinctlyTitledWindowsOfSameApp() {
        // The net must not over-collapse: different titles stay as separate per-window tiles.
        let app = makeApp(id: "test.cursor", displayName: "Cursor")
        let windows = [
            AppWindowTarget(bundleID: app.id, title: "Project A", index: 0),
            AppWindowTarget(bundleID: app.id, title: "Project B", index: 1),
        ]

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [app],
            appUsage: [:],
            runningBundleIDs: [app.id],
            windowsByAppID: [app.id: windows],
            regularBundleIDs: [app.id]
        )

        XCTAssertEqual(items.map(\.displayName), ["Project A", "Project B"])
    }

    @MainActor
    func testManualPickerSurfacesRunningHiddenBrowserAsAppTile() {
        // Apps like cmux register an http handler, get classified as a browser, and are hidden from
        // the routing picker (isVisible == false). They should still appear in the app switcher.
        let app = makeApp(id: "test.editor", displayName: "Editor")
        let hiddenBrowserApp = InstalledBrowser(
            id: "com.cmuxterm.app",
            displayName: "cmux",
            appURL: URL(fileURLWithPath: "/Applications/cmux.app"),
            isVisible: false,
            sortOrder: 5,
            supportsPrivateMode: false
        )

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [hiddenBrowserApp],
            apps: [app],
            appUsage: [:],
            runningBundleIDs: [app.id, hiddenBrowserApp.id],
            windowsByAppID: [app.id: [AppWindowTarget(bundleID: app.id, title: "w", index: 0)]],
            regularBundleIDs: [app.id, hiddenBrowserApp.id]
        )

        XCTAssertTrue(items.map(\.id).contains("com.cmuxterm.app"))
        XCTAssertEqual(items.first { $0.id == "com.cmuxterm.app" }?.displayName, "cmux")
    }

    @MainActor
    func testPickerHiddenAppsExcludeBrowserFallbackTiles() {
        let hiddenBrowserApp = InstalledBrowser(
            id: "com.cmuxterm.app",
            displayName: "cmux",
            appURL: URL(fileURLWithPath: "/Applications/cmux.app"),
            isVisible: false,
            sortOrder: 5,
            supportsPrivateMode: false
        )

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [hiddenBrowserApp],
            apps: [],
            appUsage: [:],
            runningBundleIDs: [hiddenBrowserApp.id],
            windowsByAppID: [:],
            regularBundleIDs: [hiddenBrowserApp.id],
            hiddenAppIDs: [hiddenBrowserApp.id]
        )

        XCTAssertFalse(items.map(\.id).contains("com.cmuxterm.app"))
    }

    @MainActor
    func testManualPickerExcludesIgnoredHiddenBrowser() {
        let ignoredBrowserApp = InstalledBrowser(
            id: "com.cmuxterm.app",
            displayName: "cmux",
            appURL: URL(fileURLWithPath: "/Applications/cmux.app"),
            isVisible: false,
            isIgnored: true,
            sortOrder: 5,
            supportsPrivateMode: false
        )

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [ignoredBrowserApp],
            apps: [],
            appUsage: [:],
            runningBundleIDs: [ignoredBrowserApp.id],
            windowsByAppID: [:],
            regularBundleIDs: [ignoredBrowserApp.id]
        )

        XCTAssertFalse(items.map(\.id).contains("com.cmuxterm.app"))
    }

    @MainActor
    func testSingleDetectedBrowserProfileIsShownAsProfileSupport() {
        let browser = makeBrowser(profiles: [
            BrowserProfile(directoryName: "Default", displayName: "Personal", email: nil),
        ])

        XCTAssertTrue(browser.hasProfiles)
    }

    @MainActor
    func testProfileDetectorParsesChromiumLocalState() throws {
        let appSupport = try makeTempDirectory()
        let chromeDir = appSupport.appendingPathComponent("Google/Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: chromeDir, withIntermediateDirectories: true)
        let localState = """
        {
          "profile": {
            "info_cache": {
              "Profile 1": {
                "name": "Work",
                "user_name": "work@example.com",
                "gaia_picture_file_name": "Google Profile Picture.png"
              },
              "Default": {
                "name": "Personal",
                "user_name": ""
              },
              "System Profile": {
                "name": "System",
                "is_omitted_from_profile_list": true
              }
            }
          }
        }
        """
        let avatarDirectory = chromeDir.appendingPathComponent("Profile 1", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarDirectory, withIntermediateDirectories: true)
        let avatarPath = avatarDirectory.appendingPathComponent("Google Profile Picture.png")
        try Data("fake-png".utf8).write(to: avatarPath)
        try Data(localState.utf8).write(to: chromeDir.appendingPathComponent("Local State"))

        let detector = ProfileDetector(applicationSupportDirectory: appSupport)
        let profiles = detector.detectProfiles(for: makeBrowser(
            profileDataPath: "Google/Chrome",
            profileType: .chromium
        ))

        XCTAssertEqual(profiles.map(\.directoryName), ["Default", "Profile 1"])
        XCTAssertEqual(profiles.map(\.displayName), ["Personal", "Work"])
        XCTAssertNil(profiles[0].email)
        XCTAssertEqual(profiles[1].email, "work@example.com")
        XCTAssertNil(profiles[0].avatarPath)
        XCTAssertEqual(profiles[1].avatarPath, avatarPath.path)
    }

    @MainActor
    func testProfileDetectorParsesFirefoxProfilesIni() throws {
        let appSupport = try makeTempDirectory()
        let zenDir = appSupport.appendingPathComponent("zen", isDirectory: true)
        try FileManager.default.createDirectory(at: zenDir, withIntermediateDirectories: true)
        let profilesIni = """
        [Install308046B0AF4A39CB]
        Default=Profiles/ignored.default

        [Profile1]
        Name=Work
        IsRelative=1
        Path=Profiles/gwcmmal6.Default Profile

        [General]
        StartWithLastProfile=1
        Version=2

        [Profile0]
        Name=Personal
        IsRelative=1
        Path=Profiles/zmom57wf.Default (release)
        """
        try Data(profilesIni.utf8).write(to: zenDir.appendingPathComponent("profiles.ini"))

        let detector = ProfileDetector(applicationSupportDirectory: appSupport)
        let profiles = detector.detectProfiles(for: makeBrowser(
            profileDataPath: "zen",
            profileType: .firefox
        ))

        XCTAssertEqual(profiles.map(\.directoryName), ["zmom57wf.Default (release)", "gwcmmal6.Default Profile"])
        XCTAssertEqual(profiles.map(\.displayName), ["Personal", "Work"])
    }

    private func makeApp(
        id: String,
        displayName: String? = nil,
        urlSchemes: [String] = [],
        hostPatterns: [String] = [],
        sortOrder: Int = 0,
        hotkey: Character? = nil,
        hotkeyKeyCode: UInt16? = nil,
        customFormats: [String]? = nil,
        opensUnknownTypes: Bool = false,
        detectedFormats: [String] = []
    ) -> InstalledApp {
        InstalledApp(
            id: id,
            displayName: displayName ?? id,
            appURL: URL(fileURLWithPath: "/Applications/\(id).app"),
            urlSchemes: urlSchemes,
            hostPatterns: hostPatterns,
            isVisible: true,
            sortOrder: sortOrder,
            hotkey: hotkey,
            hotkeyKeyCode: hotkeyKeyCode,
            customFormats: customFormats,
            opensUnknownTypes: opensUnknownTypes,
            detectedFormats: detectedFormats
        )
    }

    private func makeBrowser(
        profiles: [BrowserProfile] = [],
        profileDataPath: String? = nil,
        profileType: ProfileType? = nil
    ) -> InstalledBrowser {
        InstalledBrowser(
            id: "com.google.Chrome",
            displayName: "Chrome",
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isVisible: true,
            sortOrder: 0,
            supportsPrivateMode: true,
            privateModeArgs: ["--incognito"],
            profileDataPath: profileDataPath,
            profileType: profileType,
            profiles: profiles
        )
    }

    /// Build a throwaway `.app` bundle with the given frameworks under `Contents/Frameworks` so
    /// bundle-shape detection can be tested without a real installed app.
    private func makeAppBundle(named name: String, frameworks: [String]) throws -> URL {
        let root = try makeTempDirectory().appendingPathComponent("\(name).app", isDirectory: true)
        let frameworksDir = root.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        try FileManager.default.createDirectory(at: frameworksDir, withIntermediateDirectories: true)
        for framework in frameworks {
            try FileManager.default.createDirectory(
                at: frameworksDir.appendingPathComponent(framework, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    private func makeTempFile(named name: String) throws -> URL {
        let directory = try makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("test".utf8).write(to: url)
        return url
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppCatTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
