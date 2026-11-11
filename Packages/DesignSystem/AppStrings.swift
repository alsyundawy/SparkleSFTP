import Foundation

/// Supported interface languages (English and Bahasa Indonesia).
public enum AppLanguage: String, Sendable, Codable, CaseIterable, Identifiable {
    case english = "en"
    case indonesian = "id"

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .indonesian: return "Bahasa Indonesia"
        }
    }
}

/// Type-safe localized UI strings for English and Bahasa Indonesia.
public struct AppStrings: Sendable {
    public let language: AppLanguage

    public init(language: AppLanguage = .english) {
        self.language = language
    }

    public var appName: String {
        "SparkleSFTP"
    }

    public var connectionsTitle: String {
        language == .indonesian ? "Koneksi" : "Connections"
    }

    public var newConnection: String {
        language == .indonesian ? "Koneksi Baru" : "New Connection"
    }

    public var connect: String {
        language == .indonesian ? "Hubungkan" : "Connect"
    }

    public var disconnect: String {
        language == .indonesian ? "Putuskan" : "Disconnect"
    }

    public var refresh: String {
        language == .indonesian ? "Segarkan" : "Refresh"
    }

    public var upload: String {
        language == .indonesian ? "Unggah (F5)" : "Upload (F5)"
    }

    public var download: String {
        language == .indonesian ? "Unduh (F5)" : "Download (F5)"
    }

    public var move: String {
        language == .indonesian ? "Pindah (F6)" : "Move (F6)"
    }

    public var newFolder: String {
        language == .indonesian ? "Folder Baru (F7)" : "New Folder (F7)"
    }

    public var delete: String {
        language == .indonesian ? "Hapus (F8)" : "Delete (F8)"
    }

    public var terminal: String {
        language == .indonesian ? "Terminal SSH" : "SSH Terminal"
    }

    public var transfers: String {
        language == .indonesian ? "Antrean Transfer" : "Transfer Queue"
    }

    public var synchronize: String {
        language == .indonesian ? "Sinkronisasi" : "Synchronize"
    }

    public var plaintextFTPWarning: String {
        language == .indonesian
            ? "PERINGATAN: FTP tanpa enkripsi mengirimkan kredensial dan berkas dalam teks biasa."
            : "WARNING: Plain FTP transmits credentials and files unencrypted."
    }

    public var hostKeyUnknownTitle: String {
        language == .indonesian ? "Verifikasi Sidik Jari Host SSH" : "Verify SSH Host Key Fingerprint"
    }

    public var hostKeyMismatchTitle: String {
        language == .indonesian
            ? "BAHAYA: Sidik Jari Host SSH Berubah!"
            : "SECURITY ALERT: SSH Host Key Changed!"
    }

    public var securityDiagnostics: String {
        language == .indonesian ? "Diagnostik Keamanan" : "Security Diagnostics"
    }

    public var dryRunPreview: String {
        language == .indonesian ? "Pratinjau Dry-Run" : "Dry-Run Preview"
    }

    public var executeSync: String {
        language == .indonesian ? "Jalankan Sinkronisasi" : "Execute Sync"
    }

    public var settings: String {
        language == .indonesian ? "Pengaturan" : "Settings"
    }
}
