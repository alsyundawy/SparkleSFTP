import Foundation
import SparkleCore

extension CommandSnippetStore {
    public static let posixBashSnippets5: [CommandSnippet] = [
        CommandSnippet(
            title: "Bash Check Interactive Terminal Session",
            command: "[[ -t 1 ]] && echo 'Interactive TTY' || echo 'Non-interactive Pipe'",
            category: "Bash Patterns"
        ),
        CommandSnippet(
            title: "Bash Read File Lines into Array (readarray)",
            command: "readarray -t LINES < input.txt",
            category: "Bash Patterns"
        ),
        CommandSnippet(
            title: "POSIX Tcpdump Capture HTTP Requests Only",
            command: "sudo tcpdump -i any -nn -s 0 -A 'tcp[((tcp[12:1] & 0xf0) >> 2):4] = 0x47455420' " +
            "2>/dev/null",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Tcpdump Capture DNS Queries (Port 53)",
            command: "sudo tcpdump -i any -nn -s 0 -v 'udp port 53'",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Tcpdump Capture SSH Traffic on Specific Host",
            command: "sudo tcpdump -i any -nn 'port 22 and host 192.168.1.100'",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Tcpdump Save PCAP File for Wireshark",
            command: "sudo tcpdump -i any -w /tmp/capture.pcap -c 1000",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Tcpdump Read and Analyze PCAP File",
            command: "tcpdump -nn -r /tmp/capture.pcap | head -n 30",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX SS List All Listening TCP and UDP Sockets",
            command: "ss -tunlp 2>/dev/null || netstat -an | grep LISTEN",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX SS Show Socket Connection Timers",
            command: "ss -to state established",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX SS Summary Socket Statistics",
            command: "ss -s",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Find What Process Owns Local Port 8080",
            command: "lsof -i :8080 -sTCP:LISTEN || ss -lptn 'sport = :8080'",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Trace Network Sockets per Process PID",
            command: "lsof -p <PID> -a -i",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check SSL Certificate Expiry Date",
            command: "echo | openssl s_client -servername example.com -connect example.com:443 " +
            "2>/dev/null | openssl x509 -noout -dates",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check SSL Certificate Fingerprint (SHA256)",
            command: "echo | openssl s_client -connect example.com:443 2>/dev/null | openssl x509 " +
            "-noout -fingerprint -sha256",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check SSL Certificate Subject and Issuer",
            command: "echo | openssl s_client -connect example.com:443 2>/dev/null | openssl x509 " +
            "-noout -subject -issuer",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX View Local TLS Certificate File Details",
            command: "openssl x509 -in cert.pem -text -noout",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Verify TLS Private Key Matches Certificate",
            command: "openssl rsa -in key.pem -modulus -noout | openssl sha256; openssl x509 -in " +
            "cert.pem -modulus -noout | openssl sha256",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Generate Self-Signed TLS Certificate (ECC)",
            command: "openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout " +
            "server.key -out server.crt -days 365 -subj '/CN=localhost'",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Generate RSA 4096 Bit Private Key",
            command: "openssl genpkey -algorithm RSA -out rsa4096.key -pkeyopt rsa_keygen_bits:4096",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Test Cipher Support Against Remote Host",
            command: "openssl s_client -cipher 'ECDHE-ECDSA-AES256-GCM-SHA384' -connect " +
            "example.com:443 2>&1 | grep -i 'Cipher'",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Download Remote SSL Certificate to File",
            command: "echo | openssl s_client -showcerts -connect example.com:443 2>/dev/null | sed " +
            "-ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > remote_cert.crt",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Test Latency with Timestamped Ping",
            command: "ping -c 5 -D 8.8.8.8 2>/dev/null || ping -c 5 8.8.8.8",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX MTR Realtime Network Path Diagnostic",
            command: "mtr --report --report-cycles 10 1.1.1.1 2>/dev/null || traceroute -n 1.1.1.1",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check Remote SSH Server Supported Ciphers",
            command: "ssh -Q cipher",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check Remote SSH Server Key Exchange Algs",
            command: "ssh -Q kex",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check Remote SSH Server MAC Algorithms",
            command: "ssh -Q mac",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check Remote SSH HostKey Algorithms",
            command: "ssh -Q key",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Audit Listening Services with Sockets",
            command: "netstat -tulpen 2>/dev/null || ss -tulwn",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Audit World-Writable Files and Folders",
            command: "find / -perm -0002 ! -type l -ls 2>/dev/null",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Audit Files Without Known Owner (Orphan)",
            command: "find / -nouser -o -nogroup 2>/dev/null",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Audit Users with UID 0 (Root Equivalents)",
            command: "awk -F: '($3 == 0) {print $1}' /etc/passwd",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Check Sudoers File Syntax (visudo -c)",
            command: "sudo visudo -c",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Check Current User Sudo Privileges",
            command: "sudo -l",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Audit Active SSH Authorized Keys",
            command: "find /home /root -name 'authorized_keys' -exec ls -la {} + 2>/dev/null",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Check SSH Server Configuration Syntax",
            command: "sudo sshd -t",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Audit Open SSH Connections (who / w)",
            command: "w -i || who -a",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Check IPtables Active Firewall Rules",
            command: "sudo iptables -L -n -v --line-numbers 2>/dev/null",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Check NFTables Active Ruleset",
            command: "sudo nft list ruleset 2>/dev/null",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Check UFW Firewall Status (Ubuntu/Debian)",
            command: "sudo ufw status verbose 2>/dev/null",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Check Firewalld Status (RHEL/CentOS)",
            command: "sudo firewall-cmd --list-all 2>/dev/null",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Compute SHA256 Checksum of File",
            command: "sha256sum target_file 2>/dev/null || shasum -a 256 target_file",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Compute SHA512 Checksum of File",
            command: "sha512sum target_file 2>/dev/null || shasum -a 512 target_file",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Verify Checksum Manifest File",
            command: "sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Securely Erase File Data (shred)",
            command: "shred -u -z -n 3 secret_file.txt 2>/dev/null || rm -P secret_file.txt",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Audit Kernel Core Dump Settings",
            command: "sysctl fs.suid_dumpable kernel.core_pattern",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Audit ASLR Randomization Status",
            command: "sysctl kernel.randomize_va_space",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX View All Environment Variables",
            command: "printenv | sort",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX View Shell Exported Functions",
            command: "declare -F",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX View Active Aliases",
            command: "alias",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX View Shell Built-in Keywords and Builtins",
            command: "enable -a 2>/dev/null || compgen -b",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX View Active Locale and Charset",
            command: "locale",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX List All Available System Locales",
            command: "locale -a",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX Set UTF-8 Standard Environment",
            command: "export LC_ALL=en_US.UTF-8 && export LANG=en_US.UTF-8",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX Display Terminal Capabilities (infocmp)",
            command: "infocmp -1 $TERM | head -n 30",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX Test Terminal 256 Color Support",
            command: "for i in {0..255}; do printf '\\e[48;5;%dm%3d\\e[0m ' $i $i; if (( (i+1) % 16 " +
            "== 0 )); then echo; fi; done",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX Test Terminal TrueColor (24-bit RGB)",
            command: "printf '\\e[38;2;255;100;0mTRUECOLOR SUPPORTED\\e[0m\\n'",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX Check Terminal Column and Line Count",
            command: "tput cols && tput lines",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX Clear Screen via Tput Control Code",
            command: "tput clear",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX Hide Terminal Cursor (tput civis)",
            command: "tput civis",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX Show Terminal Cursor (tput cnorm)",
            command: "tput cnorm",
            category: "POSIX Env"
        ),
        CommandSnippet(
            title: "POSIX Read System Release Information",
            command: "cat /etc/os-release 2>/dev/null || sw_vers",
            category: "POSIX Env"
        )
    ]
}
