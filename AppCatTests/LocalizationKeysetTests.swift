@testable import AppCat
import XCTest

final class LocalizationKeysetTests: XCTestCase {
    func testEnglishAndUkrainianLocalizableFilesHaveSameKeys() throws {
        let english = try localizableKeys(locale: "en")
        let ukrainian = try localizableKeys(locale: "uk")

        XCTAssertEqual(
            english,
            ukrainian,
            """
            Missing in en: \(ukrainian.subtracting(english).sorted())
            Missing in uk: \(english.subtracting(ukrainian).sorted())
            """
        )
    }

    private func localizableKeys(locale: String) throws -> Set<String> {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("AppCat")
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(locale).lproj")
            .appendingPathComponent("Localizable.strings")

        guard let strings = NSDictionary(contentsOf: url) as? [String: String] else {
            XCTFail("Could not parse \(url.path) as a strings dictionary")
            return []
        }
        return Set(strings.keys)
    }
}
