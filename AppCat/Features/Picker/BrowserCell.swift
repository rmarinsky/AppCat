import SwiftUI

struct BrowserCell: View {
    let browser: InstalledBrowser
    let profile: BrowserProfile?
    let title: String
    let subtitle: String?
    let isFocused: Bool
    let shortcut: PickerShortcut?
    let showsHotkey: Bool
    let showsProfileMenuIndicator: Bool
    var compact: Bool = false
    var style: PickerPresentationStyle = .routing
    var scale: CGFloat = 1

    init(
        browser: InstalledBrowser,
        title: String? = nil,
        subtitle: String? = nil,
        isFocused: Bool,
        profile: BrowserProfile? = nil,
        shortcut: PickerShortcut? = nil,
        showsHotkey: Bool = true,
        showsProfileMenuIndicator: Bool = true,
        compact: Bool = false,
        style: PickerPresentationStyle = .routing,
        scale: CGFloat = 1
    ) {
        self.browser = browser
        self.profile = profile
        self.title = title ?? profile.map { "\(browser.displayName) - \($0.displayName)" } ?? browser.displayName
        self.subtitle = subtitle
        self.isFocused = isFocused
        self.shortcut = shortcut
        self.showsHotkey = showsHotkey
        self.showsProfileMenuIndicator = showsProfileMenuIndicator
        self.compact = compact
        self.style = style
        self.scale = scale
    }

    private var displayHotkey: Character? {
        guard showsHotkey else { return nil }
        return profile?.hotkey ?? browser.hotkey
    }

    private var displayTitle: String {
        title
    }

    private var showsProfileMenuChevron: Bool {
        showsProfileMenuIndicator && profile == nil && browser.profiles.contains(where: \.isVisible)
    }

    var body: some View {
        if compact {
            compactBody
        } else {
            normalBody
        }
    }

    private var compactBody: some View {
        let compactIconSize = PickerMetrics.iconSize(scale: scale)
        let compactIconChromeSize = PickerMetrics.iconChromeSize(scale: scale)
        let compactFallbackIconSize = PickerMetrics.fallbackIconSize(scale: scale)
        let compactCellWidth = PickerMetrics.itemWidth(scale: scale)
        let compactCellHeight = PickerMetrics.itemHeight(scale: scale)
        let focusCornerRadius = PickerMetrics.focusCornerRadius(scale: scale)
        let hotkey = displayHotkey
        let showsSecondaryRow = shortcut != nil || subtitle?.isEmpty == false || hotkey != nil

        return VStack(spacing: 4 * scale) {
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

                if let profile {
                    ProfileAvatarBadge(
                        profile: profile,
                        size: PickerMetrics.profileBadgeSize(scale: scale),
                        borderWidth: PickerMetrics.profileBadgeBorderWidth(scale: scale)
                    )
                    .offset(x: 4 * scale, y: -4 * scale)
                }
            }
            .frame(width: compactIconSize, height: compactIconSize)
            .frame(width: compactIconChromeSize, height: compactIconChromeSize)
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: focusCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: focusCornerRadius, style: .continuous)
                        .fill(Color("BrandAccentDeep").opacity(0.18))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: focusCornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color("BrandAccentDeep") : Color.clear,
                        lineWidth: PickerMetrics.focusStrokeWidth(scale: scale)
                    )
            )
            .shadow(
                color: isFocused ? Color("BrandAccentDeep").opacity(0.24) : .clear,
                radius: 12 * scale,
                y: 5 * scale
            )

            HStack(spacing: 3 * scale) {
                Text(displayTitle)
                    .font(.system(size: PickerMetrics.titleFontSize(scale: scale), weight: .medium))
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)

                if showsProfileMenuChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: compactCellWidth, height: PickerMetrics.titleHeight(scale: scale), alignment: .center)

            if showsSecondaryRow {
                HStack(spacing: 4 * scale) {
                    if let shortcut {
                        SelectionKeycapView(key: shortcut.key, compact: true, inline: true, scale: scale)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: PickerMetrics.subtitleFontSize(scale: scale), weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .truncationMode(.tail)
                    }
                    if let hotkey {
                        HotkeyKeycapView(hotkey: hotkey, compact: true, scale: scale)
                    }
                }
                .frame(width: compactCellWidth, height: PickerMetrics.subtitleHeight(scale: scale), alignment: .center)
            }
        }
        .frame(width: compactCellWidth, height: compactCellHeight)
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

                    if let profile {
                        ProfileAvatarBadge(profile: profile)
                            .offset(x: 2, y: -2)
                    }
                }

                // Hotkey badge
                if let hotkey = displayHotkey {
                    HotkeyKeycapView(hotkey: hotkey)
                        .offset(x: 4, y: -4)
                }
            }

            HStack(spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if showsProfileMenuChevron {
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
        .overlay(alignment: .topLeading) {
            if let shortcut {
                SelectionKeycapView(key: shortcut.key)
                    .offset(x: -8, y: -8)
                    .zIndex(2)
            }
        }
        .contentShape(Rectangle())
    }
}

struct HotkeyKeycapView: View {
    let hotkey: Character
    var compact: Bool = false
    var scale: CGFloat = 1

    var body: some View {
        Text(String(hotkey).uppercased())
            .font(.system(size: (compact ? 10 : 10) * scale, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.95))
            .padding(.horizontal, (compact ? 3 : 3) * scale)
            .frame(height: (compact ? 18 : 18) * scale)
            .background(
                RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                    .fill(Color("BrandAccentDeep"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.7 * scale)
            )
            .shadow(color: .black.opacity(0.3), radius: 1.2 * scale, x: 0, y: 1 * scale)
    }
}

struct SelectionKeycapView: View {
    let key: Character
    var compact: Bool = false
    var inline: Bool = false
    var scale: CGFloat = 1

    private var size: CGFloat {
        let base: CGFloat
        if inline {
            base = 16
        } else {
            base = compact ? 22 : 18
        }
        return base * scale
    }

    private var fontSize: CGFloat {
        let base: CGFloat
        if inline {
            base = 9
        } else {
            base = compact ? 11 : 9
        }
        return base * scale
    }

    private var cornerRadius: CGFloat {
        let base: CGFloat
        if inline {
            base = 5
        } else {
            base = compact ? 6 : 5
        }
        return base * scale
    }

    var body: some View {
        Text(String(key).uppercased())
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(inline ? 0.58 : 0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(inline ? 0.22 : 0.35), lineWidth: 0.7 * scale)
            )
            .shadow(
                color: .black.opacity(inline ? 0.18 : 0.35),
                radius: (inline ? 0.8 : 1.2) * scale,
                x: 0,
                y: 1 * scale
            )
    }
}

// MARK: - Shared profile avatar color

extension Color {
    static func profileAvatar(for name: String) -> Color {
        let colors: [Color] = [.orange, .red, .green, .pink, .teal, .mint, .brown]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

struct ProfileAvatarBadge: View {
    let profile: BrowserProfile
    var size: CGFloat = 16
    var borderWidth: CGFloat = 1.5

    /// Avatar files are immutable for a given path during a picker session, so decode once and
    /// reuse. Without this, `NSImage(contentsOfFile:)` re-read + re-decoded the file from disk on
    /// the main thread on every cell `body` evaluation (every focus/hover change).
    private static let avatarCache = NSCache<NSString, NSImage>()

    private var fallbackInitial: String {
        profile.displayName.first.map { String($0).uppercased() } ?? "?"
    }

    private var avatarImage: NSImage? {
        guard let avatarPath = profile.avatarPath else { return nil }
        let key = avatarPath as NSString
        if let cached = Self.avatarCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOfFile: avatarPath) else { return nil }
        Self.avatarCache.setObject(image, forKey: key)
        return image
    }

    var body: some View {
        Group {
            if let avatarImage {
                Image(nsImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(fallbackInitial)
                    .font(.system(size: max(7, size * 0.44), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color.profileAvatar(for: profile.displayName))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: borderWidth))
    }
}
