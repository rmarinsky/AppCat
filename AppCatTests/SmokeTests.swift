@testable import AppCat
import AppKit
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

    func testPickerSelectionShortcutsUseOneThroughZero() {
        XCTAssertEqual(PickerItem.selectionShortcut(for: 0), "1")
        XCTAssertEqual(PickerItem.selectionShortcut(for: 8), "9")
        XCTAssertEqual(PickerItem.selectionShortcut(for: 9), "0")
        XCTAssertNil(PickerItem.selectionShortcut(for: 10))
    }

    func testPickerNumberSelectionMapsZeroToTenthItem() {
        XCTAssertEqual(PickerItem.numberSelectionIndex(for: "1"), 0)
        XCTAssertEqual(PickerItem.numberSelectionIndex(for: "9"), 8)
        XCTAssertEqual(PickerItem.numberSelectionIndex(for: "0"), 9)
        XCTAssertNil(PickerItem.numberSelectionIndex(for: "a"))
    }

    func testPickerPanelWidthUsesContentWidthForSmallItemCounts() {
        let expected: CGFloat = 240

        let width = PickerMetrics.panelWidth(itemCount: 3, availableWidth: 1200)

        XCTAssertEqual(width, expected, accuracy: 0.001)
    }

    func testAppSwitcherPanelWidthUsesLargerCommandTabMetrics() {
        let expected: CGFloat = 352

        let width = PickerMetrics.panelWidth(itemCount: 3, availableWidth: 1200, style: .appSwitcher)

        XCTAssertEqual(width, expected, accuracy: 0.001)
    }

    func testAppSwitcherIconGapIsCompact() {
        let iconGap = PickerMetrics.itemWidth(for: .appSwitcher)
            - PickerMetrics.iconSize(for: .appSwitcher)
            + PickerMetrics.itemSpacing(for: .appSwitcher)

        XCTAssertEqual(iconGap, 18, accuracy: 0.001)
    }

    func testPickerPanelWidthClampsToAvailableScreenWidth() {
        let width = PickerMetrics.panelWidth(itemCount: 40, availableWidth: 700)

        XCTAssertEqual(width, 684, accuracy: 0.001)
    }

    func testAppSwitcherPanelCentersInVisibleFrame() {
        let origin = PickerPanelPositioning.centeredOrigin(
            panelSize: NSSize(width: 352, height: 162),
            visibleFrame: NSRect(x: 100, y: 50, width: 1200, height: 800)
        )

        XCTAssertEqual(origin.x, 524, accuracy: 0.001)
        XCTAssertEqual(origin.y, 369, accuracy: 0.001)
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

    func testPickerHotkeyResolverIgnoresAppHotkeys() {
        let item = PickerItem(app: makeApp(id: "test.figma", displayName: "Figma", hotkey: "f"))

        XCTAssertNil(PickerHotkeyResolver.browserOrProfileMatch(in: [item], keyCode: 3, keyChar: "f"))
    }

    func testPickerHotkeyResolverMatchesBrowserAndProfileHotkeys() {
        var browser = makeBrowser()
        browser.hotkey = "b"
        let profile = BrowserProfile(directoryName: "Default", displayName: "Work", email: nil, hotkey: "w")
        let profileBrowser = makeBrowser(profiles: [profile])
        let items = [
            PickerItem(browser: browser),
            PickerItem(browser: profileBrowser, profile: profile),
        ]

        XCTAssertEqual(PickerHotkeyResolver.browserOrProfileMatch(in: items, keyCode: 11, keyChar: "b")?.id, browser.id)
        XCTAssertEqual(PickerHotkeyResolver.browserOrProfileMatch(in: items, keyCode: 13, keyChar: "w")?.id, "\(profileBrowser.id):\(profile.directoryName)")
    }

    func testPickerBrowserProfileDisplayNameIncludesBrowserAndProfile() {
        let profile = BrowserProfile(directoryName: "Default", displayName: "Work", email: nil)
        let item = PickerItem(browser: makeBrowser(profiles: [profile]), profile: profile)

        XCTAssertEqual(item.displayName, "Chrome - Work")
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
    func testPickerItemsUseSameAppUsageOrderAsVisiblePicker() throws {
        let url = try XCTUnwrap(URL(string: "https://app.slack.com/client"))
        let rarelyUsed = makeApp(
            id: "test.app.rare",
            displayName: "Rare",
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
                frequentlyUsed.id: AppUsage(count: 10, lastUsed: Date()),
                rarelyUsed.id: AppUsage(count: 1, lastUsed: Date()),
            ]
        )

        XCTAssertEqual(items.map(\.id), ["app:test.app.frequent", "app:test.app.rare"])
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
            urlSchemes: [],
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
