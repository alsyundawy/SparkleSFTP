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
                    appDelegate.onTerminateCleanup = { [environment] in
                        await environment.shutdown()
                    }
                }
        }
        .commands {
            CommandMenu("Commander") {
                Button("Transfer Selected (F5)") {
                    Task { await appState.enqueueSelectedTransfer() }
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("Open SSH Terminal") {
                    Task { await appState.openTerminalTab() }
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Refresh Active Pane") {
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
