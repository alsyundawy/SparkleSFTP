import Foundation
import SparkleCore

extension CommandSnippetStore {
    public static let systemSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Disk Space Overview",
            command: "df -h",
            category: "System"
        ),
        CommandSnippet(
            title: "System Load & Uptime",
            command: "uptime && top -b -n 1 | head -n 15",
            category: "System"
        ),
        CommandSnippet(
            title: "Memory Usage Breakdown",
            command: "free -h",
            category: "System"
        ),
        CommandSnippet(
            title: "Top 10 CPU Consumers",
            command: "ps aux --sort=-%cpu | head -n 11",
            category: "System"
        ),
        CommandSnippet(
            title: "Top 10 Memory Consumers",
            command: "ps aux --sort=-%mem | head -n 11",
            category: "System"
        ),
        CommandSnippet(
            title: "CPU Architecture & Cores",
            command: "lscpu 2>/dev/null || uname -a",
            category: "System"
        ),
        CommandSnippet(
            title: "OS & Kernel Version",
            command: "cat /etc/os-release && uname -r",
            category: "System"
        ),
        CommandSnippet(
            title: "Reboot Required Check",
            command: "[ -f /var/run/reboot-required ] && echo 'Reboot REQUIRED' || echo 'No reboot needed'",
            category: "System"
        ),
        CommandSnippet(
            title: "Open File Descriptors & Limits",
            command: "ulimit -n && cat /proc/sys/fs/file-nr",
            category: "System"
        ),
        CommandSnippet(
            title: "Virtual Memory Statistics",
            command: "vmstat 1 5",
            category: "System"
        )
    ]

    public static let networkSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Listening TCP/UDP Ports",
            command: "ss -tulpn",
            category: "Network"
        ),
        CommandSnippet(
            title: "Network Interfaces & IPs",
            command: "ip -br a",
            category: "Network"
        ),
        CommandSnippet(
            title: "Routing Table",
            command: "ip r",
            category: "Network"
        ),
        CommandSnippet(
            title: "Public IP Address",
            command: "curl -s ifconfig.me && echo",
            category: "Network"
        ),
        CommandSnippet(
            title: "DNS Resolution Lookup",
            command: "dig +short google.com @1.1.1.1",
            category: "Network"
        ),
        CommandSnippet(
            title: "HTTP Response Headers",
            command: "curl -Iv https://httpbin.org/get",
            category: "Network"
        ),
        CommandSnippet(
            title: "Socket Statistics Summary",
            command: "ss -s",
            category: "Network"
        ),
        CommandSnippet(
            title: "Trace Network Route",
            command: "traceroute -m 15 1.1.1.1 2>/dev/null || mtr -r -c 5 1.1.1.1",
            category: "Network"
        ),
        CommandSnippet(
            title: "Test TCP Port Reachability",
            command: "nc -zv -w 2 127.0.0.1 22 80 443 3306 5432 2>&1",
            category: "Network"
        ),
        CommandSnippet(
            title: "ICMP Ping Latency (5 pkts)",
            command: "ping -c 5 1.1.1.1",
            category: "Network"
        )
    ]

    public static let containerSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Running Docker Containers",
            command: "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'",
            category: "Containers"
        ),
        CommandSnippet(
            title: "All Containers (Inc. Stopped)",
            command: "docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'",
            category: "Containers"
        ),
        CommandSnippet(
            title: "Live Container Resource Stats",
            command: "docker stats --no-stream",
            category: "Containers"
        ),
        CommandSnippet(
            title: "Prune Dangling Containers/Images",
            command: "docker system prune -f",
            category: "Containers"
        ),
        CommandSnippet(
            title: "Tail Container Logs (100 lines)",
            command: "docker logs --tail 100 -f <container_name>",
            category: "Containers"
        ),
        CommandSnippet(
            title: "Shell Inside Container",
            command: "docker exec -it <container_name> /bin/sh",
            category: "Containers"
        ),
        CommandSnippet(
            title: "Docker Compose Up (Detached)",
            command: "docker compose up -d",
            category: "Containers"
        ),
        CommandSnippet(
            title: "Docker Compose Live Logs",
            command: "docker compose logs -f --tail=50",
            category: "Containers"
        ),
        CommandSnippet(
            title: "List Docker Volumes",
            command: "docker volume ls",
            category: "Containers"
        ),
        CommandSnippet(
            title: "Get Container IP Address",
            command: "docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' <container_name>",
            category: "Containers"
        )
    ]

    public static let kubernetesSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Get All Pods Across Namespaces",
            command: "kubectl get pods -A -o wide",
            category: "Kubernetes"
        ),
        CommandSnippet(
            title: "Find Crashing or Pending Pods",
            command: "kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded",
            category: "Kubernetes"
        ),
        CommandSnippet(
            title: "Top Pods by CPU Usage",
            command: "kubectl top pods -A --sort-by=cpu 2>/dev/null || kubectl get pods -A",
            category: "Kubernetes"
        ),
        CommandSnippet(
            title: "Stream Cluster Events",
            command: "kubectl get events -A --sort-by='.lastTimestamp'",
            category: "Kubernetes"
        ),
        CommandSnippet(
            title: "Tail Pod Logs (Last 50)",
            command: "kubectl logs <pod-name> -n <namespace> --tail=50 -f",
            category: "Kubernetes"
        ),
        CommandSnippet(
            title: "Pod Restart Counts",
            command: "kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount'",
            category: "Kubernetes"
        ),
        CommandSnippet(
            title: "Rollout Restart Deployment",
            command: "kubectl rollout restart deployment/<name> -n <namespace>",
            category: "Kubernetes"
        ),
        CommandSnippet(
            title: "Interactive Pod Shell",
            command: "kubectl exec -it <pod-name> -n <namespace> -- /bin/sh",
            category: "Kubernetes"
        )
    ]

    public static let serviceSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Failed Systemd Services",
            command: "systemctl --failed",
            category: "Services"
        ),
        CommandSnippet(
            title: "Restart & Verify Nginx",
            command: "sudo systemctl restart nginx && sudo systemctl status nginx --no-pager",
            category: "Services"
        ),
        CommandSnippet(
            title: "Reload Systemd Daemons",
            command: "sudo systemctl daemon-reload",
            category: "Services"
        ),
        CommandSnippet(
            title: "Check Critical Services Status",
            command: "systemctl is-active docker nginx sshd 2>/dev/null",
            category: "Services"
        ),
        CommandSnippet(
            title: "List Enabled Boot Services",
            command: "systemctl list-unit-files --state=enabled",
            category: "Services"
        ),
        CommandSnippet(
            title: "List Active Systemd Timers",
            command: "systemctl list-timers",
            category: "Services"
        ),
        CommandSnippet(
            title: "Restart SSH Daemon Safely",
            command: "sudo systemctl restart sshd || sudo systemctl restart ssh",
            category: "Services"
        ),
        CommandSnippet(
            title: "Journalctl Vacuum Logs",
            command: "sudo journalctl --vacuum-time=3d",
            category: "Services"
        )
    ]
}
