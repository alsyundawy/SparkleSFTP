import Foundation
import SparkleCore
import SparkleSecurity

struct DownloadFlowRequest: Sendable {
    let metadata: TransferTaskMetadata
    let remoteFS: any RemoteFileSystem
    let remotePath: RemotePath
    let partialURL: URL
    let finalDest: URL
    let offset: Int64
}

extension TransferQueue {
    func runWithRetry(metadata: TransferTaskMetadata) async throws {
        let maxAttempts = 3
        for attempt in 1 ... maxAttempts {
            try Task.checkCancellation()
            guard isStillActive(id: metadata.id) else { throw CancellationError() }

            do {
                try await performSingleAttempt(metadata: metadata)
                return
            } catch let appError as AppError where appError.isNonRetryableSecurityOrAuthError {
                throw appError
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt == maxAttempts {
                    throw error
                }
                let delaySeconds = 1 << (attempt - 1)
                try await Task.sleep(for: .seconds(delaySeconds))
            }
        }
    }

    private func performSingleAttempt(metadata: TransferTaskMetadata) async throws {
        await updateStatus(id: metadata.id, status: .connecting)
        guard isStillActive(id: metadata.id) else { throw CancellationError() }

        switch (metadata.direction, metadata.source, metadata.destination) {
        case let (.download, .remote(profileID, _, remotePath), .local(localURL)):
            try await performDownloadAttempt(
                metadata: metadata,
                profileID: profileID,
                remotePath: remotePath,
                localURL: localURL
            )
        case let (.upload, .local(localURL), .remote(profileID, _, remotePath)):
            try await performUploadAttempt(
                metadata: metadata,
                profileID: profileID,
                localURL: localURL,
                remotePath: remotePath
            )
        default:
            throw AppError.invalidConfiguration("Unsupported transfer endpoint combination")
        }
    }

    private func performDownloadAttempt(
        metadata: TransferTaskMetadata,
        profileID: UUID,
        remotePath: RemotePath,
        localURL: URL
    ) async throws {
        let remoteFS = try await fileSystemResolver(profileID)
        guard isStillActive(id: metadata.id) else { throw CancellationError() }

        let baseDir = localURL.deletingLastPathComponent()
        let safeDest = try PathValidator.safeLocalDestination(
            filename: localURL.lastPathComponent,
            baseDirectory: baseDir
        )
        let partialName = ".\(safeDest.lastPathComponent).sparklesftp.\(metadata.id.uuidString).part"
        let partialURL = baseDir.appendingPathComponent(partialName)

        let resumeOffset = try await resolveDownloadOffset(
            taskID: metadata.id,
            remotePath: remotePath,
            partialURL: partialURL,
            remoteFS: remoteFS
        )
        let remoteMeta = try? await remoteFS.metadata(at: remotePath)
        if resumeOffset == 0 {
            try? FileManager.default.removeItem(at: partialURL)
            await resetCheckpointBytes(id: metadata.id)
        }
        await recordCheckpointContext(
            id: metadata.id,
            remoteSize: remoteMeta?.size ?? metadata.totalBytes,
            remoteModificationTime: remoteMeta?.modificationTime,
            partialLocalPath: partialURL.path
        )

        guard let finalDest = try await resolveConflictDestination(
            metadata: metadata,
            safeDest: safeDest,
            baseDir: baseDir
        ) else {
            return
        }

        let request = DownloadFlowRequest(
            metadata: metadata,
            remoteFS: remoteFS,
            remotePath: remotePath,
            partialURL: partialURL,
            finalDest: finalDest,
            offset: resumeOffset
        )
        try await executeDownloadFlow(request)
    }

    private func resolveDownloadOffset(
        taskID: UUID,
        remotePath: RemotePath,
        partialURL: URL,
        remoteFS: any RemoteFileSystem
    ) async throws -> Int64 {
        guard let checkpoint = snapshots[taskID]?.checkpoint else { return 0 }
        let decision = try await ResumeValidator.validateDownloadResume(
            remotePath: remotePath,
            partialLocalURL: partialURL,
            checkpoint: checkpoint,
            remoteFS: remoteFS
        )
        if case let .resume(offset) = decision {
            return offset
        }
        return 0
    }

    private func resolveConflictDestination(
        metadata: TransferTaskMetadata,
        safeDest: URL,
        baseDir: URL
    ) async throws -> URL? {
        guard FileManager.default.fileExists(atPath: safeDest.path) else {
            return safeDest
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: safeDest.path)
        let existingSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let resolution = await conflictResolver.resolve(
            ConflictContext(
                taskID: metadata.id,
                destinationDisplayPath: safeDest.path,
                existingSize: existingSize,
                incomingSize: metadata.totalBytes
            ),
            originalFilename: safeDest.lastPathComponent,
            overridePolicy: metadata.conflictPolicyOverride
        )
        switch resolution {
        case .skip:
            return nil
        case .overwrite:
            return safeDest
        case let .rename(newName):
            return try PathValidator.safeLocalDestination(filename: newName, baseDirectory: baseDir)
        }
    }

    private func performUploadAttempt(
        metadata: TransferTaskMetadata,
        profileID: UUID,
        localURL: URL,
        remotePath: RemotePath
    ) async throws {
        let remoteFS = try await fileSystemResolver(profileID)
        guard isStillActive(id: metadata.id) else { throw CancellationError() }

        guard let finalRemotePath = try await resolveRemoteUploadDestination(
            metadata: metadata,
            remotePath: remotePath,
            remoteFS: remoteFS
        ) else {
            return
        }

        let tempRemoteName = ".\(finalRemotePath.filename).sparklesftp.\(metadata.id.uuidString).part"
        let tempRemotePath = try finalRemotePath.parent.appending(tempRemoteName)
        let localAttrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let localSize = (localAttrs[.size] as? NSNumber)?.int64Value ?? 0
        let localModified = localAttrs[.modificationDate] as? Date
        let uploadOffset = await resolveUploadResumeOffset(
            taskID: metadata.id,
            tempRemotePath: tempRemotePath,
            localSize: localSize,
            localModificationTime: localModified,
            remoteFS: remoteFS
        )
        await recordCheckpointContext(
            id: metadata.id,
            remoteSize: localSize,
            remoteModificationTime: localModified,
            partialLocalPath: tempRemotePath.rawValue
        )

        try await remoteFS.upload(from: localURL, to: tempRemotePath, offset: uploadOffset) { [weak self] progress in
            Task { [weak self] in
                await self?.handleProgress(id: metadata.id, progress: progress)
            }
        }
        guard isStillActive(id: metadata.id) else {
            throw CancellationError()
        }

        await updateStatus(id: metadata.id, status: .verifying)
        let uploadedMeta = try await remoteFS.metadata(at: tempRemotePath)
        guard uploadedMeta.size == localSize else {
            try? await remoteFS.delete(at: tempRemotePath, isDirectory: false)
            throw AppError.partialTransferCorrupted(bytesExpected: localSize, bytesActual: uploadedMeta.size)
        }

        await updateStatus(id: metadata.id, status: .finalizing)
        try await remoteFS.rename(from: tempRemotePath, to: finalRemotePath)
    }

    private func resolveRemoteUploadDestination(
        metadata: TransferTaskMetadata,
        remotePath: RemotePath,
        remoteFS: any RemoteFileSystem
    ) async throws -> RemotePath? {
        guard let existingMeta = try? await remoteFS.metadata(at: remotePath) else {
            return remotePath
        }
        let resolution = await conflictResolver.resolve(
            ConflictContext(
                taskID: metadata.id,
                destinationDisplayPath: remotePath.rawValue,
                existingSize: existingMeta.size,
                incomingSize: metadata.totalBytes
            ),
            originalFilename: remotePath.filename,
            overridePolicy: metadata.conflictPolicyOverride
        )
        switch resolution {
        case .skip:
            return nil
        case .overwrite:
            return remotePath
        case let .rename(newName):
            return try PathValidator.canonicalizeRemote(newName, relativeTo: remotePath.parent)
        }
    }

    private func resolveUploadResumeOffset(
        taskID: UUID,
        tempRemotePath: RemotePath,
        localSize: Int64,
        localModificationTime: Date?,
        remoteFS: any RemoteFileSystem
    ) async -> Int64 {
        guard let checkpoint = snapshots[taskID]?.checkpoint,
              checkpoint.bytesTransferred > 0,
              checkpoint.remoteSize == localSize
        else {
            return 0
        }
        if let expectedTime = checkpoint.remoteModificationTime,
           let actualTime = localModificationTime,
           abs(expectedTime.timeIntervalSince(actualTime)) > 1.0 {
            return 0
        }
        guard let remotePartial = try? await remoteFS.metadata(at: tempRemotePath),
              remotePartial.size > 0,
              remotePartial.size < localSize
        else {
            return 0
        }
        return remotePartial.size
    }

    private func executeDownloadFlow(_ request: DownloadFlowRequest) async throws {
        let taskID = request.metadata.id
        try await request.remoteFS.download(
            from: request.remotePath,
            to: request.partialURL,
            offset: request.offset
        ) { [weak self] progress in
            Task { [weak self] in
                await self?.handleProgress(id: taskID, progress: progress)
            }
        }
        guard isStillActive(id: taskID) else { throw CancellationError() }

        if let expectedSHA = request.metadata.expectedSHA256 {
            await updateStatus(id: taskID, status: .verifying)
            do {
                try await SHA256Verifier.verify(fileURL: request.partialURL, expectedHex: expectedSHA)
            } catch {
                try? FileManager.default.removeItem(at: request.partialURL)
                throw error
            }
        }

        guard isStillActive(id: taskID) else { throw CancellationError() }
        await updateStatus(id: taskID, status: .finalizing)
        if FileManager.default.fileExists(atPath: request.finalDest.path) {
            _ = try FileManager.default.replaceItemAt(request.finalDest, withItemAt: request.partialURL)
        } else {
            try FileManager.default.moveItem(at: request.partialURL, to: request.finalDest)
        }
    }
}
