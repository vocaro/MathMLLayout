import Darwin
import XCTest

/// Compare work on this thread, excluding time spent waiting for the scheduler. Repeating
/// paired samples also reduces noise from cold caches and platform font initialization.
/// These are growth guards, so no assertion depends on a machine finishing in N seconds.
func assertCPUScaling(factor: Double, _ label: String,
                      baseline: () throws -> Void, larger: () throws -> Void,
                      file: StaticString = #filePath, line: UInt = #line) rethrows {
    func now() -> Double {
        var time = timespec()
        let result = clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        XCTAssertEqual(result, 0, "thread CPU clock", file: file, line: line)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }
    func measure(_ operation: () throws -> Void) rethrows -> Double {
        let start = now()
        try operation()
        return now() - start
    }
    try baseline() // Warm fonts and other lazy platform state before comparing shapes.
    var ratios: [Double] = []
    for _ in 0..<3 {
        let before = try measure(baseline)
        let large = try measure(larger)
        let after = try measure(baseline)
        let reference = (before + after) / 2
        XCTAssertGreaterThan(reference, 0, "CPU clock resolution: \(label)", file: file, line: line)
        ratios.append(large / reference)
    }
    // One interrupted or cold sample must not turn a complexity regression guard into a
    // scheduler test. A real algorithmic regression affects all three paired samples.
    XCTAssertLessThan(ratios.min()!, factor, "\(label): CPU growth ratios \(ratios), allowed \(factor)", file: file, line: line)
}
