import AppKit
import SwiftUI

struct RulesSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.urlRulesManager) private var urlRulesManager

    @State private var editingRule: URLRule?
    @State private var isAddingNew: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 12)

                Text("Open matching links automatically in the chosen browser")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.bottom, 12)

                if appState.urlRules.isEmpty {
                    emptyPanel
                } else {
                    rulesCard
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
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
                    normalizeSortOrder()
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
                    normalizeSortOrder()
                    urlRulesManager?.save(appState.urlRules)
                    isAddingNew = false
                },
                onCancel: {
                    isAddingNew = false
                }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button {
                isAddingNew = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add Rule")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 93, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color("BrandAccentDeep"))
                )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 28)
    }

    private var emptyPanel: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
            Text(String(localized: "No URL Rules"))
                .font(.system(size: 13, weight: .semibold))
            Text(String(localized: "Add rules to automatically open URLs in a specific browser and profile."))
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

    private var rulesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(appState.urlRules.enumerated()), id: \.element.id) { index, rule in
                ruleRow(rule)
                if index < appState.urlRules.count - 1 {
                    Rectangle()
                        .fill(Color("HairlineBorder"))
                        .frame(height: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }

    private func ruleRow(_ rule: URLRule) -> some View {
        let target = targetInfo(for: rule)

        return HStack(spacing: 10) {
            Text(rule.pattern.isEmpty ? String(localized: "(empty)") : rule.pattern)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color("SurfaceInset"))
                )

            Text("→")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color("BrandAccentDeep"))

            targetIcon(target)

            Text(target.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                .lineLimit(1)

            if let profile = target.profile {
                Text("· \(profile)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(Color("HairlineBorder"))
                .frame(height: 1)
                .padding(.leading, 2)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .opacity(rule.isEnabled ? 1 : 0.58)
        .contentShape(Rectangle())
        .onTapGesture {
            editingRule = rule
        }
        .contextMenu {
            Button(String(localized: "Edit")) {
                editingRule = rule
            }
            Button(rule.isEnabled ? String(localized: "Disable") : String(localized: "Enable")) {
                toggle(rule)
            }
            Button(String(localized: "Delete"), role: .destructive) {
                delete(rule)
            }
        }
    }

    @ViewBuilder
    private func targetIcon(_ target: RuleTargetInfo) -> some View {
        if let icon = target.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: target.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color("BrandAccentDeep"))
                .frame(width: 16, height: 16)
        }
    }

    private func targetInfo(for rule: URLRule) -> RuleTargetInfo {
        switch rule.targetType {
        case .browser:
            let browser = appState.browsers.first(where: { $0.id == rule.browserID })
            let profile = rule.profileDirectoryName.flatMap { directory in
                browser?.profiles.first(where: { $0.directoryName == directory })?.displayName
            }
            return RuleTargetInfo(
                name: browser?.displayName ?? String(localized: "Unknown"),
                profile: profile,
                icon: browser?.icon,
                systemImage: "globe"
            )
        case .app:
            let app = appState.apps.first(where: { $0.id == rule.browserID })
            return RuleTargetInfo(
                name: app?.displayName ?? String(localized: "Unknown"),
                profile: nil,
                icon: app?.icon,
                systemImage: "arrow.up.forward.app.fill"
            )
        }
    }

    private func toggle(_ rule: URLRule) {
        guard let idx = appState.urlRules.firstIndex(where: { $0.id == rule.id }) else { return }
        appState.urlRules[idx].isEnabled.toggle()
        urlRulesManager?.save(appState.urlRules)
    }

    private func delete(_ rule: URLRule) {
        appState.urlRules.removeAll { $0.id == rule.id }
        normalizeSortOrder()
        urlRulesManager?.save(appState.urlRules)
    }

    private func normalizeSortOrder() {
        for index in appState.urlRules.indices {
            appState.urlRules[index].sortOrder = index
        }
    }
}

private struct RuleTargetInfo {
    let name: String
    let profile: String?
    let icon: NSImage?
    let systemImage: String
}
