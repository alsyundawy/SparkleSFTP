import Foundation
@testable import SparkleTransferEngine
import Testing

private final class SimulatedPipelineClock:
    @unchecked Sendable { // JUSTIFICATION: Synchronized via internal NSLock for deterministic test simulation.
    private let lock = NSLock()
    private var currentTime: TimeInterval

    init(initial: TimeInterval = 1000.0) {
        currentTime = initial
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        currentTime += seconds
        lock.unlock()
    }

    func now() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return currentTime
    }
}

@Suite("Auto Pipeline Depth Adaptation Tests")
struct AutoPipelineControllerTests {
    @Test("Controller widens pipeline window under sustained high utilization")
    func pipelineWidening() {
        let clock = SimulatedPipelineClock(initial: 1000.0)
        let controller = AutoPipelineController(
            initialDepth: 4,
            minDepth: 1,
            maxDepth: 16,
            timeProvider: { clock.now() }
        )
        #expect(controller.depth == 4)

        // Advance 2.5 seconds with 90% utilization
        clock.advance(by: 2.5)
        controller.recordSuccess(bytes: 131_072, inFlightFraction: 0.9)
        #expect(controller.depth == 6)

        // Advance another 2.5 seconds with high utilization
        clock.advance(by: 2.5)
        controller.recordSuccess(bytes: 131_072, inFlightFraction: 0.85)
        #expect(controller.depth == 8)
    }

    @Test("Controller throttles pipeline depth by 50% on stall or backpressure")
    func pipelineThrottlingOnStall() {
        let clock = SimulatedPipelineClock(initial: 1000.0)
        let controller = AutoPipelineController(
            initialDepth: 8,
            minDepth: 1,
            maxDepth: 16,
            timeProvider: { clock.now() }
        )
        #expect(controller.depth == 8)

        controller.recordStallOrBackpressure()
        #expect(controller.depth == 4)

        controller.recordStallOrBackpressure()
        #expect(controller.depth == 2)
    }
}
