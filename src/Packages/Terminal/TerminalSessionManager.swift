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
    @Published public var title: String
    @Published public var currentDirectory: String?
    @Published public var isActive: Bool = false

    private weak var terminalView: TerminalView?
    private let resourceBox = PTYResourceBox()
    private var pendingCommandInsertion: String?

    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }

    deinit {
        resourceBox.closeAll()
    }

    public func attachTerminalView(_ view: TerminalView) {
        terminalView = view
    }

    public func attachPTYChannel(_ channel: SSHPTYChannel) {
        isActive = true
        let task = Task { [weak self, weak view = terminalView] in
            for await bytes in channel.outputStream {
                if Task.isCancelled {
                    break
                }
                await MainActor.run {
                    (self?.terminalView ?? view)?.feed(byteArray: bytes[...])
                }
            }
            await MainActor.run {
                self?.isActive = false
            }
        }
        resourceBox.replace(channel: channel, task: task)
        if let pending = pendingCommandInsertion {
            pendingCommandInsertion = nil
            let bytes = Array(pending.utf8)
            resourceBox.write(bytes[...])
        }
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
        let bytes = Array((text + "\n").utf8)
        resourceBox.write(bytes[...])
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
        currentDirectory = directory
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
