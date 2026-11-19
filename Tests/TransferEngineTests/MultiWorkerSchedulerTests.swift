import Foundation
import SparkleCore
@testable import SparkleTransferEngine
import Testing

@Suite("Multi-Worker Concurrent Transfer Scheduler Tests (TASK-10.1)")
struct MultiWorkerSchedulerTests {
    @Test("TransferScheduler prioritizes small files under equal priority to prevent head-of-line blocking")
    func smallFilePriorityAdmission() async {
        let scheduler = TransferScheduler(maxGlobalConcurrent: 1, maxPerHostConcurrent: 1)

        let largeTask = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: URL(fileURLWithPath: "/tmp/large.iso")),
            destination: .remote(profileID: UUID(), host: "server.local", path: "/var/large.iso"),
            totalBytes: 50 * 1024 * 1024,
            priority: .normal
        )
        let smallTask = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: URL(fileURLWithPath: "/tmp/script.sh")),
            destination: .remote(profileID: UUID(), host: "server.local", path: "/var/script.sh"),
            totalBytes: 16 * 1024,
            priority: .normal
        )

        await scheduler.enqueue(largeTask)
        await scheduler.enqueue(smallTask)

        // Under dynamic worker allocation, smallTask (<1MB) is sorted ahead of largeTask (>1MB)
        let next = await scheduler.nextAdmissibleTask()
        #expect(next?.id == smallTask.id)
    }

    @Test("TransferScheduler enforces per-host and global concurrency caps")
    func schedulerConcurrencyLimits() async {
        let scheduler = TransferScheduler(maxGlobalConcurrent: 4, maxPerHostConcurrent: 2)

        let hostA1 = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: URL(fileURLWithPath: "/tmp/a1")),
            destination: .remote(profileID: UUID(), host: "hostA", path: "/a1"),
            totalBytes: 1024
        )
        let hostA2 = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: URL(fileURLWithPath: "/tmp/a2")),
            destination: .remote(profileID: UUID(), host: "hostA", path: "/a2"),
            totalBytes: 1024
        )
        let hostA3 = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: URL(fileURLWithPath: "/tmp/a3")),
            destination: .remote(profileID: UUID(), host: "hostA", path: "/a3"),
            totalBytes: 1024
        )

        await scheduler.enqueueBatch([hostA1, hostA2, hostA3])

        let task1 = await scheduler.nextAdmissibleTask()
        #expect(task1 != nil)
        let task2 = await scheduler.nextAdmissibleTask()
        #expect(task2 != nil)

        // Per-host limit is 2; third task for hostA cannot start yet
        let task3 = await scheduler.nextAdmissibleTask()
        #expect(task3 == nil)

        // Release slot for hostA
        await scheduler.releaseSlot(forHost: "hostA")
        let task3Admitted = await scheduler.nextAdmissibleTask()
        #expect(task3Admitted?.id == hostA3.id)
    }
}
