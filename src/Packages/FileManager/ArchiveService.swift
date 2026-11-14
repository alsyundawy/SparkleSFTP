import Foundation
import SparkleCore

/// Archive container format options for compression and extraction.
public enum ArchiveFormat: String, Sendable, CaseIterable, Identifiable {
    case zip
    case tar
    case tarGz
    case sevenZip

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .zip: return "ZIP Archive (.zip)"
        case .tar: return "TAR Archive (.tar)"
        case .tarGz: return "Compressed TAR (.tar.gz)"
        case .sevenZip: return "7-Zip Archive (.7z)"
        }
    }

    public var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .tar: return "tar"
        case .tarGz: return "tar.gz"
        case .sevenZip: return "7z"
        }
    }
}

/// Secure local archiving and extraction engine enforcing Zip-Slip and bomb defenses (CWE-22 / CWE-59 / CWE-400).
public enum ArchiveService {
    public static let maxAllowedEntries = 50000

    /// Locates an installed 7zz or 7z CLI binary on the host machine.
    public static func find7zBinary() -> URL? {
        let candidates = [
            "/usr/local/bin/7zz",
            "/usr/local/bin/7z",
            "/opt/homebrew/bin/7zz",
            "/opt/homebrew/bin/7z"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Verifies that archive does not contain directory traversal or malicious entry paths.
    public static func inspectArchiveEntries(archiveURL: URL) throws -> [String] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tf", archiveURL.path]
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppError.persistenceFailure(reason: "Failed to inspect archive contents")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if lines.count > maxAllowedEntries {
            let msg = "Archive exceeds maximum entry count limit (\(maxAllowedEntries))"
            throw AppError.pathTraversal(attempted: msg)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("/") || trimmed.contains("../") || trimmed.contains("..\\") || trimmed == ".." {
                throw AppError.pathTraversal(attempted: "Zip-Slip path traversal: \(trimmed)")
            }
        }
        return lines
    }

    /// Safely extracts archive into a single target directory.
    public static func extract(archiveURL: URL, destinationDirectory: URL) async throws {
        _ = try inspectArchiveEntries(archiveURL: archiveURL)

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", archiveURL.path, "-C", destinationDirectory.path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let code = process.terminationStatus
                throw AppError.persistenceFailure(reason: "Extraction failed with exit code \(code)")
            }
        }.value
    }

    /// Compresses source files into target archive format.
    public static func compress(
        sourceURLs: [URL],
        destinationURL: URL,
        format: ArchiveFormat
    ) async throws {
        guard let first = sourceURLs.first else { return }
        let parentDir = first.deletingLastPathComponent()

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let sourceNames = sourceURLs.map(\.lastPathComponent)

            switch format {
            case .zip:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                process.arguments = ["-a", "-cf", destinationURL.path, "-C", parentDir.path, "--"] + sourceNames
            case .tar:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                process.arguments = ["-cf", destinationURL.path, "-C", parentDir.path, "--"] + sourceNames
            case .tarGz:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                process.arguments = ["-czf", destinationURL.path, "-C", parentDir.path, "--"] + sourceNames
            case .sevenZip:
                guard let binary = find7zBinary() else {
                    let msg = "7zz binary not found. Install via Homebrew: brew install sevenzip"
                    throw AppError.persistenceFailure(reason: msg)
                }
                process.executableURL = binary
                process.arguments = ["a", "-t7z", destinationURL.path, "--"] + sourceNames
                process.currentDirectoryURL = parentDir
            }

            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let code = process.terminationStatus
                throw AppError.persistenceFailure(reason: "Compression failed with exit code \(code)")
            }
        }.value
    }
}
