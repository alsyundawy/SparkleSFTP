import Foundation
import OSLog

/// Centralized OSLog categories enforcing CWE-532 privacy hygiene.
public enum DiagnosticsLogger {
    public static let subsystem = "com.alsyundawy.SparkleSFTP"

    public static let security = Logger(subsystem: subsystem, category: "Security")
    public static let network = Logger(subsystem: subsystem, category: "Network")
    public static let transfer = Logger(subsystem: subsystem, category: "Transfer")
    public static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    public static let terminal = Logger(subsystem: subsystem, category: "Terminal")
    public static let userInterface = Logger(subsystem: subsystem, category: "UI")
}
