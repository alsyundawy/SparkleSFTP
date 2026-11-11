import Foundation
import SparkleCore

/// SFTP v3 (`draft-ietf-secsh-filexfer-02`) packet types and data models.
public enum SFTPPacketType: UInt8, Sendable {
    case initialize = 1
    case version = 2
    case open = 3
    case close = 4
    case read = 5
    case write = 6
    case lstat = 7
    case fstat = 8
    case setstat = 9
    case fsetstat = 10
    case opendir = 11
    case readdir = 12
    case remove = 13
    case mkdir = 14
    case rmdir = 15
    case realpath = 16
    case stat = 17
    case rename = 18
    case readlink = 19
    case symlink = 20
    case status = 101
    case handle = 102
    case data = 103
    case name = 104
    case attrs = 105
}

public enum SFTPStatusCode: UInt32, Sendable, Equatable {
    case succeeded = 0
    case eof = 1
    case noSuchFile = 2
    case permissionDenied = 3
    case failure = 4
    case badMessage = 5
    case noConnection = 6
    case connectionLost = 7
    case opUnsupported = 8
}

public struct SFTPOpenFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let read = SFTPOpenFlags(rawValue: 0x0000_0001)
    public static let write = SFTPOpenFlags(rawValue: 0x0000_0002)
    public static let append = SFTPOpenFlags(rawValue: 0x0000_0004)
    public static let create = SFTPOpenFlags(rawValue: 0x0000_0008)
    public static let truncate = SFTPOpenFlags(rawValue: 0x0000_0010)
    public static let exclusive = SFTPOpenFlags(rawValue: 0x0000_0020)
}

public struct SFTPAttributes: Sendable, Equatable {
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let size = Flags(rawValue: 0x0000_0001)
        public static let uidgid = Flags(rawValue: 0x0000_0002)
        public static let permissions = Flags(rawValue: 0x0000_0004)
        public static let acmodtime = Flags(rawValue: 0x0000_0008)
    }

    public var size: UInt64?
    public var uid: UInt32?
    public var gid: UInt32?
    public var permissions: UInt32?
    public var accessTime: UInt32?
    public var modificationTime: UInt32?

    public init(
        size: UInt64? = nil,
        uid: UInt32? = nil,
        gid: UInt32? = nil,
        permissions: UInt32? = nil,
        accessTime: UInt32? = nil,
        modificationTime: UInt32? = nil
    ) {
        self.size = size
        self.uid = uid
        self.gid = gid
        self.permissions = permissions
        self.accessTime = accessTime
        self.modificationTime = modificationTime
    }

    public var isDirectory: Bool {
        guard let permissions else { return false }
        return (permissions & 0o170000) == 0o040000
    }

    public var isSymlink: Bool {
        guard let permissions else { return false }
        return (permissions & 0o170000) == 0o120000
    }
}

public struct SFTPNameEntry: Sendable, Equatable {
    public let filename: String
    public let longname: String
    public let attributes: SFTPAttributes

    public init(filename: String, longname: String, attributes: SFTPAttributes) {
        self.filename = filename
        self.longname = longname
        self.attributes = attributes
    }
}

public enum SFTPPacket: Sendable, Equatable {
    case initialize(version: UInt32)
    case version(version: UInt32, extensions: [String: String])
    case open(requestID: UInt32, path: String, flags: SFTPOpenFlags, attributes: SFTPAttributes)
    case close(requestID: UInt32, handle: Data)
    case read(requestID: UInt32, handle: Data, offset: UInt64, length: UInt32)
    case write(requestID: UInt32, handle: Data, offset: UInt64, data: Data)
    case lstat(requestID: UInt32, path: String)
    case fstat(requestID: UInt32, handle: Data)
    case setstat(requestID: UInt32, path: String, attributes: SFTPAttributes)
    case opendir(requestID: UInt32, path: String)
    case readdir(requestID: UInt32, handle: Data)
    case remove(requestID: UInt32, path: String)
    case mkdir(requestID: UInt32, path: String, attributes: SFTPAttributes)
    case rmdir(requestID: UInt32, path: String)
    case realpath(requestID: UInt32, path: String)
    case stat(requestID: UInt32, path: String)
    case rename(requestID: UInt32, oldPath: String, newPath: String)
    case readlink(requestID: UInt32, path: String)
    case status(requestID: UInt32, code: SFTPStatusCode, message: String, languageTag: String)
    case handle(requestID: UInt32, handle: Data)
    case data(requestID: UInt32, payload: Data)
    case name(requestID: UInt32, entries: [SFTPNameEntry])
    case attrs(requestID: UInt32, attributes: SFTPAttributes)

    public var requestID: UInt32? {
        switch self {
        case .initialize, .version:
            return nil
        case let .open(id, _, _, _),
             let .close(id, _),
             let .read(id, _, _, _),
             let .write(id, _, _, _),
             let .lstat(id, _),
             let .fstat(id, _),
             let .setstat(id, _, _),
             let .opendir(id, _),
             let .readdir(id, _),
             let .remove(id, _),
             let .mkdir(id, _, _),
             let .rmdir(id, _),
             let .realpath(id, _),
             let .stat(id, _),
             let .rename(id, _, _),
             let .readlink(id, _),
             let .status(id, _, _, _),
             let .handle(id, _),
             let .data(id, _),
             let .name(id, _),
             let .attrs(id, _):
            return id
        }
    }
}
