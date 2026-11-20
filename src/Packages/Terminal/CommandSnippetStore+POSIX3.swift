import Foundation
import SparkleCore

extension CommandSnippetStore {
    public static let posixBashSnippets3: [CommandSnippet] = [
        CommandSnippet(
            title: "POSIX Network Interface IP Addresses",
            command: "ip addr show || ifconfig -a",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Network Routing Table",
            command: "ip route show || netstat -rn",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check Default Gateway IP",
            command: "ip route | awk '/default/ {print $3}'",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Ping Network Host with Count Limit",
            command: "ping -c 4 -W 2 8.8.8.8",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Traceroute to Remote Host",
            command: "traceroute -n -w 2 8.8.8.8",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Display ARP / Neighbor Table",
            command: "ip neigh show || arp -an",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Show Network Interface Statistics",
            command: "netstat -i || ip -s link",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Current User Name and UID",
            command: "id -un && id -u",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Current User Groups (Numeric & Name)",
            command: "id -G && id -Gn",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX List All Logged In Users",
            command: "who -u || w",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX List Last System Logins",
            command: "last -n 20",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX List Last Bad Login Attempts",
            command: "lastb -n 20 2>/dev/null || last -x",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Lookup Group Entry in /etc/group",
            command: "getent group sudo || grep '^sudo:' /etc/group",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Change File Owner and Group",
            command: "chown user:group target_file",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Recursive Change Ownership",
            command: "chown -R www-data:www-data /var/www/html",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Change File Group Only",
            command: "chgrp developers shared_directory",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Set Sticky Bit on Directory",
            command: "chmod +t /tmp/shared_dir",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Set SUID Bit on Executable",
            command: "chmod u+s /path/to/binary",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Set SGID Bit on Directory (Group Inherit)",
            command: "chmod g+s /var/shared_projects",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Display Default Umask Value",
            command: "umask",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Set Strict Umask (027)",
            command: "umask 027",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX View User Password Expiry (chage)",
            command: "sudo chage -l $(whoami) 2>/dev/null",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Lock User Account",
            command: "sudo passwd -l target_user",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Unlock User Account",
            command: "sudo passwd -u target_user",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX Change Current Working Group",
            command: "newgrp target_group",
            category: "POSIX Auth"
        ),
        CommandSnippet(
            title: "POSIX System Architecture and Kernel",
            command: "uname -s -r -m -p",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Hostname Display",
            command: "uname -n || hostname",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX System Uptime and Load Average",
            command: "uptime",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Formatted Date and Time (ISO 8601)",
            command: "date -u +'%Y-%m-%dT%H:%M:%SZ'",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Epoch Seconds Timestamp",
            command: "date +%s",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Convert Epoch Seconds to Date",
            command: "date -d @1700000000 2>/dev/null || date -r 1700000000",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Memory Usage Summary",
            command: "free -m 2>/dev/null || vm_stat",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX CPU Core Count and Model",
            command: "getconf _NPROCESSORS_ONLN 2>/dev/null || nproc",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX System Page Size in Bytes",
            command: "getconf PAGESIZE",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Maximum Argument Length (ARG_MAX)",
            command: "getconf ARG_MAX",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Open Files Maximum System Limit",
            command: "getconf OPEN_MAX",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Standard Path Configuration",
            command: "getconf PATH",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Check System Bit Architecture",
            command: "getconf LONG_BIT",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Cron User Jobs List",
            command: "crontab -l",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX System Reboots History",
            command: "last reboot -n 10",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX System Shutdown History",
            command: "last shutdown -n 10",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Write Message to All Logged In Users",
            command: "wall 'Server maintenance in 10 minutes.'",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Terminal Device Name",
            command: "tty",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Terminal Window Size (Rows Columns)",
            command: "stty size",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Reset Stuck Terminal Attributes",
            command: "stty sane && reset",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX View Active Kernel Modules",
            command: "lsmod 2>/dev/null || kextstat",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Check PCI Devices List",
            command: "lspci 2>/dev/null || system_profiler SPPCIDataType",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Check USB Devices List",
            command: "lsusb 2>/dev/null || system_profiler SPUSBDataType",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Check Block Storage Devices",
            command: "lsblk 2>/dev/null || diskutil list",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Check SCSI / SATA Disks",
            command: "lsscsi 2>/dev/null || diskutil list",
            category: "POSIX SysAdmin"
        ),
        CommandSnippet(
            title: "POSIX Human Readable Disk Free",
            command: "df -h -P",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Filesystem Types Disk Free",
            command: "df -T 2>/dev/null || df -t ufs,apfs,ext4",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Disk Usage of Current Folder",
            command: "du -sh .",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Disk Usage of Subdirectories (Depth 1)",
            command: "du -h -d 1 2>/dev/null || du -h --max-depth=1",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Find 10 Largest Folders in Directory",
            command: "du -sk * 2>/dev/null | sort -nr | head -n 10",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX View Mounted Filesystems",
            command: "mount",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX View Mounted Filesystems Formatted",
            command: "df -P -k | column -t",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Mount Read-Only Remount",
            command: "sudo mount -o remount,ro /mount_point",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Mount Read-Write Remount",
            command: "sudo mount -o remount,rw /mount_point",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Unmount Lazy / Force",
            command: "sudo umount -l /mount_point 2>/dev/null || sudo umount -f /mount_point",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Mount ISO Image Loopback",
            command: "sudo mount -o loop image.iso /mnt/iso",
            category: "POSIX Storage"
        )
    ]
}
