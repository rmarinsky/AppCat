@testable import AppCat
import XCTest

final class BrowserLauncherTests: XCTestCase {
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
        let file = URL(fileURLWithPath: "/tmp/example.md")
        let app = makeApp(id: "com.microsoft.VSCode", urlSchemes: ["vscode"])

        XCTAssertEqual(BrowserLauncher.candidateURLs(for: file, app: app), [file])
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
