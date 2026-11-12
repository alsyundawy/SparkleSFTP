import SparkleCore
import SparkleFeatures
import SwiftUI

private struct SparkleFocusedAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var activeAppState: AppState? {
        get { self[SparkleFocusedAppStateKey.self] }
        set { self[SparkleFocusedAppStateKey.self] = newValue }
    }
}

private struct SparkleWindowRootView: View {
    @StateObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        _appState = StateObject(
            wrappedValue: environment.makeWindowState(
                initialProfileID: environment.dequeueInitialProfile()
            )
        )
    }

    var body: some View {
        MainWindowView(appState: appState)
            .frame(minWidth: 960, minHeight: 600)
            .focusedSceneValue(\.activeAppState, appState)
            .onAppear {
                let windowSignpostID = SparkleSignposts.launch.makeSignpostID()
                let windowState = SparkleSignposts.launch.beginInterval("WindowConfiguration", id: windowSignpostID)
                appState.onOpenProfileInNewWindow = { [environment] profileID in
                    environment.enqueueInitialProfile(profileID)
                    openWindow(id: "main")
                }
                SparkleSignposts.launch.endInterval("WindowConfiguration", windowState)
            }
            .task {
                await appState.bootstrap()
                if let profileID = appState.initialProfileIDForWindow {
                    appState.initialProfileIDForWindow = nil
                    if let match = appState.profiles.first(where: { $0.id == profileID }) {
                        await appState.connect(profile: match, openInNewTab: false)
                    }
                }
            }
    }
}

private struct SparkleAppCommands: Commands {
    @FocusedValue(\.activeAppState) private var focusedAppState: AppState?
    let fallbackState: AppState

    private var activeState: AppState {
        focusedAppState ?? fallbackState
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(activeState.strings.t("nav.about")) {
                activeState.openAboutWindow()
            }
        }

        CommandGroup(after: .appInfo) {
            Button(activeState.strings.t("prefs.checkNow")) {
                Task { await activeState.checkForUpdates(manual: true) }
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button(activeState.strings.t("nav.settings")) {
                activeState.openPreferencesWindow()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(after: .newItem) {
            Button(activeState.strings.t("tabs.closeTab")) {
                handleCloseActiveTabOrWindow()
            }
            .keyboardShortcut("w", modifiers: [.command])
        }

        CommandMenu("Commander") {
            Button(activeState.strings.t("tabs.newTab")) {
                _ = activeState.openNewWorkspaceTab()
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button(activeState.strings.t("tabs.duplicateTab")) {
                let targetID = activeState.activeTabID
                Task { await activeState.duplicateWorkspaceTab(id: targetID) }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button(activeState.strings.t("tabs.previousTab")) {
                activeState.selectAdjacentWorkspaceTab(delta: -1)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(activeState.workspaceTabs.count < 2)

            Button(activeState.strings.t("tabs.nextTab")) {
                activeState.selectAdjacentWorkspaceTab(delta: 1)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(activeState.workspaceTabs.count < 2)

            Divider()

            Button(activeState.strings.t("nav.upload")) {
                Task { await activeState.enqueueSelectedTransfer() }
            }
            .keyboardShortcut("u", modifiers: [.command])
            .disabled(activeState.currentSession == nil)

            Button(activeState.strings.newFolder) {
                activeState.promptCreateFolderShortcut()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button(activeState.strings.t("nav.editor")) {
                activeState.openInternalEditorWindow()
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button(activeState.strings.t("nav.terminal")) {
                Task { await activeState.toggleTerminalDrawerForActiveTab() }
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(activeState.currentSession?.sshClient == nil && !activeState.isTerminalVisible)

            Button(activeState.strings.t("nav.standaloneTerminal")) {
                activeState.openStandaloneTerminal()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Button(activeState.strings.t("activityLog.title")) {
                activeState.isActivityLogVisible.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Button(activeState.strings.synchronize) {
                activeState.isShowingSyncSheet = true
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(activeState.currentSession == nil || !activeState.featureFlags.isSyncEnabled)

            Button(activeState.strings.t("common.refresh")) {
                Task {
                    if activeState.activePane == .left {
                        await activeState.refreshLocalDirectory(activeState.localCurrentURL)
                    } else {
                        await activeState.refreshRemoteDirectory()
                    }
                }
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button(activeState.strings.t("commander.switchPane")) {
                activeState.switchCommanderPaneWithFocus()
            }
            .keyboardShortcut("\\", modifiers: [.command])
        }

        CommandMenu(activeState.strings.t("nav.switchLanguage")) {
            ForEach(activeState.availableLocales) { locale in
                Button {
                    activeState.selectLocale(code: locale.code)
                } label: {
                    if activeState.activeLocaleCode == locale.code {
                        Label("\(locale.displayName) (\(locale.code.uppercased()))", systemImage: "checkmark")
                    } else {
                        Text("\(locale.displayName) (\(locale.code.uppercased()))")
                    }
                }
            }
        }
    }

    @MainActor
    private func handleCloseActiveTabOrWindow() {
        guard let keyWindow = NSApp.keyWindow else { return }
        if keyWindow.identifier?.rawValue == "sparkle.editor" {
            let state = focusedAppState ?? fallbackState
            if state.editorManager.documents.count > 1,
               let activeDocID = state.editorManager.activeDocumentID {
                state.editorManager.closeDocument(id: activeDocID)
                return
            }
            keyWindow.performClose(nil)
            return
        }
        if let focused = focusedAppState,
           keyWindow.attachedSheet == nil,
           focused.workspaceTabs.count > 1,
           isMainWorkspaceWindow(keyWindow, appState: focused) {
            closeActiveWorkspaceTab(in: focused)
            return
        }
        keyWindow.performClose(nil)
    }

    @MainActor
    private func isMainWorkspaceWindow(_ keyWindow: NSWindow, appState: AppState) -> Bool {
        if let hostWindow = appState.hostWindow {
            return keyWindow === hostWindow
        }
        return keyWindow.title.hasPrefix("SparkleSFTP")
            || keyWindow.identifier?.rawValue.contains("main") == true
    }

    @MainActor
    private func closeActiveWorkspaceTab(in focused: AppState) {
        let outcome = focused.closeWorkspaceTabSync(id: focused.activeTabID)
        guard outcome.removedSessionID != nil || outcome.pendingLocalRefresh != nil else { return }
        Task {
            if let removedID = outcome.removedSessionID {
                await focused.disconnect(sessionID: removedID)
            }
            if let localURL = outcome.pendingLocalRefresh {
                await focused.refreshLocalDirectory(localURL, recordHistory: false)
            }
        }
    }
}

@main
struct SparkleSFTPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppEnvironment()

    var body: some Scene {
        WindowGroup("SparkleSFTP", id: "main") {
            SparkleWindowRootView(environment: environment)
                .onAppear {
                    wireDelegateShutdownHooks()
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            SparkleAppCommands(fallbackState: environment.settingsFallbackState)
        }
    }

    private func wireDelegateShutdownHooks() {
        appDelegate.onPrepareFastShutdown = { [environment] in
            environment.prepareFastShutdown()
        }
        appDelegate.onShouldDelayTermination = { [environment] in
            environment.hasActiveAsyncCleanup
        }
        appDelegate.onTerminateCleanup = { [environment] in
            await environment.shutdown()
        }
    }
}
