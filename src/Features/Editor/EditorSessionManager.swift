import Foundation
import SparkleCore

/// Observable multi-tab session coordinator for the minimalist Notepad2 internal editor.
@MainActor
public final class EditorSessionManager: ObservableObject {
    @Published public var documents: [EditorDocument] = []
    @Published public var activeDocumentID: UUID?
    @Published public var findQuery = EditorFindQuery()
    @Published public var isFindBarVisible = false
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

    public func updateActiveDocument(_ transform: (inout EditorDocument) -> Void) {
        guard let activeID = activeDocument?.id,
              let idx = documents.firstIndex(where: { $0.id == activeID })
        else { return }
        var copy = documents[idx]
        transform(&copy)
        documents[idx] = copy
    }

    public func applyTextTransform(_ kind: EditorTextTransformKind) {
        updateActiveDocument { doc in
            guard !doc.isReadOnly else { return }
            doc.content = EditorTextTransformKind.apply(kind, to: doc.content)
            doc.syncStatusKey = "editor.statusModified"
        }
    }

    public func findMatch(forward: Bool) -> Int {
        guard let doc = activeDocument else { return 0 }
        let ranges = findQuery.matchRanges(in: doc.content)
        guard !ranges.isEmpty else { return 0 }

        let currentUTF16 = utf16Offset(in: doc.content, cursor: doc.cursor)
        let selectedRange: NSRange = if forward {
            ranges.first { $0.location > currentUTF16 } ?? ranges[0]
        } else {
            ranges.last { $0.location < currentUTF16 } ?? ranges[ranges.count - 1]
        }
        textViewProxy.selectAndReveal(range: selectedRange)
        return ranges.count
    }

    public func replaceCurrentMatch() {
        guard let doc = activeDocument, !doc.isReadOnly else { return }
        let ranges = findQuery.matchRanges(in: doc.content)
        guard !ranges.isEmpty else { return }
        let currentUTF16 = utf16Offset(in: doc.content, cursor: doc.cursor)
        let target = ranges.first { $0.location >= currentUTF16 } ?? ranges[0]
        let mutable = NSMutableString(string: doc.content)
        mutable.replaceCharacters(in: target, with: findQuery.replaceText)
        let nextOffset = target.location + (findQuery.replaceText as NSString).length
        updateActiveDocument { edited in
            edited.content = mutable as String
            edited.cursor = EditorCursorLocation.locate(in: edited.content, utf16Offset: nextOffset)
            edited.syncStatusKey = "editor.statusModified"
        }
    }

    public func replaceAllMatches() -> Int {
        guard let doc = activeDocument, !doc.isReadOnly else { return 0 }
        let ranges = findQuery.matchRanges(in: doc.content)
        guard !ranges.isEmpty else { return 0 }
        let mutable = NSMutableString(string: doc.content)
        for range in ranges.reversed() {
            mutable.replaceCharacters(in: range, with: findQuery.replaceText)
        }
        updateActiveDocument { edited in
            edited.content = mutable as String
            edited.syncStatusKey = "editor.statusModified"
        }
        return ranges.count
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

    private func utf16Offset(in text: String, cursor: EditorCursorLocation) -> Int {
        var line = 1
        var col = 1
        var utf16Count = 0
        for char in text {
            if line > cursor.line || (line == cursor.line && col >= cursor.column) {
                break
            }
            if char == "\n" {
                line += 1
                col = 1
            } else {
                col += 1
            }
            utf16Count += String(char).utf16.count
        }
        return utf16Count
    }
}
