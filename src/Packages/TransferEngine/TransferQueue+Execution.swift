import Foundation
import SparkleCore
import SparkleSecurity

private final class ProgressSequenceBox: @unchecked Sendable { // JUSTIFICATION: NSLock serializes sequence counter.
    private let lock = NSLock()
    private var nextValue: UInt64 = 1

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let val = nextValue
        nextValue &+= 1
        return val
    }
}

struct DownloadFlowRequest: Sendable {
    let metadata: TransferTaskMetadata
    let remoteFS: any RemoteFileSystem
    let remotePath: RemotePath
    let partialURL: URL
    let finalDest: URL
    let offset: Int64
    let resolvedPermissions: UInt32?
}

struct UploadTransferAttemptRequest: Sendable {
    let metadata: TransferTaskMetadata
    let remoteFS: any RemoteFileSystem
    let localURL: URL
    let localSize: Int64
    let localModified: Date?
    let targetPath: RemotePath
    let offset: Int64
    let renameFinalTarget: RemotePath?
    let resolvedPermissions: UInt32?
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

        let prep = try await prepareDownloadPartial(
            metadata: metadata,
            remotePath: remotePath,
            localURL: localURL,
            remoteFS: remoteFS
        )
        guard let plan = try await resolveConflictDestination(
            DownloadConflictRequest(
                metadata: metadata,
                safeDest: prep.safeDest,
                partialURL: prep.partialURL,
                baseDir: prep.baseDir,
                remoteMeta: prep.remoteMeta
            )
        ) else {
            try? FileManager.default.removeItem(at: prep.partialURL)
            skippedIDs.insert(metadata.id)
            return
        }

        let effectiveOffset = prep.existingOffset > 0 ? prep.existingOffset : plan.resumeOffset
        let resolvedPerms = metadata.sourcePermissions ?? prep.remoteMeta?.permissions
        let request = DownloadFlowRequest(
            metadata: metadata,
            remoteFS: remoteFS,
            remotePath: remotePath,
            partialURL: prep.partialURL,
            finalDest: plan.destination,
            offset: effectiveOffset,
            resolvedPermissions: resolvedPerms
        )
        try await executeDownloadFlow(request)
    }

    func resolveDownloadOffset(
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

    private func performUploadAttempt(
        metadata: TransferTaskMetadata,
        profileID: UUID,
        localURL: URL,
        remotePath: RemotePath
    ) async throws {
        let remoteFS = try await fileSystemResolver(profileID)
        guard isStillActive(id: metadata.id) else { throw CancellationError() }

        let localAttrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let localSize = (localAttrs[.size] as? NSNumber)?.int64Value ?? 0
        let localModified = localAttrs[.modificationDate] as? Date
        let localPerms = (localAttrs[.posixPermissions] as? NSNumber)?.uint32Value
        let resolvedPerms = metadata.sourcePermissions ?? localPerms

        let conflictReq = UploadConflictRequest(
            metadata: metadata,
            localURL: localURL,
            localSize: localSize,
            localModified: localModified,
            remotePath: remotePath,
            remoteFS: remoteFS
        )
        guard let plan = try await resolveRemoteUploadDestination(conflictReq) else {
            skippedIDs.insert(metadata.id)
            return
        }

        let request = makeUploadAttemptRequest(
            plan: plan,
            conflictRequest: conflictReq,
            resolvedPermissions: resolvedPerms
        )
        let resolvedRequest: UploadTransferAttemptRequest = if plan.resumeDirectOffset != nil {
            request
        } else {
            await withResolvedTempOffset(request)
        }
        try await executeUploadTransfer(resolvedRequest)
    }

    private func makeUploadAttemptRequest(
        plan: UploadConflictPlan,
        conflictRequest: UploadConflictRequest,
        resolvedPermissions: UInt32?
    ) -> UploadTransferAttemptRequest {
        if let resumeOffset = plan.resumeDirectOffset {
            return UploadTransferAttemptRequest(
                metadata: conflictRequest.metadata,
                remoteFS: conflictRequest.remoteFS,
                localURL: conflictRequest.localURL,
                localSize: conflictRequest.localSize,
                localModified: conflictRequest.localModified,
                targetPath: plan.destination,
                offset: resumeOffset,
                renameFinalTarget: nil,
                resolvedPermissions: resolvedPermissions
            )
        }
        let tempName = ".\(plan.destination.filename).sparklesftp.\(conflictRequest.metadata.id.uuidString).part"
        let tempPath = (try? plan.destination.parent.appending(tempName)) ?? plan.destination
        return UploadTransferAttemptRequest(
            metadata: conflictRequest.metadata,
            remoteFS: conflictRequest.remoteFS,
            localURL: conflictRequest.localURL,
            localSize: conflictRequest.localSize,
            localModified: conflictRequest.localModified,
            targetPath: tempPath,
            offset: 0,
            renameFinalTarget: plan.destination,
            resolvedPermissions: resolvedPermissions
        )
    }

    private func withResolvedTempOffset(_ req: UploadTransferAttemptRequest) async -> UploadTransferAttemptRequest {
        let resumeOffset = await resolveUploadResumeOffset(
            taskID: req.metadata.id,
            tempRemotePath: req.targetPath,
            localSize: req.localSize,
            localModificationTime: req.localModified,
            remoteFS: req.remoteFS
        )
        guard resumeOffset > 0 else { return req }
        return UploadTransferAttemptRequest(
            metadata: req.metadata,
            remoteFS: req.remoteFS,
            localURL: req.localURL,
            localSize: req.localSize,
            localModified: req.localModified,
            targetPath: req.targetPath,
            offset: resumeOffset,
            renameFinalTarget: req.renameFinalTarget,
            resolvedPermissions: req.resolvedPermissions
        )
    }

    private func executeUploadTransfer(_ req: UploadTransferAttemptRequest) async throws {
        await recordCheckpointContext(
            id: req.metadata.id,
            remoteSize: req.localSize,
            remoteModificationTime: req.localModified,
            partialLocalPath: req.targetPath.rawValue
        )

        let seqBox = ProgressSequenceBox()
        try await req.remoteFS.upload(
            from: req.localURL,
            to: req.targetPath,
            offset: req.offset
        ) { [weak self] progress in
            let seq = seqBox.next()
            Task { [weak self] in
                await self?.handleProgress(id: req.metadata.id, sequence: seq, progress: progress)
            }
        }
        guard isStillActive(id: req.metadata.id) else {
            throw CancellationError()
        }

        await updateStatus(id: req.metadata.id, status: .verifying)
        let uploadedMeta = try await req.remoteFS.metadata(at: req.targetPath)
        guard uploadedMeta.size == req.localSize else {
            if req.renameFinalTarget != nil {
                try? await req.remoteFS.delete(at: req.targetPath, isDirectory: false)
            }
            throw AppError.partialTransferCorrupted(bytesExpected: req.localSize, bytesActual: uploadedMeta.size)
        }

        if let finalTarget = req.renameFinalTarget {
            await updateStatus(id: req.metadata.id, status: .finalizing)
            try await finalizeRemoteUploadRename(
                remoteFS: req.remoteFS,
                tempPath: req.targetPath,
                finalPath: finalTarget
            )
        }
        let completedTarget = req.renameFinalTarget ?? req.targetPath
        if let perms = req.resolvedPermissions, perms > 0 {
            try? await req.remoteFS.setPermissions(perms & 0o777, at: completedTarget)
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
              remotePartial.size <= localSize
        else {
            return 0
        }
        return remotePartial.size
    }

    private func executeDownloadFlow(_ request: DownloadFlowRequest) async throws {
        let taskID = request.metadata.id
        let seqBox = ProgressSequenceBox()
        try await request.remoteFS.download(
            from: request.remotePath,
            to: request.partialURL,
            offset: request.offset
        ) { [weak self] progress in
            let seq = seqBox.next()
            Task { [weak self] in
                await self?.handleProgress(id: taskID, sequence: seq, progress: progress)
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
        if let perms = request.resolvedPermissions, perms > 0 {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: perms & 0o777)],
                ofItemAtPath: request.finalDest.path
            )
        }
    }
}
