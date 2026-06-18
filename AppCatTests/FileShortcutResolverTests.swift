@testable import AppCat
import XCTest

final class FileShortcutResolverTests: XCTestCase {
    func testWeblocResolvesTargetURL() throws {
        let shortcutURL = try makeTempFile(name: "link.webloc")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["URL": "https://example.com/path"],
            format: .xml,
            options: 0
        )
        try data.write(to: shortcutURL)

        XCTAssertEqual(FileShortcutResolver.resolve(shortcutURL).absoluteString, "https://example.com/path")
    }

    func testInternetShortcutResolvesTargetURL() throws {
        let shortcutURL = try makeTempFile(name: "link.url")
        try try XCTUnwrap("""
        [InternetShortcut]
        URL=https://github.com/rmarinsky/AppCat
        """.data(using: .utf8)?.write(to: shortcutURL))

        XCTAssertEqual(FileShortcutResolver.resolve(shortcutURL).absoluteString, "https://github.com/rmarinsky/AppCat")
    }

    func testInvalidShortcutFallsBackToOriginalFileURL() throws {
        let shortcutURL = try makeTempFile(name: "broken.url")
        try try XCTUnwrap("[InternetShortcut]\n".data(using: .utf8)?.write(to: shortcutURL))

        XCTAssertEqual(FileShortcutResolver.resolve(shortcutURL), shortcutURL)
    }

    func testPlainFileReturnsOriginalFileURL() throws {
        let fileURL = try makeTempFile(name: "index.html")
        try try XCTUnwrap("<html></html>".data(using: .utf8)?.write(to: fileURL))

        XCTAssertEqual(FileShortcutResolver.resolve(fileURL), fileURL)
    }

    private func makeTempFile(name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppCatTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent(name)
    }
}
