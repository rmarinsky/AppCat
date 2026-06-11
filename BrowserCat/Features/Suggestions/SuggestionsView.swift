import SwiftUI

struct SuggestionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.suggestionsManager) private var suggestionsManager
    @Environment(\.urlRulesManager) private var urlRulesManager

    @State private var editingRule: URLRule?

    var body: some View {
        Group {
            if appState.suggestions.isEmpty {
                emptyState
            } else {
                suggestionsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(
                rule: rule,
                browsers: appState.browsers,
                apps: appState.visibleApps,
                onSave: { saved in
                    var saved = saved
                    saved.sortOrder = appState.urlRules.count
                    appState.urlRules.append(saved)
                    urlRulesManager?.save(appState.urlRules)
                    editingRule = nil
                },
                onCancel: { editingRule = nil }
            )
        }
        .navigationTitle(String(localized: "Suggestions"))
    }

    private var suggestionsList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(appState.suggestions) { suggestion in
                    SuggestionCard(suggestion: suggestion, onAccept: { rule in
                        editingRule = rule
                        suggestionsManager?.dismiss(suggestion, state: appState)
                    }, onDismiss: {
                        suggestionsManager?.dismiss(suggestion, state: appState)
                    })
                }
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(String(localized: "No Suggestions"))
                .font(.headline)
            Text(String(localized: "Open some links and BrowserCat will suggest rules based on your browsing habits."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}

// MARK: - Suggestion Card

private struct SuggestionCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.suggestionsManager) private var suggestionsManager

    let suggestion: RuleSuggestion
    let onAccept: (URLRule) -> Void
    let onDismiss: () -> Void

    private var scopeLabel: String {
        suggestion.scope.displayHost + (suggestion.scope.pathSuffix.map { "/\($0)" } ?? "")
    }

    private var browserDisplay: String {
        let name = appState.browsers.first(where: { $0.id == suggestion.browserID })?.displayName
            ?? suggestion.browserID
        if let dirName = suggestion.profileDirectoryName,
           let browser = appState.browsers.first(where: { $0.id == suggestion.browserID }),
           let profile = browser.profiles.first(where: { $0.directoryName == dirName }) {
            return "\(name) · \(profile.displayName)"
        }
        return name
    }

    var body: some View {
        HStack(spacing: 12) {
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

            VStack(alignment: .leading, spacing: 3) {
                Text(scopeLabel)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(String(localized: "Frequently opened in \(browserDisplay)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if suggestion.occurrenceCount > 1 {
                    Text(String(localized: "Opened \(suggestion.occurrenceCount) times"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(String(localized: "Create Rule")) {
                if let rule = suggestionsManager?.accept(suggestion, sortOrder: appState.urlRules.count) {
                    onAccept(rule)
                }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(Color("BrandAccentDeep"))

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.tertiary)
        )
    }
}
