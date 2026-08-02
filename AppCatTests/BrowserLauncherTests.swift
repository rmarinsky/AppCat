@testable import AppCat
import XCTest

final class BrowserLauncherTests: XCTestCase {
    @MainActor
    func testFailedBrowserOpenDoesNotRecordRoutingStats() async throws {
        let world = FakeBrowserLauncherWorld()
        world.openErrors = [BrowserLauncherTestError.failed]
        let stats = StatsManager(storage: BrowserLauncherStatsStorage())
        let coordinator = PickerCoordinator(
            browserLauncher: BrowserLauncher(dependencies: world.dependencies())
        )
        coordinator.statsManager = stats
        let state = AppState()
        let url = try XCTUnwrap(URL(string: "https://example.com/one-time"))
        state.setPendingOpen(displayURLs: [url], launchURLs: [url])
        state.isPickerVisible = true

        XCTAssertTrue(coordinator.select(PickerItem(browser: makeBrowser()), state: state))
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertTrue(stats.dailyStats.isEmpty)
    }

    @MainActor
    func testSuccessfulBrowserOpenRecordsRoutingStatsOnCompletion() throws {
        let world = FakeBrowserLauncherWorld()
        let stats = StatsManager(storage: BrowserLauncherStatsStorage())
        let coordinator = PickerCoordinator(
            browserLauncher: BrowserLauncher(dependencies: world.dependencies())
        )
        coordinator.statsManager = stats
        let state = AppState()
        let url = try XCTUnwrap(URL(string: "https://example.com/path"))
        state.setPendingOpen(displayURLs: [url], launchURLs: [url])
        state.isPickerVisible = true

        XCTAssertTrue(coordinator.select(PickerItem(browser: makeBrowser()), state: state))

        XCTAssertEqual(stats.totalOpenCount, 1)
    }

    @MainActor
    func testPartialMultiURLAppOpenRecordsOnlySuccessfulURL() throws {
        let world = FakeBrowserLauncherWorld()
        world.openErrors = [BrowserLauncherTestError.failed, nil]
        let stats = StatsManager(storage: BrowserLauncherStatsStorage())
        let coordinator = PickerCoordinator(
            browserLauncher: BrowserLauncher(dependencies: world.dependencies())
        )
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
        let historyStorage = HistoryStorage(fileURL: historyURL)
        let appUsageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-usage-\(UUID().uuidString).json")
        let appUsageStore = AppUsageFileStore(
            file: appUsageURL,
            queueLabel: "ua.com.rmarinsky.appcat.tests.appusage-\(UUID().uuidString)"
        )
        defer {
            historyStorage.flush()
            appUsageStore.flush()
            try? FileManager.default.removeItem(at: historyURL)
            try? FileManager.default.removeItem(at: appUsageURL)
        }
        coordinator.historyManager = HistoryManager(storage: historyStorage)
        coordinator.statsManager = stats
        let state = AppState(appUsageStore: appUsageStore)
        let failedURL = try XCTUnwrap(URL(string: "https://example.com/failed"))
        let openedURL = try XCTUnwrap(URL(string: "https://example.com/opened"))
        state.setPendingOpen(
            displayURLs: [failedURL, openedURL],
            launchURLs: [failedURL, openedURL]
        )
        state.isPickerVisible = true
        let app = makeApp(id: "com.test.Editor", urlSchemes: [])

        XCTAssertTrue(coordinator.select(PickerItem(app: app), state: state))

        XCTAssertEqual(state.history.map(\.url), [openedURL.absoluteString])
        XCTAssertEqual(state.appUsage[app.id]?.count, 1)
        XCTAssertEqual(stats.totalOpenCount, 1)
    }

    @MainActor
    func testNativeAppCandidatesReportOneSuccessAfterFallback() throws {
        let world = FakeBrowserLauncherWorld()
        world.openErrors = [BrowserLauncherTestError.failed, nil]
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let url = try XCTUnwrap(URL(string: "https://www.figma.com/design/AbCd/Product"))
        var results: [Bool] = []

        launcher.open(url: url, with: makeApp(id: "com.figma.Desktop", urlSchemes: ["figma"])) {
            results.append($0)
        }

        XCTAssertEqual(world.openedURLs.count, 2)
        XCTAssertEqual(results, [true])
    }

    @MainActor
    func testNativeAppCandidatesReportOneFailureWhenAllFail() throws {
        let world = FakeBrowserLauncherWorld()
        world.openErrors = Array(repeating: BrowserLauncherTestError.failed, count: 3)
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let url = try XCTUnwrap(URL(string: "https://www.figma.com/design/AbCd/Product"))
        var results: [Bool] = []

        launcher.open(url: url, with: makeApp(id: "com.figma.Desktop", urlSchemes: ["figma"])) {
            results.append($0)
        }

        XCTAssertEqual(world.openedURLs.count, 3)
        XCTAssertEqual(results, [false])
    }

    @MainActor
    func testSuccessfulManualSelectionsRecordAppAndBrowserTargets() {
        let runningApp = FakeRunningApplication()
        let world = FakeBrowserLauncherWorld(runningApplication: runningApp, hasOpenWindows: true)
        let stats = StatsManager(storage: BrowserLauncherStatsStorage())
        let coordinator = PickerCoordinator(
            browserLauncher: BrowserLauncher(dependencies: world.dependencies())
        )
        coordinator.statsManager = stats
        let state = AppState()
        state.isPickerVisible = true
        state.pickerInvocationSource = .serviceKey

        XCTAssertTrue(coordinator.select(
            PickerItem(app: makeApp(id: "Com.Test.Editor", urlSchemes: [])),
            state: state
        ))

        state.isPickerVisible = true
        state.pickerInvocationSource = .toggleShortcut
        XCTAssertTrue(coordinator.select(PickerItem(browser: makeBrowser()), state: state))

        world.activateWindowTargetResult = true
        state.isPickerVisible = true
        state.pickerInvocationSource = .holdOptionTab
        let app = makeApp(id: "Com.Test.Editor", urlSchemes: [])
        XCTAssertTrue(coordinator.select(
            PickerItem(
                app: app,
                windowTarget: AppWindowTarget(bundleID: app.id, title: "Project", index: 0)
            ),
            state: state
        ))

        XCTAssertEqual(stats.dailyStats.first?.manualPickerTargetCounts, [
            "com.test.browser": 1,
            "com.test.editor": 2,
        ])
    }

    @MainActor
    func testFailedManualActivationDoesNotRecordTarget() {
        let world = FakeBrowserLauncherWorld(runningApplication: nil, hasOpenWindows: nil)
        let stats = StatsManager(storage: BrowserLauncherStatsStorage())
        let coordinator = PickerCoordinator(
            browserLauncher: BrowserLauncher(dependencies: world.dependencies())
        )
        coordinator.statsManager = stats
        let state = AppState()
        state.isPickerVisible = true
        state.pickerInvocationSource = .serviceKey

        XCTAssertTrue(coordinator.select(
            PickerItem(app: makeApp(id: "com.test.Editor", urlSchemes: [])),
            state: state
        ))

        XCTAssertTrue(stats.dailyStats.isEmpty)
    }

    @MainActor
    func testRejectedManualActivationDoesNotRecordTarget() {
        let runningApp = FakeRunningApplication(activationResult: false)
        let world = FakeBrowserLauncherWorld(runningApplication: runningApp, hasOpenWindows: true)
        let stats = StatsManager(storage: BrowserLauncherStatsStorage())
        let coordinator = PickerCoordinator(
            browserLauncher: BrowserLauncher(dependencies: world.dependencies())
        )
        coordinator.statsManager = stats
        let state = AppState()
        state.isPickerVisible = true
        state.pickerInvocationSource = .serviceKey

        XCTAssertTrue(coordinator.select(
            PickerItem(app: makeApp(id: "com.test.Editor", urlSchemes: [])),
            state: state
        ))

        XCTAssertTrue(stats.dailyStats.isEmpty)
    }

    @MainActor
    func testLinkAndFileRoutingDoNotRecordManualTargets() throws {
        let stats = StatsManager(storage: BrowserLauncherStatsStorage())
        let coordinator = PickerCoordinator(
            browserLauncher: BrowserLauncher(dependencies: FakeBrowserLauncherWorld().dependencies())
        )
        coordinator.statsManager = stats
        let app = makeApp(id: "com.test.Editor", urlSchemes: [])

        for target in [
            try XCTUnwrap(URL(string: "https://example.com/path")),
            URL(fileURLWithPath: "/tmp/example.txt"),
        ] {
            let state = AppState()
            state.setPendingOpen(displayURLs: [target], launchURLs: [target])
            state.isPickerVisible = true
            state.pickerInvocationSource = .linkRouting

            XCTAssertTrue(coordinator.select(PickerItem(app: app), state: state))
        }

        XCTAssertEqual(stats.manualPickerSwitchCountTotal, 0)
        XCTAssertEqual(stats.totalOpenCount, 2)
    }

    @MainActor
    func testManualPickerUsageSnapshotRefreshesOnlyForNextSession() {
        let stats = StatsManager(storage: BrowserLauncherStatsStorage())
        stats.recordManualPickerSwitch(targetID: "com.test.editor")
        let coordinator = PickerCoordinator(
            browserLauncher: BrowserLauncher(dependencies: FakeBrowserLauncherWorld().dependencies())
        )
        coordinator.statsManager = stats
        let state = AppState()
        state.pickerInvocationSource = .serviceKey

        coordinator.showPicker(state: state)
        XCTAssertEqual(state.manualPickerTargetCounts, ["com.test.editor": 1])

        stats.recordManualPickerSwitch(targetID: "com.test.editor")
        XCTAssertEqual(state.manualPickerTargetCounts, ["com.test.editor": 1])

        coordinator.dismissPicker(state: state)
        state.pickerInvocationSource = .serviceKey
        coordinator.showPicker(state: state)
        XCTAssertEqual(state.manualPickerTargetCounts, ["com.test.editor": 2])
        coordinator.dismissPicker(state: state)
    }

    @MainActor
    func testManualAppSelectionDoesNotIncrementRoutingUsage() async {
        let runningApp = FakeRunningApplication()
        let world = FakeBrowserLauncherWorld(runningApplication: runningApp, hasOpenWindows: true)
        let coordinator = PickerCoordinator(
            browserLauncher: BrowserLauncher(dependencies: world.dependencies())
        )
        let state = AppState()
        state.isPickerVisible = true
        state.pickerInvocationSource = .serviceKey
        let originalCount = state.appUsage["com.test.Editor"]?.count

        XCTAssertTrue(coordinator.select(
            PickerItem(app: makeApp(id: "com.test.Editor", urlSchemes: [])),
            state: state
        ))
        try? await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(state.appUsage["com.test.Editor"]?.count, originalCount)
    }

    @MainActor
    func testPickerSelectionLaunchesChosenAppForLinksAndFiles() throws {
        let app = makeApp(id: "com.test.Editor", urlSchemes: [])
        let targets = [
            try XCTUnwrap(URL(string: "https://example.com/path")),
            URL(fileURLWithPath: "/tmp/example.txt"),
        ]

        for target in targets {
            let world = FakeBrowserLauncherWorld()
            let coordinator = PickerCoordinator(
                browserLauncher: BrowserLauncher(dependencies: world.dependencies())
            )
            let state = AppState()
            state.setPendingOpen(displayURLs: [target], launchURLs: [target])
            state.isPickerVisible = true

            XCTAssertTrue(coordinator.select(PickerItem(app: app), state: state, source: .pickerClick))
            XCTAssertEqual(world.openedURLs.count, 1)
            XCTAssertEqual(world.openedURLs[0].urls, [target])
            XCTAssertEqual(world.openedURLs[0].appURL, app.appURL)
        }
    }

    @MainActor
    func testReturnAndSpaceActivateFocusedManualPickerApp() throws {
        for (keyCode, characters) in [(UInt16(36), "\r"), (UInt16(49), " ")] {
            let runningApp = FakeRunningApplication()
            let world = FakeBrowserLauncherWorld(runningApplication: runningApp, hasOpenWindows: true)
            let coordinator = PickerCoordinator(
                browserLauncher: BrowserLauncher(dependencies: world.dependencies())
            )
            let state = AppState()
            let item = PickerItem(app: makeApp(id: "com.test.Editor", urlSchemes: []))
            state.isPickerVisible = true
            state.pickerInvocationSource = .serviceKey
            state.pickerItemsSnapshot = [item]
            let controller = PickerWindowController(appState: state, coordinator: coordinator)
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ))

            XCTAssertTrue(controller.handleKeyEvent(event))
            XCTAssertGreaterThan(runningApp.activateCount, 0)
            XCTAssertFalse(state.isPickerVisible)
        }
    }

    @MainActor
    func testManualActivationOfWindowlessRunningBrowserSendsReopenEventToExistingApp() {
        let app = FakeRunningApplication()
        let world = FakeBrowserLauncherWorld(runningApplication: app, hasOpenWindows: false)
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let browser = makeBrowser()

        launcher.activate(browser: browser)

        XCTAssertGreaterThanOrEqual(app.activateCount, 2)
        XCTAssertGreaterThanOrEqual(app.unhideCount, 2)
        XCTAssertTrue(world.openedURLs.isEmpty)
        XCTAssertEqual(world.reopenEvents, [browser.displayName])
        XCTAssertTrue(world.executableRuns.isEmpty)
    }

    @MainActor
    func testManualActivationOfWindowlessRunningNativeAppSendsReopenEventToExistingApp() {
        let runningApp = FakeRunningApplication()
        let world = FakeBrowserLauncherWorld(runningApplication: runningApp, hasOpenWindows: false)
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let app = makeApp(id: "com.test.Editor", urlSchemes: [])

        launcher.activate(app: app)

        XCTAssertEqual(world.reopenEvents, [app.displayName])
        XCTAssertGreaterThanOrEqual(runningApp.activateCount, 2)
        XCTAssertTrue(world.openedURLs.isEmpty)
        XCTAssertTrue(world.executableRuns.isEmpty)
    }

    @MainActor
    func testManualActivationRestoresMinimizedNativeAppWindows() {
        let runningApp = FakeRunningApplication()
        let world = FakeBrowserLauncherWorld(runningApplication: runningApp, hasOpenWindows: true)
        world.didActivateApplicationWindow = true
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let app = makeApp(id: "com.test.Editor", urlSchemes: [])

        launcher.activate(app: app)
        world.drainScheduledActions()

        XCTAssertEqual(world.activatedApplicationWindowAppIDs, [app.id])
        XCTAssertEqual(runningApp.activateCount, 0)
    }

    @MainActor
    func testManualActivationFocusesExistingNativeAppWindow() {
        let runningApp = FakeRunningApplication()
        let world = FakeBrowserLauncherWorld(runningApplication: runningApp, hasOpenWindows: true)
        world.didActivateApplicationWindow = true
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let app = makeApp(id: "com.test.Editor", urlSchemes: [])

        launcher.activate(app: app)
        world.drainScheduledActions()

        XCTAssertTrue(runningApp.isActive)
        XCTAssertEqual(runningApp.activateCount, 0)
    }

    @MainActor
    func testManualActivationWithProfileDoesNotLaunchProfileExecutable() {
        let app = FakeRunningApplication()
        let world = FakeBrowserLauncherWorld(runningApplication: app, hasOpenWindows: true)
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let profile = BrowserProfile(directoryName: "Default", displayName: "Work", email: nil)

        launcher.activate(browser: makeBrowser(profileType: .chromium), profile: profile)
        world.drainScheduledActions()

        XCTAssertGreaterThanOrEqual(app.activateCount, 1)
        XCTAssertTrue(world.executableRuns.isEmpty)
        XCTAssertTrue(world.openedURLs.isEmpty)
        XCTAssertTrue(world.reopenEvents.isEmpty)
    }

    @MainActor
    func testManualActivationOfStaleBrowserItemDoesNotLaunchApp() {
        let world = FakeBrowserLauncherWorld(runningApplication: nil, hasOpenWindows: nil)
        let launcher = BrowserLauncher(dependencies: world.dependencies())

        launcher.activate(browser: makeBrowser())
        world.drainScheduledActions()

        XCTAssertTrue(world.openedURLs.isEmpty)
        XCTAssertTrue(world.reopenEvents.isEmpty)
        XCTAssertTrue(world.executableRuns.isEmpty)
    }

    @MainActor
    func testManualActivationOfStaleNativeAppItemDoesNotLaunchApp() {
        let world = FakeBrowserLauncherWorld(runningApplication: nil, hasOpenWindows: nil)
        let launcher = BrowserLauncher(dependencies: world.dependencies())

        launcher.activate(app: makeApp(id: "com.test.Editor", urlSchemes: []))
        world.drainScheduledActions()

        XCTAssertTrue(world.openedURLs.isEmpty)
        XCTAssertTrue(world.reopenEvents.isEmpty)
        XCTAssertTrue(world.executableRuns.isEmpty)
    }

    @MainActor
    func testNormalURLOpenStillUsesWorkspaceURLLaunch() throws {
        let world = FakeBrowserLauncherWorld()
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let browser = makeBrowser()
        let url = try XCTUnwrap(URL(string: "https://example.com/path"))

        launcher.open(urls: [url], with: browser)

        XCTAssertEqual(world.openedURLs.count, 1)
        XCTAssertEqual(world.openedURLs[0].urls, [url])
        XCTAssertEqual(world.openedURLs[0].appURL, browser.appURL)
        XCTAssertTrue(world.openedURLs[0].activates)
        XCTAssertTrue(world.reopenEvents.isEmpty)
        XCTAssertTrue(world.executableRuns.isEmpty)
    }

    @MainActor
    func testNormalURLOpenReactivatesRunningBrowserWithoutWindows() throws {
        let app = FakeRunningApplication()
        let world = FakeBrowserLauncherWorld(runningApplication: app, hasOpenWindows: false)
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let browser = makeBrowser()
        let url = try XCTUnwrap(URL(string: "https://example.com/path"))

        launcher.open(urls: [url], with: browser)
        world.drainScheduledActions()

        XCTAssertEqual(world.openedURLs.count, 1)
        XCTAssertEqual(world.openedURLs[0].urls, [url])
        XCTAssertGreaterThanOrEqual(app.activateCount, 2)
        XCTAssertGreaterThanOrEqual(app.unhideCount, 2)
        XCTAssertTrue(world.reopenEvents.isEmpty)
        XCTAssertTrue(world.executableRuns.isEmpty)
    }

    @MainActor
    func testNormalURLOpenDoesNotManuallyReactivateBrowserWithOpenWindows() throws {
        let app = FakeRunningApplication()
        let world = FakeBrowserLauncherWorld(runningApplication: app, hasOpenWindows: true)
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let browser = makeBrowser()
        let url = try XCTUnwrap(URL(string: "https://example.com/path"))

        launcher.open(urls: [url], with: browser)
        world.drainScheduledActions()

        XCTAssertEqual(world.openedURLs.count, 1)
        XCTAssertEqual(app.activateCount, 0)
        XCTAssertEqual(app.unhideCount, 0)
        XCTAssertTrue(world.reopenEvents.isEmpty)
        XCTAssertTrue(world.executableRuns.isEmpty)
    }

    @MainActor
    func testProfileURLOpenStillUsesProfileExecutable() throws {
        let world = FakeBrowserLauncherWorld()
        let launcher = BrowserLauncher(dependencies: world.dependencies())
        let profile = BrowserProfile(directoryName: "Default", displayName: "Work", email: nil)
        let url = try XCTUnwrap(URL(string: "https://example.com/path"))

        launcher.open(urls: [url], with: makeBrowser(profileType: .chromium), profile: profile)

        XCTAssertEqual(world.executableRuns.count, 1)
        XCTAssertTrue(world.executableRuns[0].arguments.contains("--profile-directory=Default"))
        XCTAssertTrue(world.executableRuns[0].arguments.contains(url.absoluteString))
        XCTAssertTrue(world.openedURLs.isEmpty)
        XCTAssertTrue(world.reopenEvents.isEmpty)
    }

    @MainActor
    func testFallbackSchemeURLPreservesHostPathQueryAndFragment() throws {
        let url = try XCTUnwrap(URL(string: "https://www.figma.com/design/AbCd/Product?node-id=1-2#comment"))
        let fallback = try XCTUnwrap(BrowserLauncher.fallbackSchemeURL(for: url, scheme: "figma"))

        XCTAssertEqual(fallback.absoluteString, "figma://www.figma.com/design/AbCd/Product?node-id=1-2#comment")
    }

    @MainActor
    func testCandidateURLsTryAppSpecificConverterBeforeOriginalAndGenericScheme() throws {
        let url = try XCTUnwrap(URL(string: "https://www.figma.com/design/AbCd/Product?node-id=1-2"))
        let app = makeApp(id: "com.figma.Desktop", urlSchemes: ["figma"])

        let urls = BrowserLauncher.candidateURLs(for: url, app: app).map(\.absoluteString)

        XCTAssertEqual(urls, [
            "figma://design/AbCd/Product?node-id=1-2",
            "https://www.figma.com/design/AbCd/Product?node-id=1-2",
            "figma://www.figma.com/design/AbCd/Product?node-id=1-2",
        ])
    }

    @MainActor
    func testCandidateURLsForFilesOnlyTryTheOriginalFileURL() {
        let file = URL(fileURLWithPath: "/tmp/example.romanunknownformat")
        let app = makeApp(id: "com.microsoft.VSCode", urlSchemes: ["vscode"])
        let world = FakeBrowserLauncherWorld()
        let launcher = BrowserLauncher(dependencies: world.dependencies())

        launcher.open(url: file, with: app)

        XCTAssertEqual(BrowserLauncher.candidateURLs(for: file, app: app), [file])
        XCTAssertEqual(world.openedURLs.count, 1)
        XCTAssertEqual(world.openedURLs[0].urls, [file])
        XCTAssertEqual(world.openedURLs[0].appURL, app.appURL)
    }

    private func makeBrowser(profileType: ProfileType? = nil) -> InstalledBrowser {
        InstalledBrowser(
            id: "com.test.Browser",
            displayName: "Test Browser",
            appURL: URL(fileURLWithPath: "/Applications/Test Browser.app"),
            isVisible: true,
            sortOrder: 0,
            supportsPrivateMode: true,
            privateModeArgs: ["--private"],
            profileType: profileType
        )
    }

    private func makeApp(id: String, urlSchemes: [String]) -> InstalledApp {
        InstalledApp(
            id: id,
            displayName: id,
            appURL: URL(fileURLWithPath: "/Applications/\(id).app"),
            urlSchemes: urlSchemes,
            hostPatterns: [],
            isVisible: true,
            sortOrder: 0
        )
    }
}

private final class BrowserLauncherStatsStorage: StatsStoring {
    func save(_: [DailyStats]) {}
    func load() -> [DailyStats] { [] }
}

@MainActor
private final class FakeBrowserLauncherWorld {
    struct OpenedURLs {
        let urls: [URL]
        let appURL: URL
        let activates: Bool
    }

    struct ExecutableRun {
        let path: String
        let arguments: [String]
    }

    var runningApplication: FakeRunningApplication?
    var hasOpenWindows: Bool?
    var openedURLs: [OpenedURLs] = []
    var reopenEvents: [String] = []
    var executableRuns: [ExecutableRun] = []
    var openErrors: [Error?] = []
    var activatedApplicationWindowAppIDs: [String] = []
    var didActivateApplicationWindow = false
    var activateWindowTargetResult = false
    private var scheduledActions: [() -> Void] = []

    init(runningApplication: FakeRunningApplication? = nil, hasOpenWindows: Bool? = nil) {
        self.runningApplication = runningApplication
        self.hasOpenWindows = hasOpenWindows
    }

    func dependencies() -> BrowserLauncher.Dependencies {
        BrowserLauncher.Dependencies(
            activateWindowTarget: { [self] _ in activateWindowTargetResult },
            runningApplication: { [self] _ in runningApplication },
            hasOpenWindows: { [self] _ in hasOpenWindows },
            activateApplicationWindow: { [self] bundleID in
                activatedApplicationWindowAppIDs.append(bundleID)
                if didActivateApplicationWindow {
                    runningApplication?.isActive = true
                    return true
                }
                return hasOpenWindows == false ? false : nil
            },
            openURLs: { [self] urls, appURL, configuration, completion in
                openedURLs.append(OpenedURLs(urls: urls, appURL: appURL, activates: configuration.activates))
                let error = openErrors.isEmpty ? nil : openErrors.removeFirst()
                completion(nil, error)
            },
            sendReopenEvent: { [self] _, displayName in
                reopenEvents.append(displayName)
            },
            runExecutable: { [self] path, arguments in
                executableRuns.append(ExecutableRun(path: path, arguments: arguments))
            },
            schedule: { [self] _, action in
                scheduledActions.append(action)
            }
        )
    }

    func drainScheduledActions() {
        while !scheduledActions.isEmpty {
            let actions = scheduledActions
            scheduledActions = []
            actions.forEach { $0() }
        }
    }
}

private enum BrowserLauncherTestError: Error {
    case failed
}

@MainActor
private final class FakeRunningApplication: BrowserLauncherRunningApplication {
    var isActive: Bool
    var isTerminated: Bool
    let localizedName: String?
    let processIdentifier: pid_t
    private(set) var activateCount = 0
    private(set) var unhideCount = 0
    private(set) var lastActivationOptions: NSApplication.ActivationOptions?
    private let activationResult: Bool

    init(
        isActive: Bool = false,
        isTerminated: Bool = false,
        localizedName: String? = "Test Browser",
        processIdentifier: pid_t = 12345,
        activationResult: Bool = true
    ) {
        self.isActive = isActive
        self.isTerminated = isTerminated
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.activationResult = activationResult
    }

    @discardableResult
    func activate(options: NSApplication.ActivationOptions) -> Bool {
        activateCount += 1
        lastActivationOptions = options
        isActive = activationResult
        return activationResult
    }

    @discardableResult
    func unhide() -> Bool {
        unhideCount += 1
        return true
    }
}
