import Foundation
import NIOCore
import SparkleCore

/// SFTP v3 binary frame encoder and incremental decoder with complexity-bounded helpers.
public enum SFTPPacketCodec {
    public static let maxPacketLength: UInt32 = 4 * 1024 * 1024

    public static func encode(
        _ packet: SFTPPacket,
        allocator: ByteBufferAllocator = ByteBufferAllocator()
    ) -> ByteBuffer {
        var payload = allocator.buffer(capacity: 128)
        encodeBody(packet, into: &payload)
        var frame = allocator.buffer(capacity: 4 + payload.readableBytes)
        frame.writeInteger(UInt32(payload.readableBytes))
        frame.writeBuffer(&payload)
        return frame
    }

    public static func decodeNext(from buffer: inout ByteBuffer) throws -> SFTPPacket? {
        guard buffer.readableBytes >= 4 else { return nil }
        let savedReaderIndex = buffer.readerIndex
        guard let length: UInt32 = buffer.readInteger() else {
            buffer.moveReaderIndex(to: savedReaderIndex)
            return nil
        }
        guard length >= 1, length <= maxPacketLength else {
            throw AppError.protocolError(
                code: Int(SFTPStatusCode.badMessage.rawValue),
                message: "Invalid SFTP length \(length)"
            )
        }
        guard buffer.readableBytes >= Int(length) else {
            buffer.moveReaderIndex(to: savedReaderIndex)
            return nil
        }
        guard var body = buffer.readSlice(length: Int(length)),
              let rawType: UInt8 = body.readInteger(),
              let type = SFTPPacketType(rawValue: rawType)
        else {
            throw AppError.protocolError(
                code: Int(SFTPStatusCode.badMessage.rawValue),
                message: "Unsupported SFTP packet type"
            )
        }

        return try decodeBody(type: type, body: &body)
    }

    private static func encodeBody(_ packet: SFTPPacket, into payload: inout ByteBuffer) {
        if encodeHandshakeOrResponse(packet, into: &payload) {
            return
        }
        if encodeFileIOPacket(packet, into: &payload) {
            return
        }
        encodePathMetadataPacket(packet, into: &payload)
    }

    private static func encodeHandshakeOrResponse(_ packet: SFTPPacket, into payload: inout ByteBuffer) -> Bool {
        switch packet {
        case let .initialize(version):
            payload.writeInteger(SFTPPacketType.initialize.rawValue)
            payload.writeInteger(version)
        case let .version(version, extensions):
            payload.writeInteger(SFTPPacketType.version.rawValue)
            payload.writeInteger(version)
            for (key, value) in extensions {
                writeSSHString(key, into: &payload)
                writeSSHString(value, into: &payload)
            }
        case let .status(requestID, code, message, languageTag):
            payload.writeInteger(SFTPPacketType.status.rawValue)
            payload.writeInteger(requestID)
            payload.writeInteger(code.rawValue)
            writeSSHString(message, into: &payload)
            writeSSHString(languageTag, into: &payload)
        case let .handle(requestID, handle):
            payload.writeInteger(SFTPPacketType.handle.rawValue)
            payload.writeInteger(requestID)
            writeSSHData(handle, into: &payload)
        case let .data(requestID, data):
            payload.writeInteger(SFTPPacketType.data.rawValue)
            payload.writeInteger(requestID)
            writeSSHData(data, into: &payload)
        case let .name(requestID, entries):
            payload.writeInteger(SFTPPacketType.name.rawValue)
            payload.writeInteger(requestID)
            payload.writeInteger(UInt32(entries.count))
            for entry in entries {
                writeSSHString(entry.filename, into: &payload)
                writeSSHString(entry.longname, into: &payload)
                writeAttributes(entry.attributes, into: &payload)
            }
        case let .attrs(requestID, attributes):
            payload.writeInteger(SFTPPacketType.attrs.rawValue)
            payload.writeInteger(requestID)
            writeAttributes(attributes, into: &payload)
        default:
            return false
        }
        return true
    }

    private static func encodeFileIOPacket(_ packet: SFTPPacket, into payload: inout ByteBuffer) -> Bool {
        switch packet {
        case let .open(requestID, path, flags, attrs):
            payload.writeInteger(SFTPPacketType.open.rawValue)
            payload.writeInteger(requestID)
            writeSSHString(path, into: &payload)
            payload.writeInteger(flags.rawValue)
            writeAttributes(attrs, into: &payload)
        case let .close(requestID, handle):
            payload.writeInteger(SFTPPacketType.close.rawValue)
            payload.writeInteger(requestID)
            writeSSHData(handle, into: &payload)
        case let .read(requestID, handle, offset, length):
            payload.writeInteger(SFTPPacketType.read.rawValue)
            payload.writeInteger(requestID)
            writeSSHData(handle, into: &payload)
            payload.writeInteger(offset)
            payload.writeInteger(length)
        case let .write(requestID, handle, offset, data):
            payload.writeInteger(SFTPPacketType.write.rawValue)
            payload.writeInteger(requestID)
            writeSSHData(handle, into: &payload)
            payload.writeInteger(offset)
            writeSSHData(data, into: &payload)
        case let .opendir(requestID, path):
            payload.writeInteger(SFTPPacketType.opendir.rawValue)
            payload.writeInteger(requestID)
            writeSSHString(path, into: &payload)
        case let .readdir(requestID, handle):
            payload.writeInteger(SFTPPacketType.readdir.rawValue)
            payload.writeInteger(requestID)
            writeSSHData(handle, into: &payload)
        case let .fstat(requestID, handle):
            payload.writeInteger(SFTPPacketType.fstat.rawValue)
            payload.writeInteger(requestID)
            writeSSHData(handle, into: &payload)
        default:
            return false
        }
        return true
    }

    private static func encodePathMetadataPacket(_ packet: SFTPPacket, into payload: inout ByteBuffer) {
        switch packet {
        case let .lstat(requestID, path):
            writePathOnly(.lstat, requestID: requestID, path: path, into: &payload)
        case let .stat(requestID, path):
            writePathOnly(.stat, requestID: requestID, path: path, into: &payload)
        case let .remove(requestID, path):
            writePathOnly(.remove, requestID: requestID, path: path, into: &payload)
        case let .rmdir(requestID, path):
            writePathOnly(.rmdir, requestID: requestID, path: path, into: &payload)
        case let .realpath(requestID, path):
            writePathOnly(.realpath, requestID: requestID, path: path, into: &payload)
        case let .readlink(requestID, path):
            writePathOnly(.readlink, requestID: requestID, path: path, into: &payload)
        case let .setstat(requestID, path, attrs):
            payload.writeInteger(SFTPPacketType.setstat.rawValue)
            payload.writeInteger(requestID)
            writeSSHString(path, into: &payload)
            writeAttributes(attrs, into: &payload)
        case let .mkdir(requestID, path, attrs):
            payload.writeInteger(SFTPPacketType.mkdir.rawValue)
            payload.writeInteger(requestID)
            writeSSHString(path, into: &payload)
            writeAttributes(attrs, into: &payload)
        case let .rename(requestID, oldPath, newPath):
            payload.writeInteger(SFTPPacketType.rename.rawValue)
            payload.writeInteger(requestID)
            writeSSHString(oldPath, into: &payload)
            writeSSHString(newPath, into: &payload)
        default:
            break
        }
    }

    private static func writePathOnly(
        _ type: SFTPPacketType,
        requestID: UInt32,
        path: String,
        into payload: inout ByteBuffer
    ) {
        payload.writeInteger(type.rawValue)
        payload.writeInteger(requestID)
        writeSSHString(path, into: &payload)
    }

    private static func writeSSHString(_ value: String, into buffer: inout ByteBuffer) {
        writeSSHData(Data(value.utf8), into: &buffer)
    }

    private static func writeSSHData(_ data: Data, into buffer: inout ByteBuffer) {
        buffer.writeInteger(UInt32(data.count))
        buffer.writeBytes(data)
    }

    private static func writeAttributes(_ attrs: SFTPAttributes, into buffer: inout ByteBuffer) {
        var flags = SFTPAttributes.Flags()
        if attrs.size != nil {
            flags.insert(.size)
        }
        if attrs.uid != nil, attrs.gid != nil {
            flags.insert(.uidgid)
        }
        if attrs.permissions != nil {
            flags.insert(.permissions)
        }
        if attrs.accessTime != nil, attrs.modificationTime != nil {
            flags.insert(.acmodtime)
        }
        buffer.writeInteger(flags.rawValue)
        if let size = attrs.size {
            buffer.writeInteger(size)
        }
        if let uid = attrs.uid, let gid = attrs.gid {
            buffer.writeInteger(uid)
            buffer.writeInteger(gid)
        }
        if let permissions = attrs.permissions {
            buffer.writeInteger(permissions)
        }
        if let atime = attrs.accessTime, let mtime = attrs.modificationTime {
            buffer.writeInteger(atime)
            buffer.writeInteger(mtime)
        }
    }
}
