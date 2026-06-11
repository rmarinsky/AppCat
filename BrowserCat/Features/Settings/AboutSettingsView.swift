import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("BrowserCat")
                            .font(.title2.bold())

                        Text("\(String(localized: "Version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("macOS browser picker")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Developer") {
                LabeledContent("Made by") {
                    Text("Roman Marinsky 🇺🇦")
                }

                LabeledContent("") {
                    Text("Made in Ukraine with ❤️")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://rmarinsky.com.ua")!) {
                    LabeledContent {
                        HStack(spacing: 4) {
                            Text("rmarinsky.com.ua")
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .foregroundStyle(.link)
                    } label: {
                        Label("Website", systemImage: "globe")
                    }
                }

                Link(destination: URL(string: "https://github.com/rmarinsky")!) {
                    LabeledContent {
                        HStack(spacing: 4) {
                            Text("@rmarinsky")
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .foregroundStyle(.link)
                    } label: {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                Link(destination: URL(string: "https://linkedin.com/in/rmarinsky")!) {
                    LabeledContent {
                        HStack(spacing: 4) {
                            Text("in/rmarinsky")
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .foregroundStyle(.link)
                    } label: {
                        Label("LinkedIn", systemImage: "briefcase")
                    }
                }
            }

            Section {
                Link(destination: URL(string: "https://base.monobank.ua/3yGFDUvCLJuNhm#subscriptions")!) {
                    HStack {
                        Label("Support the Developer", systemImage: "heart.fill")
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .foregroundStyle(.link)
                }
            }

            Section("Project") {
                Link(destination: URL(string: "https://github.com/rmarinsky/BrowserCat")!) {
                    LabeledContent {
                        HStack(spacing: 4) {
                            Text("rmarinsky/BrowserCat")
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .foregroundStyle(.link)
                    } label: {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                LabeledContent {
                    Text("MIT")
                } label: {
                    Label("License", systemImage: "doc.text")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Account & About"))
    }
}
