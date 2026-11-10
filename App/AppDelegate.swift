import AppKit
import UserNotifications

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminateCleanup: (() async -> Void)?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        guard let cleanup = onTerminateCleanup else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await cleanup()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }
}
