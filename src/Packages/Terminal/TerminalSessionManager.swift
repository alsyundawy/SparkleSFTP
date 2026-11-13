import AppKit
import Foundation
import SparkleCore
import SparkleNetworking
import SwiftTerm

private final class PTYResourceBox: @unchecked Sendable { // JUSTIFICATION: NSLock serializes teardown handles.
    private let lock = NSLock()
    private var ptyChannel: SSHPTYChannel?
    private var readerTask: Task<Void, Never>?

    func replace(channel: SSHPTYChannel, task: Task<Void, Never>) {
        lock.lock()
        let oldTask = readerTask
        let oldChannel = ptyChannel
        ptyChannel = channel
        readerTask = task
        lock.unlock()

        oldTask?.cancel()
        oldChannel?.close()
    }

    func closeAll() {
        lock.lock()
        let task = readerTask
        let channel = ptyChannel
        readerTask = nil
        ptyChannel = nil
        lock.unlock()

        task?.cancel()
        channel?.close()
    }

    func write(_ bytes: ArraySlice<UInt8>) {
        lock.lock()
        let channel = ptyChannel
        lock.unlock()
        channel?.write(bytes: bytes)
    }

    func resize(cols: Int, rows: Int) {
        lock.lock()
        let channel = ptyChannel
        lock.unlock()
        channel?.resize(cols: cols, rows: rows)
    }
}

/// Represents a single interactive SSH PTY terminal tab or split pane with explicit resource cleanup (MEM-002).
@MainActor
public final class TerminalTabSession: Identifiable, ObservableObject {
    public let id: UUID
    public let workspaceTabID: UUID?
    public let remoteSessionID: UUID?
    @Published public var title: String
    @Published public var currentDirectory: String?
    @Published public var isActive: Bool = false

    private static let maxPendingOutputBytes = 256 * 1024
    private weak var terminalView: TerminalView?
    private let resourceBox = PTYResourceBox()
    private var pendingCommandInsertion: String?
    private var pendingOutputBuffer: [UInt8] = []

    public init(
        id: UUID = UUID(),
        title: String,
        workspaceTabID: UUID? = nil,
        remoteSessionID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.workspaceTabID = workspaceTabID
        self.remoteSessionID = remoteSessionID
    }

    deinit {
        resourceBox.closeAll()
    }

    public func attachTerminalView(_ view: TerminalView) {
        terminalView = view
        if !pendingOutputBuffer.isEmpty {
            let buffered = pendingOutputBuffer
            pendingOutputBuffer.removeAll(keepingCapacity: false)
            view.feed(byteArray: buffered[...])
        }
    }

    public func attachPTYChannel(_ channel: SSHPTYChannel) {
        isActive = true
        let task = Task { [weak self, weak view = terminalView] in
            for await bytes in channel.outputStream {
                if Task.isCancelled {
                    break
                }
                await MainActor.run {
                    if let activeView = self?.terminalView ?? view {
                        activeView.feed(byteArray: bytes[...])
                    } else if let strongSelf = self {
                        strongSelf.appendPendingOutput(bytes)
                    }
                }
            }
            await MainActor.run {
                self?.isActive = false
                self?.resourceBox.closeAll()
            }
        }
        resourceBox.replace(channel: channel, task: task)
        if let pending = pendingCommandInsertion {
            pendingCommandInsertion = nil
            let bytes = Array(pending.utf8)
            resourceBox.write(bytes[...])
        }
    }

    private func appendPendingOutput(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        if pendingOutputBuffer.count + bytes.count > Self.maxPendingOutputBytes {
            let excess = (pendingOutputBuffer.count + bytes.count) - Self.maxPendingOutputBytes
            if excess >= pendingOutputBuffer.count {
                pendingOutputBuffer.removeAll(keepingCapacity: true)
            } else {
                pendingOutputBuffer.removeFirst(excess)
            }
        }
        pendingOutputBuffer.append(contentsOf: bytes)
    }

    public func sendInput(_ bytes: ArraySlice<UInt8>) {
        resourceBox.write(bytes)
    }

    public func insertCommandText(_ text: String) {
        guard !text.isEmpty else { return }
        if isActive {
            let bytes = Array(text.utf8)
            resourceBox.write(bytes[...])
        } else {
            pendingCommandInsertion = (pendingCommandInsertion ?? "") + text
        }
    }

    public func sendCommand(_ text: String) {
        let payload = text + "\n"
        if isActive {
            let bytes = Array(payload.utf8)
            resourceBox.write(bytes[...])
        } else {
            pendingCommandInsertion = (pendingCommandInsertion ?? "") + payload
        }
    }

    public func resizePTY(cols: Int, rows: Int) {
        resourceBox.resize(cols: cols, rows: rows)
    }

    public func updateTitle(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            title = trimmed
        }
    }

    public func updateRemoteWorkingDirectory(_ directory: String?) {
        guard let directory else {
            currentDirectory = nil
            return
        }
        let parsed = Self.parseOSC7DirectoryURI(directory)
        currentDirectory = parsed
        NotificationCenter.default.post(
            name: .sparkleTerminalDirectoryDidChange,
            object: workspaceTabID,
            userInfo: ["directory": parsed]
        )
    }

    public static func parseOSC7DirectoryURI(_ uri: String) -> String {
        if let url = URL(string: uri), url.scheme?.lowercased() == "file" {
            return url.path
        }
        var cleaned = uri
        if cleaned.hasPrefix("file://") {
            cleaned = String(cleaned.dropFirst(7))
            if let slashIdx = cleaned.firstIndex(of: "/") {
                return String(cleaned[slashIdx...])
            }
        }
        return cleaned
    }

    public func close() {
        resourceBox.closeAll()
        terminalView?.terminalDelegate = nil
        terminalView = nil
        isActive = false
    }
}

/// Coordinates multi-tab and split SSH PTY terminal sessions with deterministic teardown.
@MainActor
public final class TerminalSessionManager: ObservableObject {
    @Published public private(set) var sessions: [TerminalTabSession] = []
    @Published public var selectedSessionID: UUID?

    public init() {}

    @discardableResult
    public func openSession(title: String, sshClient: SSHClientService?) async throws -> TerminalTabSession {
        let session = TerminalTabSession(title: title)
        sessions.append(session)
        selectedSessionID = session.id

        if let sshClient {
            let pty = try await sshClient.openPTYChannel()
            session.attachPTYChannel(pty)
        }
        return session
    }

    public func session(forWorkspaceTabID tabID: UUID) -> TerminalTabSession? {
        sessions.first { $0.workspaceTabID == tabID }
    }

    @discardableResult
    public func ensureSingleSession(
        workspaceTabID: UUID,
        remoteSessionID: UUID,
        title: String,
        sshClient: SSHClientService?
    ) async throws -> TerminalTabSession {
        if let existing = sessions.first(where: {
            $0.workspaceTabID == workspaceTabID && $0.remoteSessionID == remoteSessionID && $0.isActive
        }) {
            selectedSessionID = existing.id
            return existing
        }

        closeSessions(forWorkspaceTabID: workspaceTabID)
        let session = TerminalTabSession(
            title: title,
            workspaceTabID: workspaceTabID,
            remoteSessionID: remoteSessionID
        )
        sessions.append(session)
        selectedSessionID = session.id

        if let sshClient {
            let pty = try await sshClient.openPTYChannel()
            session.attachPTYChannel(pty)
        }
        return session
    }

    public func closeSessions(forWorkspaceTabID tabID: UUID) {
        let doomedIDs = sessions.filter { $0.workspaceTabID == tabID }.map(\.id)
        for id in doomedIDs {
            closeSession(id: id)
        }
    }

    public func closeSessions(forRemoteSessionID remoteID: UUID) {
        let doomedIDs = sessions.filter { $0.remoteSessionID == remoteID }.map(\.id)
        for id in doomedIDs {
            closeSession(id: id)
        }
    }

    public func closeSession(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let removed = sessions.remove(at: index)
        removed.close()
        if selectedSessionID == id {
            selectedSessionID = sessions.last?.id
        }
    }

    public func closeAll() {
        let all = sessions
        sessions.removeAll()
        selectedSessionID = nil
        for session in all {
            session.close()
        }
    }
}
