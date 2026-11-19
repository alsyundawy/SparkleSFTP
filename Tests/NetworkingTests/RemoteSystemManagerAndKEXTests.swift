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
}
