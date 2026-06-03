import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.statsManager) private var statsManager
    @Environment(\.openSettings) private var openSettings
    var onReopenURL: (String) -> Void
    var onCheckForUpdates: () -> Void

    private var recentEntries: [HistoryEntry] {
        let seen = NSMutableOrderedSet()
        var unique: [HistoryEntry] = []
        for entry in appState.history {
            if seen.contains(entry.url) { continue }
            seen.add(entry.url)
            unique.append(entry)
            if unique.count >= appState.recentLinksCount { break }
        }
        return unique
    }

    private var todayEntries: [HistoryEntry] {
        let calendar = Calendar.current
        return appState.history.filter { calendar.isDateInToday($0.openedAt) }
    }

    private var statsTeaserText: String? {
        guard let stats = statsManager else { return nil }
        let week = stats.secondsSavedThisWeek
        if week >= 60 {
            return "\(TimeSavedFormatter.teaser(seconds: week)) \(String(localized: "saved this week"))"
        }
        let total = stats.secondsSavedTotal
        if total >= 60 {
            return "\(TimeSavedFormatter.teaser(seconds: total)) \(String(localized: "saved in total"))"
        }
        return nil
    }

    var body: some View {
        Group {
            if let teaser = statsTeaserText {
                Button {
                    openSettings()
                } label: {
                    Label(teaser, systemImage: "clock.badge.checkmark")
                }
                Divider()
            }

            if recentEntries.isEmpty {
                Text("No recent items")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentEntries) { entry in
                    Button {
                        onReopenURL(entry.url)
                    } label: {
                        Label(
                            "\(timeText(entry.openedAt)) · \(shortPreview(entry))",
                            systemImage: iconForEntry(entry)
                        )
                    }
                }
            }

            Divider()

            Menu("History") {
                if todayEntries.isEmpty {
                    Text("No items today")
                } else {
                    ForEach(todayEntries) { entry in
                        Button {
                            onReopenURL(entry.url)
                        } label: {
                            Label(
                                "\(timeText(entry.openedAt)) · \(shortPreview(entry)) — \(entry.appName)",
                                systemImage: iconForEntry(entry)
                            )
                        }
                    }
                }

                Divider()

                Button {
                    openSettings()
                } label: {
                    Text("Open History...")
                }
            }

            Divider()

            Button("Check for Updates...") {
                onCheckForUpdates()
            }

            Button {
                openSettings()
            } label: {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit BrowserCat") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("Q", modifiers: .command)
        }
        .environment(\.locale, appState.appLanguage.locale)
    }

    private func shortenURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        let host = url.host() ?? urlString
        if host.count > 30 {
            return String(host.prefix(27)) + "..."
        }
        return host
    }

    private func shortPreview(_ entry: HistoryEntry) -> String {
        let value: String?
        switch entry.itemKind {
        case .link:
            value = normalized(entry.title)
                ?? normalized(entry.domain)
                ?? normalized(shortenURL(entry.url))
        case .file:
            value = normalized(entry.fileName)
                ?? normalized(entry.fileFormat)
                ?? normalized(URL(string: entry.url)?.lastPathComponent)
        }
        let fallback = entry.itemKind == .file ? String(localized: "No file") : String(localized: "No URL")
        let displayValue = value ?? fallback
        return truncate(displayValue, maxLength: 54)
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength - 1)) + "…"
    }

    private static let domainIcons: [(pattern: String, icon: String)] = [
        ("github", "chevron.left.forwardslash.chevron.right"),
        ("gitlab", "chevron.left.forwardslash.chevron.right"),
        ("bitbucket", "chevron.left.forwardslash.chevron.right"),
        ("linkedin", "briefcase"),
        ("google", "magnifyingglass"),
        ("youtube", "play.rectangle"),
        ("slack", "number"),
        ("discord", "bubble.left.and.bubble.right"),
        ("teams.microsoft", "person.3"),
        ("zoom", "video"),
        ("figma", "paintbrush"),
        ("notion", "doc.text"),
        ("spotify", "music.note"),
        ("telegram", "paperplane"),
        ("t.me", "paperplane"),
        ("whatsapp", "phone.bubble"),
        ("stackoverflow", "questionmark.circle"),
        ("reddit", "text.bubble"),
        ("medium", "book"),
        ("twitter", "at"),
        ("x.com", "at"),
        ("jira", "checklist"),
        ("confluence", "doc.richtext"),
        ("linear", "circle.dotted"),
        ("miro", "rectangle.on.rectangle"),
        ("loom", "video.bubble"),
        ("mono", "banknote"),
        ("apple", "apple.logo"),
    ]

    private func iconForEntry(_ entry: HistoryEntry) -> String {
        guard entry.itemKind == .link else { return "doc" }
        return iconForURL(entry.url)
    }

    private func iconForURL(_ urlString: String) -> String {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return "globe" }
        for entry in Self.domainIcons {
            if host.contains(entry.pattern) { return entry.icon }
        }
        return "globe"
    }
}
