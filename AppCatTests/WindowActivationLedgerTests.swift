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

    /// When a resolution fails, the app tick moves on without its window. Preferring the window key
    /// unconditionally would then sort unresolved siblings *above* the resolved window; taking the
    /// newer of the two ticks degrades honestly to "somewhere in this app" instead.
    func testStaleWindowTickDoesNotSinkBelowItsOwnAppTick() throws {
        var ledger = WindowActivationLedger()
        let firstTick = ledger.recordActivation(bundleID: "editor")
        ledger.attachFocusedWindow(bundleID: "editor", title: "Resolved", tick: firstTick)
        ledger.recordActivation(bundleID: "editor") // resolution failed: no window attached

        let resolved = try XCTUnwrap(rank(ledger, bundleID: "editor", title: "Resolved"))
        let sibling = try XCTUnwrap(rank(ledger, bundleID: "editor", title: "Other"))
        XCTAssertEqual(resolved.tick, sibling.tick)
        XCTAssertFalse(resolved > sibling)
        XCTAssertFalse(sibling > resolved)
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
}
