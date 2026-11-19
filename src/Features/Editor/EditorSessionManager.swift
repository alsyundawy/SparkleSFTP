import Foundation
import SparkleCore

/// Observable multi-tab session coordinator for the minimalist Notepad2 internal editor.
@MainActor
public final class EditorSessionManager: ObservableObject {
    @Published public var documents: [EditorDocument] = []
    @Published public var activeDocumentID: UUID?
    @Published public var findQuery = EditorFindQuery()
    @Published public var isFindBarVisible = false
    @Published public var isFindReplaceDialogVisible = false
    @Published public var isShowingGoToLine = false
    @Published public var wordWrap = true
    @Published public var showLineNumbers = true
    @Published public var showWhitespace = false
    @Published public var fontSize: CGFloat = 13

    private var untitledCounter = 1
    public let textViewProxy = NotepadTextViewProxy()

    public init() {}

    public var activeDocument: EditorDocument? {
        guard let activeDocumentID else { return documents.first }
        return documents.first { $0.id == activeDocumentID } ?? documents.first
    }

    public func ensureAtLeastOneDocument() {
        if documents.isEmpty {
            createUntitledDocument()
        }
    }

    public func createUntitledDocument() {
        let name = "Untitled-\(untitledCounter).txt"
        untitledCounter += 1
        let doc = EditorDocument(title: name, content: "", syntax: .plainText)
        documents.append(doc)
        activeDocumentID = doc.id
    }

    public func openLocalFile(at url: URL) throws {
        if let existing = documents.first(where: { $0.localURL?.standardizedFileURL == url.standardizedFileURL }) {
            activeDocumentID = existing.id
            return
        }
        let didScope = url.startAccessingSecurityScopedResource()
        defer {
            if didScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        let decoded = EditorTextEncoding.decode(data)
        let doc = EditorDocument(
            title: url.lastPathComponent,
            localURL: url,
            content: decoded.text,
            savedContent: decoded.text,
            encoding: decoded.encoding,
            lineEnding: EditorLineEnding.detect(in: decoded.text),
            syntax: .auto
        )
        documents.append(doc)
        activeDocumentID = doc.id
    }

    public struct RemoteOpenSpec: Sendable {
        public let title: String
        public let localStagingURL: URL
        public let stagingTempDir: URL
        public let profileID: UUID
        public let host: String
        public let remotePath: RemotePath

        public init(
            title: String,
            localStagingURL: URL,
            stagingTempDir: URL,
            profileID: UUID,
            host: String,
            remotePath: RemotePath
        ) {
            self.title = title
            self.localStagingURL = localStagingURL
            self.stagingTempDir = stagingTempDir
            self.profileID = profileID
            self.host = host
            self.remotePath = remotePath
        }
    }

    public func openRemoteDocument(_ spec: RemoteOpenSpec) throws {
        if let existing = documents.first(where: {
            $0.remoteProfileID == spec.profileID && $0.remotePath == spec.remotePath
        }) {
            activeDocumentID = existing.id
            return
        }
        let data = try Data(contentsOf: spec.localStagingURL)
        let decoded = EditorTextEncoding.decode(data)
        let doc = EditorDocument(
            title: spec.title,
            localURL: spec.localStagingURL,
            stagingTempDir: spec.stagingTempDir,
            remoteProfileID: spec.profileID,
            remoteHost: spec.host,
            remotePath: spec.remotePath,
            content: decoded.text,
            savedContent: decoded.text,
            encoding: decoded.encoding,
            lineEnding: EditorLineEnding.detect(in: decoded.text),
            syntax: .auto
        )
        documents.append(doc)
        activeDocumentID = doc.id
    }

    public func closeDocument(id: UUID) {
        if let doc = documents.first(where: { $0.id == id }), let tempDir = doc.stagingTempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        documents.removeAll { $0.id == id }
        if activeDocumentID == id {
            activeDocumentID = documents.last?.id
        }
    }

    public func updateDocument(id: UUID, _ transform: (inout EditorDocument) -> Void) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        var copy = documents[idx]
        transform(&copy)
        documents[idx] = copy
    }

    public func updateActiveDocument(_ transform: (inout EditorDocument) -> Void) {
        guard let activeID = activeDocument?.id else { return }
        updateDocument(id: activeID, transform)
    }

    public func applyTextTransform(_ kind: EditorTextTransformKind) {
        updateActiveDocument { doc in
            guard !doc.isReadOnly else { return }
            doc.content = EditorTextTransformKind.apply(kind, to: doc.content)
            doc.syncStatusKey = "editor.statusModified"
        }
    }

    public func zoomIn() {
        fontSize = min(32, fontSize + 1)
    }

    public func zoomOut() {
        fontSize = max(9, fontSize - 1)
    }

    public func zoomReset() {
        fontSize = 13
    }
}
