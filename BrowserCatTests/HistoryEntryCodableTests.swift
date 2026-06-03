import XCTest
@testable import BrowserCat

final class HistoryEntryCodableTests: XCTestCase {
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func testRoundTripWithIDs() throws {
        let original = HistoryEntry(
            url: "https://example.com/foo",
            domain: "example.com",
            title: "Example",
            appName: "Chrome",
            profileName: "Default",
            openedAt: Date(timeIntervalSince1970: 1_700_000_000),
            browserID: "com.google.Chrome",
            profileDirectoryName: "Default",
            targetType: .browser
        )
        let data = try encoder().encode(original)
        let decoded = try decoder().decode(HistoryEntry.self, from: data)
        XCTAssertEqual(decoded.url, original.url)
        XCTAssertEqual(decoded.browserID, "com.google.Chrome")
        XCTAssertEqual(decoded.profileDirectoryName, "Default")
        XCTAssertEqual(decoded.targetType, .browser)
        XCTAssertEqual(decoded.itemKind, .link)
    }

    func testRoundTripWithNilIDs() throws {
        let original = HistoryEntry(
            url: "https://example.com/",
            domain: "example.com",
            title: nil,
            appName: "Chrome",
            profileName: nil
        )
        let data = try encoder().encode(original)
        let decoded = try decoder().decode(HistoryEntry.self, from: data)
        XCTAssertNil(decoded.browserID)
        XCTAssertNil(decoded.profileDirectoryName)
        XCTAssertNil(decoded.targetType)
        XCTAssertEqual(decoded.itemKind, .link)
    }

    func testRoundTripWithFileMetadata() throws {
        let original = HistoryEntry(
            url: "file:///Users/roman/project/.env.local",
            domain: ".env.local",
            title: nil,
            appName: "VS Code",
            profileName: nil,
            openedAt: Date(timeIntervalSince1970: 1_700_000_000),
            browserID: "com.microsoft.VSCode",
            profileDirectoryName: nil,
            targetType: .app,
            itemKind: .file,
            fileName: ".env.local",
            fileExtension: "local",
            fileFormat: ".env.local",
            contentTypeIdentifier: "ua.com.rmarinsky.browsercat.env-config"
        )
        let data = try encoder().encode(original)
        let decoded = try decoder().decode(HistoryEntry.self, from: data)
        XCTAssertEqual(decoded.itemKind, .file)
        XCTAssertEqual(decoded.fileName, ".env.local")
        XCTAssertEqual(decoded.fileExtension, "local")
        XCTAssertEqual(decoded.fileFormat, ".env.local")
        XCTAssertEqual(decoded.contentTypeIdentifier, "ua.com.rmarinsky.browsercat.env-config")
    }

    func testDecodesLegacyFormatWithoutIDs() throws {
        // Legacy entry shape (pre-feature) — verify backward compat
        let legacyJSON = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "url": "https://example.com/",
            "domain": "example.com",
            "title": "Old entry",
            "appName": "Safari",
            "profileName": null,
            "openedAt": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded = try decoder().decode(HistoryEntry.self, from: legacyJSON)
        XCTAssertEqual(decoded.url, "https://example.com/")
        XCTAssertEqual(decoded.appName, "Safari")
        XCTAssertNil(decoded.browserID, "Legacy entries must decode with browserID = nil")
        XCTAssertNil(decoded.profileDirectoryName)
        XCTAssertNil(decoded.targetType)
        XCTAssertEqual(decoded.itemKind, .link)
    }

    func testDecodesLegacyFileURLAsFileKind() throws {
        let legacyJSON = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "url": "file:///Users/roman/project/Dockerfile",
            "domain": "Dockerfile",
            "title": null,
            "appName": "Sublime Text",
            "profileName": null,
            "openedAt": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded = try decoder().decode(HistoryEntry.self, from: legacyJSON)
        XCTAssertEqual(decoded.itemKind, .file)
        XCTAssertNil(decoded.fileFormat)
    }
}
