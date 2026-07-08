import SwiftUI

/// Overview screen — a 1:1 port of Figma node 197:716 (AppCat App — Overview).
/// Flat surfaces (SurfaceWindow/SurfaceCard), one tinted hero card, 4 metric cards,
/// a weekly bar chart, and a Suggested-rules / Recent split.
struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.statsManager) private var statsManager
    @Environment(\.suggestionsManager) private var suggestionsManager
    @Environment(\.urlRulesManager) private var urlRulesManager

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                metricRow
                chartCard
                bottomRow
                estimateFootnote
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    /// Shows the assumptions behind the "time saved" number, so it reads as an
    /// honest estimate rather than a magic figure.
    private var estimateFootnote: some View {
        Text(String(localized: "Estimate: ~7s per rule route, ~3s per picker hotkey, ~2s per picker click, +3s for profile routing, ~1s per manual app switch."))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    // MARK: - Hero

    private var heroCard: some View {
        let seconds = statsManager?.secondsSavedTotal ?? 0
        let hero = TimeSavedFormatter.hero(seconds: seconds)
        return ZStack(alignment: .topLeading) {
            // Trend (top-right) + route flow (bottom-right)
            VStack(alignment: .trailing, spacing: 0) {
                Spacer(minLength: 0)
                RouteFlowChip()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Color("BrandAccentDeep"))
                    .padding(.bottom, 6)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(hero.value)
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(hero.unit)
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .contentTransition(.numericText())
                .animation(.snappy, value: seconds)
                .padding(.bottom, 8)

                Text(subline)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("BrandTintSoft"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("BrandTintBorder"), lineWidth: 1)
        )
    }

    private var eyebrow: String {
        String(localized: "TIME SAVED · TOTAL")
    }

    private var subline: String {
        let count = statsManager?.totalOpenCount ?? 0
        let switches = statsManager?.manualPickerSwitchCountTotal ?? 0
        if switches > 0 {
            return "≈ \(count.formatted()) \(String(localized: "opens handled by AppCat")) · \(switches.formatted()) \(String(localized: "app switches"))"
        }
        return "≈ \(count.formatted()) \(String(localized: "opens handled by AppCat"))"
    }

    // MARK: - Metric row

    private var metricRow: some View {
        HStack(spacing: 16) {
            MetricCard(
                icon: "link",
                value: (statsManager?.totalOpenCount ?? 0).formatted(),
                label: String(localized: "Total opens")
            )
            MetricCard(
                icon: "scope",
                value: "\(statsManager?.autoRoutedPercent ?? 0)%",
                label: String(localized: "Opened by rules")
            )
            MetricCard(
                icon: "arrow.triangle.branch",
                value: "\(appState.urlRules.filter(\.isEnabled).count)",
                label: String(localized: "Active rules")
            )
            BrowserShareCard(history: appState.history)
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        let week = statsManager?.trailingWeekOpens() ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Opens over the last 7 days"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(String(localized: "by day"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            WeeklyBarsView(data: week)
                .padding(.top, 14)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }

    // MARK: - Bottom row

    private var bottomRow: some View {
        HStack(alignment: .top, spacing: 16) {
            SuggestedRulesCard(
                onSeeAll: { appState.mainWindowSection = .suggestions },
                onApply: applySuggestion,
                onDismiss: { suggestion in suggestionsManager?.dismiss(suggestion, state: appState) }
            )
            RecentCard(history: appState.history)
        }
    }

    private func applySuggestion(_ suggestion: RuleSuggestion) {
        guard let rule = suggestionsManager?.accept(suggestion, sortOrder: appState.urlRules.count) else { return }
        appState.urlRules.append(rule)
        urlRulesManager?.save(appState.urlRules)
        suggestionsManager?.dismiss(suggestion, state: appState)
    }
}

// MARK: - Metric card

private struct MetricCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color("BrandTintSoft"))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color("BrandAccentDeep"))
            }
            .padding(.bottom, 14)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }
}

// MARK: - Browser share card

private struct BrowserShareCard: View {
    let history: [HistoryEntry]

    private var share: (name: String, percent: Int) {
        let links = history.filter { $0.itemKind == .link }
        guard !links.isEmpty else { return (String(localized: "No data"), 0) }
        var counts: [String: Int] = [:]
        for entry in links {
            counts[entry.appName, default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return (String(localized: "No data"), 0) }
        return (top.key, Int(Double(top.value) / Double(links.count) * 100))
    }

    var body: some View {
        let (name, pct) = share
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color("BrandTintSoft"))
                        .frame(width: 20, height: 20)
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color("BrandAccentDeep"))
                }
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.bottom, 12)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color("BrandTintSoft")).frame(height: 4)
                    Capsule().fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(pct) / 100, height: 4)
                }
            }
            .frame(height: 4)

            Text("\(pct)% \(String(localized: "of links"))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }
}

// MARK: - Weekly bars

private struct WeeklyBarsView: View {
    let data: [(date: Date, count: Int, isFuture: Bool)]

    private let barZone: CGFloat = 72
    private let barWidth: CGFloat = 30

    private var maxCount: Int {
        max(1, data.map(\.count).max() ?? 1)
    }

    private var avg: Double {
        let past = data.filter { !$0.isFuture }
        guard !past.isEmpty else { return 0 }
        return Double(past.reduce(0) { $0 + $1.count }) / Double(past.count)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    private func weekday(_ date: Date) -> String {
        Self.weekdayFormatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                // Average dashed line
                if avg > 0 {
                    GeometryReader { geo in
                        let y = geo.size.height - barZone * CGFloat(avg / Double(maxCount))
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .overlay(alignment: .topTrailing) {
                            Text("\(String(localized: "avg")) \(Int(avg.rounded()))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .offset(y: max(0, y - 14))
                        }
                    }
                }

                // Baseline
                Rectangle()
                    .fill(Color("HairlineBorder"))
                    .frame(height: 1)

                // Bars
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, day in
                        bar(day)
                    }
                }
            }
            .frame(height: barZone + 16)

            // Day labels
            HStack(spacing: 0) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, day in
                    Text(weekday(day.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func bar(_ day: (date: Date, count: Int, isFuture: Bool)) -> some View {
        let isPeak = day.count == maxCount && day.count > 0
        let height = max(6, barZone * CGFloat(day.count) / CGFloat(maxCount))
        let linkUnit = day.count == 1 ? String(localized: "link") : String(localized: "links")
        VStack(spacing: 0) {
            if isPeak {
                Text("\(day.count) \(linkUnit)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color("BrandAccentDeep"))
                    .fixedSize()
                    .frame(height: 14)
            } else {
                Spacer().frame(height: 14)
            }
            Spacer(minLength: 0)
            if day.isFuture {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color("HairlineStrong"))
                    .frame(width: barWidth, height: 12)
            } else {
                UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                    .fill(Color.accentColor.opacity(isPeak ? 1.0 : 0.55 + 0.35 * Double(day.count) / Double(maxCount)))
                    .frame(width: barWidth, height: height)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Route flow chip

private struct RouteFlowChip: View {
    @Environment(AppState.self) private var appState

    private var route: (domain: String, browser: String, profile: String?)? {
        guard let last = appState.history.first(where: { $0.itemKind == .link }) else { return nil }
        return (last.domain, last.appName, last.profileName)
    }

    var body: some View {
        if let route {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    FaviconView(urlString: "https://\(route.domain)/", fallbackDomain: route.domain, size: 12)
                    Text(route.domain.isEmpty ? "example.com" : route.domain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(pillBackground)

                Text("→")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color("BrandAccentDeep"))

                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundStyle(Color("BrandAccentDeep"))
                    Text(route.profile.map { "\(route.browser) · \($0)" } ?? route.browser)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(pillBackground)
            }
        }
    }

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color("SurfaceCard"))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
            )
    }
}

// MARK: - Suggested rules card

private struct SuggestedRulesCard: View {
    @Environment(AppState.self) private var appState

    let onSeeAll: () -> Void
    let onApply: (RuleSuggestion) -> Void
    let onDismiss: (RuleSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "Suggested rules"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if !appState.suggestions.isEmpty {
                    Button(action: onSeeAll) {
                        Text("\(String(localized: "See all")) ›")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)

            if let suggestion = appState.suggestions.first {
                inner(suggestion)
                if appState.suggestions.count > 1 {
                    Button(action: onSeeAll) {
                        Text("+ \(appState.suggestions.count - 1) \(String(localized: "more suggestions")) ›")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }
            } else {
                Text(String(localized: "No suggestions yet — keep opening links."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }

    private func inner(_ suggestion: RuleSuggestion) -> some View {
        let pattern = suggestion.scope.displayHost + (suggestion.scope.pathSuffix.map { "/\($0)" } ?? "")
        let browser = browserDisplay(suggestion)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(pattern)  →  \(browser)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(String(localized: "AppCat noticed")): \(browserName(suggestion)) \(suggestion.occurrenceCount)× \(String(localized: "this week"))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 4)

            HStack(spacing: 8) {
                Button { onApply(suggestion) } label: {
                    Text(String(localized: "Apply"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 96, minHeight: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color("BrandAccentDeep"))
                        )
                }
                .buttonStyle(.plain)

                Button { onDismiss(suggestion) } label: {
                    Text(String(localized: "Dismiss"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 84, minHeight: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("BrandTintSoft"))
        )
    }

    private func browserName(_ suggestion: RuleSuggestion) -> String {
        appState.browsers.first(where: { $0.id == suggestion.browserID })?.displayName ?? suggestion.browserID
    }

    private func browserDisplay(_ suggestion: RuleSuggestion) -> String {
        let name = browserName(suggestion)
        if let dirName = suggestion.profileDirectoryName,
           let browser = appState.browsers.first(where: { $0.id == suggestion.browserID }),
           let profile = browser.profiles.first(where: { $0.directoryName == dirName })
        {
            return "\(name) · \(profile.displayName)"
        }
        return name
    }
}

// MARK: - Recent card

private struct RecentCard: View {
    let history: [HistoryEntry]

    private var recent: [HistoryEntry] {
        var seen = Set<String>()
        var unique: [HistoryEntry] = []
        for entry in history where entry.itemKind == .link {
            if seen.contains(entry.domain) { continue }
            seen.insert(entry.domain)
            unique.append(entry)
            if unique.count >= 4 { break }
        }
        return unique
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Recent"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 12)

            if recent.isEmpty {
                Text(String(localized: "Nothing opened yet."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(Color("HairlineBorder"))
                            .frame(height: 1)
                    }
                    row(entry)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }

    private func row(_ entry: HistoryEntry) -> some View {
        let target = entry.profileName.map { "\(entry.appName) · \($0)" } ?? entry.appName
        return HStack(spacing: 10) {
            FaviconView(urlString: entry.url, fallbackDomain: entry.domain, size: 16)
            Text(entry.domain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("→ \(target)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(relativeShort(entry.openedAt))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }

    private func relativeShort(_ date: Date) -> String {
        let secs = max(0, Date().timeIntervalSince(date))
        if secs < 60 { return "\(Int(secs))s" }
        if secs < 3600 { return "\(Int(secs / 60))m" }
        if secs < 86400 { return "\(Int(secs / 3600))h" }
        return "\(Int(secs / 86400))d"
    }
}
