import AppKit
import SparkleCore
import SparkleDesignSystem
import SparklePersistence
import SwiftUI
import UniformTypeIdentifiers

/// Modal dialog allowing users to export connection configurations in sanitized, encrypted, or plaintext formats.
public struct ExportConnectionsSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var exportSelectedOnly: Bool
    @State private var securityMode: ConnectionExportSecurityMode = .sanitizedWithoutSecrets
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var isExporting = false
    @State private var errorMessage: String?

    public init(appState: AppState) {
        self.appState = appState
        _exportSelectedOnly = State(initialValue: appState.exportSelectedOnly)
    }

    private var strings: AppStrings {
        appState.strings
    }

    private var targetCount: Int {
        if exportSelectedOnly {
            return appState.selectedProfileIDs.count
        }
        return appState.profiles.count
    }

    private var isPassphraseValid: Bool {
        if securityMode != .passwordProtected {
            return true
        }
        return passphrase.count >= 6 && passphrase == confirmPassphrase
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            headerView
            scopePickerView
            securityModePickerView

            if securityMode == .passwordProtected {
                passphraseInputView
            } else if securityMode == .plaintextSecrets {
                plaintextWarningView
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.danger)
            }

            Spacer(minLength: 0)
            footerActionView
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 560, height: 490)
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
        VStack(alignment: .leading, spacing: 4) {
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

    private var securityModePickerView: some View {
        VStack(alignment: .leading, spacing: 4) {
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

    private var passphraseInputView: some View {
        VStack(alignment: .leading, spacing: 6) {
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

    private var plaintextWarningView: some View {
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

    private func triggerSavePanel() {
        guard isPassphraseValid else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: Date())

        let ext = securityMode == .passwordProtected ? "sparklesftp" : "json"
        let defaultName = "SparkleSFTP-Connections-\(dateString).\(ext)"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [
            securityMode == .passwordProtected
                ? (UTType(filenameExtension: "sparklesftp") ?? .data)
                : .json
        ]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        if panel.runModal() == .OK, let targetURL = panel.url {
            executeExport(to: targetURL)
        }
    }

    private func executeExport(to destinationURL: URL) {
        isExporting = true
        errorMessage = nil
        let mode = securityMode
        let pass = passphrase
        let selected = exportSelectedOnly

        Task {
            do {
                let data = try await appState.exportConnections(
                    mode: mode,
                    passphrase: pass,
                    selectedOnly: selected
                )
                try data.write(to: destinationURL, options: [.atomic])
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
