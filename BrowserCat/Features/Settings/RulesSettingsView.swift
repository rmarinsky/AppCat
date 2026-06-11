import SwiftUI

struct RulesSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.urlRulesManager) private var urlRulesManager
    @Environment(\.suggestionsManager) private var suggestionsManager

    @State private var selectedRuleID: UUID?
    @State private var editingRule: URLRule?
    @State private var isAddingNew: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if !appState.suggestions.isEmpty {
                suggestionsSection
                Divider()
            }

            if appState.urlRules.isEmpty {
                emptyState
            } else {
                rulesList
            }

            Divider()

            bottomBar
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(
                rule: rule,
                browsers: appState.browsers,
                apps: appState.visibleApps,
                onSave: { updatedRule in
                    if let idx = appState.urlRules.firstIndex(where: { $0.id == updatedRule.id }) {
                        appState.urlRules[idx] = updatedRule
                    } else {
                        appState.urlRules.append(updatedRule)
                    }
                    urlRulesManager?.save(appState.urlRules)
                    editingRule = nil
                },
                onCancel: {
                    editingRule = nil
                }
            )
        }
        .sheet(isPresented: $isAddingNew) {
            RuleEditorSheet(
                rule: URLRule(sortOrder: appState.urlRules.count),
                browsers: appState.browsers,
                apps: appState.visibleApps,
                onSave: { newRule in
                    appState.urlRules.append(newRule)
                    urlRulesManager?.save(appState.urlRules)
                    isAddingNew = false
                },
                onCancel: {
                    isAddingNew = false
                }
            )
        }
        .navigationTitle(String(localized: "Rules"))
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.tint)
                Text("Suggestions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ForEach(appState.suggestions) { suggestion in
                suggestionRow(suggestion)
            }
        }
        .padding(.bottom, 6)
    }

    private func suggestionRow(_ suggestion: RuleSuggestion) -> some View {
        let scopeLabel = suggestion.scope.displayHost + (suggestion.scope.pathSuffix.map { "/\($0)" } ?? "")
        let browserName = appState.browsers.first(where: { $0.id == suggestion.browserID })?.displayName ?? suggestion.browserID
        let profileDisplay: String? = {
            guard let dirName = suggestion.profileDirectoryName,
                  let browser = appState.browsers.first(where: { $0.id == suggestion.browserID }),
                  let profile = browser.profiles.first(where: { $0.directoryName == dirName })
            else { return nil }
            return profile.displayName
        }()

        return HStack(spacing: 10) {
            FaviconView(urlString: "https://\(suggestion.scope.displayHost)/", fallbackDomain: suggestion.scope.displayHost, size: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(scopeLabel)
                    .font(.system(size: 12, weight: .medium))
                if let profileDisplay {
                    Text("Frequently opened in \(browserName) (\(profileDisplay))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Frequently opened in \(browserName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Create Rule") {
                let newRule = suggestionsManager?.accept(suggestion, sortOrder: appState.urlRules.count)
                editingRule = newRule
                suggestionsManager?.dismiss(suggestion, state: appState)
            }
            .controlSize(.small)

            Button {
                suggestionsManager?.dismiss(suggestion, state: appState)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Dismiss"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No URL Rules")
                .font(.headline)
            Text("Add rules to automatically open URLs\nin a specific browser and profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rulesList: some View {
        @Bindable var state = appState

        return List(selection: $selectedRuleID) {
            ForEach(state.urlRules) { rule in
                HStack(spacing: 12) {
                    // Enabled indicator
                    Circle()
                        .fill(rule.isEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    // Pattern
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.pattern.isEmpty ? String(localized: "(empty)") : rule.pattern)
                            .font(.system(size: 12, weight: .medium))
                        Text(rule.matchType.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Target (Browser/App + Profile)
                    VStack(alignment: .trailing, spacing: 2) {
                        let targetName: String = {
                            switch rule.targetType {
                            case .browser:
                                return appState.browsers.first(where: { $0.id == rule.browserID })?.displayName ?? String(localized: "Unknown")
                            case .app:
                                return appState.apps.first(where: { $0.id == rule.browserID })?.displayName ?? String(localized: "Unknown")
                            }
                        }()
                        HStack(spacing: 4) {
                            if rule.targetType == .app {
                                Image(systemName: "arrow.up.forward.app.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color("BrandAccentDeep"))
                            }
                            Text(targetName)
                                .font(.system(size: 12))
                        }

                        if rule.targetType == .browser,
                           let profileDir = rule.profileDirectoryName,
                           let browser = appState.browsers.first(where: { $0.id == rule.browserID }),
                           let profile = browser.profiles.first(where: { $0.directoryName == profileDir })
                        {
                            Text(profile.displayName)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tag(rule.id)
                .padding(.vertical, 2)
            }
            .onMove { source, destination in
                state.urlRules.move(fromOffsets: source, toOffset: destination)
                for i in state.urlRules.indices {
                    state.urlRules[i].sortOrder = i
                }
                urlRulesManager?.save(state.urlRules)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var bottomBar: some View {
        HStack {
            Button {
                isAddingNew = true
            } label: {
                Image(systemName: "plus")
            }

            Button {
                if let id = selectedRuleID,
                   let idx = appState.urlRules.firstIndex(where: { $0.id == id })
                {
                    appState.urlRules.remove(at: idx)
                    for i in appState.urlRules.indices {
                        appState.urlRules[i].sortOrder = i
                    }
                    urlRulesManager?.save(appState.urlRules)
                    selectedRuleID = nil
                }
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selectedRuleID == nil)

            Spacer()

            Button("Edit") {
                if let id = selectedRuleID,
                   let rule = appState.urlRules.first(where: { $0.id == id })
                {
                    editingRule = rule
                }
            }
            .disabled(selectedRuleID == nil)
        }
        .padding(8)
    }
}
