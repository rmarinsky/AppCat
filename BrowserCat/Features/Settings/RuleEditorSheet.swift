import SwiftUI

struct RuleEditorSheet: View {
    @State var rule: URLRule
    let browsers: [InstalledBrowser]
    let apps: [InstalledApp]
    let onSave: (URLRule) -> Void
    let onCancel: () -> Void

    private var selectedBrowser: InstalledBrowser? {
        browsers.first { $0.id == rule.browserID }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("URL Rule")
                .font(.headline)

            Form {
                // Pattern
                TextField("Pattern", text: $rule.pattern)
                    .textFieldStyle(.roundedBorder)

                // Match type
                Picker("Match Type", selection: $rule.matchType) {
                    ForEach(URLRule.MatchType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Text(rule.matchType.helpText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if rule.matchType == .regex {
                    regexExamples
                }

                // Target type
                Picker("Open In", selection: $rule.targetType) {
                    ForEach(URLRule.TargetType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: rule.targetType) {
                    // Reset selection when switching target type
                    rule.browserID = ""
                    rule.profileDirectoryName = nil
                }

                // Browser or App selection
                switch rule.targetType {
                case .browser:
                    Picker("Browser", selection: $rule.browserID) {
                        Text("Select...").tag("")
                        ForEach(browsers) { browser in
                            Text(browser.displayName).tag(browser.id)
                        }
                    }

                    // Profile
                    if let browser = selectedBrowser, !browser.profiles.isEmpty {
                        Picker("Profile", selection: profileBinding) {
                            Text("Any Profile").tag(String?.none)
                            ForEach(browser.profiles) { profile in
                                Text(profileLabel(profile)).tag(Optional(profile.directoryName))
                            }
                        }
                        Text("\"Any Profile\" uses the browser's last-used profile.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                case .app:
                    Picker("App", selection: $rule.browserID) {
                        Text("Select...").tag("")
                        ForEach(apps) { app in
                            Text(app.displayName).tag(app.id)
                        }
                    }
                }

                // Enabled
                Toggle("Enabled", isOn: $rule.isEnabled)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(rule)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.pattern.isEmpty || rule.browserID.isEmpty)
            }
        }
        .padding()
        .frame(width: 460, height: rule.matchType == .regex && showRegexExamples ? 700 : 500)
    }

    @State private var showRegexExamples: Bool = false

    private var regexExamples: some View {
        DisclosureGroup(isExpanded: $showRegexExamples) {
            VStack(alignment: .leading, spacing: 10) {
                regexExampleRow(
                    title: String(localized: "OR — any of the options"),
                    pattern: #"gitlab\.com|github\.com"#,
                    description: String(localized: "Use | between options. This matches links that contain gitlab.com OR github.com.")
                )
                regexExampleRow(
                    title: String(localized: "AND — all options at once"),
                    pattern: #"(?=.*work)(?=.*gitlab)"#,
                    description: String(localized: "Matches when the link contains BOTH \"work\" AND \"gitlab\", in any order.")
                )
                regexExampleRow(
                    title: String(localized: "Starts with"),
                    pattern: #"^https://github\.com"#,
                    description: String(localized: "The link must start with this. ^ means \"beginning\".")
                )
                regexExampleRow(
                    title: String(localized: "Ends with"),
                    pattern: #"/work$"#,
                    description: String(localized: "The link must end with this. $ means \"end\".")
                )
                Text("Tip: dots and slashes have a special meaning. Write \\. and \\/ to match a literal dot or slash.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            Text("Examples")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func regexExampleRow(title: String, pattern: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            HStack {
                Text(pattern)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.18))
                    .cornerRadius(4)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    rule.pattern = pattern
                } label: {
                    Text("Use")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Insert this pattern into the field above"))
            }
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var profileBinding: Binding<String?> {
        Binding(
            get: { rule.profileDirectoryName },
            set: { rule.profileDirectoryName = $0 }
        )
    }

    private func profileLabel(_ profile: BrowserProfile) -> String {
        if let email = profile.email {
            return "\(profile.displayName) (\(email))"
        }
        return profile.displayName
    }
}
