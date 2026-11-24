import AppKit
import Foundation
import SparkleCore
import SparkleSecurity
import SparkleTransferEngine

extension AppState {
    func openInExternalEditor(file: RemoteFile?, isLocal: Bool) async {
        guard let file, !file.isDirectory else { return }
        if isLocal {
            let localURL = URL(fileURLWithPath: file.path.rawValue)
            openLocalWithExternalEditor(localURL: localURL, filename: file.name)
        } else {
            await openRemoteInExternalEditor(file: file)
        }
    }

    private func openLocalWithExternalEditor(localURL: URL, filename: String) {
        let installed = ExternalEditorDetector.detectInstalledEditors()
        let savedPath = extendedSettings.editorExternalAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preferred = ExternalEditorDetector.resolveEditor(
               savedPath: savedPath.isEmpty ? nil : savedPath,
               available: installed
           ),
           let appURL = preferred.appURL {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([localURL], withApplicationAt: appURL, configuration: config)
        } else {
            NSWorkspace.shared.open(localURL)
        }
        statusBannerMessage = "\(strings.t("pane.openedExternal")): \(filename)"
    }

    private func openRemoteInExternalEditor(file: RemoteFile) async {
        guard let session = currentSession, !file.isDirectory else { return }
        let profileID = session.profile.id
        let host = session.profile.host
        let remotePath = file.path
        var stagingTempDir: URL?
        do {
            let tempDir = try SecureTempDirectory.createIsolatedWorkingDirectory(prefix: "SparkleExtEdit")
            stagingTempDir = tempDir
            let localCopy = try PathValidator.safeLocalDestination(filename: file.name, baseDirectory: tempDir)
            try await session.service.fileSystem.download(from: remotePath, to: localCopy) { _ in }
            let initialDigest = try await SHA256Verifier.computeHexDigest(of: localCopy)

            openLocalWithExternalEditor(localURL: localCopy, filename: file.name)
            watchEditedLocalFile(
                RemoteEditWatchRequest(
                    tempDir: tempDir,
                    localCopy: localCopy,
                    initialDigest: initialDigest,
                    profileID: profileID,
                    host: host,
                    remotePath: remotePath
                )
            )
            stagingTempDir = nil
        } catch {
            if let stagingTempDir {
                try? FileManager.default.removeItem(at: stagingTempDir)
            }
            reportNonCancellationError(error, asBannerOnly: true)
        }
    }
}
