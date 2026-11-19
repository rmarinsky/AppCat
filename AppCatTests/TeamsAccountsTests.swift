@testable import AppCat
import AppKit
import XCTest

final class TeamsAccountsTests: XCTestCase {
    private let mainTitle = "Chat | Team Velocity | Once For All Limited | Roman.Marinskyi@onceforall.com"
    private let callTitle = "Daily Velocity | Microsoft Teams"

    func testMainWindowTitleNamesTheActiveAccount() {
        XCTAssertEqual(TeamsAccounts.accountEmail(inWindowTitle: mainTitle), "Roman.Marinskyi@onceforall.com")
        XCTAssertEqual(TeamsAccounts.leadingSegment(ofWindowTitle: mainTitle), "Chat")
        XCTAssertNil(TeamsAccounts.accountEmail(inWindowTitle: callTitle))
        XCTAssertEqual(TeamsAccounts.shortName(ofEmail: "roman.marinskyi@intellias.com"), "intellias")
    }

    func testInactiveAccountsBecomeExtraTargets() {
        let main = AppWindowTarget(bundleID: TeamsAccounts.bundleID, title: mainTitle, index: 0)
        let targets = TeamsAccounts.addingAccountTargets(to: [main], accounts: [
            .init(email: "Roman.Marinskyi@onceforall.com", isActive: true),
            .init(email: "roman.marinskyi@intellias.com", isActive: false),
        ])

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[1].teamsAccount, "roman.marinskyi@intellias.com")
    }

    func testNoAccountTargetsWithoutAMainWindow() {
        let call = AppWindowTarget(bundleID: TeamsAccounts.bundleID, title: callTitle, index: 0)
        let targets = TeamsAccounts.addingAccountTargets(to: [call], accounts: [
            .init(email: "roman.marinskyi@intellias.com", isActive: false),
        ])
        XCTAssertEqual(targets, [call])
    }

    @MainActor
    func testSwitcherShowsCallAndBothAccountsWithCallRightAfterCurrentWindow() throws {
        let teams = makeApp(id: TeamsAccounts.bundleID, displayName: "Microsoft Teams")
        let editor = makeApp(id: "test.editor", displayName: "Editor")
        let notes = makeApp(id: "test.notes", displayName: "Notes")
        let teamsWindows = TeamsAccounts.addingAccountTargets(
            to: [
                AppWindowTarget(bundleID: teams.id, title: mainTitle, index: 0),
                AppWindowTarget(bundleID: teams.id, title: callTitle, index: 1),
            ],
            accounts: [.init(email: "roman.marinskyi@intellias.com", isActive: false)]
        )
        let ids = [teams.id, editor.id, notes.id]

        let items = PickerItem.items(
            for: nil,
            pickerBrowsers: [],
            allBrowsers: [],
            apps: [teams, editor, notes],
            appUsage: [:],
            runningBundleIDs: Set(ids),
            windowsByAppID: [
                teams.id: teamsWindows,
                editor.id: [AppWindowTarget(bundleID: editor.id, title: "Editor", index: 0)],
                notes.id: [AppWindowTarget(bundleID: notes.id, title: "Notes", index: 0)],
            ],
            windowActivationRanks: [
                WindowActivationKey.app(editor.id): 3,
                WindowActivationKey.app(notes.id): 2,
            ],
            regularBundleIDs: Set(ids)
        )

        XCTAssertEqual(items[0].app?.id, editor.id)
        XCTAssertEqual(items[1].teamsTile, .call)
        XCTAssertEqual(items[1].displayName, "Daily Velocity")

        let accountTiles = items.filter { if case .account = $0.teamsTile { true } else { false } }
        XCTAssertEqual(accountTiles.map(\.displayName), ["Chat", "Microsoft Teams"])
        XCTAssertEqual(accountTiles.map(\.switcherSubtitle), ["onceforall", "intellias"])
    }

    private func makeApp(id: String, displayName: String) -> InstalledApp {
        InstalledApp(
            id: id,
            displayName: displayName,
            appURL: URL(fileURLWithPath: "/Applications/\(displayName).app"),
            urlSchemes: [],
            hostPatterns: [],
            isVisible: true,
            sortOrder: 0,
            isSystemApp: false,
            icon: nil
        )
    }
}
