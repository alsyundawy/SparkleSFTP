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
    public let localShellPath: String?
    public let localWorkingDirectory: URL?
    @Published public var title: String
    @Published public var currentDirectory: String?
    @Published public var isActive: Bool = false

    public var isLocalShell: Bool {
        localShellPath != nil
    }

    private weak var terminalView: TerminalView?
    private weak var localProcessView: LocalProcessTerminalView?
    private let resourceBox = PTYResourceBox()

    public init(
        id: UUID = UUID(),
        title: String,
        localShellPath: String? = nil,
        localWorkingDirectory: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.localShellPath = localShellPath
        self.localWorkingDirectory = localWorkingDirectory
    }

    deinit {
        resourceBox.closeAll()
    }

    public func attachTerminalView(_ view: TerminalView) {
        terminalView = view
    }

    public func attachLocalProcessView(_ view: LocalProcessTerminalView) {
        localProcessView = view
        isActive = true
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
    }

    public func sendInput(_ bytes: ArraySlice<UInt8>) {
        resourceBox.write(bytes)
    }

    public func sendCommand(_ text: String) {
        if let localProcessView {
            localProcessView.send(txt: text + "\n")
            return
        }
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
        if let localProcessView {
            localProcessView.processDelegate = nil
            localProcessView.terminate()
            self.localProcessView = nil
        }
        terminalView?.terminalDelegate = nil
        terminalView = nil
        isActive = false
    }
}

/// Coordinates multi-tab and split SSH PTY and local shell terminal sessions with deterministic teardown.
@MainActor
public final class TerminalSessionManager: ObservableObject {
    @Published public private(set) var sessions: [TerminalTabSession] = []
    @Published public var selectedSessionID: UUID?

    public init() {}

    @discardableResult
    public func openLocalShell(shellPath: String, directory: URL? = nil) -> TerminalTabSession {
        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent
        let session = TerminalTabSession(
            title: "Local: \(shellName)",
            localShellPath: shellPath,
            localWorkingDirectory: directory
        )
        sessions.append(session)
        selectedSessionID = session.id
        return session
    }

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
