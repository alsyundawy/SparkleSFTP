import AppKit
import SparkleDesignSystem
import SwiftUI

extension AboutView {
    var aboutOverviewSection: some View {
        let palette = appState.activePalette
        return VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack(alignment: .top, spacing: 14) {
                appLogoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("SparkleSFTP v\(appState.installedAppVersion)")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(palette.primaryTextColor)
                        pillBadge("STABLE", background: palette.accentColor, foreground: .white)
                        pillBadge(
                            "macOS 13+ Universal 2",
                            background: palette.windowColor,
                            foreground: palette.primaryTextColor
                        )
                    }
                    Text(appState.strings.t("about.tagline"))
                        .font(SparkleTheme.Typography.headline)
                        .foregroundStyle(palette.primaryTextColor)
                    Text("Swift 6 • SwiftUI + AppKit NSTableView • Direct NIOSSH & libcurl FTPS")
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                }
            }

            HStack(spacing: 6) {
                featureBadge("\(appState.availableThemes.count) Themes", palette: palette)
                featureBadge("Dual-Pane NSTableView", palette: palette)
                featureBadge("Notepad2 Editor (⌘E)", palette: palette)
                featureBadge("SwiftTerm PTY", palette: palette)
                featureBadge("Keychain + TOFU", palette: palette)
            }

            accentCard(palette: palette) {
                LabeledContent("GitHub") {
                    linkText(
                        "github.com/alsyundawy/SparkleSFTP",
                        urlString: "https://github.com/alsyundawy/SparkleSFTP"
                    )
                }
                LabeledContent("Maintainer") {
                    Text("Harry Dertin Sutisna Alsyundawy (@alsyundawy) — ALSYUNDAWY IT SOLUTION")
                }
                LabeledContent("Engine & License") {
                    Text("MIT License • swift-nio-ssh 0.15.1 • SwiftTerm 1.20.0 • SQLite3 WAL")
                }
            }

            accentCard(palette: palette) {
                Text("Independent Open-Source Project")
                    .font(SparkleTheme.Typography.headline)
                Text(
                    "SparkleSFTP is built cleanly in Swift 6 with native macOS Security.framework, Keychain, "
                        + "Touch ID, and SecTrust isolation — inspired by SparkNotePad, SubnetCalc, and orthodox "
                        + "dual-pane Commander workflows across versions 0.1.0 through 0.5.0."
                )
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
            }
        }
    }

    var maintainerSection: some View {
        let palette = appState.activePalette
        return VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text("Maintainer & Official Channels")
                .font(SparkleTheme.Typography.title)
            accentCard(palette: palette) {
                LabeledContent("Lead Architect", value: "HARRY DERTIN SUTISNA ALSYUNDAWY (@alsyundawy)")
                LabeledContent("Organization", value: "ALSYUNDAWY IT SOLUTION")
                LabeledContent("Website") {
                    linkText("https://alsyundawy.com", urlString: "https://alsyundawy.com")
                }
                LabeledContent("Email") {
                    linkText("alsyundawy@gmail.com", urlString: "mailto:alsyundawy@gmail.com")
                }
                LabeledContent("PayPal Support") {
                    linkText("https://www.paypal.me/alsyundawy", urlString: "https://www.paypal.me/alsyundawy")
                }
            }
        }
    }

    var creditsSection: some View {
        let palette = appState.activePalette
        return VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            Text("Open-Source Technologies & Design Credits")
                .font(SparkleTheme.Typography.title)
            accentCard(palette: palette) {
                creditRow(
                    "Google Gemini 3.8 Flash & Google Antigravity IDE",
                    detail: "Advanced AI-assisted architecture, multi-skill orchestration "
                        + "& 14-pillar empirical review"
                )
                creditRow(
                    "SparkNotePad & Notepad2 Inspiration",
                    detail: "macOS code editor ergonomics, 76 developer color palettes "
                        + "& typography tokens (v0.1.0–v0.5.0)"
                )
                creditRow(
                    "SubnetCalc",
                    detail: "Network IP calculation algorithms, CIDR subnetting "
                        + "& protocol port engineering foundations"
                )
                creditRow(
                    "apple/swift-nio & swift-nio-ssh (0.15.1)",
                    detail: "Async EventLoop SSH transport, RFC SFTP v3 framing "
                        + "& DirectTCPIP forwarding (v0.1.0–v0.5.0)"
                )
                creditRow(
                    "apple/swift-crypto",
                    detail: "Streaming off-MainActor SHA-256 verification "
                        + "& OpenSSH Ed25519/ECDSA key parsing (v0.1.0–v0.5.0)"
                )
                creditRow(
                    "migueldeicaza/SwiftTerm (1.20.0)",
                    detail: "Native xterm/VT100 terminal emulation, standalone workspace "
                        + "& OSC 7 directory sync (v0.1.0–v0.5.0)"
                )
                creditRow(
                    "sparkle-project/Sparkle (2.10.1)",
                    detail: "Ed25519-signed automated software update delivery "
                        + "& appcast validation (v0.2.0–v0.5.0)"
                )
                creditRow(
                    "Apple macOS SDK Frameworks",
                    detail: "libcurl FTPS with C11 wrapper, SQLite3 WAL journal, "
                        + "Security.framework Keychain with Touch ID"
                )
                creditRow(
                    "FileZilla & WinSCP Workflows",
                    detail: "Orthodox commander layout, 8 transfer conflict policies, "
                        + "XML/INI importers & command sanitization"
                )
            }
        }
    }

    var librariesSection: some View {
        let palette = appState.activePalette
        return VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            Text(appState.strings.t("prefs.terminalAndLibs"))
                .font(SparkleTheme.Typography.title)
            accentCard(palette: palette) {
                if appState.toolchainReport.libraries.isEmpty {
                    Text("Inspecting host libraries and CLI tools...")
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                } else {
                    ForEach(appState.toolchainReport.libraries) { lib in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: lib.isAvailable ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(lib.isAvailable ? SparkleTheme.Colors.success : palette
                                    .secondaryTextColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(lib.name) · \(lib.version)")
                                    .font(SparkleTheme.Typography.headline)
                                Text("\(lib.role) — \(lib.detail)")
                                    .font(SparkleTheme.Typography.caption)
                                    .foregroundStyle(palette.secondaryTextColor)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .task {
                if appState.toolchainReport.libraries.isEmpty {
                    await appState.refreshToolchainReport()
                }
            }
        }
    }

    var diagnosticsSection: some View {
        let palette = appState.activePalette
        return VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            Text("Runtime, Theme & Security Diagnostics")
                .font(SparkleTheme.Typography.title)
            accentCard(palette: palette) {
                Text(buildDiagnosticsText())
                    .font(SparkleTheme.Typography.monoSmall)
                    .textSelection(.enabled)
            }
        }
    }

    var shortcutsSection: some View {
        let palette = appState.activePalette
        let rows: [(String, String)] = [
            ("Double-Click / Return", "Connect profile / Open directory / Edit file"),
            ("↑ / ↓ Arrows", "Navigate connection list & file panes cleanly"),
            ("Tab (Table) / ⌘\\", "Switch active Dual-Pane side (without stealing field Tab focus)"),
            ("Backspace / ⌘↑", "Open parent directory (File Pane)"),
            ("Space", "Quick Look preview (File Pane)"),
            ("⌘T / ⇧⌘T / ⌘W", "New Tab / Duplicate Tab / Close Active Tab or Window"),
            ("⌘⇧[ / ⌘⇧]", "Select Previous / Next Workspace Tab"),
            ("⌘U / ⇧⌘N / F7", "Upload or Download selected / New Folder"),
            ("⌘E / ⌘K", "Open Notepad2 Editor / Toggle Active Tab SSH Shell (1 Tab = 1 Shell)"),
            ("⌘⇧S / ⌘R", "Directory Synchronize / Refresh directory"),
            ("⌘↩ / ⌥↩", "Insert Filenames to Shell / Properties"),
            ("⌘C / ⌘⇧C / ⌘⌥C", "Copy to Clipboard / Copy Filenames / Copy Full Paths"),
            ("F2 / F5 / ⇧F5 / F6 / F8 / F9", "Rename / Transfer / Copy To / Move To / Delete / Properties"),
            ("⌘A / ⌘⌫", "Select All / Delete selected items")
        ]
        return VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            Text("Key Productivity Shortcuts")
                .font(SparkleTheme.Typography.title)
            accentCard(palette: palette) {
                ForEach(rows, id: \.0) { shortcut, desc in
                    HStack {
                        Text(shortcut)
                            .font(SparkleTheme.Typography.monoSmall)
                            .foregroundStyle(palette.accentColor)
                            .frame(width: 190, alignment: .leading)
                        Text(desc)
                            .font(SparkleTheme.Typography.caption)
                        Spacer()
                    }
                }
            }
        }
    }

    var licenseSection: some View {
        let palette = appState.activePalette
        return VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            Text("MIT License")
                .font(SparkleTheme.Typography.title)
            accentCard(palette: palette) {
                Text(
                    """
                    MIT License — Copyright (c) 2026 Harry Dertin Sutisna Alsyundawy (ALSYUNDAWY IT SOLUTION)

                    Permission is hereby granted, free of charge, to any person obtaining a copy of this \
                    software and associated documentation files (the "Software"), to deal in the Software \
                    without restriction, including without limitation the rights to use, copy, modify, merge, \
                    publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons \
                    to whom the Software is furnished to do so.
                    """
                )
                .font(SparkleTheme.Typography.caption)
                .textSelection(.enabled)
            }
        }
    }

    private var appLogoImage: Image {
        if let appIcon = NSApplication.shared.applicationIconImage {
            return Image(nsImage: appIcon)
        }
        return Image(systemName: SparkleTheme.Symbols.sftp)
    }

    @ViewBuilder
    private func linkText(_ title: String, urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(title, destination: url)
        } else {
            Text(title)
        }
    }

    private func featureBadge(_ text: String, palette: SparkleThemePalette) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(palette.windowColor)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.borderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func pillBadge(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func creditRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(SparkleTheme.Typography.headline)
            Text(detail)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(appState.activePalette.secondaryTextColor)
        }
    }

    private func accentCard(
        palette: SparkleThemePalette,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.windowColor)
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.accentColor).frame(width: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func buildDiagnosticsText() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return """
        App: SparkleSFTP v\(appState.installedAppVersion)
        OS: \(osVersion)
        Active Theme: \(appState.activePalette.displayName) (\(appState.activePalette.family))
        Locale: \(appState.activeLocaleCode.uppercased()) (\(appState.availableLocales.count) catalogs)
        Profiles: \(appState.profiles.count) · Active Sessions: \(appState.activeSessions.count)
        Transfers: \(appState.transferSnapshots.count) · Trusted Hosts: \(appState.trustedHosts.count)
        Security: Keychain WhenUnlockedThisDeviceOnly · 6-state TOFU · SecTrust TLS 1.2+
        """
    }
}
