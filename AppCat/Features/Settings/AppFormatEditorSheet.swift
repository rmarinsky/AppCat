import SwiftUI

/// Per-app format editor — the AppCat take on Papuga's edit-rule modal. Shows the file
/// extensions an app opens as removable chips (read from the app's Info.plist, overridable),
/// lets you add your own, and exposes the "send unknown file types here" routing toggle.
struct AppFormatEditorSheet: View {
    let app: InstalledApp
    /// `customFormats` is `nil` when the edited list still equals what the app itself declares
    /// (no override needed); non-nil when the user has trimmed or extended it.
    let onSave: (_ customFormats: [String]?, _ opensUnknownTypes: Bool) -> Void
    let onCancel: () -> Void

    @State private var formats: [String]
    @State private var opensUnknownTypes: Bool
    @State private var isAddingFormat = false
    @State private var newFormat = ""
    @FocusState private var addFieldFocused: Bool

    init(
        app: InstalledApp,
        onSave: @escaping (_ customFormats: [String]?, _ opensUnknownTypes: Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.app = app
        self.onSave = onSave
        self.onCancel = onCancel
        _formats = State(initialValue: app.fileFormats)
        _opensUnknownTypes = State(initialValue: app.opensUnknownTypes)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            formatsSection
            divider
            unknownTypesRow
            divider
            footer
        }
        .frame(width: 480)
        .background(Color("SurfaceCard"))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            appIconTile
            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.displayName) — \(String(localized: "File formats"))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Choose which files AppCat opens in \(app.displayName).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var appIconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color("SurfaceInset"))
                .frame(width: 44, height: 44)
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Formats

    private var formatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OPENS THESE FORMATS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.44)
                .foregroundStyle(.tertiary)

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(formats, id: \.self) { format in
                    chip(format)
                }
                addControl
            }

            Text("Formats are read from the app. Add or remove any to override what \(app.displayName) opens.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func chip(_ format: String) -> some View {
        HStack(spacing: 5) {
            Text(format)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Button {
                formats.removeAll { $0 == format }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Remove"))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color("SurfaceInset"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var addControl: some View {
        if isAddingFormat {
            HStack(spacing: 3) {
                TextField(String(localized: "ext"), text: $newFormat)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .frame(width: 52)
                    .focused($addFieldFocused)
                    .onSubmit { commitNewFormat(keepAdding: true) }
                    .onChange(of: addFieldFocused) { _, focused in
                        if !focused { commitNewFormat(keepAdding: false) }
                    }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color("BrandTintSoft"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color("BrandAccentDeep"), lineWidth: 1)
            )
        } else {
            Button {
                isAddingFormat = true
                addFieldFocused = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Add format")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color("BrandAccentDeep"))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            Color("BrandAccentDeep").opacity(0.6),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func commitNewFormat(keepAdding: Bool) {
        let normalized = InstalledApp.normalizedFileFormat(newFormat)

        if let normalized, !formats.contains(normalized) {
            formats.append(normalized)
        }
        newFormat = ""
        if keepAdding {
            addFieldFocused = true
        } else {
            isAddingFormat = false
        }
    }

    // MARK: - Unknown types

    private var unknownTypesRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open unknown file types here")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text("When macOS can't match a file's type, AppCat sends it to \(app.displayName).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $opensUnknownTypes)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color("SurfaceInset"))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button(action: save) {
                Text("Save")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color("BrandAccentDeep"))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func save() {
        // Commit any extension still sitting in the add field.
        commitNewFormat(keepAdding: false)
        let override: [String]? = (formats == app.detectedFormats) ? nil : formats
        onSave(override, opensUnknownTypes)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color("HairlineBorder"))
            .frame(height: 1)
    }
}
