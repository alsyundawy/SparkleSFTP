import SparkleFeatures
import SwiftUI

@main
struct SparkleSFTPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    private let environment: AppEnvironment

    init() {
        let env = AppEnvironment()
        environment = env
        _appState = StateObject(wrappedValue: env.appState)
    }

    var body: some Scene {
        WindowGroup("SparkleSFTP") {
            MainWindowView(appState: appState)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear {
                    appDelegate.onPrepareFastShutdown = { [appState] in
                        appState.prepareFastShutdown()
                    }
                    appDelegate.onShouldDelayTermination = { [appState] in
                        appState.hasActiveAsyncCleanup
                    }
                    appDelegate.onTerminateCleanup = { [environment] in
                        await environment.shutdown()
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(appState.strings.t("nav.about")) {
                    appState.openAboutWindow()
                }
            }

            CommandGroup(after: .appInfo) {
                Button(appState.strings.t("prefs.checkNow")) {
                    Task { await appState.checkForUpdates(manual: true) }
                }
            }

            CommandMenu("Commander") {
                Button(appState.strings.t("nav.upload")) {
                    Task { await appState.enqueueSelectedTransfer() }
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button(appState.strings.t("nav.editor")) {
                    appState.openInternalEditorWindow()
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button(appState.strings.t("nav.terminal")) {
                    Task { await appState.openTerminalTab() }
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button(appState.strings.t("common.refresh")) {
                    Task {
                        if appState.activePane == .left {
                            await appState.refreshLocalDirectory(appState.localCurrentURL)
                        } else {
                            await appState.refreshRemoteDirectory()
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Switch Commander Pane") {
                    appState.switchActivePane()
                }
                .keyboardShortcut("\t", modifiers: [])
            }
        }

        Settings {
            PreferencesView(appState: appState)
        }
    }
}
