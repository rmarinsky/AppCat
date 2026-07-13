@testable import AppCat
import Foundation
import XCTest

final class AppConfigTests: XCTestCase {
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
