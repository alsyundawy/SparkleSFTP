import Crypto
import Foundation
import SparkleCore
import SparkleSecurity

extension TransferQueue {
    /// Resolves the verified upload resume offset with prefix block-level SHA-256 validation (Task 3.7 / T-151).
    func resolveUploadResumeOffset(request: UploadTransferAttemptRequest) async -> Int64 {
        let taskID = request.metadata.id
        guard let checkpoint = snapshots[taskID]?.checkpoint,
              checkpoint.remoteSize == request.localSize
        else {
            return 0
        }
        if let expectedTime = checkpoint.remoteModificationTime,
           let actualTime = request.localModified,
           abs(expectedTime.timeIntervalSince(actualTime)) > 1.0 {
            return 0
        }
        guard let remotePartial = try? await request.remoteFS.metadata(at: request.targetPath),
              remotePartial.size > 0,
              remotePartial.size <= request.localSize
        else {
            return 0
        }
        // Task 3.7: Verify prefix block checksum before resuming
        guard await verifyPrefixIntegrity(
            localURL: request.localURL,
            remotePath: request.targetPath,
            remoteFS: request.remoteFS
        ) else {
            return 0
        }
        let verifiedOffset = min(checkpoint.bytesTransferred, remotePartial.size)
        return verifiedOffset > 0 ? verifiedOffset : remotePartial.size
    }

    private func verifyPrefixIntegrity(
        localURL: URL,
        remotePath: RemotePath,
        remoteFS: any RemoteFileSystem
    ) async -> Bool {
        let tempPrefixURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sparkle_prefix_\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tempPrefixURL) }

        do {
            try await remoteFS.download(from: remotePath, to: tempPrefixURL, offset: 0) { _ in }
            guard let remoteData = try? Data(contentsOf: tempPrefixURL) else { return false }
            let compareLength = min(remoteData.count, 65_536)
            guard compareLength > 0 else { return true }

            let localHandle = try FileHandle(forReadingFrom: localURL)
            defer { try? localHandle.close() }
            guard let localPrefixData = try localHandle.read(upToCount: compareLength) else { return false }

            let remotePrefixSlice = remoteData.prefix(compareLength)
            return SHA256.hash(data: remotePrefixSlice) == SHA256.hash(data: localPrefixData)
        } catch {
            return false
        }
    }
}
