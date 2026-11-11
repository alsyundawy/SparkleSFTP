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
        HStack(spacing: 6) {
            Picker("", selection: $appState.quickConnectProtocol) {
                ForEach(ProtocolType.allCases, id: \.self) { proto in
                    Text(proto.displayName).tag(proto)
                }
            }
            .labelsHidden()
            .frame(width: 112)
            .controlSize(.small)

            TextField(strings.t("conn.host"), text: $appState.quickConnectHost)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(minWidth: 130, idealWidth: 180)
                .onSubmit { triggerQuickConnect() }

            TextField(strings.t("conn.port"), text: $appState.quickConnectPort)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 54)
                .onSubmit { triggerQuickConnect() }

            TextField(strings.t("conn.username"), text: $appState.quickConnectUsername)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 96)
                .onSubmit { triggerQuickConnect() }

            SecureField(strings.t("conn.password"), text: $appState.quickConnectPassword)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 108)
                .onSubmit { triggerQuickConnect() }

            Toggle(strings.t("tabs.saveQuickSite"), isOn: $appState.quickConnectSaveProfile)
                .controlSize(.small)

            Button(strings.t("tabs.quickConnectButton")) {
                triggerQuickConnect()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(appState.quickConnectHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .padding(.vertical, 5)
        .background(palette.windowColor)
        .overlay(alignment: .bottom) {
            palette.borderColor.frame(height: 1)
        }
    }

    private func triggerQuickConnect() {
        Task { await appState.performQuickConnect() }
    }
}
