import AppKit
import UserNotifications

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    var onPrepareFastShutdown: (() -> Void)?
    var onShouldDelayTermination: (() -> Bool)?
    var onTerminateCleanup: (() async -> Void)?
    private var didReplyTermination = false

    public func applicationDidFinishLaunching(_: Notification) {
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        configureApplicationIcon()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func configureApplicationIcon() {
        var iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "png")
        if iconURL == nil, Bundle.main.bundleURL.pathExtension != "app" {
            iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png")
                ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        }
        if let iconURL, let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        onPrepareFastShutdown?()
        guard let cleanup = onTerminateCleanup, onShouldDelayTermination?() == true else {
            return .terminateNow
        }

        didReplyTermination = false
        Task { @MainActor [weak self] in
            await cleanup()
            self?.finishDelayedTermination(sender)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.finishDelayedTermination(sender)
        }
        return .terminateLater
    }

    private func finishDelayedTermination(_ sender: NSApplication) {
        guard !didReplyTermination else { return }
        didReplyTermination = true
        sender.reply(toApplicationShouldTerminate: true)
    }
}
