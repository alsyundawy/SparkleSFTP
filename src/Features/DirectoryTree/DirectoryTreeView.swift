import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SwiftUI

/// Collapsible tree navigation sidebar for local or remote file systems (v0.5.0).
public struct DirectoryTreeView: View {
    @ObservedObject var appState: AppState
    let isLocal: Bool
    @StateObject private var treeCoordinator = DirectoryTreeCoordinator()

    public init(appState: AppState, isLocal: Bool) {
        self.appState = appState
        self.isLocal = isLocal
    }

    private var palette: SparkleThemePalette {
        appState.activePalette
    }

    private var currentActivePath: String {
        if isLocal {
            return appState.localCurrentURL.path
        } else {
            return appState.currentSession?.currentRemotePath.rawValue ?? "/"
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(palette.borderColor)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if let root = treeCoordinator.rootNode {
                        DirectoryTreeNodeRow(
                            node: root,
                            level: 0,
                            selectedPath: currentActivePath,
                            palette: palette,
                            onSelect: { node in
                                selectNode(node)
                            },
                            onToggleExpand: { node in
                                Task {
                                    await toggleNode(node)
                                }
                            }
                        )
                    } else if treeCoordinator.isLoadingRoot {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(appState.strings.t("common.loading"))
                                .font(SparkleTheme.Typography.caption)
                                .foregroundStyle(palette.secondaryTextColor)
                        }
                        .padding(SparkleTheme.Spacing.medium)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(palette.windowColor)
        .onAppear {
            Task {
                await treeCoordinator.initializeRoot(
                    isLocal: isLocal,
                    initialPath: currentActivePath,
                    appState: appState
                )
            }
        }
        .onChange(of: currentActivePath) { newPath in
            Task {
                await treeCoordinator.syncToPath(newPath, appState: appState)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: isLocal ? "folder.badge.gearshape" : "network.badge.shield.half.filled")
                .foregroundStyle(palette.accentColor)
                .font(.system(size: 12))
            Text(isLocal ? appState.strings.t("tree.localTitle") : appState.strings.t("tree.remoteTitle"))
                .font(SparkleSemanticTokens.captionSemiboldFont)
                .foregroundStyle(palette.primaryTextColor)
            Spacer()

            Button {
                Task {
                    await treeCoordinator.refresh(isLocal: isLocal, currentPath: currentActivePath, appState: appState)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help(appState.strings.refresh)
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .padding(.vertical, 6)
        .background(palette.windowColor)
    }

    private func selectNode(_ node: DirectoryTreeNode) {
        if isLocal {
            let url = URL(fileURLWithPath: node.path)
            Task { await appState.refreshLocalDirectory(url) }
        } else {
            Task { await appState.refreshRemoteDirectory(at: RemotePath(rawValue: node.path)) }
        }
    }

    private func toggleNode(_ node: DirectoryTreeNode) async {
        if node.isExpanded {
            node.isExpanded = false
        } else {
            await treeCoordinator.expandNode(node, appState: appState)
            node.isExpanded = true
        }
    }
}

/// Row view representing a single directory tree node with lazy expansion controls.
struct DirectoryTreeNodeRow: View {
    @ObservedObject var node: DirectoryTreeNode
    let level: Int
    let selectedPath: String
    let palette: SparkleThemePalette
    let onSelect: (DirectoryTreeNode) -> Void
    let onToggleExpand: (DirectoryTreeNode) -> Void

    private var isSelected: Bool {
        selectedPath == node.path
    }

    private var nodeIconName: String {
        if node.isSymlink {
            return "arrow.triangle.turn.up.right.diamond"
        }
        return node.isExpanded ? "folder.fill" : "folder"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Spacer().frame(width: CGFloat(level * 14))

                Button {
                    onToggleExpand(node)
                } label: {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.secondaryTextColor)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)

                Button {
                    onSelect(node)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: nodeIconName)
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? palette.accentColor : palette.secondaryTextColor)

                        Text(node.name)
                            .font(SparkleTheme.Typography.caption)
                            .foregroundStyle(isSelected ? palette.accentColor : palette.primaryTextColor)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if node.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(isSelected ? palette.selectionColor.opacity(0.6) : Color.clear)
            .cornerRadius(4)

            if node.isExpanded, let children = node.children {
                ForEach(children) { child in
                    DirectoryTreeNodeRow(
                        node: child,
                        level: level + 1,
                        selectedPath: selectedPath,
                        palette: palette,
                        onSelect: onSelect,
                        onToggleExpand: onToggleExpand
                    )
                }
            }
        }
    }
}

/// Coordinates directory node fetching and tree state caching (v0.5.0).
@MainActor
final class DirectoryTreeCoordinator: ObservableObject {
    @Published var rootNode: DirectoryTreeNode?
    @Published var isLoadingRoot: Bool = false

    func initializeRoot(isLocal: Bool, initialPath: String, appState: AppState) async {
        guard rootNode == nil else { return }
        isLoadingRoot = true
        defer { isLoadingRoot = false }

        let rootPath = isLocal ? "/" : "/"
        let rootName = isLocal ? "Macintosh HD" : "Root (/)"
        let root = DirectoryTreeNode(name: rootName, path: rootPath, isRemote: !isLocal)
        rootNode = root

        await expandNode(root, appState: appState)
        root.isExpanded = true
        await syncToPath(initialPath, appState: appState)
    }

    func expandNode(_ node: DirectoryTreeNode, appState: AppState) async {
        await node.loadChildren { path in
            if node.isRemote {
                return await Self.fetchRemoteChildren(at: path, appState: appState)
            } else {
                return await Self.fetchLocalChildren(at: path, appState: appState)
            }
        }
    }

    func syncToPath(_ path: String, appState: AppState) async {
        guard let root = rootNode else { return }
        await root.expandPath(path) { subPath in
            if root.isRemote {
                return await Self.fetchRemoteChildren(at: subPath, appState: appState)
            } else {
                return await Self.fetchLocalChildren(at: subPath, appState: appState)
            }
        }
    }

    func refresh(isLocal: Bool, currentPath: String, appState: AppState) async {
        rootNode = nil
        await initializeRoot(isLocal: isLocal, initialPath: currentPath, appState: appState)
    }

    private static func fetchLocalChildren(at path: String, appState: AppState) async -> [DirectoryTreeNode] {
        let url = URL(fileURLWithPath: path)
        guard let items = try? await appState.localFileService.listDirectory(at: url) else {
            return []
        }
        let directories = items
            .filter(\.isDirectory)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return directories.map { file in
            DirectoryTreeNode(
                name: file.name,
                path: file.path.rawValue,
                isRemote: false,
                isSymlink: file.isSymlink,
                canonicalPath: URL(fileURLWithPath: file.path.rawValue).resolvingSymlinksInPath().path
            )
        }
    }

    private static func fetchRemoteChildren(at path: String, appState: AppState) async -> [DirectoryTreeNode] {
        guard let session = appState.currentSession,
              let items = try? await session.service.fileSystem.listDirectory(at: RemotePath(rawValue: path)) else {
            return []
        }
        let directories = items
            .filter(\.isDirectory)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return directories.map { file in
            DirectoryTreeNode(
                name: file.name,
                path: file.path.rawValue,
                isRemote: true,
                isSymlink: file.isSymlink,
                canonicalPath: file.symlinkTarget ?? file.path.rawValue
            )
        }
    }
}
