import Foundation
import SparkleCore

extension CommandSnippetStore {
    public static let posixBashSnippets6: [CommandSnippet] = [
        CommandSnippet(
            title: "POSIX Check Character Class (Alpha)",
            command: "printf '%s\n' \"$VAR\" | grep -E '^[[:alpha:]]+$'",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Check Numeric Value Only",
            command: "printf '%s\n' \"$VAR\" | grep -E '^[[:digit:]]+$'",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Check Alphanumeric Value Only",
            command: "printf '%s\n' \"$VAR\" | grep -E '^[[:alnum:]]+$'",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Check Hexadecimal Value",
            command: "printf '%s\n' \"$VAR\" | grep -iE '^[0-9a-f]+$'",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Remove Trailing Newlines",
            command: "printf '%s' \"$(cat file.txt)\"",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Strip Trailing Slashes from Path",
            command: "printf '%s\n' \"${DIR%/}\"",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Strip Path File Extension",
            command: "printf '%s\n' \"${FILE%.*}\"",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Extract File Extension Only",
            command: "printf '%s\n' \"${FILE##*.}\"",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Directory Name of Path (dirname)",
            command: "dirname /path/to/file.txt",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Base Name of Path (basename)",
            command: "basename /path/to/file.txt",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Check File Is Block Device",
            command: "[ -b /dev/sda ] && echo 'Block device'",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Check File Is Character Device",
            command: "[ -c /dev/null ] && echo 'Character device'",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Check File Is FIFO / Named Pipe",
            command: "[ -p /tmp/pipe ] && echo 'Named pipe'",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Check File Is Symbolic Link",
            command: "[ -L /path/to/link ] && echo 'Symlink'",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Check File Is Socket",
            command: "[ -S /var/run/docker.sock ] && echo 'Socket'",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Test Multiple Logical AND Conditions",
            command: "[ -f \"$FILE\" ] && [ -s \"$FILE\" ] && echo 'Non-empty file'",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Test Logical OR Conditions",
            command: "[ -z \"$A\" ] || [ -z \"$B\" ] && echo 'At least one unset'",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Find Files Not Owned by Specified User",
            command: "find . -type f ! -user root",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Find Files Modified Within Minutes (-mmin)",
            command: "find /tmp -type f -mmin -60",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Find Files Accessed Within Minutes (-amin)",
            command: "find /tmp -type f -amin -30",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Find Files Changed Status (-cmin)",
            command: "find /tmp -type f -cmin -15",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Find Files with Strict Permission Match",
            command: "find . -type f -perm 0600",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Find Directory with Write Permission for Group",
            command: "find . -type d -perm -g+w",
            category: "POSIX Files"
        ),
        CommandSnippet(
            title: "POSIX Generate SHA1 Checksum",
            command: "openssl sha1 file.txt || sha1sum file.txt",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Base64 Encode String",
            command: "printf '%s' 'secret_payload' | base64",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Base64 Decode to Stdout",
            command: "printf '%s' 'c2VjcmV0X3BheWxvYWQ=' | base64 -d",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Base64 Encode Multi-line File",
            command: "base64 < binary_file.bin > encoded.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX URL Decode String with Hex Printf",
            command: "sed 's/+/ /g; s/%/\\\\x/g' | xargs -0 printf '%b'",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Strip ANSI Escape Color Sequences",
            command: "sed -E 's/\\\\x1B\\[[0-9;]*[mK]//g' colored_output.log 2>/dev/null",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Print Duplicate Lines with Frequency",
            command: "awk '{count[$0]++} END {for (line in count) if (count[line] > 1) print " +
                "count[line], line}' file.txt",
            category: "POSIX Streams"
        ),
        CommandSnippet(
            title: "POSIX Invert Case of First Character",
            command: "NAME=\"alice\"; echo \"${NAME^}\"",
            category: "Bash Core"
        ),
        CommandSnippet(
            title: "POSIX Invert Case of Entire String",
            command: "NAME=\"AlIcE\"; echo \"${NAME~~}\"",
            category: "Bash Core"
        ),
        CommandSnippet(
            title: "POSIX Check If Variable Is Set At All (-v)",
            command: "[[ -v CONFIG_FLAG ]] && echo 'Declared'",
            category: "Bash Core"
        ),
        CommandSnippet(
            title: "POSIX Read Null Delimited Stream in While Loop",
            command: "find . -type f -print0 | while IFS= read -r -d '' file; do echo \"File: $file\"; done",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Measure Time in Seconds and Exit Code",
            command: "{ time command ; } 2> time.log",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Batch Touch Create Numbered Files",
            command: "touch file_{001..050}.txt",
            category: "Bash Core"
        ),
        CommandSnippet(
            title: "POSIX Batch Rename with Prefix Strip",
            command: "for f in prefix_*.txt; do mv \"$f\" \"${f#prefix_}\"; done",
            category: "Bash Core"
        ),
        CommandSnippet(
            title: "POSIX Batch Rename Replace Extension",
            command: "for f in *.jpeg; do mv \"$f\" \"${f%.jpeg}.jpg\"; done",
            category: "Bash Core"
        ),
        CommandSnippet(
            title: "POSIX Execute Function in Background with PID",
            command: "long_worker() { sleep 10; }; long_worker & echo \"Worker PID: $!\"",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Kill Children Processes of Current Shell",
            command: "pkill -P $$ 2>/dev/null || true",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Wait for Specific Background PID",
            command: "sleep 5 & PID=$!; wait $PID && echo 'Finished'",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Check if Port is Free on Localhost",
            command: "! nc -z 127.0.0.1 8080 2>/dev/null && echo 'Port is free'",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Test SOCKS5 Proxy Connection",
            command: "curl -x socks5h://127.0.0.1:1080 -s https://ifconfig.co",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX HTTP Download Resuming Broken Transfer (-C -)",
            command: "curl -C - -O -L https://example.com/large_iso.iso",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX HTTP Follow Redirects Only Show Final URL",
            command: "curl -s -L -o /dev/null -w '%{url_effective}\n' https://httpbin.org/redirect/3",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX HTTP Post JSON Body with Headers",
            command: "curl -s -X POST -H 'Content-Type: application/json' -d '{\"status\":\"ok\"}' " +
                "https://httpbin.org/post",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check DNS Response Latency",
            command: "dig example.com | grep 'Query time'",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check SSH Agent Loaded Keys",
            command: "ssh-add -l",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Add SSH Key to Agent with Lifetime (1 hour)",
            command: "ssh-add -t 3600 ~/.ssh/id_ed25519",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Delete All Keys from SSH Agent",
            command: "ssh-add -D",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Lock SSH Agent with Passphrase",
            command: "ssh-add -x",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Unlock SSH Agent with Passphrase",
            command: "ssh-add -X",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Test SSH Key Signature Verification",
            command: "ssh-keygen -Y sign -f ~/.ssh/id_ed25519 -n file payload.txt",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Convert OpenSSH Key to PKCS8 PEM",
            command: "ssh-keygen -e -m PKCS8 -f ~/.ssh/id_rsa > rsa_pkcs8.pem",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Change SSH Private Key Passphrase",
            command: "ssh-keygen -p -f ~/.ssh/id_ed25519",
            category: "POSIX Security"
        ),
        CommandSnippet(
            title: "POSIX Check Git Repository Status Concisely",
            command: "git status -s -b",
            category: "Bash Patterns"
        ),
        CommandSnippet(
            title: "POSIX Verify SSH Configuration Syntax",
            command: "ssh -G localhost",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Display Open SSH Sockets (ControlMaster)",
            command: "ssh -O check user@host 2>/dev/null",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Graceful SSH ControlMaster Exit",
            command: "ssh -O exit user@host 2>/dev/null",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Clear Screen and Terminal Scrollback",
            command: "printf '\\033[2J\\033[3J\\033[H'",
            category: "POSIX Env"
        )
    ]
}
