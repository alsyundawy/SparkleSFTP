import AppKit
import UserNotifications

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminateCleanup: (() async -> Void)?

    public func applicationDidFinishLaunching(_: Notification) {
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        configureApplicationIcon()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func configureApplicationIcon() {
        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "png")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        if let iconURL, let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    public func applicationWillTerminate(_: Notification) {
        guard let cleanup = onTerminateCleanup else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await cleanup()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }
}
