import Foundation
import SparkleCore
import SparkleSecurity

extension AppState {
    public func openLocalFileInInternalEditor(_ file: RemoteFile) {
        guard !file.isDirectory else { return }
        let url = URL(fileURLWithPath: file.path.rawValue)
        do {
            try editorManager.openLocalFile(at: url)
            editorWindowController.present(appState: self)
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    public func openRemoteFileInInternalEditor(_ file: RemoteFile) async {
        guard let session = currentSession, !file.isDirectory else { return }
        do {
            let tempDir = try SecureTempDirectory.createIsolatedWorkingDirectory(prefix: "SparkleNotepad")
            let localCopy = try PathValidator.safeLocalDestination(filename: file.name, baseDirectory: tempDir)
            try await session.service.fileSystem.download(from: file.path, to: localCopy) { _ in }
            try editorManager.openRemoteDocument(
                EditorSessionManager.RemoteOpenSpec(
                    title: file.name,
                    localStagingURL: localCopy,
                    stagingTempDir: tempDir,
                    profileID: session.profile.id,
                    host: session.profile.host,
                    remotePath: file.path
                )
            )
            editorWindowController.present(appState: self)
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    public func openInternalEditorWindow() {
        editorManager.ensureAtLeastOneDocument()
        editorWindowController.present(appState: self)
    }

    func saveActiveEditorDocument() async {
        guard let doc = editorManager.activeDocument, !doc.isReadOnly else { return }
        let normalized = EditorLineEnding.normalize(doc.content, to: doc.lineEnding)
        let encoded = doc.encoding.encode(normalized)

        guard let localURL = doc.localURL else { return }
        let savedText = doc.content
        do {
            editorManager.updateDocument(id: doc.id) { edited in
                edited.isSaving = true
                if doc.isRemote {
                    edited.syncStatusKey = "editor.statusUploading"
                }
            }
            try encoded.write(to: localURL, options: [.atomic])

            if let remotePath = doc.remotePath, let profileID = doc.remoteProfileID {
                let remoteFS = try resolveRemoteFileSystem(for: profileID)
                try await remoteFS.upload(from: localURL, to: remotePath) { _ in }
                if currentSession?.profile.id == profileID {
                    await refreshRemoteDirectory(recordHistory: false)
                }
                editorManager.updateDocument(id: doc.id) { edited in
                    edited.savedContent = savedText
                    edited.isSaving = false
                    edited.syncStatusKey = "editor.statusUploaded"
                }
            } else {
                await refreshLocalDirectory(localCurrentURL, recordHistory: false)
                editorManager.updateDocument(id: doc.id) { edited in
                    edited.savedContent = savedText
                    edited.isSaving = false
                    edited.syncStatusKey = "editor.statusSaved"
                }
            }
        } catch {
            editorManager.updateDocument(id: doc.id) { edited in
                edited.isSaving = false
                edited.syncStatusKey = "transfers.transferFailed"
            }
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    func saveActiveEditorDocumentAs(url: URL) async {
        guard let doc = editorManager.activeDocument else { return }
        let didScope = url.startAccessingSecurityScopedResource()
        defer {
            if didScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let normalized = EditorLineEnding.normalize(doc.content, to: doc.lineEnding)
        let encoded = doc.encoding.encode(normalized)
        do {
            try encoded.write(to: url, options: [.atomic])
            editorManager.updateDocument(id: doc.id) { edited in
                edited.title = url.lastPathComponent
                edited.localURL = url
                edited.remotePath = nil
                edited.remoteProfileID = nil
                edited.remoteHost = nil
                edited.savedContent = doc.content
                edited.syncStatusKey = "editor.statusSaved"
            }
            await refreshLocalDirectory(localCurrentURL, recordHistory: false)
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    func reloadActiveEditorDocument() async {
        guard let doc = editorManager.activeDocument else { return }
        do {
            if let remotePath = doc.remotePath, let profileID = doc.remoteProfileID, let localURL = doc.localURL {
                let remoteFS = try resolveRemoteFileSystem(for: profileID)
                try await remoteFS.download(from: remotePath, to: localURL) { _ in }
            }
            guard let localURL = doc.localURL else { return }
            let data = try Data(contentsOf: localURL)
            let decoded = EditorTextEncoding.decode(data)
            let lfText = EditorLineEnding.normalize(decoded.text, to: .unixLF)
            editorManager.updateDocument(id: doc.id) { edited in
                edited.content = lfText
                edited.savedContent = lfText
                edited.encoding = decoded.encoding
                edited.lineEnding = EditorLineEnding.detect(in: decoded.text)
                edited.syncStatusKey = doc.isRemote ? "editor.statusUploaded" : "editor.statusSaved"
            }
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }
}
