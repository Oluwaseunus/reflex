import SwiftUI

struct SearchPopupView: View {
    @ObservedObject var viewModel: SearchViewModel
    @ObservedObject private var preferences = PreferencesManager.shared

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if showsContent {
                Divider().opacity(0.3)
                contentArea
            }
        }
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toast {
                ToastView(message: toast)
                    .padding(.bottom, 44)
            }
        }
    }

    private var showsContent: Bool {
        if case .idle = viewModel.state { return false }
        return true
    }

    private var cursorColor: NSColor {
        switch preferences.prefs.searchHighlightStyle {
        case .accent: return .controlAccentColor
        case .neutral: return .labelColor
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
            SearchField(
                text: Binding(
                    get: { viewModel.query },
                    set: { viewModel.onQueryChanged($0) }
                ),
                placeholder: "Search Spotify…",
                cursorColor: cursorColor,
                onMoveUp: { viewModel.moveSelection(by: -1) },
                onMoveDown: { viewModel.moveSelection(by: 1) },
                onEnter: { viewModel.onEnterPressed() },
                onEscape: { SearchPopupController.shared.close(restoreFocus: true) }
            )
            .frame(height: 28)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.state {
        case .idle:
            Color.clear
        case .commands(let commands):
            VStack(spacing: 0) {
                CommandsHeader()
                if commands.isEmpty {
                    EmptyCommandsView()
                } else {
                    CommandsListView(
                        commands: commands,
                        selectedIndex: viewModel.selectedIndex,
                        highlightStyle: preferences.prefs.searchHighlightStyle,
                        onSelect: { index in
                            viewModel.selectedIndex = index
                        },
                        onActivate: { index in
                            viewModel.selectedIndex = index
                            viewModel.onEnterPressed()
                        }
                    )
                }
                StatusBar(primaryActionLabel: "to run")
            }
        }
    }
}

private struct StatusBar: View {
    var primaryActionLabel: String = "to play"

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Image(systemName: "arrow.down")
                    Text("to navigate").padding(.leading, 2)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "return")
                    Text(primaryActionLabel).padding(.leading, 2)
                }
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Sub-views

private struct EmptyCommandsView: View {
    var body: some View {
        HStack {
            Spacer()
            Text("No commands")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 24)
    }
}

private struct CommandsHeader: View {
    var body: some View {
        HStack {
            Text("Commands")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

private struct CommandsListView: View {
    let commands: [SearchCommandItem]
    let selectedIndex: Int
    let highlightStyle: SearchHighlightStyle
    var onSelect: (Int) -> Void
    var onActivate: (Int) -> Void

    @FocusState private var focusedCommand: SearchCommandKind?

    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 56

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: commands.count > Self.visibleRows) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { idx, command in
                        Button {
                            onActivate(idx)
                        } label: {
                            CommandRow(
                                command: command,
                                isSelected: idx == selectedIndex && command.isEnabled,
                                highlightStyle: highlightStyle
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!command.isEnabled)
                        .focused($focusedCommand, equals: command.id)
                        .focusEffectDisabled()
                        .accessibilityLabel("\(command.title), \(command.subtitle)")
                        .accessibilityAddTraits(idx == selectedIndex && command.isEnabled ? .isSelected : [])
                        .id(command.id)
                        .contentShape(Rectangle())
                    }
                }
                .onChange(of: focusedCommand) { _, commandID in
                    guard let commandID,
                          let index = commands.firstIndex(where: { $0.id == commandID }),
                          commands[index].isEnabled else { return }
                    onSelect(index)
                }
            }
            .frame(height: listHeight)
            .onAppear {
                scrollToSelection(proxy)
            }
            .onChange(of: selectedIndex) { _, _ in
                scrollToSelection(proxy)
            }
            .onChange(of: commands.map { $0.id }) { _, _ in
                scrollToSelection(proxy)
            }
        }
    }

    private var listHeight: CGFloat {
        CGFloat(min(commands.count, Self.visibleRows)) * Self.rowHeight
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard commands.indices.contains(selectedIndex) else { return }
        proxy.scrollTo(commands[selectedIndex].id, anchor: .center)
    }
}

private struct CommandRow: View {
    let command: SearchCommandItem
    let isSelected: Bool
    let highlightStyle: SearchHighlightStyle

    private var useInvertedForeground: Bool {
        isSelected && highlightStyle == .accent
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                Text(command.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(subtitleColor)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(highlightBackground)
        .opacity(command.isEnabled ? 1 : 0.48)
    }

    private var titleColor: Color {
        if !command.isEnabled { return .secondary }
        return useInvertedForeground ? .white : .primary
    }

    private var subtitleColor: Color {
        if useInvertedForeground { return Color.white.opacity(0.75) }
        return .secondary
    }

    private var iconColor: Color {
        if useInvertedForeground { return .white }
        return command.isEnabled ? .primary : .secondary
    }

    private var iconBackground: Color {
        if useInvertedForeground { return Color.white.opacity(0.2) }
        return Color.secondary.opacity(0.16)
    }

    @ViewBuilder
    private var highlightBackground: some View {
        if isSelected {
            switch highlightStyle {
            case .accent: Color.accentColor
            case .neutral: Color.primary.opacity(0.1)
            }
        } else {
            Color.clear
        }
    }
}

private struct ToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

private struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
