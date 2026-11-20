import Foundation
import SparkleCore

extension CommandSnippetStore {
    public static let posixBashSnippets4: [CommandSnippet] = [
        CommandSnippet(
            title: "POSIX Check Open Files by Mount Point (fuser)",
            command: "fuser -m /mount_point 2>/dev/null",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Kill Processes Accessing Mount Point",
            command: "sudo fuser -k -m /mount_point",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Check Disk UUIDs and Labels",
            command: "sudo blkid 2>/dev/null || diskutil info /",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Sync and Drop Memory Caches",
            command: "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches 2>/dev/null",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Display Swap Space Utilization",
            command: "swapon --show 2>/dev/null || sysctl vm.swapusage",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Create Sparse File (1GB)",
            command: "truncate -s 1G sparse_disk.img || dd if=/dev/zero of=sparse_disk.img bs=1 " +
                "count=0 seek=1G",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Zero Out File Completely",
            command: "dd if=/dev/zero of=wipe_file.bin bs=1M count=10 status=progress",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Benchmarking Disk Write Speed (dd)",
            command: "dd if=/dev/zero of=test_bench.tmp bs=1M count=1024 conv=fdatasync 2>&1; rm -f " +
                "test_bench.tmp",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Benchmarking Disk Read Speed (dd)",
            command: "dd if=/dev/sda of=/dev/null bs=1M count=1024 status=progress 2>/dev/null",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Check SMART Health Status (smartctl)",
            command: "sudo smartctl -H /dev/sda 2>/dev/null",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Check Bad Blocks on Unmounted Drive",
            command: "sudo badblocks -v /dev/sdb1 2>/dev/null",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX File System Consistency Check (fsck)",
            command: "sudo fsck -fy /dev/sdb1",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Disk Partition Table (fdisk)",
            command: "sudo fdisk -l 2>/dev/null || sudo gpt -r show /dev/disk0",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Disk I/O Realtime Stats (iostat)",
            command: "iostat -x 1 5 2>/dev/null",
            category: "POSIX Storage"
        ),
        CommandSnippet(
            title: "POSIX Tar Create Archive (Strict POSIX Format)",
            command: "tar --format=posix -cvf backup.tar source_dir/",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Tar Extract to Specific Directory",
            command: "tar -xvf backup.tar -C /dest/dir/",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Tar List Contents Without Extracting",
            command: "tar -tvf backup.tar",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Tar Gzip Compression Max Level",
            command: "GZIP=-9 tar -czvf archive.tar.gz source_dir/",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Tar Bzip2 Compression",
            command: "tar -cjvf archive.tar.bz2 source_dir/",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Tar Xz Multi-Threaded Compression",
            command: "tar -cvf - source_dir/ | xz -T0 -9 > archive.tar.xz",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Tar Exclude Pattern During Archive",
            command: "tar --exclude='*.log' --exclude='.git' -czvf app.tar.gz app/",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Tar Extract Single File from Archive",
            command: "tar -xvf backup.tar path/to/target.txt",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Tar Pipe Direct Copy to Remote SSH",
            command: "tar -cf - . | ssh remote_host 'tar -xf - -C /remote/dir/'",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Cpio Create Archive from File List",
            command: "find . -depth -print0 | cpio --null -ov > archive.cpio",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Cpio Extract Archive In-Place",
            command: "cpio -idv < archive.cpio",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Cpio List Archive Table of Contents",
            command: "cpio -it < archive.cpio",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Cpio Pass-Through Directory Tree Copy",
            command: "find . -depth -print0 | cpio --null -pvd /destination/dir/",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Gzip Compress File Keeping Original (-k)",
            command: "gzip -k -9 file.txt",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Gunzip Decompress to Stdout (-c)",
            command: "gunzip -c file.txt.gz > file.txt",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Zcat View Gzipped Text Stream",
            command: "zcat file.txt.gz | grep 'ERROR'",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Zgrep Search Inside Gzipped Archives",
            command: "zgrep -i 'exception' /var/log/syslog.*.gz",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Bzip2 Compress High Ratio (-9)",
            command: "bzip2 -k -9 large_dataset.csv",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Bzcat View Bzip2 Stream",
            command: "bzcat large_dataset.csv.bz2 | head -n 20",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Xz Compress with Maximum Compression",
            command: "xz -k -9e backup.sql",
            category: "POSIX Archive"
        ),
        CommandSnippet(
            title: "POSIX Comm Show Lines Common to Two Files",
            command: "comm -12 <(sort file1.txt) <(sort file2.txt)",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Comm Show Lines Unique to File 1",
            command: "comm -23 <(sort file1.txt) <(sort file2.txt)",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Comm Show Lines Unique to File 2",
            command: "comm -13 <(sort file1.txt) <(sort file2.txt)",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Cmp Compare Two Files Byte by Byte",
            command: "cmp -l file1.bin file2.bin | head -n 20",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Diff Unified Format (3 Lines Context)",
            command: "diff -u file1.conf file2.conf",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Diff Directory Comparison Recursive",
            command: "diff -ruN dir1/ dir2/",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Patch Apply Unified Diff Patch",
            command: "patch -p1 < changes.patch",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Patch Revert Applied Patch (-R)",
            command: "patch -R -p1 < changes.patch",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Sdiff Side-by-Side Comparison",
            command: "sdiff -w 120 file1.txt file2.txt | head -n 40",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Nl Number All Lines of File",
            command: "nl -ba -w4 -s': ' code.c",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Expand Convert Tabs to Spaces",
            command: "expand -t 4 input.py > output.py",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Unexpand Convert Spaces to Tabs",
            command: "unexpand -t 4 input.txt > output.txt",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Pr Paginate File for Printing",
            command: "pr -h 'Header Title' -l 60 file.txt",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Join Merge Two Files on Key Field",
            command: "join -t: -1 1 -2 1 <(sort file1.txt) <(sort file2.txt)",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Look Fast Binary Search in Sorted File",
            command: "look 'prefix' sorted_dictionary.txt",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Hexdump Canonical Hex and ASCII View",
            command: "hexdump -C binary_data.bin | head -n 30",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Od Octal Dump File View",
            command: "od -c input.txt",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Strings Extract Printable Strings",
            command: "strings -n 8 /bin/ls | head -n 30",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Rev Reverse Every Line Characters",
            command: "rev input.txt",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "POSIX Colrm Remove Columns from File",
            command: "colrm 1 8 < input.txt",
            category: "POSIX Text"
        ),
        CommandSnippet(
            title: "Bash Robust Script Header (Strict Mode)",
            command: "#!/usr/bin/env bash\nset -euo pipefail\nIFS=$'\\n\\t'",
            category: "Bash Patterns"
        ),
        CommandSnippet(
            title: "Bash Lockfile Concurrency Guard (flock)",
            command: "exec 200>/var/lock/myscript.lock; flock -n 200 || { echo 'Already running'; exit 1; }",
            category: "Bash Patterns"
        ),
        CommandSnippet(
            title: "Bash Read JSON Key Value (jq)",
            command: "curl -s https://api.github.com/zen | jq -r '.'",
            category: "Bash Patterns"
        ),
        CommandSnippet(
            title: "Bash Retry Loop with Exponential Backoff",
            command: "for i in {1..5}; do curl -s --fail https://api.service.com && break || sleep " +
                "$((2**i)); done",
            category: "Bash Patterns"
        ),
        CommandSnippet(
            title: "Bash Color Output Helper Constants",
            command: "RED=$'\\e[31m' GREEN=$'\\e[32m' YELLOW=$'\\e[33m' RESET=$'\\e[0m'",
            category: "Bash Patterns"
        ),
        CommandSnippet(
            title: "Bash Read Single Character Without Enter",
            command: "read -n 1 -s -r -p 'Press any key to continue...' KEY; echo",
            category: "Bash Patterns"
        ),
        CommandSnippet(
            title: "Bash Heredoc to Remote Ssh Session",
            command: "ssh user@host 'bash -s' < script.sh",
            category: "Bash Patterns"
        )
    ]
}
