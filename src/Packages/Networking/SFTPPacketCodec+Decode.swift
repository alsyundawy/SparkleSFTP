import Foundation
import NIOCore
import SparkleCore

extension SFTPPacketCodec {
    static func decodeBody(type: SFTPPacketType, body: inout ByteBuffer) throws -> SFTPPacket {
        if let decoded = try decodeHandshakeOrResponse(type: type, body: &body) {
            return decoded
        }
        if let decoded = try decodeFileIO(type: type, body: &body) {
            return decoded
        }
        return try decodePathAndMetadata(type: type, body: &body)
    }

    private static func decodeHandshakeOrResponse(type: SFTPPacketType, body: inout ByteBuffer) throws -> SFTPPacket? {
        switch type {
        case .initialize:
            return try .initialize(version: readUInt32(&body))
        case .version:
            let version = try readUInt32(&body)
            var extensions: [String: String] = [:]
            while body.readableBytes > 0 {
                let key = try readSSHString(&body)
                let val = try readSSHString(&body)
                extensions[key] = val
            }
            return .version(version: version, extensions: extensions)
        case .status:
            let requestID = try readUInt32(&body)
            let codeRaw = try readUInt32(&body)
            let code = SFTPStatusCode(rawValue: codeRaw) ?? .failure
            let message = try body.readableBytes > 0 ? readSSHString(&body) : ""
            let lang = try body.readableBytes > 0 ? readSSHString(&body) : ""
            return .status(requestID: requestID, code: code, message: message, languageTag: lang)
        case .handle:
            return try .handle(requestID: readUInt32(&body), handle: readSSHData(&body))
        case .data:
            return try .data(requestID: readUInt32(&body), payload: readSSHData(&body))
        case .name:
            return try decodeNamePacket(body: &body)
        case .attrs:
            return try .attrs(requestID: readUInt32(&body), attributes: readAttributes(&body))
        default:
            return nil
        }
    }

    private static func decodeNamePacket(body: inout ByteBuffer) throws -> SFTPPacket {
        let requestID = try readUInt32(&body)
        let count = try readUInt32(&body)
        guard Int(count) <= (body.readableBytes / 12) + 1 else {
            throw AppError.protocolError(
                code: Int(SFTPStatusCode.badMessage.rawValue),
                message: "Invalid SFTP NAME entry count"
            )
        }
        var entries: [SFTPNameEntry] = []
        entries.reserveCapacity(min(Int(count), 1024))
        for _ in 0 ..< count {
            let filename = try readSSHString(&body)
            let longname = try readSSHString(&body)
            let attrs = try readAttributes(&body)
            entries.append(SFTPNameEntry(filename: filename, longname: longname, attributes: attrs))
        }
        return .name(requestID: requestID, entries: entries)
    }

    private static func decodeFileIO(type: SFTPPacketType, body: inout ByteBuffer) throws -> SFTPPacket? {
        switch type {
        case .open:
            return try .open(
                requestID: readUInt32(&body),
                path: readSSHString(&body),
                flags: SFTPOpenFlags(rawValue: readUInt32(&body)),
                attributes: readAttributes(&body)
            )
        case .close:
            return try .close(requestID: readUInt32(&body), handle: readSSHData(&body))
        case .read:
            return try .read(
                requestID: readUInt32(&body),
                handle: readSSHData(&body),
                offset: readUInt64(&body),
                length: readUInt32(&body)
            )
        case .write:
            return try .write(
                requestID: readUInt32(&body),
                handle: readSSHData(&body),
                offset: readUInt64(&body),
                data: readSSHData(&body)
            )
        case .opendir:
            return try .opendir(requestID: readUInt32(&body), path: readSSHString(&body))
        case .readdir:
            return try .readdir(requestID: readUInt32(&body), handle: readSSHData(&body))
        case .fstat:
            return try .fstat(requestID: readUInt32(&body), handle: readSSHData(&body))
        default:
            return nil
        }
    }

    private static func decodePathAndMetadata(type: SFTPPacketType, body: inout ByteBuffer) throws -> SFTPPacket {
        switch type {
        case .lstat:
            return try .lstat(requestID: readUInt32(&body), path: readSSHString(&body))
        case .stat:
            return try .stat(requestID: readUInt32(&body), path: readSSHString(&body))
        case .remove:
            return try .remove(requestID: readUInt32(&body), path: readSSHString(&body))
        case .rmdir:
            return try .rmdir(requestID: readUInt32(&body), path: readSSHString(&body))
        case .realpath:
            return try .realpath(requestID: readUInt32(&body), path: readSSHString(&body))
        case .readlink:
            return try .readlink(requestID: readUInt32(&body), path: readSSHString(&body))
        case .setstat:
            return try .setstat(
                requestID: readUInt32(&body),
                path: readSSHString(&body),
                attributes: readAttributes(&body)
            )
        case .mkdir:
            return try .mkdir(
                requestID: readUInt32(&body),
                path: readSSHString(&body),
                attributes: readAttributes(&body)
            )
        case .rename:
            return try .rename(
                requestID: readUInt32(&body),
                oldPath: readSSHString(&body),
                newPath: readSSHString(&body)
            )
        default:
            throw AppError.protocolError(
                code: Int(SFTPStatusCode.opUnsupported.rawValue),
                message: "Unsupported request packet"
            )
        }
    }

    private static func readUInt32(_ buffer: inout ByteBuffer) throws -> UInt32 {
        guard let value: UInt32 = buffer.readInteger() else {
            throw AppError.protocolError(code: Int(SFTPStatusCode.badMessage.rawValue), message: "Truncated UInt32")
        }
        return value
    }

    private static func readUInt64(_ buffer: inout ByteBuffer) throws -> UInt64 {
        guard let value: UInt64 = buffer.readInteger() else {
            throw AppError.protocolError(code: Int(SFTPStatusCode.badMessage.rawValue), message: "Truncated UInt64")
        }
        return value
    }

    private static func readSSHData(_ buffer: inout ByteBuffer) throws -> Data {
        let len = try Int(readUInt32(&buffer))
        guard let bytes = buffer.readBytes(length: len) else {
            throw AppError.protocolError(code: Int(SFTPStatusCode.badMessage.rawValue), message: "Truncated SSH bytes")
        }
        return Data(bytes)
    }

    private static func readSSHString(_ buffer: inout ByteBuffer) throws -> String {
        let data = try readSSHData(&buffer)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppError.protocolError(code: Int(SFTPStatusCode.badMessage.rawValue), message: "Invalid UTF-8 string")
        }
        return text
    }

    private static func readAttributes(_ buffer: inout ByteBuffer) throws -> SFTPAttributes {
        let flags = try SFTPAttributes.Flags(rawValue: readUInt32(&buffer))
        var attrs = SFTPAttributes()
        if flags.contains(.size) {
            attrs.size = try readUInt64(&buffer)
        }
        if flags.contains(.uidgid) {
            attrs.uid = try readUInt32(&buffer)
            attrs.gid = try readUInt32(&buffer)
        }
        if flags.contains(.permissions) {
            attrs.permissions = try readUInt32(&buffer)
        }
        if flags.contains(.acmodtime) {
            attrs.accessTime = try readUInt32(&buffer)
            attrs.modificationTime = try readUInt32(&buffer)
        }
        if (flags.rawValue & 0x8000_0000) != 0 {
            let extendedCount = try readUInt32(&buffer)
            guard extendedCount <= 1024 else {
                throw AppError.protocolError(
                    code: Int(SFTPStatusCode.badMessage.rawValue),
                    message: "Excessive SFTP extended attributes (\(extendedCount))"
                )
            }
            for _ in 0 ..< extendedCount {
                _ = try readSSHData(&buffer)
                _ = try readSSHData(&buffer)
            }
        }
        return attrs
    }
}
