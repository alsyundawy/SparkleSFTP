import Foundation
import SparkleCore

/// Hierarchical model node representing a local or remote directory with cycle-safe lazy expansion (v0.5.0).
@MainActor
public final class DirectoryTreeNode: Identifiable, ObservableObject {
    public let id: String
    public let name: String
    public let path: String
    public let isRemote: Bool
    public let isSymlink: Bool
    public let canonicalPath: String

    @Published public var children: [DirectoryTreeNode]?
    @Published public var isExpanded: Bool = false
    @Published public var isLoading: Bool = false

    public init(
        name: String,
        path: String,
        isRemote: Bool,
        isSymlink: Bool = false,
        canonicalPath: String? = nil
    ) {
        id = path
        self.name = name
        self.path = path
        self.isRemote = isRemote
        self.isSymlink = isSymlink
        self.canonicalPath = canonicalPath ?? path
        children = nil
    }

    /// Loads subdirectories lazily on-demand, preventing symlink cycle freezes.
    public func loadChildren(
        visitedAncestors: Set<String> = [],
        loader: @escaping @MainActor (String) async -> [DirectoryTreeNode]
    ) async {
        guard children == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // Symlink cycle detection: prevent infinite recursion
        var updatedAncestors = visitedAncestors
        if isSymlink, visitedAncestors.contains(canonicalPath) {
            children = []
            return
        }
        updatedAncestors.insert(canonicalPath)

        let result = await loader(path)
        children = result
    }

    /// Finds or auto-expands the node matching the target path.
    public func expandPath(
        _ targetPath: String,
        visitedAncestors: Set<String> = [],
        loader: @escaping @MainActor (String) async -> [DirectoryTreeNode]
    ) async {
        guard targetPath.hasPrefix(path) || path == "/" else { return }

        if children == nil {
            await loadChildren(visitedAncestors: visitedAncestors, loader: loader)
        }

        isExpanded = true

        if let subNodes = children {
            for child in subNodes where targetPath.hasPrefix(child.path) {
                var nextAncestors = visitedAncestors
                nextAncestors.insert(canonicalPath)
                await child.expandPath(targetPath, visitedAncestors: nextAncestors, loader: loader)
            }
        }
    }
}
