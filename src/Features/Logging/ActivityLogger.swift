import Foundation
import SparkleCore
import SparkleDesignSystem
import SwiftUI

public enum ActivityLogType: String, CaseIterable, Identifiable, Sendable {
    case status
    case command
    case response
    case error
    case transfer

    public var id: String {
        rawValue
    }

    public var prefix: String {
        switch self {
        case .status: return "Status:"
        case .command: return "Command:"
        case .response: return "Response:"
        case .error: return "Error:"
        case .transfer: return "Transfer:"
        }
    }
}

public struct ActivityLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let type: ActivityLogType
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), type: ActivityLogType, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.message = message
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    public var formattedTimeString: String {
        Self.timeFormatter.string(from: timestamp)
    }

    public var formattedFullLine: String {
        "[\(formattedTimeString)] \(type.prefix.padding(toLength: 10, withPad: " ", startingAt: 0)) \(message)"
    }
}

public enum ActivityLogFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case status
    case command
    case response
    case error
    case transfer

    public var id: String {
        rawValue
    }

    public func matches(_ type: ActivityLogType) -> Bool {
        switch self {
        case .all: return true
        case .status: return type == .status
        case .command: return type == .command
        case .response: return type == .response
        case .error: return type == .error
        case .transfer: return type == .transfer
        }
    }

    public func localizedTitle(strings: AppStrings) -> String {
        switch self {
        case .all: return strings.t("activityLog.filterAll")
        case .status: return strings.t("activityLog.filterStatus")
        case .command: return strings.t("activityLog.filterCommand")
        case .response: return strings.t("activityLog.filterResponse")
        case .error: return strings.t("activityLog.filterError")
        case .transfer: return strings.t("activityLog.filterTransfer")
        }
    }
}

@MainActor
public final class ActivityLogger: ObservableObject {
    public static let shared = ActivityLogger()

    @Published public private(set) var entries: [ActivityLogEntry] = []
    @Published public var selectedFilter: ActivityLogFilter = .all
    @Published public var isAutoScrollEnabled: Bool = true

    public static let maxEntriesLimit = 600

    public init() {}

    public func log(_ message: String, type: ActivityLogType = .status) {
        let entry = ActivityLogEntry(type: type, message: message)
        entries.append(entry)
        if entries.count > Self.maxEntriesLimit {
            entries.removeFirst(entries.count - Self.maxEntriesLimit)
        }
    }

    public func logStatus(_ message: String) {
        log(message, type: .status)
    }

    public func logCommand(_ message: String) {
        log(message, type: .command)
    }

    public func logResponse(_ message: String) {
        log(message, type: .response)
    }

    public func logError(_ message: String) {
        log(message, type: .error)
    }

    public func logTransfer(_ message: String) {
        log(message, type: .transfer)
    }

    public func clear() {
        entries.removeAll(keepingCapacity: true)
    }

    public func copyAllFormatted() -> String {
        entries.map(\.formattedFullLine).joined(separator: "\n")
    }
}
