import Foundation
import SparkleCore

extension CommandSnippetStore {
    public static let gitSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Git Working Tree Status",
            command: "git status -sb",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Compact Commit Graph",
            command: "git log --graph --oneline --decorate -n 15",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Branch List & Remotes",
            command: "git branch -av",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Remote URLs",
            command: "git remote -v",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Diff Stat Last Commit",
            command: "git diff --stat HEAD~1 HEAD",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Discard Uncommitted Changes",
            command: "git reset --hard HEAD && git clean -fd",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Stash List & Inspect",
            command: "git stash list && git stash show -p 2>/dev/null",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Fetch & Prune Origin",
            command: "git fetch --prune --tags origin",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Verify Tag Signatures",
            command: "git tag -n --sort=-v:refname | head -n 10",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Top Commit Authors",
            command: "git shortlog -sn --all --no-merges | head -n 10",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Submodule Status",
            command: "git submodule status --recursive",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Show Commit Details",
            command: "git show --stat HEAD",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git Unpushed Commits Check",
            command: "git log @{u}.. --oneline 2>/dev/null || git status",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git List Ignored Files",
            command: "git status --ignored -s",
            category: "Git"
        ),
        CommandSnippet(
            title: "Git File Modification History",
            command: "git log --follow -p -n 3 --",
            category: "Git"
        )
    ]

    public static let webServerSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Nginx Test Configuration",
            command: "sudo nginx -t",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Nginx Graceful Reload",
            command: "sudo nginx -s reload || sudo systemctl reload nginx",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Apache Test Configuration",
            command: "sudo apachectl configtest || sudo httpd -t",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Caddyfile Validation",
            command: "caddy validate --config /etc/caddy/Caddyfile 2>/dev/null",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "PHP-FPM Active Pool Status",
            command: "sudo systemctl status 'php*-fpm' --no-pager",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Certbot SSL Certificates",
            command: "sudo certbot certificates",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Certbot Dry Run Renewal",
            command: "sudo certbot renew --dry-run",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Test Gzip Compression",
            command: "curl -s -I -H 'Accept-Encoding: gzip' http://localhost | grep -i 'Content-Encoding'",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "HTTP Latency & Curl Timers",
            command: "curl -w 'DNS: %{time_namelookup}s\\nTotal: %{time_total}s\\n' -so /dev/null http://localhost",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Nginx Active Virtual Hosts",
            command: "sudo nginx -T 2>/dev/null | grep -E 'server_name\\s+' | sort -u",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Inspect Remote SSL Expiry",
            command: "echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -dates",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Top 10 Requested URLs in Nginx",
            command: "awk '{print $7}' /var/log/nginx/access.log 2>/dev/null | sort | uniq -c | sort -nr | head -n 10",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Nginx HTTP 5xx Error Counts",
            command: "awk '($9 ~ /^5/) {print $9, $7}' /var/log/nginx/access.log 2>/dev/null | sort | uniq -c",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Inspect OpenSSL Supported Ciphers",
            command: "openssl ciphers -v 'HIGH:!aNULL:!MD5' | head -n 15",
            category: "Web & Proxy"
        ),
        CommandSnippet(
            title: "Inspect Let's Encrypt Log",
            command: "sudo tail -n 50 /var/log/letsencrypt/letsencrypt.log 2>/dev/null",
            category: "Web & Proxy"
        )
    ]

    public static let networkProbesSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "MTR Network Path & Loss",
            command: "mtr -rwz -c 10 1.1.1.1 2>/dev/null || traceroute -q 2 1.1.1.1",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "Capture 10 TCP Packets",
            command: "sudo tcpdump -i any -c 10 -nn -q 2>/dev/null",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "DNS Full Recursive Trace",
            command: "dig +trace +nodnssec google.com",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "Query DNS Nameservers (NS)",
            command: "dig NS google.com +short",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "Query MX Mail Records",
            command: "dig MX google.com +short",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "Check Gateway & Route to IP",
            command: "ip route get 8.8.8.8 2>/dev/null || route get 8.8.8.8",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "ARP Cache & Neighbor Table",
            command: "ip neigh 2>/dev/null || arp -a",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "Test Remote Port With Timeout",
            command: "timeout 3 bash -c '</dev/tcp/1.1.1.1/443' && echo 'OPEN' || echo 'CLOSED'",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "Network Interface MTU & Stats",
            command: "ip -s link 2>/dev/null || ifconfig -a",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "WireGuard Interface Status",
            command: "sudo wg show 2>/dev/null || echo 'WireGuard not running'",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "Show Network Sockets by Protocol",
            command: "cat /proc/net/sockstat 2>/dev/null || ss -s",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "List Network Namespaces",
            command: "ip netns list 2>/dev/null || echo 'No network namespaces'",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "Check IP Forwarding State",
            command: "sysctl net.ipv4.ip_forward",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "Check TCP BBR Congestion Control",
            command: "sysctl net.ipv4.tcp_congestion_control",
            category: "Network Probes"
        ),
        CommandSnippet(
            title: "Test Iperf3 Bandwidth Client",
            command: "iperf3 -c 127.0.0.1 -t 5 2>/dev/null || echo 'iperf3 server not available'",
            category: "Network Probes"
        )
    ]

    public static let observabilitySnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Monitor System Calls (strace)",
            command: "sudo strace -c -p 1 -t 2>/dev/null || echo 'strace requires root'",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Process Memory Maps (pmap)",
            command: "pmap -x 1 2>/dev/null | tail -n 5",
            category: "Observability"
        ),
        CommandSnippet(
            title: "OOM Killer Event Search",
            command: "sudo dmesg -T | grep -i -E 'killed process|oom-killer|out of memory' | tail -n 15",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Systemd CGroup Resource Monitor",
            command: "systemd-cgtop -n 1 -b | head -n 20",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Virtual Memory Detailed Stats",
            command: "vmstat -s | head -n 20",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Disk I/O Per Process (pidstat)",
            command: "pidstat -d 1 1 2>/dev/null | head -n 20 || echo 'pidstat not installed'",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Context Switches & Migrations",
            command: "pidstat -w 1 1 2>/dev/null | head -n 20",
            category: "Observability"
        ),
        CommandSnippet(
            title: "IPC Shared Memory & Semaphores",
            command: "ipcs -m -s -q 2>/dev/null || ipcs",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Prometheus Node Exporter Scrape",
            command: "curl -s http://localhost:9100/metrics | grep -E '^node_memory_MemAvailable' | head -n 5",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Systemd Logins & Session List",
            command: "loginctl list-sessions --no-pager",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Inspect Hardware Thermal Sensors",
            command: "sensors 2>/dev/null || cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Disk Space by Mount point",
            command: "findmnt -l -t ext4,xfs,btrfs,zfs,nfs",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Check Dmesg Delta Buffer",
            command: "dmesg --show-delta 2>/dev/null | tail -n 20",
            category: "Observability"
        ),
        CommandSnippet(
            title: "List Loaded Kernel Modules",
            command: "lsmod | head -n 20",
            category: "Observability"
        ),
        CommandSnippet(
            title: "Inspect Kernel Boot Parameters",
            command: "cat /proc/cmdline",
            category: "Observability"
        )
    ]
}
