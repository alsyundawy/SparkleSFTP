import Foundation
import SparkleCore

extension CommandSnippetStore {
    public static let posixBashSnippets1: [CommandSnippet] = [
        CommandSnippet(
            title: "POSIX Safe Directory Traversal",
            command: "find . -type f -exec ls -ld {} +",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "Find Files Modified in Last 24 Hours",
            command: "find . -type f -mtime -1",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "Find Empty Files and Directories",
            command: "find . -empty",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Count Files in Directory",
            command: "find . -maxdepth 1 -type f | wc -l",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "Find Files by Exact Inode",
            command: "find . -inum 12345678",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "Find SUID and SGID Executables",
            command: "find / -perm /6000 -type f -exec ls -ld {} + 2>/dev/null",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Compare File Checksums (cksum)",
            command: "cksum *",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Verify Path Resolution",
            command: "command -v bash || which bash",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX File Status and Timestamp",
            command: "stat -c '%n: %s bytes, modified %y' * 2>/dev/null || stat -f '%N: %z bytes, %Sm' *",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Hard Link Creation",
            command: "ln source.txt hardlink.txt",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Symbolic Link Relative",
            command: "ln -sf target symlink",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Readlink Canonical Path",
            command: "readlink -f /path/to/symlink || realpath /path/to/symlink",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "Find Dangling Symlinks",
            command: "find . -xtype l",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Tree Simulation with Find",
            command: "find . -print | sed -e 's;[^/]*/;|____;g;s;____|; |;g'",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Safely Create Temp Directory",
            command: "TMPDIR=$(mktemp -d /tmp/spksftp.XXXXXX)",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Safely Create Temp File",
            command: "TMPFILE=$(mktemp /tmp/spksftp_file.XXXXXX)",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "Find Files by Exact Size Zero",
            command: "find . -type f -size 0c -exec rm -f {} +",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "Find Files Larger Than 100M",
            command: "find . -type f -size +100M -exec ls -lh {} +",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "Batch Set Directory Permissions (755)",
            command: "find . -type d -exec chmod 755 {} +",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "Batch Set File Permissions (644)",
            command: "find . -type f -exec chmod 644 {} +",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Synchronize Disk Buffers",
            command: "sync",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Touch File Update Timestamp",
            command: "touch -c -m target_file",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Directory Stack Navigation",
            command: "pushd /var/log && dirs -v && popd",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Read Directory File Count",
            command: "ls -1q | wc -l",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Check Available Inodes",
            command: "df -i",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Awk Delimited Field Extraction",
            command: "awk -F: '{print $1, $6, $7}' /etc/passwd",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Awk Filter by Regex Match",
            command: "awk '/ERROR|FATAL/ {print $0}' /var/log/syslog 2>/dev/null",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Sed Replace In-Place",
            command: "sed -i.bak 's/search_string/replacement/g' config.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Sed Delete Empty and Comment Lines",
            command: "sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' config.conf",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Sed Print Specific Line Range",
            command: "sed -n '10,25p' file.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Sed Prepend Line to File",
            command: "sed -i '1i\\# Header Banner' file.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Cut Extract Delimited Fields",
            command: "cut -d: -f1,3 /etc/passwd",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Cut by Byte Position",
            command: "cut -b1-16 /var/log/syslog",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Paste Combine Two Files Horizontally",
            command: "paste -d',' file1.txt file2.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Tr Remove Duplicate Blank Lines",
            command: "cat -s file.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Tr Delete Carriage Returns (CRLF to LF)",
            command: "tr -d '\\r' < dos_file.txt > unix_file.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Tr Transform Uppercase to Lowercase",
            command: "tr '[:upper:]' '[:lower:]' < input.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Tr Squeeze Repeated Characters",
            command: "tr -s ' ' < input.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Sort Unique with Count",
            command: "sort input.txt | uniq -c | sort -nr",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Sort by Numeric Column",
            command: "sort -k2,2n -t: input.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Uniq Duplicate Lines Only",
            command: "sort input.txt | uniq -d",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Uniq Unique Non-Duplicated Lines Only",
            command: "sort input.txt | uniq -u",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Fold Wrap Text at 80 Columns",
            command: "fold -w 80 -s input.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Fmt Format Paragraphs",
            command: "fmt -w 72 input.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Head First 20 Lines",
            command: "head -n 20 input.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Tail Last 20 Lines",
            command: "tail -n 20 input.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Tail Follow Multiple Logs",
            command: "tail -f /var/log/messages /var/log/secure 2>/dev/null",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Split File by Line Count",
            command: "split -l 1000 bigfile.txt part_",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Split File by Byte Chunk",
            command: "split -b 50M bigfile.tar.gz chunk_",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Csplit Split by Regex Pattern",
            command: "csplit -f section_ file.txt '/^## /' '{*}'",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Wc Count Lines Words Bytes",
            command: "wc -l -w -c file.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Grep Context Lines Before and After",
            command: "grep -C 3 'pattern' file.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Grep Invert Match Exclude Pattern",
            command: "grep -v 'exclude_pattern' file.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Grep Exact Word Boundary",
            command: "grep -w 'term' file.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "Bash Enable Strict Error Mode",
            command: "set -euo pipefail; IFS=$'\\n\\t'",
            category: "Bash Core"
        ),
        CommandSnippet(
            title: "Bash Process Substitution Compare",
            command: "diff -u <(sort file1.txt) <(sort file2.txt)",
            category: "Bash Core"
        ),
        CommandSnippet(
            title: "POSIX Process Tree with Command Line",
            command: "ps -ef --forest 2>/dev/null || ps -axo pid,ppid,user,command",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Top Memory Consuming Processes",
            command: "ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 15",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Top CPU Consuming Processes",
            command: "ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -n 15",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Find PID by Name (pgrep)",
            command: "pgrep -l -u $(whoami) ssh",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Graceful Signal Terminate (SIGTERM)",
            command: "kill -TERM <PID>",
            category: "POSIX Process"
        )
    ]
}
