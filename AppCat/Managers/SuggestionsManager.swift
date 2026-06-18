import Foundation
import os

@MainActor
final class SuggestionsManager {
    private let matcher = URLRuleMatcher()
    private(set) var dismissedKeys: Set<String> = []
    private var lastAnalyzedAt: Date?

    init() {
        dismissedKeys = SuggestionDismissalStorage.shared.load()
        lastAnalyzedAt = SuggestionStateStorage.shared.load().lastAnalyzedAt
    }

    /// Loads cached suggestions immediately so the UI reflects last-known state without a full pass.
    func loadCached(into state: AppState) {
        state.suggestions = SuggestionStateStorage.shared.load().suggestions
    }

    /// Analyses only newly-added history entries. No-op when nothing has changed since the last pass.
    func analyseIfNeeded(state: AppState, now: Date = Date()) {
        let newest = state.history.first?.openedAt
        let shouldAnalyse: Bool = {
            guard let newest else { return false }
            guard let last = lastAnalyzedAt else { return true }
            return newest > last
        }()
        guard shouldAnalyse else {
            Log.app.debug("Suggestion analysis skipped — no new history since last pass")
            return
        }
        recompute(state: state, now: now)
    }

    /// Forces a full pass — used after a new URL open or rule change.
    func recompute(state: AppState, now: Date = Date()) {
        let suggestions = SuggestionEngine.suggest(
            history: state.history,
            rules: state.urlRules,
            matcher: matcher,
            dismissedKeys: dismissedKeys,
            now: now
        )
        let changed = suggestions != state.suggestions
        state.suggestions = suggestions
        lastAnalyzedAt = state.history.first?.openedAt ?? lastAnalyzedAt
        if changed {
            persist(state: state)
        }
        Log.app.debug("Recomputed \(suggestions.count) rule suggestions (changed: \(changed))")
    }

    func dismiss(_ suggestion: RuleSuggestion, state: AppState) {
        dismissedKeys.insert(suggestion.dismissalKey)
        SuggestionDismissalStorage.shared.save(dismissedKeys)
        state.suggestions.removeAll { $0.id == suggestion.id }
        persist(state: state)
    }

    func accept(_ suggestion: RuleSuggestion, sortOrder: Int) -> URLRule {
        URLRule(
            pattern: suggestion.pattern,
            matchType: suggestion.matchType,
            browserID: suggestion.browserID,
            profileDirectoryName: suggestion.profileDirectoryName,
            targetType: suggestion.targetType,
            isEnabled: true,
            sortOrder: sortOrder
        )
    }

    private func persist(state: AppState) {
        SuggestionStateStorage.shared.save(
            SuggestionState(suggestions: state.suggestions, lastAnalyzedAt: lastAnalyzedAt)
        )
    }
}
