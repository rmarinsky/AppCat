@testable import AppCat
import XCTest

final class AppDefinitionTests: XCTestCase {
    func testFigmaConverterBuildsDesktopDeepLink() throws {
        let definition = try XCTUnwrap(AppDefinition.registryByID["com.figma.Desktop"])
        let url = try XCTUnwrap(URL(string: "https://www.figma.com/design/AbCd1234/Product?node-id=1-2&t=token#comment"))

        let deepLink = try XCTUnwrap(definition.convertURL?(url))

        XCTAssertEqual(deepLink.absoluteString, "figma://design/AbCd1234/Product?node-id=1-2&t=token#comment")
    }

    func testFigmaConverterSupportsLegacyFileLinks() throws {
        let definition = try XCTUnwrap(AppDefinition.registryByID["com.figma.Desktop"])
        let url = try XCTUnwrap(URL(string: "https://figma.com/file/AbCd1234/Product?type=design&node-id=1%3A2"))

        let deepLink = try XCTUnwrap(definition.convertURL?(url))

        XCTAssertEqual(deepLink.absoluteString, "figma://file/AbCd1234/Product?type=design&node-id=1%3A2")
    }

    func testFigmaConverterSupportsPrototypeLinks() throws {
        let definition = try XCTUnwrap(AppDefinition.registryByID["com.figma.Desktop"])
        let url = try XCTUnwrap(URL(string: "https://www.figma.com/proto/AbCd1234/Product?page-id=0%3A1&node-id=2-3"))

        let deepLink = try XCTUnwrap(definition.convertURL?(url))

        XCTAssertEqual(deepLink.absoluteString, "figma://proto/AbCd1234/Product?page-id=0%3A1&node-id=2-3")
    }

    func testFigmaBetaConverterUsesBetaScheme() throws {
        let definition = try XCTUnwrap(AppDefinition.registryByID["com.figma.Desktop.beta"])
        let url = try XCTUnwrap(URL(string: "https://www.figma.com/design/AbCd1234/Product"))

        let deepLink = try XCTUnwrap(definition.convertURL?(url))

        XCTAssertEqual(deepLink.absoluteString, "figma-beta://design/AbCd1234/Product")
    }

    func testFigmaConverterIgnoresNonFigmaLinks() throws {
        let definition = try XCTUnwrap(AppDefinition.registryByID["com.figma.Desktop"])
        let url = try XCTUnwrap(URL(string: "https://example.com/design/AbCd1234/Product"))

        XCTAssertNil(definition.convertURL?(url))
    }
}
