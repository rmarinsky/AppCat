@testable import AppCat
import XCTest

final class BrowserLauncherTests: XCTestCase {
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
    private var scheduledActions: [() -> Void] = []

    init(runningApplication: FakeRunningApplication? = nil, hasOpenWindows: Bool? = nil) {
        self.runningApplication = runningApplication
        self.hasOpenWindows = hasOpenWindows
    }

    func dependencies() -> BrowserLauncher.Dependencies {
        BrowserLauncher.Dependencies(
            activateWindowTarget: { _ in false },
            runningApplication: { [weak self] _ in self?.runningApplication },
            hasOpenWindows: { [weak self] _ in self?.hasOpenWindows },
            openURLs: { [weak self] urls, appURL, configuration, completion in
                self?.openedURLs.append(OpenedURLs(urls: urls, appURL: appURL, activates: configuration.activates))
                completion(nil, nil)
            },
            sendReopenEvent: { [weak self] _, displayName in
                self?.reopenEvents.append(displayName)
            },
            runExecutable: { [weak self] path, arguments in
                self?.executableRuns.append(ExecutableRun(path: path, arguments: arguments))
            },
            schedule: { [weak self] _, action in
                self?.scheduledActions.append(action)
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

@MainActor
private final class FakeRunningApplication: BrowserLauncherRunningApplication {
    var isActive: Bool
    var isTerminated: Bool
    let localizedName: String?
    let processIdentifier: pid_t
    private(set) var activateCount = 0
    private(set) var unhideCount = 0
    private(set) var lastActivationOptions: NSApplication.ActivationOptions?

    init(isActive: Bool = false, isTerminated: Bool = false, localizedName: String? = "Test Browser", processIdentifier: pid_t = 12345) {
        self.isActive = isActive
        self.isTerminated = isTerminated
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
    }

    @discardableResult
    func activate(options: NSApplication.ActivationOptions) -> Bool {
        activateCount += 1
        lastActivationOptions = options
        isActive = true
        return true
    }

    @discardableResult
    func unhide() -> Bool {
        unhideCount += 1
        return true
    }
}
