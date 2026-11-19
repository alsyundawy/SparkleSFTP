import Foundation
import SparkleCore
import SparkleNetworking
import Testing

@Suite("Remote Linux System Manager & KEX Tests")
struct RemoteSystemManagerAndKEXTests {
    @Test("RemoteSystemManager builds sanitized systemctl commands for allowed services")
    func testAllowedServiceCommands() throws {
        let cmd = try RemoteSystemManager.buildSystemctlCommand(action: .restart, service: "nginx")
        #expect(cmd == "systemctl restart nginx")

        let statusCmd = try RemoteSystemManager.buildSystemctlCommand(action: .status, service: "mariadb")
        #expect(statusCmd == "systemctl status mariadb")
    }

    @Test("RemoteSystemManager rejects non-whitelisted service targets (CWE-78)")
    func testRejectsArbitraryCommands() {
        #expect(throws: AppError.self) {
            _ = try RemoteSystemManager.buildSystemctlCommand(action: .restart, service: "evil; rm -rf /")
        }
        #expect(throws: AppError.self) {
            _ = try RemoteSystemManager.buildSystemctlCommand(action: .stop, service: "custom_daemon")
        }
    }

    @Test("RemoteSystemManager parses /proc/loadavg correctly")
    func testParseLoadAverage() {
        let sample = "0.45 0.32 0.28 2/312 9482\n"
        let parsed = RemoteSystemManager.parseLoadAverage(from: sample)
        #expect(parsed != nil)
        #expect(parsed?.oneMinute == 0.45)
        #expect(parsed?.fiveMinute == 0.32)
        #expect(parsed?.fifteenMinute == 0.28)
    }

    @Test("RemoteSystemManager parses free -m memory output correctly")
    func testParseFreeMemory() {
        let sample = """
                       total        used        free      shared  buff/cache   available
        Mem:           15892        4312        8120         128        3460       11152
        Swap:           2048           0        2048
        """
        let parsed = RemoteSystemManager.parseFreeMemory(from: sample)
        #expect(parsed != nil)
        #expect(parsed?.totalMB == 15892)
        #expect(parsed?.usedMB == 4312)
        #expect(parsed?.freeMB == 8120)
        #expect(parsed?.availableMB == 11152)
        #expect(parsed?.percentUsed ?? 0 > 27.0 && parsed?.percentUsed ?? 0 < 28.0)
    }

    @Test("SSHKeyExchangeAlgorithm identifies Post-Quantum hybrids and classical algorithms")
    func testPostQuantumKEXClassification() {
        let mlkem = SSHKeyExchangeAlgorithm.resolve(from: "mlkem768x25519-sha256")
        #expect(mlkem?.isPostQuantum == true)
        #expect(mlkem?.badgeTitle == "Post-Quantum Safe (PQ)")

        let sntrup = SSHKeyExchangeAlgorithm.resolve(from: "sntrup761x25519-sha512@openssh.com")
        #expect(sntrup?.isPostQuantum == true)

        let classical = SSHKeyExchangeAlgorithm.resolve(from: "curve25519-sha256")
        #expect(classical?.isPostQuantum == false)
        #expect(classical?.badgeTitle == "Classical Security")
    }

    @Test("SFTPOpenSSHExtensions models disk capacity and inode stats correctly")
    func testStatVFSCalculations() {
        let vfs = SFTPOpenSSHExtensions.StatVFS(
            blockSize: 4096,
            totalBlocks: 1_000_000,
            freeBlocks: 400_000,
            availableBlocks: 350_000,
            totalInodes: 500_000,
            freeInodes: 450_000
        )
        #expect(vfs.totalBytes == 4_096_000_000)
        #expect(vfs.availableBytes == 1_433_600_000)
        #expect(vfs.usedBytes == 2_662_400_000)
        #expect(vfs.percentUsed == 65.0)
    }

    @Test("RemoteProcessManager parses ps aux output and builds safe kill commands")
    func testProcessManagerCommandsAndParsing() throws {
        let sample = """
        USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
        root      1042  5.2  2.1 123456 32100 ?        Ss   09:00   0:15 /usr/sbin/nginx -g daemon on;
        www-data  1043  1.5  1.2  65432 16000 ?        S    09:01   0:04 nginx: worker process
        """
        let list = RemoteProcessManager.parseProcessList(from: sample)
        #expect(list.count == 2)
        #expect(list[0].pid == 1042)
        #expect(list[0].user == "root")
        #expect(list[0].cpuPercent == 5.2)

        let termCmd = try RemoteProcessManager.buildKillCommand(pid: 1042, signal: .term)
        #expect(termCmd == "kill -15 1042")

        let killCmd = try RemoteProcessManager.buildKillCommand(pid: 1043, signal: .kill)
        #expect(killCmd == "kill -9 1043")

        #expect(throws: AppError.self) {
            _ = try RemoteProcessManager.buildKillCommand(pid: 1, signal: .kill)
        }
    }

    @Test("RemoteProcessManager parses Docker containers and builds valid commands")
    func testDockerCommandsAndParsing() throws {
        let sample = "c1234\tnginx:alpine\tmy_nginx\tUp 2 hours\trunning\n"
        let containers = RemoteProcessManager.parseDockerContainers(from: sample)
        #expect(containers.count == 1)
        #expect(containers[0].id == "c1234")
        #expect(containers[0].name == "my_nginx")
        #expect(containers[0].isRunning == true)

        let restartCmd = try RemoteProcessManager.buildDockerCommand(action: .restart, containerId: "my_nginx")
        #expect(restartCmd == "docker restart my_nginx")

        let logsCmd = try RemoteProcessManager.buildDockerCommand(
            action: .logs,
            containerId: "my_nginx",
            tailLines: 150
        )
        #expect(logsCmd == "docker logs --tail 150 my_nginx")

        #expect(throws: AppError.self) {
            _ = try RemoteProcessManager.buildDockerCommand(action: .stop, containerId: "bad;rm -rf /")
        }
    }

    @Test("RemoteLogManager builds sanitized tail commands and rejects empty paths")
    func testRemoteLogManager() throws {
        let cmd = try RemoteLogManager.buildTailCommand(
            path: "/var/log/nginx/error.log",
            lines: 300,
            follow: true,
            useSudo: true
        )
        #expect(cmd == "sudo -n tail -n 300 -f '/var/log/nginx/error.log'")

        #expect(throws: AppError.self) {
            _ = try RemoteLogManager.buildTailCommand(path: "   ")
        }
    }

    @Test("POSIXPermissionFormatter converts between symbolic and octal representations")
    func testPOSIXPermissionFormatter() {
        #expect(POSIXPermissionFormatter.formatOctal(0o755) == "0755")
        #expect(POSIXPermissionFormatter.formatSymbolic(0o755) == "rwxr-xr-x")
        #expect(POSIXPermissionFormatter.formatSymbolic(0o644) == "rw-r--r--")

        #expect(POSIXPermissionFormatter.parseSymbolic("rwxr-xr-x") == 0o755)
        #expect(POSIXPermissionFormatter.parseSymbolic("-rw-r--r--") == 0o644)
        #expect(POSIXPermissionFormatter.parseSymbolic("invalid") == nil)

        #expect(POSIXPermissionFormatter.parseOctal("0755") == 0o755)
        #expect(POSIXPermissionFormatter.makeExecutable(0o644) == 0o755)
        #expect(POSIXPermissionFormatter.securePrivate(0o777) == 0o600)
    }
}
