import SwiftUI

struct SuggestionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.suggestionsManager) private var suggestionsManager
    @Environment(\.urlRulesManager) private var urlRulesManager

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("AppCat spotted these routing patterns this week. Apply one to turn it into an automatic rule.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.bottom, 22)

                    if appState.suggestions.isEmpty {
                        emptyPanel
                    } else {
                        VStack(spacing: 16) {
                            ForEach(appState.suggestions) { suggestion in
                                SuggestionCard(
                                    suggestion: suggestion,
                                    onApply: { apply(suggestion) },
                                    onDismiss: { suggestionsManager?.dismiss(suggestion, state: appState) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
    }

    private var emptyPanel: some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
            Text(String(localized: "No Suggestions"))
                .font(.system(size: 13, weight: .semibold))
            Text(String(localized: "Open some links and AppCat will suggest rules based on your browsing habits."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }

    private func apply(_ suggestion: RuleSuggestion) {
        guard let rule = suggestionsManager?.accept(suggestion, sortOrder: appState.urlRules.count) else { return }
        appState.urlRules.append(rule)
        urlRulesManager?.save(appState.urlRules)
        suggestionsManager?.dismiss(suggestion, state: appState)
    }
}

// MARK: - Suggestion Card

private struct SuggestionCard: View {
    @Environment(AppState.self) private var appState

    let suggestion: RuleSuggestion
    let onApply: () -> Void
    let onDismiss: () -> Void

    private var scopeLabel: String {
        suggestion.scope.displayHost + (suggestion.scope.pathSuffix.map { "/\($0)" } ?? "")
    }

    private var browserDisplay: String {
        let name = appState.browsers.first(where: { $0.id == suggestion.browserID })?.displayName
            ?? suggestion.browserID
        if let dirName = suggestion.profileDirectoryName,
           let browser = appState.browsers.first(where: { $0.id == suggestion.browserID }),
           let profile = browser.profiles.first(where: { $0.directoryName == dirName })
        {
            return "\(name) · \(profile.displayName)"
        }
        return name
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color("BrandTintSoft"))
                    .frame(width: 36, height: 36)
                FaviconView(
                    urlString: "https://\(suggestion.scope.displayHost)/",
                    fallbackDomain: suggestion.scope.displayHost,
                    size: 20
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("\(scopeLabel)  →  \(browserDisplay)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detailText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SuggestionButton(title: String(localized: "Dismiss"), kind: .secondary, action: onDismiss)
            SuggestionButton(title: String(localized: "Apply"), kind: .primary, action: onApply)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }

    private var detailText: String {
        if suggestion.occurrenceCount > 1 {
            return String(localized: "Opened in \(browserDisplay) \(suggestion.occurrenceCount) times this week — never anywhere else.")
        }
        return String(localized: "Opened in \(browserDisplay) this week — never anywhere else.")
    }
}

private struct SuggestionButton: View {
    enum Kind {
        case primary
        case secondary
    }

    let title: String
    let kind: Kind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(kind == .primary ? Color.white : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, kind == .primary ? 14 : 12)
                .frame(minWidth: kind == .primary ? 96 : 84, minHeight: kind == .primary ? 32 : 28)
                .background(background)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color("BrandAccentDeep"))
        case .secondary:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
                )
        }
    }
}
