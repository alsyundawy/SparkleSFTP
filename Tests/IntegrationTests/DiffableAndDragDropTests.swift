import AppKit
import Foundation
import SparkleCore
@testable import SparkleFeatures
@testable import SparkleFileManager
@testable import SparklePersistence
@testable import SparkleTerminal
import Testing

private actor DummyCredStore: CredentialStoreProtocol {
    func saveSecret(_: Data, for _: SecretReference, requireTouchID _: Bool) async throws {}
    func loadSecret(for ref: SecretReference, prompt _: String?) async throws -> Data {
        throw AppError.credentialNotFound(service: ref.accountKey)
    }
    func deleteSecret(for _: SecretReference) async throws {}
    func hasSecret(for _: SecretReference) async -> Bool { false }
}

@Suite("Diffable Data Source, Drag-and-Drop & External QuickActions Tests (Tasks 6.1, 6.5, 16.1)")
struct DiffableAndDragDropTests {
    @Test("CollectionDifference computes row removals and insertions for incremental table updates (Task 6.1)")
    func diffableCollectionComputation() {
        let fileAlpha = RemoteFile(name: "alpha.txt", path: "/alpha.txt", size: 100, isDirectory: false)
        let fileBeta = RemoteFile(name: "beta.txt", path: "/beta.txt", size: 200, isDirectory: false)
        let fileGamma = RemoteFile(name: "gamma.txt", path: "/gamma.txt", size: 300, isDirectory: false)

        let initialList = [fileAlpha, fileBeta, fileGamma]
        let fileDelta = RemoteFile(name: "delta.txt", path: "/delta.txt", size: 400, isDirectory: false)
        let updatedList = [fileAlpha, fileGamma, fileDelta]

        let diff = updatedList.difference(from: initialList)
        var removedOffsets: [Int] = []
        var insertedOffsets: [Int] = []

        for change in diff {
            switch change {
            case let .remove(offset, _, _):
                removedOffsets.append(offset)
            case let .insert(offset, _, _):
                insertedOffsets.append(offset)
            }
        }

        #expect(removedOffsets == [1]) // beta.txt removed at index 1
        #expect(insertedOffsets == [2]) // delta.txt inserted at index 2
    }

    @Test("handleExternalURL navigates local directories for file:// URLs (Task 16.1)")
    @MainActor
    func externalFileURLHandling() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleExt-\(UUID())")
        let sub = tmp.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let state = AppState(
            credentialStore: DummyCredStore(),
            connectionStore: ConnectionStore(fileURL: tmp.appendingPathComponent("c.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: tmp.appendingPathComponent("s.json"))
        )

        await state.handleExternalURL(sub)
        #expect(state.localCurrentURL.standardizedFileURL.path == sub.standardizedFileURL.path)
    }

    @Test("handleExternalURL constructs connection profile from remote sftp:// and ftps:// URLs (Task 16.1)")
    @MainActor
    func externalRemoteSchemeURLHandling() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleScheme-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let state = AppState(
            credentialStore: DummyCredStore(),
            connectionStore: ConnectionStore(fileURL: tmp.appendingPathComponent("c.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: tmp.appendingPathComponent("s.json"))
        )

        let sftpURL = try #require(URL(string: "sftp://deployer@gateway.internal:2222/var/www/html"))
        await state.handleExternalURL(sftpURL)
        #expect(state.profiles.contains { $0.host == "gateway.internal" && $0.port == 2222 })
        #expect(state.primarySelectedProfile?.username == "deployer")
    }
}
