import SwiftUI

struct AboutView: View {
    @State private var selectedLicense: LicenseInfo?

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

            Section("Acknowledgments") {
                ForEach(LicenseInfo.allLicenses) { license in
                    Button {
                        selectedLicense = license
                    } label: {
                        LabeledContent {
                            Text(license.licenseType)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(license.name)
                                Text(license.copyright)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedLicense) { license in
            NavigationView {
                ScrollView {
                    Text(license.fullText)
                        .font(.caption.monospaced())
                        .padding()
                }
                .navigationTitle(license.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { selectedLicense = nil }
                    }
                }
            }
        }
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

struct LicenseInfo: Identifiable {
    let id: String
    let name: String
    let copyright: String
    let licenseType: String
    let fullText: String

    static let allLicenses: [LicenseInfo] = [
        .swiftTerm,
        .citadel,
        .whisperKit,
        .swiftNIOSSH,
        .bigInt,
    ]

    static let swiftTerm = LicenseInfo(
        id: "swiftterm",
        name: "SwiftTerm",
        copyright: "Miguel de Icaza",
        licenseType: "MIT",
        fullText: """
        Copyright (c) 2019-2022 Miguel de Icaza
        Copyright (c) 2017-2019, The xterm.js authors
        Copyright (c) 2014-2016, SourceLair Private Company
        Copyright (c) 2012-2013, Christopher Jeffrey

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    )

    static let citadel = LicenseInfo(
        id: "citadel",
        name: "Citadel",
        copyright: "Orlandos Technologies",
        licenseType: "MIT",
        fullText: """
        MIT License

        Copyright (c) 2022 Orlandos

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    )

    static let whisperKit = LicenseInfo(
        id: "whisperkit",
        name: "WhisperKit",
        copyright: "argmax, inc.",
        licenseType: "MIT",
        fullText: """
        MIT License

        Copyright (c) 2024 argmax, inc.

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    )

    static let swiftNIOSSH = LicenseInfo(
        id: "swift-nio-ssh",
        name: "Swift NIO SSH",
        copyright: "Apple Inc.",
        licenseType: "Apache 2.0",
        fullText: """
        Copyright (c) Apple Inc.

        Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
        """
    )

    static let bigInt = LicenseInfo(
        id: "bigint",
        name: "BigInt",
        copyright: "Karoly Lorentey",
        licenseType: "MIT",
        fullText: """
        Copyright (c) 2016-2017 Karoly Lorentey

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    )
}
