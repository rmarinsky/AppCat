import Foundation

enum HotkeyTarget: Hashable {
    case browser(id: String)
    case profile(browserId: String, directoryName: String)
    case app(id: String)
}
