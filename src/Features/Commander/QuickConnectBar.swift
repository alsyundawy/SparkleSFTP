import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct QuickConnectBar: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        let strings = appState.strings
        let palette = appState.activePalette
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Picker("", selection: $appState.quickConnectProtocol) {
                    ForEach(ProtocolType.allCases, id: \.self) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
                .labelsHidden()
                .frame(width: 96)
                .controlSize(.small)
                .help(strings.t("quickConnect.protocolTooltip"))

                TextField(strings.t("conn.host"), text: $appState.quickConnectHost)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(minWidth: 110, idealWidth: 160, maxWidth: 220)
                    .help(strings.t("quickConnect.hostTooltip"))
                    .onSubmit { triggerQuickConnect() }

                TextField(strings.t("conn.port"), text: $appState.quickConnectPort)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 52)
                    .help(strings.t("quickConnect.portTooltip"))
                    .onSubmit { triggerQuickConnect() }

                TextField(strings.t("conn.username"), text: $appState.quickConnectUsername)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 84)
                    .help(strings.t("quickConnect.usernameTooltip"))
                    .onSubmit { triggerQuickConnect() }

                SecureField(strings.t("conn.password"), text: $appState.quickConnectPassword)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 96)
                    .help(strings.t("quickConnect.passwordTooltip"))
                    .onSubmit { triggerQuickConnect() }

                Toggle(strings.t("tabs.saveQuickSite"), isOn: $appState.quickConnectSaveProfile)
                    .controlSize(.small)
                    .fixedSize()
                    .help(strings.t("quickConnect.saveTooltip"))

                Button(strings.t("tabs.quickConnectButton")) {
                    triggerQuickConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize()
                .help(strings.t("quickConnect.connectTooltip"))
                .disabled(appState.quickConnectHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, SparkleTheme.Spacing.small)
            .padding(.vertical, 5)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 32)
        .background(palette.windowColor)
        .overlay(alignment: .bottom) {
            palette.borderColor.frame(height: 1)
        }
    }

    private func triggerQuickConnect() {
        Task { await appState.performQuickConnect() }
    }
}
