import Foundation

enum ProfileType: String, Codable {
    case chromium
    case firefox
}

struct BrowserDefinition {
    let bundleID: String
    let displayName: String
    let privateModeArgs: [String]?
    let profileDataPath: String?
    let profileType: ProfileType?

    var supportsPrivateMode: Bool {
        privateModeArgs != nil
    }

    static let registry: [String: BrowserDefinition] = {
        let browsers: [BrowserDefinition] = [
            BrowserDefinition(
                bundleID: "com.apple.Safari",
                displayName: "Safari",
                privateModeArgs: nil,
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "com.google.Chrome",
                displayName: "Chrome",
                privateModeArgs: ["--incognito"],
                profileDataPath: "Google/Chrome",
                profileType: .chromium
            ),
            BrowserDefinition(
                bundleID: "com.google.Chrome.canary",
                displayName: "Chrome Canary",
                privateModeArgs: ["--incognito"],
                profileDataPath: "Google/Chrome Canary",
                profileType: .chromium
            ),
            BrowserDefinition(
                bundleID: "com.google.Chrome.for.Testing",
                displayName: "Google Chrome for Testing",
                privateModeArgs: ["--incognito"],
                profileDataPath: "Google/Chrome for Testing",
                profileType: .chromium
            ),
            BrowserDefinition(
                bundleID: "org.mozilla.firefox",
                displayName: "Firefox",
                privateModeArgs: ["-private-window"],
                profileDataPath: "Firefox",
                profileType: .firefox
            ),
            BrowserDefinition(
                bundleID: "org.mozilla.nightly",
                displayName: "Nightly",
                privateModeArgs: ["-private-window"],
                profileDataPath: "Firefox",
                profileType: .firefox
            ),
            BrowserDefinition(
                bundleID: "org.mozilla.firefoxdeveloperedition",
                displayName: "Firefox Developer Edition",
                privateModeArgs: ["-private-window"],
                profileDataPath: "Firefox",
                profileType: .firefox
            ),
            BrowserDefinition(
                bundleID: "company.thebrowser.Browser",
                displayName: "Arc",
                privateModeArgs: ["--incognito"],
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "com.microsoft.edgemac",
                displayName: "Edge",
                privateModeArgs: ["--inprivate"],
                profileDataPath: "Microsoft Edge",
                profileType: .chromium
            ),
            BrowserDefinition(
                bundleID: "com.brave.Browser",
                displayName: "Brave",
                privateModeArgs: ["--incognito"],
                profileDataPath: "BraveSoftware/Brave-Browser",
                profileType: .chromium
            ),
            BrowserDefinition(
                bundleID: "com.operasoftware.Opera",
                displayName: "Opera",
                privateModeArgs: ["--private"],
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "com.vivaldi.Vivaldi",
                displayName: "Vivaldi",
                privateModeArgs: ["--incognito"],
                profileDataPath: "Vivaldi",
                profileType: .chromium
            ),
            BrowserDefinition(
                bundleID: "org.chromium.Chromium",
                displayName: "Chromium",
                privateModeArgs: ["--incognito"],
                profileDataPath: "Chromium",
                profileType: .chromium
            ),
            BrowserDefinition(
                bundleID: "com.kagi.kagimacOS",
                displayName: "Orion",
                privateModeArgs: nil,
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "app.zen-browser.zen",
                displayName: "Zen",
                privateModeArgs: ["-private-window"],
                profileDataPath: "zen",
                profileType: .firefox
            ),
            BrowserDefinition(
                bundleID: "net.waterfox.waterfox",
                displayName: "Waterfox",
                privateModeArgs: ["-private-window"],
                profileDataPath: "Waterfox",
                profileType: .firefox
            ),
            BrowserDefinition(
                bundleID: "com.sigmaos.sigmaos.macos",
                displayName: "SigmaOS",
                privateModeArgs: nil,
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "com.nickvision.nickvision-browser",
                displayName: "GNOME Web",
                privateModeArgs: nil,
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "org.torproject.torbrowser",
                displayName: "Tor Browser",
                privateModeArgs: nil,
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "com.nickel-browser.nickel",
                displayName: "Nickel",
                privateModeArgs: nil,
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "com.naver.Whale",
                displayName: "Whale",
                privateModeArgs: ["--incognito"],
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "ru.yandex.desktop.yandex-browser",
                displayName: "Yandex",
                privateModeArgs: ["--incognito"],
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "com.aspect.browser",
                displayName: "Aspect",
                privateModeArgs: nil,
                profileDataPath: nil,
                profileType: nil
            ),
            BrowserDefinition(
                bundleID: "com.nickel.nickel",
                displayName: "Nickel",
                privateModeArgs: nil,
                profileDataPath: nil,
                profileType: nil
            ),
        ]
        var dict = [String: BrowserDefinition]()
        for browser in browsers {
            if dict[browser.bundleID] == nil {
                dict[browser.bundleID] = browser
            }
        }
        return dict
    }()
}
