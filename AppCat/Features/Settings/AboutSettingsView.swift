import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                appCard

                sectionCaption("DEVELOPER")
                card {
                    valueRow(title: String(localized: "Made by"), value: "Roman Marinsky 🇺🇦")
                    divider
                    linkRow(
                        title: String(localized: "Website"),
                        value: "rmarinsky.com.ua",
                        systemImage: "globe",
                        url: "https://rmarinsky.com.ua"
                    )
                    divider
                    linkRow(
                        title: "GitHub",
                        value: "@rmarinsky",
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        url: "https://github.com/rmarinsky"
                    )
                    divider
                    linkRow(
                        title: "LinkedIn",
                        value: "in/rmarinsky",
                        systemImage: "briefcase",
                        url: "https://linkedin.com/in/rmarinsky"
                    )
                }

                card {
                    linkRow(
                        title: String(localized: "Support the Developer"),
                        value: String(localized: "Monobank subscription"),
                        systemImage: "heart.fill",
                        url: "https://base.monobank.ua/3yGFDUvCLJuNhm#subscriptions",
                        accent: true
                    )
                }

                sectionCaption("PROJECT")
                card {
                    linkRow(
                        title: String(localized: "Source Code"),
                        value: "rmarinsky/AppCat",
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        url: "https://github.com/rmarinsky/AppCat"
                    )
                    divider
                    valueRow(title: String(localized: "License"), value: "MIT", systemImage: "doc.text")
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
    }

    private var appCard: some View {
        card {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("AppCat")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(versionText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text("macOS app and browser picker")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 14)
            .frame(height: 76)
        }
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(String(localized: "Version")) \(version) (\(build))"
    }

    private func sectionCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.tertiary)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color("SurfaceCard"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color("HairlineBorder"))
            .frame(height: 1)
    }

    private func valueRow(title: String, value: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private func linkRow(
        title: String,
        value: String,
        systemImage: String,
        url: String,
        accent: Bool = false
    ) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent ? Color("BrandAccentDeep") : .secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent ? Color("BrandAccentDeep") : .primary)

                Spacer(minLength: 12)

                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
