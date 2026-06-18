import SwiftUI

struct RuleEditorSheet: View {
    @State var rule: URLRule
    let browsers: [InstalledBrowser]
    let apps: [InstalledApp]
    let onSave: (URLRule) -> Void
    let onCancel: () -> Void

    @State private var showRegexExamples: Bool = false

    private var selectedBrowser: InstalledBrowser? {
        browsers.first { $0.id == rule.browserID }
    }

    private var isSaveDisabled: Bool {
        rule.pattern.isEmpty || rule.browserID.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionCaption("MATCH")
                    matchCard

                    sectionCaption("DESTINATION")
                    destinationCard
                }
                .padding(20)
            }

            footer
        }
        .frame(width: 500, height: rule.matchType == .regex && showRegexExamples ? 680 : 540)
        .background(Color("SurfaceWindow"))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("URL Rule")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Match a link pattern and choose where it should open.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle("Enabled", isOn: $rule.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Color.accentColor)
                .help(String(localized: "Enable this rule"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color("SurfaceCard"))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color("HairlineBorder")).frame(height: 1)
        }
    }

    private var matchCard: some View {
        settingCard {
            VStack(spacing: 0) {
                settingRow(
                    title: String(localized: "Pattern"),
                    detail: String(localized: "Domain, URL fragment, or regular expression.")
                ) {
                    TextField("github.com", text: $rule.pattern)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .frame(width: 230)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color("SurfaceInset"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
                        )
                }

                divider

                settingRow(title: String(localized: "Match type"), detail: rule.matchType.helpText) {
                    Picker("", selection: $rule.matchType) {
                        ForEach(URLRule.MatchType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 190)
                }

                if rule.matchType == .regex {
                    divider
                    regexExamples
                }
            }
        }
    }

    private var destinationCard: some View {
        settingCard {
            VStack(spacing: 0) {
                settingRow(
                    title: String(localized: "Rule destination"),
                    detail: String(localized: "Choose whether the rule targets a browser or a Mac app.")
                ) {
                    Picker("", selection: $rule.targetType) {
                        ForEach(URLRule.TargetType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 180)
                }
                .onChange(of: rule.targetType) {
                    rule.browserID = ""
                    rule.profileDirectoryName = nil
                }

                divider

                switch rule.targetType {
                case .browser:
                    browserPickerRow

                    if let browser = selectedBrowser, !browser.profiles.isEmpty {
                        divider
                        profilePickerRow
                    }

                case .app:
                    appPickerRow
                }
            }
        }
    }

    private var browserPickerRow: some View {
        settingRow(
            title: String(localized: "Browser"),
            detail: String(localized: "AppCat will route matching links to this browser.")
        ) {
            Picker("", selection: $rule.browserID) {
                Text("Select...").tag("")
                ForEach(browsers) { browser in
                    Text(browser.displayName).tag(browser.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 210)
        }
    }

    private var profilePickerRow: some View {
        settingRow(
            title: String(localized: "Profile"),
            detail: String(localized: "Any Profile uses the browser's last-used profile.")
        ) {
            Picker("", selection: profileBinding) {
                Text("Any Profile").tag(String?.none)
                if let browser = selectedBrowser {
                    ForEach(browser.profiles) { profile in
                        Text(profileLabel(profile)).tag(Optional(profile.directoryName))
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 210)
        }
    }

    private var appPickerRow: some View {
        settingRow(
            title: String(localized: "App"),
            detail: String(localized: "AppCat will route matching links or files to this app.")
        ) {
            Picker("", selection: $rule.browserID) {
                Text("Select...").tag("")
                ForEach(apps) { app in
                    Text(app.displayName).tag(app.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 210)
        }
    }

    private var regexExamples: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showRegexExamples.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showRegexExamples ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12)
                    Text("Examples")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showRegexExamples {
                VStack(alignment: .leading, spacing: 10) {
                    regexExampleRow(
                        title: String(localized: "OR - any of the options"),
                        pattern: #"gitlab\.com|github\.com"#,
                        description: String(localized: "Use | between options. This matches links that contain gitlab.com OR github.com.")
                    )
                    regexExampleRow(
                        title: String(localized: "AND - all options at once"),
                        pattern: #"(?=.*work)(?=.*gitlab)"#,
                        description: String(localized: "Matches when the link contains both \"work\" and \"gitlab\", in any order.")
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
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color("SurfaceInset"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
                )
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                onSave(rule)
            } label: {
                Text("Save")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSaveDisabled ? Color.gray.opacity(0.5) : Color("BrandAccentDeep"))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaveDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color("SurfaceCard"))
        .overlay(alignment: .top) {
            Rectangle().fill(Color("HairlineBorder")).frame(height: 1)
        }
    }

    private func sectionCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.44)
            .foregroundStyle(.tertiary)
    }

    private func settingCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(Color("HairlineBorder")).frame(height: 1)
    }

    private func settingRow<Control: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
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
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color("SurfaceInset"))
                    )
                    .textSelection(.enabled)
                Spacer()
                Button {
                    rule.pattern = pattern
                } label: {
                    Text("Use")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color("BrandAccentDeep"))
                }
                .buttonStyle(.plain)
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
