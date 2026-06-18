import SwiftUI

struct ProfilePopover: View {
    let browser: InstalledBrowser
    let onSelect: (BrowserProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Open with Profile"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)

            ForEach(Array(browser.profiles.filter(\.isVisible).enumerated()), id: \.element.id) { _, profile in
                Button {
                    onSelect(profile)
                } label: {
                    HStack(spacing: 8) {
                        ProfileAvatarBadge(
                            profile: profile,
                            size: 18,
                            borderWidth: profile.avatarPath == nil ? 0 : 1
                        )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.displayName)
                                .font(.system(size: 12))

                            if let email = profile.email {
                                Text(email)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.001)) // Invisible but clickable
                )
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 180)
    }
}
