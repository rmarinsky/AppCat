@testable import AppCat
import Foundation
import XCTest

final class AppConfigTests: XCTestCase {
    @MainActor
    func testOlderBackgroundAppRefreshCannotOverwriteNewerResult() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstStarted = expectation(description: "first detection started")
        let releaseFirst = DispatchSemaphore(value: 0)
        let oldApp = InstalledApp(
            id: "test.old",
            displayName: "Old",
            appURL: URL(fileURLWithPath: "/Applications/Old.app"),
            urlSchemes: [],
            hostPatterns: [],
            isVisible: true,
            sortOrder: 0
        )
        let newApp = InstalledApp(
            id: "test.new",
            displayName: "New",
            appURL: URL(fileURLWithPath: "/Applications/New.app"),
            urlSchemes: [],
            hostPatterns: [],
            isVisible: true,
            sortOrder: 0
        )
        let detections = AppDetectionSequence(
            firstStarted: firstStarted,
            releaseFirst: releaseFirst,
            oldResult: [oldApp],
            newResult: [newApp]
        )
        let storage = AppConfigStorage(fileURL: directory.appendingPathComponent("apps.json"))
        let manager = AppManager(configStorage: storage, detectApps: detections.next)
        let state = AppState()

        let olderRefresh = manager.refreshAppsInBackground(into: state)
        await fulfillment(of: [firstStarted])
        let newerRefresh = manager.refreshAppsInBackground(into: state)
        await newerRefresh.value
        releaseFirst.signal()
        await olderRefresh.value

        XCTAssertEqual(state.apps.map(\.id), ["test.new"])
    }

    @MainActor
    func testBrowserRefreshPreservesMalformedExistingConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("browsers.json")
        let malformed = Data("not valid JSON".utf8)
        try malformed.write(to: fileURL)

        let state = AppState()
        BrowserManager(configStorage: BrowserConfigStorage(fileURL: fileURL)).refreshBrowsers(into: state)

        XCTAssertEqual(try Data(contentsOf: fileURL), malformed)
    }

    @MainActor
    func testAppRefreshPreservesMalformedExistingConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("apps.json")
        let malformed = Data("not valid JSON".utf8)
        try malformed.write(to: fileURL)

        let state = AppState()
        AppManager(configStorage: AppConfigStorage(fileURL: fileURL), detectApps: { [] }).refreshApps(into: state)

        XCTAssertEqual(try Data(contentsOf: fileURL), malformed)
    }

    func testKnownUniversalEditorsKeepRegistryDefaults() {
        let editorIDs = [
            "com.sublimetext.4",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "dev.zed.Zed",
            "com.jetbrains.intellij",
            "com.jetbrains.WebStorm",
        ]

        for id in editorIDs {
            XCTAssertEqual(AppDefinition.registryByID[id]?.handlesAllFiles, true, id)
        }
    }

    func testLegacyUnknownTypeOptInMigratesToHandlesAllFiles() throws {
        let legacyJSON = """
        {
          "id": "test.editor.legacy",
          "displayName": "Legacy Editor",
          "isVisible": true,
          "sortOrder": 0,
          "opensUnknownTypes": true
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: legacyJSON)

        XCTAssertEqual(config.handlesAllFiles, true)
    }

    func testLegacyUnknownTypeOptOutDoesNotOverrideRegistryDefault() throws {
        let legacyJSON = """
        {
          "id": "test.editor.legacy",
          "displayName": "Legacy Editor",
          "isVisible": true,
          "sortOrder": 0,
          "opensUnknownTypes": false
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: legacyJSON)

        XCTAssertNil(config.handlesAllFiles)
    }

    func testMigratedConfigEncodesOnlyTheNewCapabilityKey() throws {
        let legacyJSON = """
        {
          "id": "test.editor.legacy",
          "displayName": "Legacy Editor",
          "isVisible": true,
          "sortOrder": 0,
          "opensUnknownTypes": true
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: legacyJSON)

        let encoded = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["handlesAllFiles"] as? Bool, true)
        XCTAssertNil(object["opensUnknownTypes"])
    }

    func testCapabilityMigrationPreservesRegistryDefaultsAndExplicitOverrides() {
        XCTAssertFalse(AppFileCapabilityPolicy.resolveHandlesAllFiles(
            savedValue: nil,
            registryDefault: false
        ))
        XCTAssertTrue(AppFileCapabilityPolicy.resolveHandlesAllFiles(
            savedValue: nil,
            registryDefault: true
        ))
        XCTAssertFalse(AppFileCapabilityPolicy.resolveHandlesAllFiles(
            savedValue: false,
            registryDefault: true
        ))
        XCTAssertTrue(AppFileCapabilityPolicy.resolveHandlesAllFiles(
            savedValue: true,
            registryDefault: false
        ))
    }
}

private final class AppDetectionSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var invocationCount = 0
    private let firstStarted: XCTestExpectation
    private let releaseFirst: DispatchSemaphore
    private let oldResult: [InstalledApp]
    private let newResult: [InstalledApp]

    init(
        firstStarted: XCTestExpectation,
        releaseFirst: DispatchSemaphore,
        oldResult: [InstalledApp],
        newResult: [InstalledApp]
    ) {
        self.firstStarted = firstStarted
        self.releaseFirst = releaseFirst
        self.oldResult = oldResult
        self.newResult = newResult
    }

    func next() -> [InstalledApp] {
        let invocation = lock.withLock {
            invocationCount += 1
            return invocationCount
        }
        guard invocation == 1 else { return newResult }
        firstStarted.fulfill()
        releaseFirst.wait()
        return oldResult
    }
}
