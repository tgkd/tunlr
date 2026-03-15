import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("tunlr")
                        .font(.title2.bold())
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("Version \(version) (\(build))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                FontRow(
                    name: "Fira Code",
                    author: "Nikita Prokopov",
                    urlString: "https://github.com/tonsky/FiraCode"
                )
                FontRow(
                    name: "JetBrains Mono",
                    author: "JetBrains",
                    urlString: "https://github.com/JetBrains/JetBrainsMono"
                )
                FontRow(
                    name: "Source Code Pro",
                    author: "Adobe",
                    urlString: "https://github.com/adobe-fonts/source-code-pro"
                )
            } header: {
                Text("Open Source Fonts")
            } footer: {
                Text("All fonts are licensed under the SIL Open Font License 1.1.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FontRow: View {
    let name: String
    let author: String
    let urlString: String

    var body: some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                LabeledContent {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
