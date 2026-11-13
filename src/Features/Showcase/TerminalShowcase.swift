import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// High-fidelity iTerm2-inspired split terminal workspace showcase synchronized with active theme palette.
public struct TerminalShowcase: View {
    @State private var activeTabIndex: Int = 0
    @State private var splitLayout: SplitMode = .vertical
    @State private var focusedPaneID: Int = 1
    @State private var showSearchBar: Bool = true
    @State private var searchQuery: String = "nginx"

    @Environment(\.sparklePalette) private var palette

    public enum SplitMode: String, CaseIterable {
        case vertical = "Vertical"
        case horizontal = "Horizontal"
    }

    public init() {}

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        VStack(spacing: 0) {
            // MARK: - Terminal Window Tabs & Split Controls

            terminalHeaderBar(tokens: tokens)

            if showSearchBar {
                searchOverlayBar(tokens: tokens)
            }

            Divider().overlay(tokens.hairlineBorder)

            // MARK: - Split Terminal Panes

            Group {
                if splitLayout == .vertical {
                    HSplitView {
                        remoteSSHPane(tokens: tokens)
                        localShellPane(tokens: tokens)
                    }
                } else {
                    VSplitView {
                        remoteSSHPane(tokens: tokens)
                        localShellPane(tokens: tokens)
                    }
                }
            }
            .padding(SparkleSemanticTokens.spacingSm)

            // MARK: - Bottom PTY Status Bar

            terminalStatusBar(tokens: tokens)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(tokens.windowBackground)
    }

    // MARK: - Terminal Header Bar

    private func terminalHeaderBar(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 12) {
            // Tabs
            HStack(spacing: 4) {
                terminalTab(
                    index: 0,
                    title: "SSH: web-01 (Split)",
                    icon: "terminal.fill",
                    isConnected: true,
                    tokens: tokens
                )
                terminalTab(
                    index: 1,
                    title: "Local: /bin/bash",
                    icon: "apple.terminal.fill",
                    isConnected: true,
                    tokens: tokens
                )
                terminalTab(
                    index: 2,
                    title: "SSH: bsd-mirror",
                    icon: "server.rack",
                    isConnected: false,
                    tokens: tokens
                )
            }

            Spacer()

            // Split & Find Controls
            HStack(spacing: 8) {
                Picker("Split", selection: $splitLayout) {
                    Image(systemName: "rectangle.split.2x1").tag(SplitMode.vertical)
                    Image(systemName: "rectangle.split.1x2").tag(SplitMode.horizontal)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)

                Button {
                    showSearchBar.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .tint(showSearchBar ? tokens.accent : tokens.secondaryText)

                Button {} label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingMd)
        .padding(.vertical, 6)
        .background(tokens.elevatedHeaderBackground)
    }

    private func terminalTab(
        index: Int,
        title: String,
        icon: String,
        isConnected: Bool,
        tokens: SparkleSemanticTokens
    ) -> some View {
        let isSelected = (activeTabIndex == index)
        return Button {
            activeTabIndex = index
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? tokens.accent : tokens.secondaryText)

                Text(title)
                    .font(isSelected ? SparkleSemanticTokens.captionSemiboldFont : SparkleSemanticTokens.captionFont)
                    .foregroundStyle(isSelected ? tokens.primaryText : tokens.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? tokens.cardBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? tokens.hairlineBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search Scrollback Bar

    private func searchOverlayBar(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(tokens.secondaryText)

            TextField("Find in scrollback (⌘F)...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(SparkleSemanticTokens.monoFont)
                .frame(maxWidth: 240)

            Text("3 matches")
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.tertiaryText)

            Button {} label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)

            Button {} label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                showSearchBar = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingMd)
        .padding(.vertical, 5)
        .background(tokens.cardBackground)
    }

    // MARK: - Remote SSH Terminal Pane

    private func remoteSSHPane(tokens: SparkleSemanticTokens) -> some View {
        RemoteSSHPaneView(
            isFocused: focusedPaneID == 1,
            tokens: tokens,
            palette: palette,
            onFocus: { focusedPaneID = 1 }
        )
    }

    // MARK: - Local Shell Terminal Pane

    private func localShellPane(tokens: SparkleSemanticTokens) -> some View {
        LocalShellPaneView(
            isFocused: focusedPaneID == 2,
            tokens: tokens,
            palette: palette,
            onFocus: { focusedPaneID = 2 }
        )
    }

    // MARK: - Bottom PTY Status Bar

    private func terminalStatusBar(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("PTY Connected · SSH-2.0-OpenSSH_9.6p1 · RTT 38 ms")
                    .font(SparkleSemanticTokens.captionFont)
                    .foregroundStyle(tokens.secondaryText)
            }

            Spacer()

            Text("Theme Sync: \(palette.displayName) · ⌘D Split Vertical · ⌘⇧D Split Horizontal")
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.tertiaryText)
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingMd)
        .padding(.vertical, 5)
        .background(tokens.elevatedHeaderBackground)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(tokens.hairlineBorder),
            alignment: .top
        )
    }
}

public typealias TerminalMockup = TerminalShowcase

// MARK: - Xcode Previews (1280×800)

#if DEBUG
    struct TerminalShowcase_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            Group {
                TerminalShowcase()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultDark)
                    .preferredColorScheme(.dark)
                    .previewDisplayName("Split Terminal Dark (1280×800)")

                TerminalShowcase()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultLight)
                    .preferredColorScheme(.light)
                    .previewDisplayName("Split Terminal Light (1280×800)")
            }
            .frame(width: 1280, height: 800)
        }
    }
#endif
