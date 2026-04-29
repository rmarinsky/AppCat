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
    }
}
