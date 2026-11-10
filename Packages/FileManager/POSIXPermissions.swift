import Foundation

/// POSIX permission parser and octal/symbolic formatter (TASK-069).
public struct POSIXPermissions: Sendable, Equatable {
    public var mode: UInt32

    public init(mode: UInt32) {
        self.mode = mode & 0o7777
    }

    public var octalString: String {
        String(format: "%03o", mode)
    }

    public var symbolicString: String {
        let bits: [(UInt32, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        return String(bits.map { (mode & $0.0) != 0 ? $0.1 : "-" })
    }

    public static func from(octalString: String) -> POSIXPermissions? {
        let trimmed = octalString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = UInt32(trimmed, radix: 8), parsed <= 0o7777 else {
            return nil
        }
        return POSIXPermissions(mode: parsed)
    }
}
