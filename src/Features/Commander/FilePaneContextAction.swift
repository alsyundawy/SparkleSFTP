import Foundation

public enum FilePaneContextAction: Int, Sendable {
    case open = 1
    case transfer = 2
    case quickLook = 3
    case edit = 4
    case rename = 5
    case permissions = 6
    case inspect = 7
    case newFolder = 8
    case delete = 9
    case openExternalApp = 10
    case configureEditor = 11
    case copyTo = 12
    case moveTo = 13
    case copyClipboard = 14
    case compareFiles = 15
    case compressAndUpload = 16
    case verifyChecksum = 17
    case customSSHCommand = 18
    case insertCommandLine = 19
    case copyFileNames = 20
    case copyFullPaths = 21
    case selectAll = 22
    case showInFinder = 23
}
