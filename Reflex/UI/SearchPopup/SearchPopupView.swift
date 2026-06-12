import SwiftUI

struct SearchPopupView: View {
    @ObservedObject var viewModel: SearchViewModel
    @ObservedObject private var preferences = PreferencesManager.shared
    @ObservedObject private var spotifyAuth = SpotifyAuthManager.shared

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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.toast)
    }

    private var showsContent: Bool {
        if case .idle = viewModel.state { return false }
        return true
    }

    private func selectedIsTrack(_ items: [MediaSearchResult]) -> Bool {
        guard items.indices.contains(viewModel.selectedIndex) else { return false }
        return items[viewModel.selectedIndex].type == .track
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
                placeholder: "Search for a song or album…",
                cursorColor: cursorColor,
                onMoveUp: { viewModel.moveSelection(by: -1) },
                onMoveDown: { viewModel.moveSelection(by: 1) },
                onEnter: { viewModel.onEnterPressed() },
                onCommandEnter: { viewModel.onCommandEnterPressed() },
                onShiftEnter: { viewModel.onShiftEnterPressed() },
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
        case .loading:
            PlaceholderRowsView()
        case .results(let items):
            VStack(spacing: 0) {
                ResultsListView(
                    results: items,
                    selectedIndex: viewModel.selectedIndex,
                    highlightStyle: preferences.prefs.searchHighlightStyle,
                    onTap: { index in
                        viewModel.selectedIndex = index
                        viewModel.onEnterPressed()
                    }
                )
                StatusBar(
                    showQueueHint: spotifyAuth.isSignedIn && selectedIsTrack(items),
                    showCommandsHint: true
                )
            }
        case .recents(let items):
            VStack(spacing: 0) {
                RecentsHeader()
                ResultsListView(
                    results: items,
                    selectedIndex: viewModel.selectedIndex,
                    highlightStyle: preferences.prefs.searchHighlightStyle,
                    onTap: { index in
                        viewModel.selectedIndex = index
                        viewModel.onEnterPressed()
                    }
                )
                StatusBar(
                    showQueueHint: spotifyAuth.isSignedIn && selectedIsTrack(items),
                    showCommandsHint: true
                )
            }
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
                        onTap: { index in
                            viewModel.selectedIndex = index
                            viewModel.onEnterPressed()
                        }
                    )
                }
                StatusBar(primaryActionLabel: "to run")
            }
        case .empty:
            EmptyResultsView()
        case .error(let kind):
            ErrorBanner(kind: kind, onOpenSpotify: { viewModel.openSpotifyApp() })
        }
    }
}

private struct RecentsHeader: View {
    var body: some View {
        HStack {
            Text("Recently played")
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

private struct StatusBar: View {
    var showQueueHint: Bool = false
    var showCommandsHint: Bool = false
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
                if showQueueHint {
                    HStack(spacing: 4) {
                        Image(systemName: "command")
                        Image(systemName: "return")
                        Text("to queue").padding(.leading, 2)
                    }
                    .padding(.leading, 12)
                }
                if showCommandsHint {
                    HStack(spacing: 4) {
                        Text(">")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Text("for commands").padding(.leading, 2)
                    }
                    .padding(.leading, 12)
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

private struct PlaceholderRowsView: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2)).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2)).frame(width: 180, height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15)).frame(width: 120, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct EmptyResultsView: View {
    var body: some View {
        HStack {
            Spacer()
            Text("No results")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 24)
    }
}

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

private struct ResultsListView: View {
    let results: [MediaSearchResult]
    let selectedIndex: Int
    let highlightStyle: SearchHighlightStyle
    var onTap: (Int) -> Void
    @State private var hoveredID: MediaSearchResult.ID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { idx, item in
                ResultRow(
                    result: item,
                    isHighlighted: idx == selectedIndex || hoveredID == item.id,
                    highlightStyle: highlightStyle
                )
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        if isHovering {
                            hoveredID = item.id
                        } else if hoveredID == item.id {
                            hoveredID = nil
                        }
                    }
                    .pointingHandCursor()
                    .onTapGesture { onTap(idx) }
            }
        }
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
    var onTap: (Int) -> Void

    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 56

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: commands.count > Self.visibleRows) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { idx, command in
                        CommandRow(
                            command: command,
                            isSelected: idx == selectedIndex && command.isEnabled,
                            highlightStyle: highlightStyle
                        )
                        .id(command.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard command.isEnabled else { return }
                            onTap(idx)
                        }
                    }
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
        withAnimation(.easeInOut(duration: 0.12)) {
            proxy.scrollTo(commands[selectedIndex].id, anchor: .center)
        }
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

private struct ResultRow: View {
    let result: MediaSearchResult
    let isHighlighted: Bool
    let highlightStyle: SearchHighlightStyle

    private var useInvertedForeground: Bool {
        isHighlighted && highlightStyle == .accent
    }

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(useInvertedForeground ? .white : .primary)
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(useInvertedForeground ? Color.white.opacity(0.75) : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            TypeTag(type: result.type, useInvertedForeground: useInvertedForeground)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(highlightBackground)
    }

    @ViewBuilder
    private var highlightBackground: some View {
        if isHighlighted {
            switch highlightStyle {
            case .accent: Color.accentColor
            case .neutral: Color.primary.opacity(0.1)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = result.artworkURL {
            CachedArtworkImage(url: url) {
                Color.secondary.opacity(0.2)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 40)
        }
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @State private var didPushCursor = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                if isHovering, !didPushCursor {
                    NSCursor.pointingHand.push()
                    didPushCursor = true
                } else if !isHovering, didPushCursor {
                    NSCursor.pop()
                    didPushCursor = false
                }
            }
            .onDisappear {
                if didPushCursor {
                    NSCursor.pop()
                    didPushCursor = false
                }
            }
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}

private struct TypeTag: View {
    let type: MediaItemType
    var useInvertedForeground: Bool = false
    private var label: String {
        switch type {
        case .track: return "Track"
        case .album: return "Album"
        case .playlist: return "Playlist"
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(useInvertedForeground ? Color.white.opacity(0.25) : Color.secondary.opacity(0.2))
            .clipShape(Capsule())
            .foregroundColor(useInvertedForeground ? .white : .secondary)
    }
}

private struct ErrorBanner: View {
    let kind: SearchBannerKind
    var onOpenSpotify: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            if kind == .playerNotRunning {
                Button("Open Spotify", action: onOpenSpotify)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var message: String {
        switch kind {
        case .playerNotRunning: return "Spotify isn't running. Open Spotify and try again."
        case .rateLimited: return "Too many requests. Please wait a moment and try again."
        case .network: return "Network error. Check your connection and try again."
        case .notAuthenticated: return "Connect your Spotify account in Settings to search."
        case .generic: return "Something went wrong. Please try again."
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
