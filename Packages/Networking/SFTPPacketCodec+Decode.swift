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
            return .initialize(version: try readUInt32(&body))
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
            let message = body.readableBytes > 0 ? (try readSSHString(&body)) : ""
            let lang = body.readableBytes > 0 ? (try readSSHString(&body)) : ""
            return .status(requestID: requestID, code: code, message: message, languageTag: lang)
        case .handle:
            return .handle(requestID: try readUInt32(&body), handle: try readSSHData(&body))
        case .data:
            return .data(requestID: try readUInt32(&body), payload: try readSSHData(&body))
        case .name:
            let requestID = try readUInt32(&body)
            let count = try readUInt32(&body)
            var entries: [SFTPNameEntry] = []
            entries.reserveCapacity(min(Int(count), 1024))
            for _ in 0 ..< count {
                let filename = try readSSHString(&body)
                let longname = try readSSHString(&body)
                let attrs = try readAttributes(&body)
                entries.append(SFTPNameEntry(filename: filename, longname: longname, attributes: attrs))
            }
            return .name(requestID: requestID, entries: entries)
        case .attrs:
            return .attrs(requestID: try readUInt32(&body), attributes: try readAttributes(&body))
        default:
            return nil
        }
    }

    private static func decodeFileIO(type: SFTPPacketType, body: inout ByteBuffer) throws -> SFTPPacket? {
        switch type {
        case .open:
            return .open(
                requestID: try readUInt32(&body),
                path: try readSSHString(&body),
                flags: SFTPOpenFlags(rawValue: try readUInt32(&body)),
                attributes: try readAttributes(&body)
            )
        case .close:
            return .close(requestID: try readUInt32(&body), handle: try readSSHData(&body))
        case .read:
            return .read(
                requestID: try readUInt32(&body),
                handle: try readSSHData(&body),
                offset: try readUInt64(&body),
                length: try readUInt32(&body)
            )
        case .write:
            return .write(
                requestID: try readUInt32(&body),
                handle: try readSSHData(&body),
                offset: try readUInt64(&body),
                data: try readSSHData(&body)
            )
        case .opendir:
            return .opendir(requestID: try readUInt32(&body), path: try readSSHString(&body))
        case .readdir:
            return .readdir(requestID: try readUInt32(&body), handle: try readSSHData(&body))
        case .fstat:
            return .fstat(requestID: try readUInt32(&body), handle: try readSSHData(&body))
        default:
            return nil
        }
    }

    private static func decodePathAndMetadata(type: SFTPPacketType, body: inout ByteBuffer) throws -> SFTPPacket {
        switch type {
        case .lstat:
            return .lstat(requestID: try readUInt32(&body), path: try readSSHString(&body))
        case .stat:
            return .stat(requestID: try readUInt32(&body), path: try readSSHString(&body))
        case .remove:
            return .remove(requestID: try readUInt32(&body), path: try readSSHString(&body))
        case .rmdir:
            return .rmdir(requestID: try readUInt32(&body), path: try readSSHString(&body))
        case .realpath:
            return .realpath(requestID: try readUInt32(&body), path: try readSSHString(&body))
        case .readlink:
            return .readlink(requestID: try readUInt32(&body), path: try readSSHString(&body))
        case .setstat:
            return .setstat(
                requestID: try readUInt32(&body),
                path: try readSSHString(&body),
                attributes: try readAttributes(&body)
            )
        case .mkdir:
            return .mkdir(
                requestID: try readUInt32(&body),
                path: try readSSHString(&body),
                attributes: try readAttributes(&body)
            )
        case .rename:
            return .rename(
                requestID: try readUInt32(&body),
                oldPath: try readSSHString(&body),
                newPath: try readSSHString(&body)
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
        let len = Int(try readUInt32(&buffer))
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
        let flags = SFTPAttributes.Flags(rawValue: try readUInt32(&buffer))
        var attrs = SFTPAttributes()
        if flags.contains(.size) { attrs.size = try readUInt64(&buffer) }
        if flags.contains(.uidgid) {
            attrs.uid = try readUInt32(&buffer)
            attrs.gid = try readUInt32(&buffer)
        }
        if flags.contains(.permissions) { attrs.permissions = try readUInt32(&buffer) }
        if flags.contains(.acmodtime) {
            attrs.accessTime = try readUInt32(&buffer)
            attrs.modificationTime = try readUInt32(&buffer)
        }
        return attrs
    }
}
