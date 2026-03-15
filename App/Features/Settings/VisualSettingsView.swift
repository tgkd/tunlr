import SwiftUI

struct VisualSettingsView: View {
    @ObservedObject var viewModel: AppearanceViewModel

    var body: some View {
        Form {
            fontSection
            cursorSection
            scrollbackSection
            themeSection
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Font

    @ViewBuilder
    private var fontSection: some View {
        Section("Font") {
            Picker("Family", selection: binding(\.fontName)) {
                ForEach(TerminalFontName.allCases, id: \.self) { font in
                    Text(font.displayName).tag(font)
                }
            }

            Stepper(
                "Size: \(Int(viewModel.appearance.fontSize))",
                value: binding(\.fontSize),
                in: 8...24,
                step: 1
            )

            Text("AaBbCc 0123456789 {}[]")
                .font(Font(viewModel.appearance.fontName.uiFont(size: viewModel.appearance.fontSize)))
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Cursor

    @ViewBuilder
    private var cursorSection: some View {
        Section("Cursor") {
            Picker("Style", selection: binding(\.cursorStyle)) {
                ForEach(TerminalCursorStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            Toggle("Blink", isOn: binding(\.cursorBlink))
        }
    }

    // MARK: - Scrollback

    @ViewBuilder
    private var scrollbackSection: some View {
        Section("Scrollback") {
            Picker("Buffer Size", selection: binding(\.scrollbackSize)) {
                ForEach(ScrollbackSize.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Theme

    private var themeSection: some View {
        Section("Theme") {
            let themes = TerminalThemeCatalog.allThemes
            let rows = stride(from: 0, to: themes.count, by: 3).map {
                Array(themes[$0..<min($0 + 3, themes.count)])
            }
            VStack(spacing: 12) {
                ForEach(rows, id: \.first!.name) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.name) { theme in
                            ThemeSwatchView(
                                theme: theme,
                                isSelected: viewModel.appearance.themeName == theme.name
                            )
                            .frame(maxWidth: .infinity)
                            .onTapGesture {
                                var updated = viewModel.appearance
                                updated.themeName = theme.name
                                Task { await viewModel.update(updated) }
                            }
                        }
                        if row.count < 3 {
                            ForEach(0..<(3 - row.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<TerminalAppearance, T>) -> Binding<T> {
        Binding(
            get: { viewModel.appearance[keyPath: keyPath] },
            set: { newValue in
                var updated = viewModel.appearance
                updated[keyPath: keyPath] = newValue
                Task { await viewModel.update(updated) }
            }
        )
    }
}

struct ThemeSwatchView: View {
    let theme: TerminalTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.backgroundColor.swiftUIColor)

                VStack(spacing: 2) {
                    HStack(spacing: 3) {
                        ForEach(0..<8, id: \.self) { i in
                            Circle()
                                .fill(theme.ansiColors[i].swiftUIColor)
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text("Aa")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.foregroundColor.swiftUIColor)
                }
            }
            .frame(height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )

            Text(theme.displayName)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.primary)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            } else {
                Color.clear.frame(height: 12)
            }
        }
    }
}
