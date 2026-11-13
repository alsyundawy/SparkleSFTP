import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleTerminal
import SwiftUI

/// Retractable quick remote command bar docked at the bottom of the remote commander pane (v0.5.0).
public struct RemoteCommandBar: View {
    @ObservedObject var appState: AppState
    @State private var commandInput: String = ""
    @State private var isExpanded: Bool = true
    @State private var pendingPromptCommand: String?
    @State private var promptEntries: [(prompt: String, defaultValue: String)] = []
    @State private var promptAnswers: [String: String] = [:]
    @State private var isShowingPromptSheet: Bool = false
    @State private var errorMessage: String?

    public init(appState: AppState) {
        self.appState = appState
    }

    private var palette: SparkleThemePalette {
        appState.activePalette
    }

    private var currentRemotePath: String {
        appState.currentSession?.currentRemotePath.rawValue ?? "/"
    }

    private var primarySelectedFileName: String? {
        guard let session = appState.currentSession,
              let firstID = session.selectedRemoteFileIDs.first,
              let file = session.remoteFiles.visibleFiles.first(where: { $0.id == firstID })
        else {
            return nil
        }
        return file.name
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                HStack(spacing: SparkleTheme.Spacing.tiny) {
                    presetsMenu

                    TextField(appState.strings.t("cmd.quickCommandPlaceholder"), text: $commandInput)
                        .textFieldStyle(.roundedBorder)
                        .font(SparkleTheme.Typography.monoSmall)
                        .onSubmit {
                            executeCommand(commandInput)
                        }

                    Button {
                        executeCommand(commandInput)
                    } label: {
                        Label(appState.strings.t("cmd.run"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(appState.strings.t("cmd.runTooltip"))

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded = false
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .help(appState.strings.t("cmd.hideBarTooltip"))
                }
                .padding(.horizontal, SparkleTheme.Spacing.small)
                .padding(.vertical, 5)
                .background(palette.windowColor)

                if let err = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(SparkleTheme.Colors.danger)
                            .font(.system(size: 11))
                        Text(err)
                            .font(SparkleTheme.Typography.caption)
                            .foregroundStyle(SparkleTheme.Colors.danger)
                        Spacer()
                        Button {
                            errorMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, SparkleTheme.Spacing.small)
                    .padding(.vertical, 2)
                    .background(SparkleTheme.Colors.danger.opacity(0.12))
                }
            } else {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9, weight: .bold))
                            Text(appState.strings.t("cmd.showBar"))
                                .font(SparkleTheme.Typography.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(palette.windowColor)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(palette.borderColor.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(appState.strings.t("cmd.showBarTooltip"))
                    Spacer()
                }
                .padding(.vertical, 2)
                .background(palette.windowColor.opacity(0.8))
            }
        }
        .sheet(isPresented: $isShowingPromptSheet) {
            promptSheet
        }
    }

    private var presetsMenu: some View {
        Menu {
            ForEach(RemoteOSTarget.allCases, id: \.self) { target in
                let presets = RemoteCommandPreset.defaultPresets.filter { $0.targetOS == target }
                if !presets.isEmpty {
                    Section(header: Text(target.rawValue)) {
                        ForEach(presets) { preset in
                            Button {
                                selectPreset(preset)
                            } label: {
                                Label(preset.name, systemImage: "terminal")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                Text(appState.strings.t("cmd.presets"))
            }
            .font(SparkleTheme.Typography.caption)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 84)
    }

    private var promptSheet: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text(appState.strings.t("cmd.promptParametersTitle"))
                .font(SparkleTheme.Typography.title)
                .foregroundStyle(palette.primaryTextColor)

            ForEach(promptEntries, id: \.prompt) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.prompt)
                        .font(SparkleTheme.Typography.headline)
                        .foregroundStyle(palette.primaryTextColor)
                    TextField(
                        entry.defaultValue.isEmpty ? entry.prompt : entry.defaultValue,
                        text: Binding(
                            get: { promptAnswers[entry.prompt] ?? entry.defaultValue },
                            set: { promptAnswers[entry.prompt] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(SparkleTheme.Typography.monoSmall)
                }
            }

            HStack {
                Spacer()
                Button(appState.strings.t("common.cancel"), role: .cancel) {
                    isShowingPromptSheet = false
                    pendingPromptCommand = nil
                }
                Button(appState.strings.t("cmd.run")) {
                    if let cmd = pendingPromptCommand {
                        isShowingPromptSheet = false
                        dispatchSanitizedExecution(template: cmd, answers: promptAnswers)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 420)
        .sparkleWorkspaceSurface(palette)
    }

    private func selectPreset(_ preset: RemoteCommandPreset) {
        commandInput = preset.commandTemplate
    }

    private func executeCommand(_ rawCommand: String) {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil

        let prompts = RemoteCommandSanitizer.extractPrompts(from: trimmed)
        if !prompts.isEmpty {
            promptEntries = prompts
            promptAnswers = [:]
            pendingPromptCommand = trimmed
            isShowingPromptSheet = true
            return
        }

        dispatchSanitizedExecution(template: trimmed, answers: [:])
    }

    private func dispatchSanitizedExecution(template: String, answers: [String: String]) {
        do {
            let sanitized = try RemoteCommandSanitizer.substitutePlaceholders(
                template: template,
                selectedFile: primarySelectedFileName,
                remotePath: currentRemotePath,
                promptInputs: answers
            )

            ActivityLogger.shared.logCommand("EXEC (Terminal): \(sanitized)")

            Task { @MainActor in
                await sendToActiveTerminalSession(sanitized)
            }
        } catch {
            errorMessage = error.localizedDescription
            ActivityLogger.shared.logError("Command Sanitization Failed: \(error.localizedDescription)")
        }
    }

    private func sendToActiveTerminalSession(_ commandText: String) async {
        let targetTabID = appState.activeTabID
        if appState.terminalManager.session(forWorkspaceTabID: targetTabID) == nil {
            if appState.currentSession?.sshClient != nil {
                await appState.openTerminalTab()
            } else {
                errorMessage = appState.strings.t("nav.noActivePTY")
                return
            }
        }

        if let termSession = appState.terminalManager.session(forWorkspaceTabID: targetTabID) {
            appState.terminalManager.selectedSessionID = termSession.id
            appState.setActiveTabTerminalVisibility(true)
            termSession.sendCommand(commandText)
            appState.statusBannerMessage = "\(appState.strings.t("cmd.executed")): \(commandText)"
        }
    }
}
