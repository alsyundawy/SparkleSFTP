import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

// MARK: - Remote SSH Terminal Pane View

struct RemoteSSHPaneView: View {
    let isFocused: Bool
    let tokens: SparkleSemanticTokens
    let palette: SparkleThemePalette
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(tokens.hairlineBorder)
            bufferScrollView
        }
        .clipShape(RoundedRectangle(cornerRadius: SparkleSemanticTokens.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SparkleSemanticTokens.cardCornerRadius, style: .continuous)
                .stroke(isFocused ? tokens.focusBorder : tokens.hairlineBorder, lineWidth: isFocused ? 1.5 : 1)
        )
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            StatusBadge(title: "SSH PTY", iconName: "lock.shield.fill", tint: .blue)
            Text("deploy@web-01.eu-west.internal: /var/log/nginx")
                .font(SparkleSemanticTokens.monoFont)
                .foregroundStyle(tokens.secondaryText)
            Spacer()
            Text("120×34")
                .font(SparkleSemanticTokens.monoFont)
                .foregroundStyle(tokens.tertiaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tokens.elevatedHeaderBackground)
    }

    private var bufferScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ShowcaseData.showcaseTerminalLines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        if let prompt = line.prompt, let cmd = line.command {
                            HStack(spacing: 6) {
                                Text(prompt)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.functionColor)
                                Text(cmd)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundStyle(palette.keywordColor)
                            }
                        }

                        Text(line.output)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(line.isError ? Color.red : tokens.primaryText)
                            .textSelection(.enabled)
                    }
                }

                HStack(spacing: 6) {
                    Text("deploy@web-01:~$")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.functionColor)
                    Rectangle()
                        .fill(tokens.accent)
                        .frame(width: 8, height: 15)
                }
                .padding(.top, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.canvasColor)
        .onTapGesture(perform: onFocus)
    }
}

// MARK: - Local Shell Terminal Pane View

struct LocalShellPaneView: View {
    let isFocused: Bool
    let tokens: SparkleSemanticTokens
    let palette: SparkleThemePalette
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(tokens.hairlineBorder)
            bufferScrollView
        }
        .clipShape(RoundedRectangle(cornerRadius: SparkleSemanticTokens.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SparkleSemanticTokens.cardCornerRadius, style: .continuous)
                .stroke(isFocused ? tokens.focusBorder : tokens.hairlineBorder, lineWidth: isFocused ? 1.5 : 1)
        )
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            StatusBadge(title: "LOCAL BASH 5.3", iconName: "laptopcomputer", tint: .teal)
            Text("developer@macbook-pro: ~/Downloads/GitHub/SparkleSFTP")
                .font(SparkleSemanticTokens.monoFont)
                .foregroundStyle(tokens.secondaryText)
            Spacer()
            Text("120×34")
                .font(SparkleSemanticTokens.monoFont)
                .foregroundStyle(tokens.tertiaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tokens.elevatedHeaderBackground)
    }

    private var bufferScrollView: some View {
        let gitStatusOutput = "## main...origin/main\n"
            + " M src/Packages/DesignSystem/SemanticSurfaceTokens.swift\n"
            + "?? src/Features/Showcase/"

        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("developer@mbp:~/SparkleSFTP$")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.stringColor)
                        Text("git status -sb")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.keywordColor)
                    }
                    Text(gitStatusOutput)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(tokens.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("developer@mbp:~/SparkleSFTP$")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.stringColor)
                        Text("swift build --configuration release")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.keywordColor)
                    }
                    Text("Building for production...\n[14/14] Linking SparkleSFTP\nBuild complete! (18.42s)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.green)
                }

                HStack(spacing: 6) {
                    Text("developer@mbp:~/SparkleSFTP$")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.stringColor)
                    Rectangle()
                        .fill(tokens.secondaryText)
                        .frame(width: 8, height: 15)
                        .opacity(0.6)
                }
                .padding(.top, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.canvasColor)
        .onTapGesture(perform: onFocus)
    }
}
