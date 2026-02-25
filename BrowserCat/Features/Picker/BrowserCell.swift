import SwiftUI

struct BrowserCell: View {
    let browser: InstalledBrowser
    let profile: BrowserProfile?
    let isFocused: Bool
    var compact: Bool = false

    init(browser: InstalledBrowser, isFocused: Bool, profile: BrowserProfile? = nil, compact: Bool = false) {
        self.browser = browser
        self.profile = profile
        self.isFocused = isFocused
        self.compact = compact
    }

    private var displayHotkey: Character? {
        profile?.hotkey ?? browser.hotkey
    }

    var body: some View {
        if compact {
            compactBody
        } else {
            normalBody
        }
    }

    private var compactBody: some View {
        let compactIconSize: CGFloat = 84
        let compactFallbackIconSize: CGFloat = 58
        let compactCellSize: CGFloat = 98

        return ZStack {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    ZStack(alignment: .bottomLeading) {
                        if let icon = browser.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: compactIconSize, height: compactIconSize)
                        } else {
                            Image(systemName: "globe")
                                .font(.system(size: compactFallbackIconSize))
                                .frame(width: compactIconSize, height: compactIconSize)
                        }

                        // Profile avatar badge
                        if let profile {
                            profileBadge(for: profile)
                                .offset(x: -3, y: 3)
                        }
                    }

                    // Hotkey keycap badge
                    if let hotkey = displayHotkey {
                        hotkeyKeycap(hotkey, compact: true)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(profile?.displayName ?? browser.displayName)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: compactIconSize + 2)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
            }
        }
        .frame(width: compactCellSize, height: compactCellSize)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }

    private var normalBody: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomLeading) {
                    if let icon = browser.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 40, height: 40)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 32))
                            .frame(width: 40, height: 40)
                    }

                    // Profile avatar badge
                    if let profile {
                        profileBadge(for: profile)
                            .offset(x: -4, y: 4)
                    }
                }

                // Hotkey badge
                if let hotkey = displayHotkey {
                    hotkeyKeycap(hotkey)
                        .offset(x: 4, y: -4)
                }
            }

            HStack(spacing: 2) {
                Text(profile?.displayName ?? browser.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if profile == nil && browser.profiles.contains(where: \.isVisible) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

        }
        .frame(width: 72, height: 78)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }

    private func profileBadge(for profile: BrowserProfile) -> some View {
        let initial = profile.displayName.first.map { String($0).uppercased() } ?? "?"
        return Text(initial)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(avatarColor(for: profile.displayName), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
    }

    private func avatarColor(for name: String) -> Color {
        .profileAvatar(for: name)
    }

    private func hotkeyKeycap(_ hotkey: Character, compact: Bool = false) -> some View {
        Text(String(hotkey).uppercased())
            .font(.system(size: compact ? 11 : 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.95))
            .padding(.horizontal, compact ? 4 : 3)
            .frame(height: compact ? 20 : 18)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.3), radius: 1.2, x: 0, y: 1)
    }
}

// MARK: - Shared profile avatar color

extension Color {
    static func profileAvatar(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}
