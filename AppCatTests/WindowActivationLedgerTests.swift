@testable import AppCat
import AppKit
import XCTest

final class WindowActivationLedgerTests: XCTestCase {
    private func rank(_ ledger: WindowActivationLedger, bundleID: String, title: String? = nil) -> WindowActivationRank? {
        ledger.rank(
            windowKey: title.map { WindowActivationKey.window(bundleID: bundleID, title: $0) },
            appKey: WindowActivationKey.app(bundleID)
        )
    }

    func testLaterActivationOutranksEarlierOne() throws {
        var ledger = WindowActivationLedger()
        ledger.recordActivation(bundleID: "a")
        ledger.recordActivation(bundleID: "b")

        let a = try XCTUnwrap(rank(ledger, bundleID: "a"))
        let b = try XCTUnwrap(rank(ledger, bundleID: "b"))
        XCTAssertTrue(b > a)
        XCTAssertEqual(ledger.frontmostKey, WindowActivationKey.app("b"))
    }

    /// Title resolution is asynchronous, so a slow read for an older activation can land after a
    /// newer one. It must not drag a window the user has since returned to back down the order.
    func testLateWindowResolutionNeverLowersARank() {
        var ledger = WindowActivationLedger()
        let firstTick = ledger.recordActivation(bundleID: "editor")
        let secondTick = ledger.recordActivation(bundleID: "editor")

        ledger.attachFocusedWindow(bundleID: "editor", title: "Recent", tick: secondTick)
        ledger.attachFocusedWindow(bundleID: "editor", title: "Recent", tick: firstTick)

        let resolved = ledger.rank(
            windowKey: WindowActivationKey.window(bundleID: "editor", title: "Recent"),
            appKey: nil
        )
        XCTAssertEqual(resolved?.tick, secondTick)
    }

    func testResolvedWindowOutranksSiblingsSharingTheAppTick() throws {
        var ledger = WindowActivationLedger()
        let tick = ledger.recordActivation(bundleID: "editor")
        ledger.attachFocusedWindow(bundleID: "editor", title: "Second", tick: tick)

        let resolved = try XCTUnwrap(rank(ledger, bundleID: "editor", title: "Second"))
        let sibling = try XCTUnwrap(rank(ledger, bundleID: "editor", title: "First"))
        XCTAssertTrue(resolved.isExactWindow)
        XCTAssertFalse(sibling.isExactWindow, "An unresolved sibling only inherits the app tick")
        XCTAssertTrue(resolved > sibling)
    }

    /// Activating one window of an app must not drag its sibling windows to the front with it:
    /// the sibling stays where its own last activation put it.
    func testActivatingAWindowLeavesItsSiblingInPlace() throws {
        var ledger = WindowActivationLedger()
        ledger.attachFocusedWindow(bundleID: "chrome", title: "Work", tick: ledger.recordActivation(bundleID: "chrome"))
        let mailTick = ledger.recordActivation(bundleID: "mail")
        ledger.attachFocusedWindow(bundleID: "chrome", title: "Personal", tick: ledger.recordActivation(bundleID: "chrome"))

        let personal = try XCTUnwrap(rank(ledger, bundleID: "chrome", title: "Personal"))
        let work = try XCTUnwrap(rank(ledger, bundleID: "chrome", title: "Work"))
        let mail = try XCTUnwrap(rank(ledger, bundleID: "mail"))
        XCTAssertEqual(mail.tick, mailTick)
        XCTAssertTrue(personal > mail)
        XCTAssertTrue(mail > work, "The sibling window stays behind the app used after it")
    }

    func testCapacityTrimKeepsTheMostRecentEntries() {
        var ledger = WindowActivationLedger(capacity: 10, trimTarget: 6)
        for index in 0 ..< 30 {
            ledger.recordActivation(bundleID: "app.\(index)")
        }

        XCTAssertLessThanOrEqual(ledger.snapshot.count, 10)
        XCTAssertNotNil(ledger.rank(windowKey: nil, appKey: WindowActivationKey.app("app.29")))
        XCTAssertNil(ledger.rank(windowKey: nil, appKey: WindowActivationKey.app("app.0")))
    }

    func testForgetDropsAppAndWindowKeys() {
        var ledger = WindowActivationLedger()
        let tick = ledger.recordActivation(bundleID: "gone")
        ledger.attachFocusedWindow(bundleID: "gone", title: "Window", tick: tick)
        ledger.recordActivation(bundleID: "stays")

        ledger.forget(bundleID: "gone")

        XCTAssertNil(rank(ledger, bundleID: "gone", title: "Window"))
        XCTAssertNotNil(rank(ledger, bundleID: "stays"))
    }

    func testSeedOrdersFrontToBackAndIsOutrankedByAnyLiveActivation() throws {
        var ledger = WindowActivationLedger()
        ledger.seed(frontToBack: [
            AppWindowTarget(bundleID: "front", title: "Front", index: 0),
            AppWindowTarget(bundleID: "middle", title: "Middle", index: 0),
            AppWindowTarget(bundleID: "back", title: "Back", index: 0),
        ])

        let front = try XCTUnwrap(rank(ledger, bundleID: "front", title: "Front"))
        let back = try XCTUnwrap(rank(ledger, bundleID: "back", title: "Back"))
        XCTAssertTrue(front > back)
        XCTAssertEqual(ledger.frontmostKey, WindowActivationKey.window(bundleID: "front", title: "Front"))

        ledger.recordActivation(bundleID: "back")
        let promoted = try XCTUnwrap(rank(ledger, bundleID: "back"))
        XCTAssertTrue(promoted > front, "The first real activation must outrank the whole seed")
    }

    func testSeedNeverOverwritesALiveRecord() {
        var ledger = WindowActivationLedger()
        ledger.recordActivation(bundleID: "live")
        let before = ledger.snapshot[WindowActivationKey.app("live")]

        ledger.seed(frontToBack: [AppWindowTarget(bundleID: "live", title: "Whatever", index: 0)])

        XCTAssertEqual(ledger.snapshot[WindowActivationKey.app("live")], before)
    }

    /// A ledger entry and a rendered tile have to agree on identity, or a window's recency would
    /// never be found for the tile it belongs to.
    func testWindowKeyMatchesPickerItemDedupeKeyFolding() {
        let target = AppWindowTarget(bundleID: "test.app", title: "Café RÉSUMÉ", index: 3)
        let item = PickerItem(app: makeApp(id: "test.app"), windowTarget: target)

        XCTAssertEqual(
            WindowActivationKey.window(bundleID: target.bundleID, title: target.title),
            item.switcherDedupeKey
        )
        XCTAssertEqual(item.activationRankKeys.window, item.switcherDedupeKey)
    }

    func testAppLevelTilesRankByBundleIdentifier() {
        let item = PickerItem(app: makeApp(id: "test.app"))
        XCTAssertNil(item.activationRankKeys.window)
        XCTAssertEqual(item.activationRankKeys.app, WindowActivationKey.app("test.app"))
        XCTAssertTrue(item.matchesActivationRankKey(WindowActivationKey.app("test.app")))
    }

    private func makeApp(id: String) -> InstalledApp {
        InstalledApp(
            id: id,
            displayName: id,
            appURL: URL(fileURLWithPath: "/Applications/\(id).app"),
            urlSchemes: [],
            hostPatterns: [],
            isVisible: true,
            sortOrder: 0,
            isSystemApp: false,
            icon: nil
        )
    }

    /// Two windows of one app, switched between through the picker. Opening the picker again must
    /// still know which window is current, even though its just-in-time focused-window read has
    /// not come back yet when the session order is frozen.
    @MainActor
    func testPickerSwitchBetweenSiblingWindowsSurvivesPendingRefresh() {
        let releaseRead = DispatchSemaphore(value: 0)
        defer { releaseRead.signal() }
        let tracker = WindowActivationTracker(dependencies: .init(
            focusedWindowTitle: { _ in
                releaseRead.wait()
                return nil
            },
            frontToBackWindows: { [] }
        ))
        let newTab = WindowActivationKey.window(bundleID: "chrome", title: "New tab")
        let dropbox = WindowActivationKey.window(bundleID: "chrome", title: "Dropbox")

        tracker.recordWindowActivation(bundleID: "chrome", title: "New tab")
        tracker.recordWindowActivation(bundleID: "chrome", title: "Dropbox")
        tracker.recordFrontmostRefresh(bundleID: "chrome", processIdentifier: 1)
        let snapshot = tracker.sessionSnapshot()

        XCTAssertEqual(snapshot.frontmostKey, dropbox)
        let appTick = snapshot.ranks[WindowActivationKey.app("chrome")] ?? .max
        XCTAssertGreaterThanOrEqual(snapshot.ranks[dropbox] ?? .min, appTick)
        XCTAssertLessThan(snapshot.ranks[newTab] ?? .max, snapshot.ranks[dropbox] ?? .min)
    }

    /// Chrome activates but its focused window cannot be read. Its tiles must not fall below Mail,
    /// which was used before it, and its windows keep their order among themselves.
    func testUnreadableActivationPromotesTheAppsLatestWindow() throws {
        var ledger = WindowActivationLedger()
        ledger.attachFocusedWindow(bundleID: "chrome", title: "Work", tick: ledger.recordActivation(bundleID: "chrome"))
        ledger.attachFocusedWindow(bundleID: "chrome", title: "Personal", tick: ledger.recordActivation(bundleID: "chrome"))
        ledger.recordActivation(bundleID: "mail")
        ledger.promoteMostRecentWindow(bundleID: "chrome", tick: ledger.recordActivation(bundleID: "chrome"))

        let personal = try XCTUnwrap(rank(ledger, bundleID: "chrome", title: "Personal"))
        let work = try XCTUnwrap(rank(ledger, bundleID: "chrome", title: "Work"))
        let mail = try XCTUnwrap(rank(ledger, bundleID: "mail"))
        XCTAssertTrue(personal > mail)
        XCTAssertTrue(mail > work)
    }

    /// The frontmost refresh reads Personal, but Mail is activated before the read returns. The
    /// read still lands between Work and Mail instead of being dropped.
    @MainActor
    func testRefreshReadThatReturnsAfterAnotherActivationKeepsItsPlace() async {
        let releaseRead = DispatchSemaphore(value: 0)
        let tracker = WindowActivationTracker(dependencies: .init(
            focusedWindowTitle: { _ in
                releaseRead.wait()
                return "Personal"
            },
            frontToBackWindows: { [] }
        ))
        tracker.recordWindowActivation(bundleID: "chrome", title: "Work")
        tracker.recordFrontmostRefresh(bundleID: "chrome", processIdentifier: 1)
        tracker.recordWindowActivation(bundleID: "mail", title: "Inbox")
        releaseRead.signal()

        let personal = WindowActivationKey.window(bundleID: "chrome", title: "Personal")
        for _ in 0 ..< 200 where tracker.sessionSnapshot().ranks[personal] == nil {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let ranks = tracker.sessionSnapshot().ranks
        let work = WindowActivationKey.window(bundleID: "chrome", title: "Work")
        let inbox = WindowActivationKey.window(bundleID: "mail", title: "Inbox")
        XCTAssertNotNil(ranks[personal])
        XCTAssertGreaterThan(ranks[personal] ?? .min, ranks[work] ?? .max)
        XCTAssertLessThan(ranks[personal] ?? .max, ranks[inbox] ?? .min)
    }
}
