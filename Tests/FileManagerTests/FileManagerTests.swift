import Foundation
import SparkleCore
@testable import SparkleFileManager
import Testing

@Suite("SparkleFileManager Tests")
struct FileManagerTests {
    @Test("POSIXPermissions converts octal and symbolic strings accurately")
    func posixPermissionsFormatting() {
        let perms = POSIXPermissions.from(octalString: "755")
        #expect(perms?.mode == 0o755)
        #expect(perms?.octalString == "755")
        #expect(perms?.symbolicString == "rwxr-xr-x")
        #expect(POSIXPermissions.from(octalString: "999") == nil)
    }

    @Test("FileSortDescriptor sorts folders first and respects field/order")
    func fileSorting() async {
        let files = [
            RemoteFile(name: "zeta.txt", path: "/zeta.txt", size: 10, isDirectory: false),
            RemoteFile(name: "alpha", path: "/alpha", size: 0, isDirectory: true),
            RemoteFile(name: "beta.bin", path: "/beta.bin", size: 500, isDirectory: false)
        ]
        let byName = await FileSortDescriptor.sortRemoteFiles(
            files,
            by: FileSortDescriptor(field: .name, ascending: true)
        )
        #expect(byName.map(\.name) == ["alpha", "beta.bin", "zeta.txt"])

        let bySizeDesc = await FileSortDescriptor.sortRemoteFiles(
            files,
            by: FileSortDescriptor(field: .size, ascending: false)
        )
        #expect(bySizeDesc.map(\.name) == ["alpha", "beta.bin", "zeta.txt"])
    }

    @Test("PaginatedFileWindow slices 10K+ entries incrementally without full allocation")
    func paginatedWindow() {
        let items = (0 ..< 2500).map { idx in
            RemoteFile(name: "file_\(idx)", path: RemotePath(rawValue: "/file_\(idx)"), size: 1, isDirectory: false)
        }
        var window = PaginatedFileWindow(allFiles: items, pageSize: 1000)
        #expect(window.visibleFiles.count == 1000)
        #expect(window.hasMorePages)
        window.loadNextPage()
        #expect(window.visibleFiles.count == 2000)
        window.loadNextPage()
        #expect(window.visibleFiles.count == 2500)
        #expect(!window.hasMorePages)
    }
}
