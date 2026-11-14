import AppKit
import SparkleCore
import SparkleDesignSystem
import SparklePersistence
import SwiftUI
import UniformTypeIdentifiers

/// Target formats available for exporting connection profiles.
public enum ExportTargetFormat: String, CaseIterable, Identifiable {
    case sparklesftp = "SparkleSFTP"
    case winscp = "WinSCP (.ini)"
    case filezilla = "FileZilla (.xml)"

    public var id: String {
        rawValue
    }
}

/// Modal dialog allowing users to export connection configurations in sanitized, encrypted, or plaintext formats.
public struct ExportConnectionsSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var exportSelectedOnly: Bool
    @State var exportFormat: ExportTargetFormat = .sparklesftp
    @State var securityMode: ConnectionExportSecurityMode = .sanitizedWithoutSecrets
    @State var passphrase = ""
    @State var confirmPassphrase = ""
    @State var isExporting = false
    @State var errorMessage: String?

    public init(appState: AppState) {
        self.appState = appState
        _exportSelectedOnly = State(initialValue: appState.exportSelectedOnly)
    }

    var strings: AppStrings {
        appState.strings
    }

    var targetProfiles: [ConnectionProfile] {
        if exportSelectedOnly {
            return appState.profiles.filter { appState.selectedProfileIDs.contains($0.id) }
        }
        return appState.profiles
    }

    var targetCount: Int {
        targetProfiles.count
    }

    var isPassphraseValid: Bool {
        if exportFormat != .sparklesftp || securityMode != .passwordProtected {
            return true
        }
        return passphrase.count >= 6 && passphrase == confirmPassphrase
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            headerView
            scopePickerView
            formatPickerView

            if exportFormat == .sparklesftp {
                securityModePickerView
                if securityMode == .passwordProtected {
                    passphraseInputView
                } else if securityMode == .plaintextSecrets {
                    plaintextWarningView
                }
            }

            connectionsPreviewList

            if let errorMessage {
                Text(errorMessage)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.danger)
            }

            Spacer(minLength: 0)
            footerActionView
        }
        .padding(SparkleTheme.Spacing.medium)
        .frame(width: 580, height: 560)
        .sparkleWorkspaceSurface(appState.activePalette)
    }

    private var headerView: some View {
        HStack {
            Label(strings.t("export.title"), systemImage: "square.and.arrow.up.on.square")
                .font(SparkleTheme.Typography.title)
            Spacer()
            Button(strings.t("common.close")) {
                dismiss()
            }
        }
    }

    private var scopePickerView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(strings.t("export.scopeTitle"))
                .font(SparkleTheme.Typography.headline)

            Picker("", selection: $exportSelectedOnly) {
                Text("\(strings.t("export.scopeAll")) (\(appState.profiles.count))")
                    .tag(false)
                Text("\(strings.t("export.scopeSelected")) (\(appState.selectedProfileIDs.count))")
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(appState.selectedProfileIDs.isEmpty)
        }
    }

    private var formatPickerView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(strings.t("export.formatTitle"))
                .font(SparkleTheme.Typography.headline)

            Picker("", selection: $exportFormat) {
                ForEach(ExportTargetFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var securityModePickerView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(strings.t("export.securityTitle"))
                .font(SparkleTheme.Typography.headline)

            Picker("", selection: $securityMode) {
                Text(strings.t("export.mode.sanitized")).tag(ConnectionExportSecurityMode.sanitizedWithoutSecrets)
                Text(strings.t("export.mode.encrypted")).tag(ConnectionExportSecurityMode.passwordProtected)
                Text(strings.t("export.mode.plaintext")).tag(ConnectionExportSecurityMode.plaintextSecrets)
            }
            .pickerStyle(.radioGroup)
        }
    }

    private var footerActionView: some View {
        HStack {
            Spacer()
            Button(strings.t("common.cancel"), role: .cancel) {
                dismiss()
            }

            Button("\(strings.t("export.actionButton")) (\(targetCount))") {
                triggerSavePanel()
            }
            .buttonStyle(.borderedProminent)
            .disabled(targetCount == 0 || !isPassphraseValid || isExporting)
        }
    }
}

// MARK: - Subviews & Credentials

extension ExportConnectionsSheet {
    var passphraseInputView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(strings.t("export.passphrasePrompt"))
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(appState.activePalette.secondaryTextColor)

            SecureField(strings.t("export.passphrasePlaceholder"), text: $passphrase)
                .textFieldStyle(.roundedBorder)

            PasswordStrengthMeter(level: PasswordStrengthLevel.evaluate(passphrase))

            SecureField(strings.t("export.confirmPassphrasePlaceholder"), text: $confirmPassphrase)
                .textFieldStyle(.roundedBorder)

            if !passphrase.isEmpty, passphrase.count < 6 {
                Text(strings.t("export.passphraseTooShort"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.warning)
            } else if !confirmPassphrase.isEmpty, passphrase != confirmPassphrase {
                Text(strings.t("export.passphraseMismatch"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.warning)
            }
        }
        .padding(SparkleTheme.Spacing.small)
        .background(appState.activePalette.canvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    var plaintextWarningView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SparkleTheme.Colors.warning)
            Text(strings.t("export.plaintextWarning"))
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(appState.activePalette.secondaryTextColor)
        }
        .padding(SparkleTheme.Spacing.small)
        .background(SparkleTheme.Colors.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    var connectionsPreviewList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(strings.t("export.previewTitle"))
                    .font(SparkleTheme.Typography.headline)
                Spacer()
                Text("\(targetProfiles.count) connection(s)")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(appState.activePalette.secondaryTextColor)
            }

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(targetProfiles) { profile in
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .font(SparkleTheme.Typography.body)
                                .lineLimit(1)
                            protocolBadge(for: profile.protocolType)
                            Spacer()
                            Text("\(profile.username)@\(profile.host):\(profile.port)")
                                .font(SparkleTheme.Typography.monoSmall)
                                .foregroundStyle(appState.activePalette.secondaryTextColor)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appState.activePalette.canvasColor.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .frame(maxHeight: 120)
            .padding(4)
            .background(appState.activePalette.canvasColor.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    func protocolBadge(for protocolType: ProtocolType) -> some View {
        let (label, tint): (String, Color) = switch protocolType {
        case .sftp: ("SFTP", SparkleTheme.Colors.accent)
        case .scp: ("SCP", Color.purple)
        case .ftp: ("FTP", Color.orange)
        case .ftpsExplicit: ("FTPS Explicit", Color.teal)
        case .ftpsImplicit: ("FTPS Implicit", Color.green)
        }
        return Text(label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.2))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

// MARK: - Save Panel & Execution

extension ExportConnectionsSheet {
    func triggerSavePanel() {
        guard isPassphraseValid else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: Date())

        let defaultName: String
        let allowedTypes: [UTType]

        switch exportFormat {
        case .sparklesftp:
            let ext = securityMode == .passwordProtected ? "sparklesftp" : "json"
            defaultName = "SparkleSFTP-Connections-\(dateString).\(ext)"
            allowedTypes = [
                securityMode == .passwordProtected
                    ? (UTType(filenameExtension: "sparklesftp") ?? .data)
                    : .json
            ]
        case .winscp:
            defaultName = "WinSCP.ini"
            allowedTypes = [UTType(filenameExtension: "ini") ?? .plainText, .plainText]
        case .filezilla:
            defaultName = "sitemanager.xml"
            allowedTypes = [.xml, .plainText]
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        if panel.runModal() == .OK, let targetURL = panel.url {
            executeExport(to: targetURL)
        }
    }

    func executeExport(to destinationURL: URL) {
        isExporting = true
        errorMessage = nil
        let mode = securityMode
        let pass = passphrase
        let selected = exportSelectedOnly
        let format = exportFormat
        let targets = targetProfiles
        let groups = appState.groups

        Task {
            do {
                switch format {
                case .sparklesftp:
                    let data = try await appState.exportConnections(
                        mode: mode,
                        passphrase: pass,
                        selectedOnly: selected
                    )
                    try data.write(to: destinationURL, options: [.atomic])
                case .winscp:
                    let iniString = ConfigExporter.exportToWinSCPINI(profiles: targets, groups: groups)
                    try Data(iniString.utf8).write(to: destinationURL, options: [.atomic])
                case .filezilla:
                    let xmlString = ConfigExporter.exportToFileZillaXML(profiles: targets, groups: groups)
                    try Data(xmlString.utf8).write(to: destinationURL, options: [.atomic])
                }
                await MainActor.run {
                    appState.statusBannerMessage = strings.t("export.success")
                    isExporting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}
