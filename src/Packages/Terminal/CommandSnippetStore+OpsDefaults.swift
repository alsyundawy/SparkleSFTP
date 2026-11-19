import Foundation
import SparkleCore

extension CommandSnippetStore {
    public static let diagnosticSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Recent System Logs (50 lines)",
            command: "journalctl -n 50 --no-pager",
            category: "Diagnostics"
        ),
        CommandSnippet(
            title: "Follow Live System Journal",
            command: "journalctl -f",
            category: "Diagnostics"
        ),
        CommandSnippet(
            title: "Failed SSH Login Attempts",
            command: "sudo grep 'Failed password' /var/log/auth.log /var/log/secure 2>/dev/null | tail -n 20",
            category: "Diagnostics"
        ),
        CommandSnippet(
            title: "Tail Nginx Error Log",
            command: "tail -n 50 /var/log/nginx/error.log 2>/dev/null",
            category: "Diagnostics"
        ),
        CommandSnippet(
            title: "Top 10 Web Visitor IPs",
            command: "awk '{print $1}' /var/log/nginx/access.log 2>/dev/null | sort | uniq -c | sort -nr | head -n 10",
            category: "Diagnostics"
        ),
        CommandSnippet(
            title: "Kernel Errors & Warnings (dmesg)",
            command: "sudo dmesg -T --level=err,warn 2>/dev/null | tail -n 30",
            category: "Diagnostics"
        ),
        CommandSnippet(
            title: "Logged In Users & Recent Logins",
            command: "w && last -n 5",
            category: "Diagnostics"
        ),
        CommandSnippet(
            title: "Disk I/O Statistics",
            command: "iostat -xz 1 3 2>/dev/null || vmstat 1 3",
            category: "Diagnostics"
        )
    ]

    public static let securitySnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "UFW Firewall Status",
            command: "sudo ufw status verbose 2>/dev/null",
            category: "Security"
        ),
        CommandSnippet(
            title: "Fail2Ban Banned IPs",
            command: "sudo fail2ban-client status 2>/dev/null",
            category: "Security"
        ),
        CommandSnippet(
            title: "Processes with Listening Sockets",
            command: "sudo lsof -i -P -n | grep LISTEN",
            category: "Security"
        ),
        CommandSnippet(
            title: "Sudo Privileges for Current User",
            command: "sudo -l",
            category: "Security"
        ),
        CommandSnippet(
            title: "SSL/TLS Certificate Expiration",
            command: "echo | openssl s_client -connect 127.0.0.1:443 2>/dev/null | openssl x509 -noout -dates",
            category: "Security"
        ),
        CommandSnippet(
            title: "Generate Secure Random Token",
            command: "openssl rand -base64 32",
            category: "Security"
        ),
        CommandSnippet(
            title: "File Checksum Verification",
            command: "sha256sum <filename>",
            category: "Security"
        ),
        CommandSnippet(
            title: "Find SUID Binaries",
            command: "find / -perm /6000 -type f 2>/dev/null | head -n 25",
            category: "Security"
        )
    ]

    public static let databaseSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "MySQL/MariaDB Ping & Alive",
            command: "mysqladmin ping -u root -p 2>/dev/null || mariadb-admin ping",
            category: "Databases"
        ),
        CommandSnippet(
            title: "MySQL Active Processlist",
            command: "mysql -e 'SHOW FULL PROCESSLIST;' 2>/dev/null",
            category: "Databases"
        ),
        CommandSnippet(
            title: "PostgreSQL Active Connections",
            command: "sudo -u postgres psql -c 'SELECT datname, numbackends FROM pg_stat_database;'",
            category: "Databases"
        ),
        CommandSnippet(
            title: "Redis Ping & Memory Usage",
            command: "redis-cli ping && redis-cli info memory | grep used_memory_human",
            category: "Databases"
        ),
        CommandSnippet(
            title: "Redis Key Count",
            command: "redis-cli dbsize",
            category: "Databases"
        ),
        CommandSnippet(
            title: "PostgreSQL Database Sizes",
            command: "sudo -u postgres psql -c "
                + "'SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;'",
            category: "Databases"
        )
    ]

    public static let devopsSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Git Working Tree & Upstream",
            command: "git status -s && git branch -vv",
            category: "DevOps"
        ),
        CommandSnippet(
            title: "Git Compact Commit Graph",
            command: "git log --oneline --graph --decorate -n 10",
            category: "DevOps"
        ),
        CommandSnippet(
            title: "Git Recent Commit Changes",
            command: "git show --stat",
            category: "DevOps"
        ),
        CommandSnippet(
            title: "Git Dry Run Clean Unversioned",
            command: "git clean -ndx",
            category: "DevOps"
        ),
        CommandSnippet(
            title: "CI/CD Git Commit Head",
            command: "git rev-parse HEAD && git status --short",
            category: "DevOps"
        ),
        CommandSnippet(
            title: "Environment Variables Filtered",
            command: "printenv | grep -E '^(PATH|USER|SHELL|LANG|NODE_ENV|APP_ENV)'",
            category: "DevOps"
        )
    ]

    public static let fileSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Find Files Larger Than 100MB",
            command: "find . -type f -size +100M -exec ls -lh {} + 2>/dev/null",
            category: "Files"
        ),
        CommandSnippet(
            title: "Modified Files in Last 24h",
            command: "find . -type f -mtime -1",
            category: "Files"
        ),
        CommandSnippet(
            title: "Standardize Web Permissions",
            command: "find . -type d -exec chmod 755 {} + && find . -type f -exec chmod 644 {} +",
            category: "Files"
        ),
        CommandSnippet(
            title: "Create Gzip Tar Archive",
            command: "tar -czvf backup-archive.tar.gz ./",
            category: "Files"
        ),
        CommandSnippet(
            title: "Extract Tar Archive",
            command: "tar -xzvf archive.tar.gz",
            category: "Files"
        ),
        CommandSnippet(
            title: "Top 10 Largest Folders",
            command: "du -sh * 2>/dev/null | sort -hr | head -n 10",
            category: "Files"
        )
    ]
}
