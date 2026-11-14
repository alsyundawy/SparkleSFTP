import Foundation
import SparkleCore

/// Flavor of rsync toolchain available on the system.
public enum RsyncFlavor: String, Sendable, Equatable {
    case gnuRsync
    case openRsync
    case unknown
}

/// Capability report for host rsync binary.
public struct RsyncCapability: Sendable, Equatable {
    public let isAvailable: Bool
    public let path: String
    public let versionString: String
    public let flavor: RsyncFlavor
    public let supportsProgress2: Bool

    public init(
        isAvailable: Bool = false,
        path: String = "",
        versionString: String = "",
        flavor: RsyncFlavor = .unknown,
        supportsProgress2: Bool = false
    ) {
        self.isAvailable = isAvailable
        self.path = path
        self.versionString = versionString
        self.flavor = flavor
        self.supportsProgress2 = supportsProgress2
    }
}

/// Service probing host rsync and generating safe command invocations (CWE-88).
public enum RsyncIntegrationService {
    /// Inspects rsync binary at given path or standard paths.
    public static func probe(customPath: String? = nil) -> RsyncCapability {
        let candidates = [
            customPath,
            "/usr/local/bin/rsync",
            "/opt/homebrew/bin/rsync",
            "/usr/bin/rsync"
        ].compactMap(\.self).filter { !$0.isEmpty }

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if let cap = inspectBinary(at: path) {
                return cap
            }
        }
        return RsyncCapability()
    }

    private static func inspectBinary(at path: String) -> RsyncCapability? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            let firstLine = output.components(separatedBy: .newlines).first ?? ""

            let isGNU = firstLine.lowercased().contains("rsync version 3")
            let isOpen = firstLine.lowercased().contains("openrsync")
            let flavor: RsyncFlavor = isGNU ? .gnuRsync : (isOpen ? .openRsync : .unknown)

            return RsyncCapability(
                isAvailable: true,
                path: path,
                versionString: firstLine,
                flavor: flavor,
                supportsProgress2: isGNU
            )
        } catch {
            return nil
        }
    }

    /// Constructs safe arguments for an rsync transfer, preventing argument injection (CWE-88).
    public static func buildArguments(
        capability: RsyncCapability,
        source: String,
        destination: String,
        delete: Bool = false
    ) -> [String] {
        var args = ["-avz"]
        if capability.supportsProgress2 {
            args.append("--info=progress2")
        }
        if delete {
            args.append("--delete")
        }
        args.append("--")
        args.append(source)
        args.append(destination)
        return args
    }
}
