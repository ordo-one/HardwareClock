// ===----------------------------------------------------------------------===//
//
// Copyright © 2022-2026 Ordo One AB
//
// Licensed under Apache License v2.0
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2022-2026 Ordo One AB
//
// https://ordo.one
//
// ===----------------------------------------------------------------------===//

#if (os(Linux) && arch(x86_64)) || (arch(arm64) && (canImport(Darwin) || os(Linux)))
import Foundation
@testable import HardwareClock
import Testing

@Suite("HardwareClock calibration")
struct CalibrationTests {
    @Test("calibration reference clock is monotonic and un-slewed")
    func calibrationReferenceIsMonotonic() {
        var previous = HardwareClock.calibrationReferenceNanos()
        for _ in 0 ..< 1000 {
            let current = HardwareClock.calibrationReferenceNanos()
            #expect(current >= previous)
            previous = current
        }

        // Guards against a reference that does not advance or measures a different epoch.
        let start = HardwareClock.calibrationReferenceNanos()
        let osStart = ContinuousClock.now
        while ContinuousClock.now - osStart < .milliseconds(5) {}
        let elapsed = HardwareClock.calibrationReferenceNanos() &- start
        #expect(elapsed > 1_000_000)
        #expect(elapsed < 100_000_000)
    }

    @Test("real calibration is repeatable across runs", .enabled(if: HardwareClock.isAvailable))
    func calibrationIsRepeatable() throws {
        let first = try #require(HardwareClock.calibrate()).frequency
        let second = try #require(HardwareClock.calibrate()).frequency

        let spread = Double(max(first, second) - min(first, second)) / Double(min(first, second))
        #expect(spread < 0.001, "frequency spread \(spread) between \(first) and \(second)")
    }

    @Test("sample frequency rejects backwards and zero-length samples")
    func sampleFrequencyGuards() {
        #expect(HardwareClock._sampleFrequency(ticks: 10, 5, nanos: 1_000) == nil)
        #expect(HardwareClock._sampleFrequency(ticks: 0, 1_000, nanos: 0) == nil)
        #expect(HardwareClock._sampleFrequency(ticks: 0, 1_000, nanos: 1_000) == 1_000_000_000)
        #expect(HardwareClock._sampleFrequency(ticks: 0, .max, nanos: 1) == nil)
    }
}
#endif
