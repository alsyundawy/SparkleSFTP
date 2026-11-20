import Foundation
import SparkleCore

extension CommandSnippetStore {
    public static let containerOrchestrationSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Docker Top Containers by CPU/RAM",
            command: "docker stats --no-stream --format 'table {{.Name}}\\t{{.CPUPerc}}\\t{{.MemUsage}}'",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "Docker Inspect Container IP",
            command: "docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}'",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "Docker Port Mappings",
            command: "docker ps --format 'table {{.Names}}\\t{{.Ports}}\\t{{.Status}}'",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "Docker Prune Dangling Images",
            command: "docker image prune -f",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "Docker Inspect Volume Mounts",
            command: "docker inspect -f '{{json .Mounts}}' 2>/dev/null",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "K8s Failing Pods Across Cluster",
            command: "kubectl get pods -A --field-selector status.phase!=Running,status.phase!=Succeeded",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "K8s Top Node Resources",
            command: "kubectl top nodes 2>/dev/null || echo 'metrics-server not available'",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "K8s Top Pod Resources",
            command: "kubectl top pods -A 2>/dev/null | head -n 20 || echo 'metrics-server not available'",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "K8s Cluster Events (Recent)",
            command: "kubectl get events -A --sort-by='.metadata.creationTimestamp' | tail -n 20",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "K8s Describe Deployments",
            command: "kubectl get deployments -A -o wide",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "K8s Ingress Routes",
            command: "kubectl get ingress -A 2>/dev/null",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "K8s Persistent Volume Claims",
            command: "kubectl get pvc -A",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "Helm List Deployed Releases",
            command: "helm list -A 2>/dev/null || echo 'helm not installed'",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "Docker Compose Running Services",
            command: "docker compose ps 2>/dev/null || docker-compose ps",
            category: "Containers & K8s"
        ),
        CommandSnippet(
            title: "Docker Container Restart Count",
            command: "docker inspect -f '{{.Name}}: {{.RestartCount}} restarts' $(docker ps -q 2>/dev/null)",
            category: "Containers & K8s"
        )
    ]

    public static let databaseCloudSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Postgres Active Connections",
            command: "sudo -u postgres psql -c 'SELECT count(*) FROM pg_stat_activity;' 2>/dev/null",
            category: "Databases"
        ),
        CommandSnippet(
            title: "Postgres Long Running Queries",
            command: "sudo -u postgres psql -c \"SELECT pid, query FROM pg_stat_activity WHERE state != 'idle';\"",
            category: "Databases"
        ),
        CommandSnippet(
            title: "Postgres Database Sizes",
            command: "psql -c 'SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;'",
            category: "Databases"
        ),
        CommandSnippet(
            title: "Postgres Vacuum Progress Check",
            command: "sudo -u postgres psql -c 'SELECT * FROM pg_stat_progress_vacuum;' 2>/dev/null",
            category: "Databases"
        ),
        CommandSnippet(
            title: "MySQL Active Processlist",
            command: "mysql -e 'SHOW FULL PROCESSLIST;' 2>/dev/null || mariadb -e 'SHOW FULL PROCESSLIST;' 2>/dev/null",
            category: "Databases"
        ),
        CommandSnippet(
            title: "MySQL InnoDB Status Summary",
            command: "mysql -e 'SHOW ENGINE INNODB STATUS\\G' 2>/dev/null | head -n 35",
            category: "Databases"
        ),
        CommandSnippet(
            title: "MySQL Uptime and Questions Count",
            command: "mysql -e 'SHOW GLOBAL STATUS LIKE \"Uptime\";' 2>/dev/null",
            category: "Databases"
        ),
        CommandSnippet(
            title: "Redis Ping Check",
            command: "redis-cli ping 2>/dev/null || echo 'Redis not running'",
            category: "Databases"
        ),
        CommandSnippet(
            title: "Redis Memory Stats",
            command: "redis-cli info memory 2>/dev/null | grep -E 'used_memory_human|maxmemory_human'",
            category: "Databases"
        ),
        CommandSnippet(
            title: "Redis Slow Queries Log",
            command: "redis-cli slowlog get 10 2>/dev/null",
            category: "Databases"
        ),
        CommandSnippet(
            title: "Redis Connected Clients Count",
            command: "redis-cli info clients 2>/dev/null | grep 'connected_clients'",
            category: "Databases"
        ),
        CommandSnippet(
            title: "SQLite Quick Integrity Check",
            command: "sqlite3 /var/lib/db.sqlite 'PRAGMA quick_check;' 2>/dev/null || echo 'Specify DB path'",
            category: "Databases"
        ),
        CommandSnippet(
            title: "MongoDB Server Status Ping",
            command: "mongosh --eval 'db.runCommand({ ping: 1 })' 2>/dev/null || mongo --eval 'db.ping()' 2>/dev/null",
            category: "Databases"
        ),
        CommandSnippet(
            title: "RabbitMQ Queue Message Counts",
            command: "sudo rabbitmqctl list_queues name messages 2>/dev/null || echo 'RabbitMQ not installed'",
            category: "Databases"
        ),
        CommandSnippet(
            title: "Memcached Stats Summary",
            command: "echo 'stats' | nc -w 1 127.0.0.1 11211 2>/dev/null | head -n 15",
            category: "Databases"
        )
    ]

    public static let systemHardeningSnippets: [CommandSnippet] = [
        CommandSnippet(
            title: "Find World-Writable Files",
            command: "sudo find / -xdev -type f -perm -0002 2>/dev/null | head -n 20",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Find SUID Root Binaries",
            command: "sudo find / -perm -4000 -user root -type f 2>/dev/null | head -n 25",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Find SGID Binaries",
            command: "sudo find / -perm -2000 -type f 2>/dev/null | head -n 20",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Check Sudoers Configuration",
            command: "sudo grep -rE '^[a-zA-Z0-9%].*ALL' /etc/sudoers /etc/sudoers.d/ 2>/dev/null",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Verify SSH Host Key Fingerprints",
            command: "for f in /etc/ssh/ssh_host_*_key.pub; do [ -f \"$f\" ] && ssh-keygen -lf \"$f\"; done",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Fail2ban Jails & Status",
            command: "sudo fail2ban-client status 2>/dev/null || echo 'Fail2ban not installed'",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Audit Open Listening Sockets (PID)",
            command: "sudo lsof -i -P -n | grep LISTEN | head -n 20",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Systemd Journal Disk Usage",
            command: "journalctl --disk-usage",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Vacuum Systemd Journal (<200M)",
            command: "sudo journalctl --vacuum-size=200M",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Check NTP / Chrony Sync",
            command: "chronyc tracking 2>/dev/null || timedatectl status",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Verify Package Signatures (Debian)",
            command: "sudo debsums -s 2>/dev/null || echo 'debsums not installed'",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Verify Package Signatures (RPM)",
            command: "rpm -Va 2>/dev/null | head -n 20 || echo 'rpm not used'",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Inspect Kernel ASLR Status",
            command: "sysctl kernel.randomize_va_space",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Inspect AppArmor or SELinux",
            command: "sestatus 2>/dev/null || aa-status 2>/dev/null || echo 'Neither SELinux nor AppArmor'",
            category: "Security & Audit"
        ),
        CommandSnippet(
            title: "Audit Active SSH Sessions",
            command: "who -u && echo '---' && sudo netstat -tnp 2>/dev/null | grep :22",
            category: "Security & Audit"
        )
    ]
}
