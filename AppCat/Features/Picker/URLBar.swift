import SwiftUI

struct URLBar: View {
    let url: URL?
    let title: String?
    var additionalCount: Int = 0
    @State private var showCopied = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: url == nil ? "app.dashed" : (url?.isFileURL == true ? "doc" : "link"))
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                if let primaryText, !primaryText.isEmpty {
                    Text(primaryText)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                }

                Text(secondaryText)
                    .font(.system(size: primaryText != nil ? 10 : 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(primaryText != nil ? .secondary : .primary)
                    .textSelection(.enabled)
            }

            Spacer()

            if additionalCount > 0 {
                Text("+\(additionalCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.tertiary)
                    )
                    .help(String(localized: "Additional files"))
            }

            if url != nil {
                Button {
                    copyURL()
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(showCopied ? Color("BrandAccentDeep") : .secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: .command)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
        )
    }

    private var primaryText: String? {
        if let url, url.isFileURL {
            return url.lastPathComponent
        }
        guard let title, !title.isEmpty else { return nil }
        return title
    }

    private var secondaryText: String {
        guard let url else { return String(localized: "Choose app") }
        if url.isFileURL {
            return url.deletingLastPathComponent().path
        }
        return url.host() ?? url.absoluteString
    }

    private func copyURL() {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.isFileURL ? url.path : url.absoluteString, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
}
