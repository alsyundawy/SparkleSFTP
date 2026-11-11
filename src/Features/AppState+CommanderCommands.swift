import AppKit
import Foundation
import SparkleCore
import SparkleFileManager
import SparkleNetworking
import SparkleSecurity
import SparkleTransferEngine

public extension AppState {
    func copyItemsToClipboard(files: [RemoteFile], isLocal: Bool) {
        guard !files.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if isLocal {
            let urls = files.map { URL(fileURLWithPath: $0.path.rawValue) as NSURL }
            pasteboard.writeObjects(urls)
        } else {
            pasteboard.setString(files.map(\.path.rawValue).joined(separator: "\n"), forType: .string)
        }
        statusBannerMessage = "\(strings.t("pane.copiedClipboard")) (\(files.count))"
    }

    func copyFileNamesToClipboard(files: [RemoteFile], includePaths: Bool) {
        guard !files.isEmpty else { return }
        let text = files.map { includePaths ? $0.path.rawValue : $0.name }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusBannerMessage = "\(strings.t("pane.copiedClipboard")) (\(files.count))"
    }

    func insertFileNamesToCommandLine(files: [RemoteFile], useFullPath: Bool) async {
        guard !files.isEmpty else { return }
        let quotedTokens = files.compactMap { file -> String? in
            let raw = useFullPath ? file.path.rawValue : file.name
            return try? PathValidator.escapePOSIXSingleQuoted(raw)
        }
        guard !quotedTokens.isEmpty else { return }
        let textToInsert = quotedTokens.joined(separator: " ") + " "

        let targetTabID = activeTabID
        if terminalManager.session(forWorkspaceTabID: targetTabID) == nil {
            if currentSession?.sshClient != nil {
                await openTerminalTab()
            } else {
                statusBannerMessage = strings.t("nav.noActivePTY")
                return
            }
        }
        if let termSession = terminalManager.session(forWorkspaceTabID: targetTabID) {
            terminalManager.selectedSessionID = termSession.id
            setActiveTabTerminalVisibility(true)
            termSession.insertCommandText(textToInsert)
            statusBannerMessage = strings.t("pane.insertedCommandLine")
        }
    }

    func openInExternalEditor(file: RemoteFile?, isLocal: Bool) async {
        guard let file, !file.isDirectory else { return }
        if isLocal {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.path.rawValue))
            statusBannerMessage = "\(strings.t("pane.openedExternal")): \(file.name)"
        } else {
            await openRemoteFileInEditor(file)
        }
    }

    func showInFinder(file: RemoteFile?) {
        let urls: [URL] = if let file {
            [URL(fileURLWithPath: file.path.rawValue)]
        } else {
            [localCurrentURL]
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func compressAndUploadLocalFiles(_ files: [RemoteFile]) async {
        guard let session = currentSession, !files.isEmpty else { return }
        do {
            let tempDir = try SecureTempDirectory.createIsolatedWorkingDirectory(prefix: "SparkleGz")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let archiveSpec = try await buildCompressedUploadArtifact(
                files: files,
                in: tempDir,
                localRootPath: localCurrentURL.path
            )
            let remoteDest = try session.currentRemotePath.appending(archiveSpec.archiveName)
            try await session.service.fileSystem.upload(from: archiveSpec.archiveURL, to: remoteDest) { _ in }
            await refreshRemoteDirectory(recordHistory: false)
            statusBannerMessage = "\(strings.t("pane.compressedUploaded")): \(archiveSpec.archiveName)"
        } catch {
            reportNonCancellationError(error)
        }
    }

    private func buildCompressedUploadArtifact(
        files: [RemoteFile],
        in tempDir: URL,
        localRootPath: String
    ) async throws -> (archiveName: String, archiveURL: URL) {
        if files.count == 1, let single = files.first, !single.isDirectory {
            let sourceURL = URL(fileURLWithPath: single.path.rawValue)
            let archiveName = "\(single.name).gz"
            let archiveURL = try PathValidator.safeLocalDestination(filename: archiveName, baseDirectory: tempDir)
            try await Task.detached(priority: .userInitiated) {
                let plainData = try Data(contentsOf: sourceURL)
                let gzData = try ZlibCompressionCodec.compress(plainData, level: 6, format: .gzip)
                try gzData.write(to: archiveURL, options: [.atomic])
            }.value
            return (archiveName, archiveURL)
        }

        let baseName = files.first?.name ?? "archive"
        let archiveName = "\(baseName).tar.gz"
        let archiveURL = try PathValidator.safeLocalDestination(filename: archiveName, baseDirectory: tempDir)
        let fileNames = files.map(\.name)
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-czf", archiveURL.path, "-C", localRootPath, "--"] + fileNames
            let pipe = Pipe()
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let errText = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw AppError.transferFailed(reason: "tar failed (\(process.terminationStatus)): \(errText)")
            }
        }.value
        return (archiveName, archiveURL)
    }

    func verifySHA256Checksum(for file: RemoteFile, isLocal: Bool) async {
        guard !file.isDirectory else { return }
        do {
            if isLocal {
                let url = URL(fileURLWithPath: file.path.rawValue)
                let hex = try await SHA256Verifier.computeHexDigest(of: url)
                pendingChecksumReport = FileChecksumReport(
                    filename: file.name,
                    path: file.path.rawValue,
                    isLocal: true,
                    sha256: hex,
                    byteCount: file.size,
                    sourceNote: "Local CryptoKit SHA-256"
                )
            } else {
                let digest = try await computeRemoteSHA256(file: file)
                pendingChecksumReport = FileChecksumReport(
                    filename: file.name,
                    path: file.path.rawValue,
                    isLocal: false,
                    sha256: digest.hex,
                    byteCount: file.size,
                    sourceNote: digest.note
                )
            }
        } catch {
            reportNonCancellationError(error)
        }
    }

    func computeRemoteSHA256(file: RemoteFile) async throws -> (hex: String, note: String) {
        guard let session = currentSession else { throw AppError.notConnected }
        if let sshClient = session.sshClient {
            let quoted = try PathValidator.escapePOSIXSingleQuoted(file.path.rawValue)
            let cmd = "LC_ALL=C sha256sum \(quoted) 2>/dev/null || LC_ALL=C shasum -a 256 \(quoted) 2>/dev/null"
            if let out = try? await sshClient.executeCommand(cmd, timeoutSeconds: 5),
               out.exitCode == 0 {
                let firstToken = out.stdout
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: \.isWhitespace)
                    .first
                    .map(String.init) ?? ""
                if firstToken.count == 64 {
                    return (firstToken.lowercased(), "Remote SSH (\(cmd.contains("sha256sum") ? "sha256" : "shasum"))")
                }
            }
        }

        let tempDir = try SecureTempDirectory.createIsolatedWorkingDirectory(prefix: "SparkleHash")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let localTemp = try PathValidator.safeLocalDestination(filename: file.name, baseDirectory: tempDir)
        try await session.service.fileSystem.download(from: file.path, to: localTemp) { _ in }
        let hex = try await SHA256Verifier.computeHexDigest(of: localTemp)
        return (hex, "Streamed & Hashed Locally")
    }

    func compareWithOppositePane(file: RemoteFile, isLocal: Bool) async {
        guard !file.isDirectory, let session = currentSession else { return }
        let localMatch: RemoteFile? = isLocal
            ? file
            : localFiles.allFiles.first { $0.name == file.name && !$0.isDirectory }
        let remoteMatch: RemoteFile? = isLocal
            ? session.remoteFiles.allFiles.first { $0.name == file.name && !$0.isDirectory }
            : file

        let localHex: String? = if let localMatch {
            try? await SHA256Verifier.computeHexDigest(of: URL(fileURLWithPath: localMatch.path.rawValue))
        } else {
            nil
        }
        let remoteHex: String? = if let remoteMatch {
            await (try? computeRemoteSHA256(file: remoteMatch))?.hex
        } else {
            nil
        }

        let verdictKey = if localMatch == nil {
            "compare.missingLocal"
        } else if remoteMatch == nil {
            "compare.missingRemote"
        } else if let lHex = localHex, let rHex = remoteHex, lHex == rHex {
            "compare.identical"
        } else {
            "compare.different"
        }

        pendingComparisonReport = FileComparisonReport(
            filename: file.name,
            localItem: localMatch,
            remoteItem: remoteMatch,
            localSHA256: localHex,
            remoteSHA256: remoteHex,
            verdictKey: verdictKey
        )
    }

    func performCopyOrMove(
        request: CopyMoveRequest,
        destinationDir: String,
        transferToOppositePane: Bool
    ) async {
        let trimmedDest = destinationDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDest.isEmpty else { return }
        do {
            if transferToOppositePane, let session = currentSession {
                try await performCrossPaneCopyOrMove(
                    request: request,
                    destinationDir: trimmedDest,
                    session: session
                )
            } else {
                try await performSameSideCopyOrMove(request: request, destinationDir: trimmedDest)
            }
            if request.isLocal || transferToOppositePane {
                await refreshLocalDirectory(localCurrentURL, recordHistory: false)
            }
            if !request.isLocal || transferToOppositePane {
                await refreshRemoteDirectory(recordHistory: false)
            }
        } catch {
            reportNonCancellationError(error)
        }
    }

    private func performCrossPaneCopyOrMove(
        request: CopyMoveRequest,
        destinationDir: String,
        session: ActiveSessionModel
    ) async throws {
        if request.isLocal {
            let remoteDir = RemotePath(rawValue: destinationDir)
            for item in request.files {
                let localURL = URL(fileURLWithPath: item.path.rawValue)
                let remoteDest = try remoteDir.appending(item.name)
                if item.isDirectory {
                    await enqueueLocalItemUpload(url: localURL, isDirectory: true, into: session)
                } else {
                    try await session.service.fileSystem.upload(from: localURL, to: remoteDest) { _ in }
                    if request.isMove {
                        try await localFileService.delete(itemAt: localURL)
                    }
                }
            }
        } else {
            let localDirURL = URL(fileURLWithPath: destinationDir)
            for item in request.files {
                let localDest = try PathValidator.safeLocalDestination(
                    filename: item.name,
                    baseDirectory: localDirURL,
                    symlinkTarget: item.symlinkTarget
                )
                if item.isDirectory {
                    await enqueueRemoteItemDownload(file: item, localParentDir: localDirURL, session: session)
                } else {
                    try await session.service.fileSystem.download(from: item.path, to: localDest) { _ in }
                    if request.isMove {
                        try await session.service.fileSystem.delete(at: item.path, isDirectory: item.isDirectory)
                    }
                }
            }
        }
    }

    private func performSameSideCopyOrMove(request: CopyMoveRequest, destinationDir: String) async throws {
        if request.isLocal {
            let destURL = URL(fileURLWithPath: destinationDir)
            for item in request.files {
                let srcURL = URL(fileURLWithPath: item.path.rawValue)
                let targetURL = try PathValidator.safeLocalDestination(
                    filename: item.name,
                    baseDirectory: destURL,
                    symlinkTarget: item.symlinkTarget
                )
                if request.isMove {
                    try FileManager.default.moveItem(at: srcURL, to: targetURL)
                } else {
                    try FileManager.default.copyItem(at: srcURL, to: targetURL)
                }
            }
            return
        }

        guard let session = currentSession else { throw AppError.notConnected }
        let destRemoteDir = RemotePath(rawValue: destinationDir)
        for item in request.files {
            let targetRemote = try destRemoteDir.appending(item.name)
            if request.isMove {
                try await session.service.fileSystem.rename(from: item.path, to: targetRemote)
            } else if let sshClient = session.sshClient {
                let srcQ = try PathValidator.escapePOSIXSingleQuoted(item.path.rawValue)
                let dstQ = try PathValidator.escapePOSIXSingleQuoted(targetRemote.rawValue)
                let out = try await sshClient.executeCommand("LC_ALL=C cp -r \(srcQ) \(dstQ)", timeoutSeconds: 30)
                if out.exitCode != 0 {
                    throw AppError.protocolError(code: out.exitCode, message: out.stderr)
                }
            } else {
                let tempDir = try SecureTempDirectory.createIsolatedWorkingDirectory(prefix: "SparkleCopy")
                defer { try? FileManager.default.removeItem(at: tempDir) }
                let stage = try PathValidator.safeLocalDestination(filename: item.name, baseDirectory: tempDir)
                try await session.service.fileSystem.download(from: item.path, to: stage) { _ in }
                try await session.service.fileSystem.upload(from: stage, to: targetRemote) { _ in }
            }
        }
    }

    func executeCustomRemoteCommand(
        template: String,
        request: CustomCommandRequest
    ) async throws -> CustomCommandResult {
        guard let sshClient = currentSession?.sshClient else {
            throw AppError.notConnected
        }
        let quotedFile = try PathValidator.escapePOSIXSingleQuoted(request.targetFile?.name ?? "")
        let quotedPath = try PathValidator.escapePOSIXSingleQuoted(
            request.targetFile?.path.rawValue ?? request.currentRemoteDir
        )
        let quotedDir = try PathValidator.escapePOSIXSingleQuoted(request.currentRemoteDir)

        var rendered = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rendered.isEmpty else {
            throw AppError.transferFailed(reason: "Command cannot be empty")
        }
        rendered = rendered
            .replacingOccurrences(of: "{file}", with: quotedFile)
            .replacingOccurrences(of: "{path}", with: quotedPath)
            .replacingOccurrences(of: "{dir}", with: quotedDir)

        let fullCommand = "cd \(quotedDir) && \(rendered)"
        let output = try await sshClient.executeCommand(fullCommand, timeoutSeconds: 30)
        return CustomCommandResult(
            command: fullCommand,
            exitCode: output.exitCode,
            stdout: output.stdout,
            stderr: output.stderr
        )
    }
}
