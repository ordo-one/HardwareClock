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

#if canImport(Darwin)
internal import Darwin
#elseif canImport(Glibc)
internal import Glibc
#elseif canImport(Musl)
internal import Musl
#endif

#if (os(Linux) && arch(x86_64)) || (arch(arm64) && (canImport(Darwin) || os(Linux)))
extension HardwareClock {
    /// Creates a clock with the CPU-reported or measured counter frequency, or `nil` if ``isAvailable`` is false
    /// or measurement does not converge.
    ///
    /// Uses `CNTFRQ_EL0` on arm64 and CPUID leaf 0x15 on x86_64 when the CPU reports them. Otherwise busy-spins
    /// the calling thread against `CLOCK_MONOTONIC_RAW`, sampling every 10 ms until 5 consecutive estimates agree
    /// within 0.1%, and returns `nil` after 2 s without agreement.
    public static func calibrate() -> HardwareClock? {
        isAvailable ? _calibrate() : nil
    }

    private static func _calibrate() -> HardwareClock? {
        if let freq = _exactFrequency() {
            return HardwareClock(frequency: freq)
        }

        let spinInterval: UInt64 = 10_000_000
        let maxDuration: UInt64 = 2_000_000_000
        let convergenceCount = 5
        let convergenceThreshold = 0.001

        let wall0 = calibrationReferenceNanos()
        let tsc0 = readCounter().ticks

        var recent = [UInt64](repeating: 0, count: convergenceCount)
        var sampleCount = 0
        var target: UInt64 = 0

        while true {
            // Advances even when a sample is rejected, so a backwards counter does not turn the wait into a hot loop.
            target += spinInterval
            while calibrationReferenceNanos() &- wall0 < target {}

            let wall1 = calibrationReferenceNanos()
            let tsc1 = readCounter().ticks
            if let freq = _sampleFrequency(ticks: tsc0, tsc1, nanos: wall1 &- wall0) {
                recent[sampleCount % convergenceCount] = freq
                sampleCount += 1
            }

            if sampleCount >= convergenceCount {
                let minFreq = recent.min()!
                let maxFreq = recent.max()!
                let mid = minFreq + (maxFreq - minFreq) / 2
                if mid > 0 && Double(maxFreq - minFreq) / Double(mid) < convergenceThreshold {
                    var sorted = recent
                    sorted.sort()
                    return HardwareClock(frequency: sorted[convergenceCount / 2])
                }
            }

            if wall1 &- wall0 >= maxDuration {
                return nil
            }
        }
    }

    /// Ticks per second over one sample; `nil` when the counter went backwards, which unsynchronized
    /// TSCs allow after a core migration, or the rate does not fit `UInt64`.
    static func _sampleFrequency(ticks start: UInt64, _ end: UInt64, nanos: UInt64) -> UInt64? {
        guard nanos > 0, end >= start else { return nil }
        let rate = Double(end - start) / Double(nanos) * 1_000_000_000.0
        return rate < 0x1p64 ? UInt64(rate) : nil
    }

    /// Un-slewed monotonic nanoseconds, the calibration reference.
    ///
    /// `CLOCK_MONOTONIC` carries the NTP/PTP rate adjustment, which calibration would bake
    /// into the tick frequency as permanent drift (several ppm under PTP or NTP discipline).
    static func calibrationReferenceNanos() -> UInt64 {
        var time = timespec()
        // A zero return would hang _calibrate's busy-spin, so fall back rather than trust it.
        guard clock_gettime(CLOCK_MONOTONIC_RAW, &time) == 0 else {
            clock_gettime(CLOCK_MONOTONIC, &time)
            return UInt64(time.tv_sec) &* 1_000_000_000 &+ UInt64(time.tv_nsec)
        }
        return UInt64(time.tv_sec) &* 1_000_000_000 &+ UInt64(time.tv_nsec)
    }
}
#endif
