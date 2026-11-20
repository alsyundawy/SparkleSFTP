import Foundation
import SparkleCore

extension CommandSnippetStore {
    public static let posixBashSnippets2: [CommandSnippet] = [
        CommandSnippet(
            title: "POSIX Immediate Force Kill (SIGKILL)",
            command: "kill -9 <PID>",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Hangup Reload Config (SIGHUP)",
            command: "kill -HUP <PID>",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Kill All by Process Name",
            command: "pkill -f 'worker_process'",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Check If Process is Running",
            command: "kill -0 <PID> 2>/dev/null && echo 'Running' || echo 'Stopped'",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Run Process in Background Unattended",
            command: "nohup ./long_job.sh > job.log 2>&1 &",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Disown Active Background Job",
            command: "disown -h %1",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX View Active Shell Jobs",
            command: "jobs -l",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Wait for Background PIDs to Finish",
            command: "wait $PID1 $PID2 && echo 'All completed'",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Nice Process Priority Execution",
            command: "nice -n 19 ./heavy_task.sh",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Renice Running Process Priority",
            command: "renice -n 10 -p <PID>",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Process Limits (ulimit)",
            command: "ulimit -a",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Open File Limit Increase",
            command: "ulimit -n 65535",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Time Command Execution",
            command: "time ./script.sh",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Run Command with Timeout",
            command: "timeout 30s curl -s https://example.com || echo 'Timed out'",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Execute with Fresh Environment",
            command: "env -i PATH=/usr/bin:/bin HOME=$HOME ./script.sh",
            category: "POSIX Process"
        ),
        CommandSnippet(
            title: "POSIX Hexadecimal to Decimal Conversion",
            command: "printf '%d\\n' 0xFF",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Decimal to Hexadecimal Conversion",
            command: "printf '0x%X\\n' 255",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Decimal to Octal Conversion",
            command: "printf '%o\\n' 511",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Random Number Generation (od)",
            command: "od -vAn -N4 -tu4 < /dev/urandom | tr -d ' '",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Generate Random Alphanumeric String",
            command: "LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32; echo",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Generate Secure Random Hex Token",
            command: "head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \\n'",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Sequential Number Generation (seq)",
            command: "seq 1 10",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Sequential Number Padded Format",
            command: "seq -f 'node%03g' 1 20",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Read Input with Custom Prompt",
            command: "printf 'Enter target: '; read -r TARGET",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Silent Password Input (No Echo)",
            command: "stty -echo; printf 'Password: '; read -r PASS; stty echo; echo",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "POSIX Exit Shell with Status Code",
            command: "exit 0",
            category: "POSIX Scripting"
        ),
        CommandSnippet(
            title: "Redirect Stdout and Stderr to Single File",
            command: "command > output.log 2>&1",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "Redirect Stdout to File, Discard Stderr",
            command: "command > output.log 2>/dev/null",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "Discard Both Stdout and Stderr (/dev/null)",
            command: "command >/dev/null 2>&1",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "Append Stdout and Stderr to File (>>)",
            command: "command >> append.log 2>&1",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Tee Duplicate Output to Screen and File",
            command: "command 2>&1 | tee output.log",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Tee Append Output (tee -a)",
            command: "command 2>&1 | tee -a append.log",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Pipe Stderr to Next Command",
            command: "command 2>&1 >/dev/null | grep 'error'",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Create Custom File Descriptor (FD 3)",
            command: "exec 3> custom_output.log; echo 'log message' >&3; exec 3>&-",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Read Input from Custom File Descriptor",
            command: "exec 3< input.txt; read -r FIRST_LINE <&3; exec 3<&-",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Close File Descriptor 3",
            command: "exec 3>&-",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Named Pipe (FIFO) Creation",
            command: "mkfifo /tmp/named_pipe && ls -ld /tmp/named_pipe",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Write to Named Pipe in Background",
            command: "cat /var/log/syslog > /tmp/named_pipe &",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Read from Named Pipe",
            command: "grep 'CRON' < /tmp/named_pipe",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Heredoc With Strip Leading Tabs",
            command: "cat <<- EOF\n\tTab-stripped block\nEOF",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Xargs Batch Command Execution",
            command: "find . -name '*.log' -print0 | xargs -0 rm -f",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Xargs Limit Arguments per Command (-n)",
            command: "echo 1 2 3 4 5 6 | xargs -n 2 echo 'Pair:'",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Xargs Parallel Command Execution (-P)",
            command: "cat urls.txt | xargs -P 4 -n 1 curl -s -O",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Xargs Replacement String Placeholder (-I)",
            command: "ls *.tar.gz | xargs -I {} tar -ztf {}",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Subshell Isolation (() vs {})",
            command: "( cd /tmp && ls -la ); pwd",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Current Shell Grouping ({ ...; })",
            command: "{ echo 'Step 1'; echo 'Step 2'; } > steps.log",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Clean Stderr Suppress Warning Only",
            command: "grep 'key' /etc/* 2>/dev/null",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Binary Safe Stream Null Separation",
            command: "find . -type f -name '*.txt' -print0 | xargs -0 wc -l",
            category: "POSIX I/O"
        ),
        CommandSnippet(
            title: "POSIX Check Remote TCP Port (/dev/tcp)",
            command: "(echo > /dev/tcp/1.1.1.1/53) >/dev/null 2>&1 && echo 'Port open' || echo 'Closed'",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Fetch HTTP Headers via /dev/tcp",
            command: "exec 3<>/dev/tcp/example.com/80; printf 'HEAD / HTTP/1.0\\r\\nHost: " +
            "example.com\\r\\n\\r\\n' >&3; cat <&3; exec 3<&-",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Netcat Simple Port Scan",
            command: "nc -z -v -w2 127.0.0.1 20-30",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Netcat Listen Simple Socket Server",
            command: "nc -l -p 9000",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Netcat Send File Over Network",
            command: "nc 192.168.1.50 9000 < backup.tar.gz",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Netcat Receive File Over Network",
            command: "nc -l -p 9000 > received_backup.tar.gz",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Query DNS Record via Dig",
            command: "dig +short A example.com",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Query DNS MX Mail Records",
            command: "dig +short MX example.com",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Query DNS TXT Records (SPF/DKIM)",
            command: "dig +short TXT example.com",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Reverse DNS Lookup (PTR)",
            command: "dig +short -x 8.8.8.8",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX DNS Trace Complete Delegation",
            command: "dig +trace example.com",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Query Specific DNS Nameserver",
            command: "dig @1.1.1.1 example.com +short",
            category: "POSIX Network"
        ),
        CommandSnippet(
            title: "POSIX Check Domain Expiry via Whois",
            command: "whois example.com | grep -iE 'expiry|expiration'",
            category: "POSIX Network"
        )
    ]
}
