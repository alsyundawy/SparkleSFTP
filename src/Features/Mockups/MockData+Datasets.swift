import Foundation
import SparkleCore
import SparkleDesignSystem
import SwiftUI

// MARK: - Extended Deterministic Mock Datasets

public extension MockData {
    // MARK: - Local macOS Files (/Users/developer/Projects/SparkleSFTP)

    static let localMacOSFiles: [MockFileItem] = [
        MockFileItem(name: ".build", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-12 15:10"),
        MockFileItem(name: ".github", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-11 18:22"),
        MockFileItem(
            name: "Package.swift",
            isDirectory: false,
            sizeBytes: 8636,
            formattedSize: "8.6 KB",
            permissions: "-rw-r--r--",
            modifiedAt: "2026-11-12 12:44"
        ),
        MockFileItem(
            name: "README.md",
            isDirectory: false,
            sizeBytes: 30047,
            formattedSize: "30.0 KB",
            permissions: "-rw-r--r--",
            modifiedAt: "2026-11-12 20:52"
        ),
        MockFileItem(name: "Sources", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-12 15:40"),
        MockFileItem(name: "Tests", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-12 15:35"),
        MockFileItem(name: "Tools", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-12 07:47"),
        MockFileItem(name: "dist", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-12 22:26"),
        MockFileItem(name: "docs", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-12 12:54"),
        MockFileItem(name: "tasks", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-12 22:30")
    ]

    // MARK: - Remote Linux Files (/var/log/nginx)

    static let remoteLinuxFiles: [MockFileItem] = [
        MockFileItem(name: "..", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-10 00:00"),
        MockFileItem(
            name: "access.log",
            isDirectory: false,
            sizeBytes: 42_540_112,
            formattedSize: "40.5 MB",
            permissions: "-rw-r-----",
            modifiedAt: "2026-11-12 22:28"
        ),
        MockFileItem(
            name: "access.log.1",
            isDirectory: false,
            sizeBytes: 104_857_600,
            formattedSize: "100.0 MB",
            permissions: "-rw-r-----",
            modifiedAt: "2026-11-12 00:00"
        ),
        MockFileItem(
            name: "access.log.2.gz",
            isDirectory: false,
            sizeBytes: 12_451_840,
            formattedSize: "11.8 MB",
            permissions: "-rw-r-----",
            modifiedAt: "2026-11-11 00:00"
        ),
        MockFileItem(
            name: "error.log",
            isDirectory: false,
            sizeBytes: 1_240_500,
            formattedSize: "1.2 MB",
            permissions: "-rw-r-----",
            modifiedAt: "2026-11-12 22:15"
        ),
        MockFileItem(
            name: "error.log.1",
            isDirectory: false,
            sizeBytes: 4_194_304,
            formattedSize: "4.0 MB",
            permissions: "-rw-r-----",
            modifiedAt: "2026-11-12 00:00"
        ),
        MockFileItem(
            name: "nginx.conf.bak",
            isDirectory: false,
            sizeBytes: 4096,
            formattedSize: "4.0 KB",
            permissions: "-rw-r--r--",
            modifiedAt: "2026-10-30 11:20"
        ),
        MockFileItem(name: "ssl-certs", isDirectory: true, permissions: "drwx------", modifiedAt: "2026-11-01 09:12"),
        MockFileItem(
            name: "current -> access.log",
            isDirectory: false,
            isSymlink: true,
            sizeBytes: 10,
            formattedSize: "10 B",
            permissions: "lrwxrwxrwx",
            modifiedAt: "2026-11-12 22:29"
        )
    ]

    // MARK: - Remote BSD Files (/usr/ports/security)

    static let remoteBSDFiles: [MockFileItem] = [
        MockFileItem(name: "..", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-01 00:00"),
        MockFileItem(
            name: "Makefile",
            isDirectory: false,
            sizeBytes: 2450,
            formattedSize: "2.4 KB",
            permissions: "-rw-r--r--",
            modifiedAt: "2026-11-08 14:15"
        ),
        MockFileItem(
            name: "distinfo",
            isDirectory: false,
            sizeBytes: 1024,
            formattedSize: "1.0 KB",
            permissions: "-rw-r--r--",
            modifiedAt: "2026-11-08 14:15"
        ),
        MockFileItem(name: "gnupg", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-05 18:00"),
        MockFileItem(
            name: "openssh-portable",
            isDirectory: true,
            permissions: "drwxr-xr-x",
            modifiedAt: "2026-11-10 12:40"
        ),
        MockFileItem(
            name: "pkg-descr",
            isDirectory: false,
            sizeBytes: 312,
            formattedSize: "312 B",
            permissions: "-rw-r--r--",
            modifiedAt: "2026-10-15 09:00"
        ),
        MockFileItem(
            name: "pkg-plist",
            isDirectory: false,
            sizeBytes: 8920,
            formattedSize: "8.7 KB",
            permissions: "-rw-r--r--",
            modifiedAt: "2026-11-08 14:15"
        ),
        MockFileItem(name: "sudo", isDirectory: true, permissions: "drwxr-xr-x", modifiedAt: "2026-11-02 21:30")
    ]

    // MARK: - Transfer Queue Jobs

    static let mockTransfers: [MockTransferItem] = [
        MockTransferItem(
            filename: "ubuntu-24.04-live-server-amd64.iso",
            sourcePath: "/Users/developer/Downloads/ubuntu-24.04-live-server-amd64.iso",
            destinationPath: "/var/iso/ubuntu-24.04-live-server-amd64.iso",
            direction: .upload,
            status: .active,
            fraction: 0.68,
            speedMBs: 14.8,
            etaString: "00:01:42",
            totalSizeBytes: 2_147_483_648
        ),
        MockTransferItem(
            filename: "database_backup_20261112.sql.gz",
            sourcePath: "/var/backups/database_backup_20261112.sql.gz",
            destinationPath: "/Users/developer/Backups/database_backup_20261112.sql.gz",
            direction: .download,
            status: .active,
            fraction: 0.42,
            speedMBs: 9.4,
            etaString: "00:03:15",
            totalSizeBytes: 1_048_576_000
        ),
        MockTransferItem(
            filename: "nginx_access.log",
            sourcePath: "/var/log/nginx/access.log",
            destinationPath: "/Users/developer/Logs/nginx_access.log",
            direction: .download,
            status: .conflict,
            fraction: 0.0,
            speedMBs: 0.0,
            etaString: "Paused (Conflict)",
            totalSizeBytes: 42_540_112
        ),
        MockTransferItem(
            filename: "site_assets.tar.zst",
            sourcePath: "/Users/developer/Staging/site_assets.tar.zst",
            destinationPath: "/var/www/static/site_assets.tar.zst",
            direction: .upload,
            status: .queued,
            fraction: 0.0,
            speedMBs: 0.0,
            etaString: "Queued",
            totalSizeBytes: 524_288_000
        ),
        MockTransferItem(
            filename: "ssl_certificate.crt",
            sourcePath: "/Users/developer/Certs/wildcard_sparkle.crt",
            destinationPath: "/etc/ssl/certs/wildcard_sparkle.crt",
            direction: .upload,
            status: .completed,
            fraction: 1.0,
            speedMBs: 0.0,
            etaString: "Done",
            totalSizeBytes: 4096
        )
    ]

    // MARK: - Terminal History Mock

    static let mockTerminalLines: [MockTerminalLine] = [
        MockTerminalLine(
            id: 1,
            prompt: "deploy@web-01:~$",
            command: "uname -srmo",
            output: "Linux 6.8.0-45-generic x86_64 GNU/Linux"
        ),
        MockTerminalLine(
            id: 2,
            prompt: "deploy@web-01:~$",
            command: "df -h /var",
            output: "Filesystem      Size  Used Avail Use% Mounted on\n/dev/sda3       120G   72G   48G  60% /var"
        ),
        MockTerminalLine(
            id: 3,
            prompt: "deploy@web-01:~$",
            command: "systemctl status nginx --no-pager",
            output: "● nginx.service - High performance web server\n"
                + "   Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled)\n"
                + "   Active: active (running) since Tue 2026-11-10 04:12:00 UTC\n"
                + " Main PID: 1420 (nginx)"
        ),
        MockTerminalLine(
            id: 4,
            prompt: "deploy@web-01:~$",
            command: "tail -n 2 /var/log/nginx/error.log",
            output: "2026/11/12 22:15:02 [warn] 1420#1420: *45122 client sent invalid header\n"
                + "2026/11/12 22:20:10 [notice] 1420#1420: signal process started"
        )
    ]
}
