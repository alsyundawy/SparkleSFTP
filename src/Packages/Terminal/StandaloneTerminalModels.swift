import Foundation

/// Split divider orientation using iTerm2 naming conventions:
/// `.verticalDivider` places two panes side-by-side (`⌘D`); `.horizontalDivider` stacks top/bottom (`⌘⇧D`).
public enum TerminalSplitAxis: String, Sendable, Codable, Equatable {
    case verticalDivider
    case horizontalDivider
}

/// Shell or remote transport profile launched inside a standalone terminal pane.
public enum StandaloneShellKind: String, Sendable, CaseIterable, Identifiable, Equatable {
    case userDefault
    case bash
    case zsh
    case ssh

    public var id: String {
        rawValue
    }
}

/// Sanitized launch parameters executed inside `SwiftTerm.LocalProcessTerminalView`.
public struct StandaloneShellLaunchConfig: Sendable, Equatable {
    public let executable: String
    public let args: [String]
    public let initialDirectory: String
    public let displayTitle: String
    public let kind: StandaloneShellKind

    public init(
        executable: String,
        args: [String],
        initialDirectory: String,
        displayTitle: String,
        kind: StandaloneShellKind
    ) {
        self.executable = executable
        self.args = args
        self.initialDirectory = initialDirectory
        self.displayTitle = displayTitle
        self.kind = kind
    }
}

/// Metadata for a single live pane inside a standalone terminal tab.
public struct StandaloneTerminalPane: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var currentDirectory: String
    public let launchConfig: StandaloneShellLaunchConfig
    public var hasExited: Bool
    public var exitCode: Int32?

    public init(
        id: UUID = UUID(),
        title: String,
        currentDirectory: String,
        launchConfig: StandaloneShellLaunchConfig,
        hasExited: Bool = false,
        exitCode: Int32? = nil
    ) {
        self.id = id
        self.title = title
        self.currentDirectory = currentDirectory
        self.launchConfig = launchConfig
        self.hasExited = hasExited
        self.exitCode = exitCode
    }
}

/// Immutable binary split-pane layout tree supporting arbitrary nested iTerm2 splits.
public indirect enum TerminalSplitNode: Sendable, Equatable {
    case pane(UUID)
    case split(
        id: UUID,
        axis: TerminalSplitAxis,
        ratio: Double,
        first: TerminalSplitNode,
        second: TerminalSplitNode
    )

    public var paneIDs: [UUID] {
        switch self {
        case let .pane(id):
            return [id]
        case let .split(_, _, _, first, second):
            return first.paneIDs + second.paneIDs
        }
    }

    public func contains(paneID: UUID) -> Bool {
        paneIDs.contains(paneID)
    }

    public func splitting(targetPaneID: UUID, axis: TerminalSplitAxis, newPaneID: UUID) -> TerminalSplitNode {
        switch self {
        case let .pane(id):
            guard id == targetPaneID else { return self }
            return .split(
                id: UUID(),
                axis: axis,
                ratio: 0.5,
                first: .pane(id),
                second: .pane(newPaneID)
            )
        case let .split(splitID, existingAxis, ratio, first, second):
            return .split(
                id: splitID,
                axis: existingAxis,
                ratio: ratio,
                first: first.splitting(targetPaneID: targetPaneID, axis: axis, newPaneID: newPaneID),
                second: second.splitting(targetPaneID: targetPaneID, axis: axis, newPaneID: newPaneID)
            )
        }
    }

    public func removing(targetPaneID: UUID) -> TerminalSplitNode? {
        switch self {
        case let .pane(id):
            return id == targetPaneID ? nil : self
        case let .split(splitID, axis, ratio, first, second):
            let updatedFirst = first.removing(targetPaneID: targetPaneID)
            let updatedSecond = second.removing(targetPaneID: targetPaneID)
            switch (updatedFirst, updatedSecond) {
            case (nil, nil):
                return nil
            case let (nil, remaining?):
                return remaining
            case let (remaining?, nil):
                return remaining
            case let (left?, right?):
                return .split(id: splitID, axis: axis, ratio: ratio, first: left, second: right)
            }
        }
    }

    public func adjacentPaneID(from paneID: UUID, delta: Int) -> UUID? {
        let ordered = paneIDs
        guard ordered.count > 1, let idx = ordered.firstIndex(of: paneID) else { return ordered.first }
        let nextIndex = (idx + delta % ordered.count + ordered.count) % ordered.count
        return ordered[nextIndex]
    }
}

/// Top-level standalone terminal window tab holding a binary tree of split panes.
public struct StandaloneTerminalTab: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var rootNode: TerminalSplitNode
    public var focusedPaneID: UUID

    public init(id: UUID = UUID(), title: String, rootNode: TerminalSplitNode, focusedPaneID: UUID) {
        self.id = id
        self.title = title
        self.rootNode = rootNode
        self.focusedPaneID = focusedPaneID
    }
}
