import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.updaterManager) private var updaterManager
    @State private var latestVersionText = "Перевірити"

    private let currentID: AboutProduct.IDValue = .appCat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                currentAppHero
                appGrid
                authorCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 26)
            .frame(maxWidth: 840, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
        .task {
            await loadLatestVersion()
        }
    }

    private var currentProduct: AboutProduct {
        products.first { $0.id == currentID } ?? products[0]
    }

    private var currentAppHero: some View {
        HStack(alignment: .center, spacing: 16) {
            ProductMark(product: currentProduct, size: 76)

            VStack(alignment: .leading, spacing: 5) {
                Text("Про апку")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(currentProduct.accentDeep)
                Text(currentProduct.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(currentProduct.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            updateCard
                .frame(width: 190)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(currentProduct.tintSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(currentProduct.tintBorder, lineWidth: 1)
        )
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Оновлення доступне")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(currentProduct.accentDeep)

            VStack(spacing: 4) {
                versionLine("Поточна", value: currentVersionText)
                versionLine("Найновіша", value: latestVersionText)
                versionLine("Перевірено", value: "сьогодні")
            }

            Button {
                updaterManager?.checkForUpdates()
            } label: {
                Label("Оновити зараз", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(currentProduct.accentDeep)
            .controlSize(.small)
            .disabled(updaterManager?.canCheckForUpdates == false)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.48))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(currentProduct.tintBorder, lineWidth: 1)
        )
    }

    private func versionLine(_ title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var appGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(products) { product in
                AppPromoCard(product: product, isCurrent: product.id == currentID)
            }
        }
    }

    private var authorCard: some View {
        card {
            HStack(alignment: .top, spacing: 14) {
                Text("RM")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(currentProduct.accentDeep)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color("SurfaceInset"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Автор")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(currentProduct.accentDeep)
                        Text("Roman Marinskyi")
                            .font(.system(size: 15, weight: .semibold))
                        Text("IT-підприємець і розробник macOS інструментів продуктивності. Розробляю Diduny, Papuga і AppCat - практичні утиліти для прискорення твоєї робочої рутини.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                        AuthorLinkRow(title: "Website", value: "rmarinsky.com.ua", icon: "globe", url: "https://rmarinsky.com.ua")
                        AuthorLinkRow(title: "GitHub", value: "@rmarinsky", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/rmarinsky")
                        AuthorLinkRow(title: "LinkedIn", value: "in/rmarinsky", icon: "briefcase", url: "https://linkedin.com/in/rmarinsky")
                        AuthorLinkRow(title: "YOY", value: "платформа для івентів", icon: "calendar", url: "https://yoy.fyi")
                        AuthorLinkRow(title: "Monobase", value: "підтримати розробку", icon: "heart.fill", url: "https://base.monobank.ua/3yGFDUvCLJuNhm#subscriptions")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
                    )
                }
            }
            .padding(16)
        }
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
    }

    private var currentVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func loadLatestVersion() async {
        await MainActor.run {
            latestVersionText = "Перевіряю"
        }

        guard let feed = Bundle.main.infoDictionary?["SUFeedURL"] as? String,
              let url = URL(string: feed)
        else {
            await MainActor.run { latestVersionText = "Немає URL" }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let xml = String(data: data, encoding: .utf8) ?? ""
            let parsed = Self.extractLatestVersion(from: xml) ?? "Немає даних"
            await MainActor.run {
                latestVersionText = parsed
            }
        } catch {
            await MainActor.run {
                latestVersionText = "Недоступно"
            }
        }
    }

    private static func extractLatestVersion(from xml: String) -> String? {
        for marker in ["sparkle:shortVersionString=\"", "sparkle:version=\""] {
            if let value = quotedValue(after: marker, in: xml) {
                return value
            }
        }
        for tag in ["sparkle:shortVersionString", "sparkle:version"] {
            if let value = taggedValue(tag, in: xml) {
                return value
            }
        }
        return nil
    }

    private static func quotedValue(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        let rest = text[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static func taggedValue(_ tag: String, in text: String) -> String? {
        guard let start = text.range(of: "<\(tag)>"),
              let end = text.range(of: "</\(tag)>", range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }
}

private struct AppPromoCard: View {
    let product: AboutProduct
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ProductMark(product: product, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(product.tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Text("Ви тут")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color("HairlineStrong"), lineWidth: 1)
                        )
                }
            }

            Text(product.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if isCurrent {
                    Text("Встановлено")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color("SurfaceInset"), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Link(destination: product.downloadURL) {
                        Text("Завантажити")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(product.accentDeep)
                    .controlSize(.small)
                }

                Link(destination: product.sourceURL) {
                    Text("GitHub")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(minHeight: 196, alignment: .topLeading)
        .background(Color("SurfaceCard"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }
}

private struct AuthorLinkRow: View {
    let title: String
    let value: String
    let icon: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color("BrandAccentDeep"))
                    .frame(width: 24, height: 24)
                    .background(Color("BrandTintSoft"), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(value)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(Color("SurfaceCard"))
        }
        .buttonStyle(.plain)
    }
}

private struct ProductMark: View {
    let product: AboutProduct
    let size: CGFloat

    var body: some View {
        ZStack {
            switch product.id {
            case .papuga:
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Color(nsColor: .secondaryLabelColor).opacity(0.72))
                    .frame(width: size * 0.78, height: size * 0.54)
                Image(systemName: "bird.fill")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white)
            default:
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(product.tintSoft)
                Image(systemName: product.systemImage)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(product.accentDeep)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }
}

private struct AboutProduct: Identifiable {
    enum IDValue: String {
        case diduny
        case papuga
        case appCat
    }

    let id: IDValue
    let name: String
    let tagline: String
    let description: String
    let systemImage: String
    let tintSoft: Color
    let tintBorder: Color
    let accentDeep: Color
    let downloadURL: URL
    let sourceURL: URL
}

private let products: [AboutProduct] = [
    AboutProduct(
        id: .diduny,
        name: "Diduny",
        tagline: "Диктування і транскрипція для macOS",
        description: "Натиснув клавішу, сказав думку, отримав чистий текст. Плюс записи зустрічей і Dynamic Notch feedback.",
        systemImage: "mic.fill",
        tintSoft: Color(red: 252.0 / 255.0, green: 237.0 / 255.0, blue: 241.0 / 255.0),
        tintBorder: Color(red: 231.0 / 255.0, green: 59.0 / 255.0, blue: 94.0 / 255.0).opacity(0.18),
        accentDeep: Color(red: 196.0 / 255.0, green: 42.0 / 255.0, blue: 77.0 / 255.0),
        downloadURL: URL(string: "https://github.com/rmarinsky/Diduny/releases/latest")!,
        sourceURL: URL(string: "https://github.com/rmarinsky/Diduny")!
    ),
    AboutProduct(
        id: .papuga,
        name: "Papuga",
        tagline: "Рятує текст, набраний не тією розкладкою",
        description: "Виділив текст, натиснув shortcut, отримав нормальну мову без ручного перенабору.",
        systemImage: "bird.fill",
        tintSoft: Color(red: 234.0 / 255.0, green: 247.0 / 255.0, blue: 240.0 / 255.0),
        tintBorder: Color(red: 31.0 / 255.0, green: 175.0 / 255.0, blue: 92.0 / 255.0).opacity(0.18),
        accentDeep: Color(red: 23.0 / 255.0, green: 140.0 / 255.0, blue: 74.0 / 255.0),
        downloadURL: URL(string: "https://github.com/rmarinsky/papuga/releases/latest")!,
        sourceURL: URL(string: "https://github.com/rmarinsky/papuga")!
    ),
    AboutProduct(
        id: .appCat,
        name: "AppCat",
        tagline: "Контроль над тим, куди відкриваються посилання",
        description: "Роутить URL, браузери, профілі й апки без копіпасту між Chrome, Safari, Slack і IDE.",
        systemImage: "cat.fill",
        tintSoft: Color("BrandTintSoft"),
        tintBorder: Color("BrandTintBorder"),
        accentDeep: Color("BrandAccentDeep"),
        downloadURL: URL(string: "https://github.com/rmarinsky/AppCat/releases/latest")!,
        sourceURL: URL(string: "https://github.com/rmarinsky/AppCat")!
    ),
]
