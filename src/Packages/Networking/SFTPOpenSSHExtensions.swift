import Foundation
import SparkleCore

/// Data models and parsers for OpenSSH SFTP protocol extensions.
public enum SFTPOpenSSHExtensions {
    public static let limitsExtensionName = "limits@openssh.com"
    public static let statVFSExtensionName = "statvfs@openssh.com"
    public static let fstatVFSExtensionName = "fstatvfs@openssh.com"
    public static let fsyncExtensionName = "fsync@openssh.com"
    public static let copyDataExtensionName = "copy-data"
    public static let sha256ExtensionName = "sha256@openssh.com"
    public static let md5ExtensionName = "md5-hash@openssh.com"

    /// Server packet and transfer limits reported via `limits@openssh.com`.
    public struct Limits: Sendable, Equatable {
        public let maxPacketLength: UInt64
        public let maxReadLength: UInt64
        public let maxWriteLength: UInt64
        public let maxOpenHandles: UInt64

        public init(
            maxPacketLength: UInt64 = 262_144, // 256 KB default
            maxReadLength: UInt64 = 262_144,
            maxWriteLength: UInt64 = 262_144,
            maxOpenHandles: UInt64 = 100
        ) {
            self.maxPacketLength = maxPacketLength
            self.maxReadLength = maxReadLength
            self.maxWriteLength = maxWriteLength
            self.maxOpenHandles = maxOpenHandles
        }
    }

    /// Remote filesystem capacity and inode statistics reported via `statvfs@openssh.com`.
    public struct StatVFS: Sendable, Equatable {
        public let blockSize: UInt64
        public let totalBlocks: UInt64
        public let freeBlocks: UInt64
        public let availableBlocks: UInt64
        public let totalInodes: UInt64
        public let freeInodes: UInt64

        public init(
            blockSize: UInt64,
            totalBlocks: UInt64,
            freeBlocks: UInt64,
            availableBlocks: UInt64,
            totalInodes: UInt64,
            freeInodes: UInt64
        ) {
            self.blockSize = blockSize
            self.totalBlocks = totalBlocks
            self.freeBlocks = freeBlocks
            self.availableBlocks = availableBlocks
            self.totalInodes = totalInodes
            self.freeInodes = freeInodes
        }

        public var totalBytes: UInt64 {
            totalBlocks * blockSize
        }

        public var availableBytes: UInt64 {
            availableBlocks * blockSize
        }

        public var usedBytes: UInt64 {
            totalBytes > availableBytes ? totalBytes - availableBytes : 0
        }

        public var percentUsed: Double {
            guard totalBytes > 0 else { return 0.0 }
            return (Double(usedBytes) / Double(totalBytes)) * 100.0
        }
    }

    /// Remote hash response for end-to-end checksum verification without file download.
    public struct RemoteHashResult: Sendable, Equatable {
        public let hashType: String
        public let digestHex: String

        public init(hashType: String, digestHex: String) {
            self.hashType = hashType
            self.digestHex = digestHex
        }
    }
}
