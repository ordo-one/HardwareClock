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
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// Exit tests trap on purpose; a core per run fills /cores.
private func disableCoreDumps() {
    var limit = rlimit(rlim_cur: 0, rlim_max: 0)
    #if canImport(Glibc)
    _ = setrlimit(__rlimit_resource_t(RLIMIT_CORE.rawValue), &limit)
    #else
    _ = setrlimit(RLIMIT_CORE, &limit)
    #endif
}

private func monotonicNanos() -> UInt64 {
    var time = timespec()
    clock_gettime(CLOCK_MONOTONIC, &time)
    return UInt64(time.tv_sec) &* 1_000_000_000 &+ UInt64(time.tv_nsec)
}

// MARK: - Pure arithmetic tests (no hardware clock required)

@Suite("HardwareClock unit tests")
struct HardwareClockUnitTests {

    // MARK: - nanoseconds(_:) conversion

    @Test("nanoseconds(fromTicks:) converts at the stored frequency", arguments: [
        (UInt64(3_000_000_000), UInt64(0), UInt64(0)),
        (3_000_000_000, 3_000_000_000, 1_000_000_000),
        (1_000_000_000, 1, 1),
        (1_000_000_000, 1000, 1000),
        (1_000_000_000, 1_000_000_000, 1_000_000_000),
        (2_000_000_000, 2, 1),
    ])
    func nanosecondsAtFrequency(frequency: UInt64, ticks: UInt64, nanos: UInt64) {
        let clock = HardwareClock(frequency: frequency)
        #expect(clock.frequency == frequency)
        #expect(clock.nanoseconds(fromTicks: ticks) == nanos)
    }

    @Test("minimumResolution rounds one tick up to whole nanoseconds", arguments: [
        (UInt64(1_000_000_000), Duration.nanoseconds(1)),
        (3_000_000_000, .nanoseconds(1)),
        (24_000_000, .nanoseconds(42)),
    ])
    func minimumResolution(frequency: UInt64, expected: Duration) {
        #expect(HardwareClock(frequency: frequency).minimumResolution == expected)
    }

    // MARK: - Instant arithmetic

    @Test("duration(to:) converts whole-second tick deltas without overflow", arguments: [
        (UInt64(24_000_000), UInt64(1)), // typical arm64
        (3_000_000_000, 60), // typical x86_64
    ])
    func durationWholeSeconds(frequency: UInt64, seconds: UInt64) {
        let a = HardwareClock.Instant(ticks: 0, frequency: frequency)
        let b = HardwareClock.Instant(ticks: frequency * seconds, frequency: frequency)
        #expect(a.duration(to: b) == .seconds(seconds))
    }

    @Test("advanced(by:) then duration(to:) round-trips")
    func advancedDurationRoundTrip() {
        let freq: UInt64 = 24_000_000
        let a = HardwareClock.Instant(ticks: 1_000_000, frequency: freq)
        let offset: Duration = .milliseconds(500)
        let b = a.advanced(by: offset)
        #expect(a.duration(to: b) == offset)
    }

    @Test("advanced(by:) with negative duration goes backward")
    func advancedNegative() {
        let freq: UInt64 = 24_000_000
        let a = HardwareClock.Instant(ticks: freq * 10, frequency: freq) // 10s in
        let b = a.advanced(by: .seconds(-3))
        let d = b.duration(to: a)
        #expect(d == .seconds(3))
        #expect(b < a)
    }

    @Test("advanced(by:) saturates when the tick count overflows Int64")
    func advancedSaturates() {
        let a = HardwareClock.Instant(ticks: 1_000, frequency: 24_000_000)
        let later = a.advanced(by: .seconds(400_000_000_000))
        #expect(later > a)
        #expect(a.duration(to: later) > .zero)
        #expect(a.advanced(by: .seconds(-400_000_000_000)).ticks == 0)
    }

    @Test("advanced(by:) clamps a forward step past UInt64.max to UInt64.max")
    func advancedClampsAtMax() {
        let a = HardwareClock.Instant(ticks: .max - 10, frequency: 24_000_000)
        #expect(a.advanced(by: .seconds(1)).ticks == .max)
        #expect(a.advanced(by: .seconds(400_000_000_000)).ticks == .max)
    }

    @Test("nanoseconds(fromTicks:) handles frequencies above 18.4 GHz")
    func nanosecondsAtHighFrequency() {
        #expect(HardwareClock(frequency: 20_000_000_000).nanoseconds(fromTicks: 19_000_000_000) == 950_000_000)
    }

    @Test("advanced(by:) clamps a backward step past tick zero to zero")
    func advancedNegativeClampsAtZero() {
        let a = HardwareClock.Instant(ticks: 1_000, frequency: 24_000_000)
        let earlier = a.advanced(by: .seconds(-1))
        #expect(earlier.ticks == 0)
        #expect(earlier < a)
    }

    @Test("nanoseconds(fromTicks:) saturates instead of trapping on a wrapped delta")
    func nanosecondsSaturates() {
        let clock = HardwareClock(frequency: 24_000_000)
        #expect(clock.nanoseconds(fromTicks: UInt64.max) == UInt64.max)
        #expect(clock.nanoseconds(fromTicks: 0 &- 24_000_000) == UInt64.max)
    }

    @Test("duration(to:) with sub-millisecond span preserves tick precision")
    func durationSubMillisecond() {
        let freq: UInt64 = 24_000_000
        // 240 ticks at 24 MHz = 10 us. The attosecond conversion truncates
        // because 1e18 / 24e6 is not exact, so we verify via round-trip:
        // the recovered tick count should match the original delta.
        let a = HardwareClock.Instant(ticks: 1000, frequency: freq)
        let b = HardwareClock.Instant(ticks: 1240, frequency: freq)
        let d = a.duration(to: b)
        let (sec, atto) = d.components
        #expect(sec == 0)
        // Verify the nanoseconds are approximately 10 us (within 1 tick ~ 41.67 ns)
        let nanos = atto / 1_000_000_000
        #expect(nanos >= 9_950 && nanos <= 10_050, "Expected ~10000 ns, got \(nanos)")
        // Verify round-trip: advanced(by: d) should recover the original tick count
        let recovered = a.advanced(by: d)
        #expect(recovered.ticks == b.ticks)
    }

    @Test("HardwareClock.Instant round-trips through JSONEncoder/JSONDecoder")
    func instantCodableRoundTrip() throws {
        let original = HardwareClock.Instant(ticks: 0xDEAD_BEEF_CAFE, frequency: 24_000_000)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HardwareClock.Instant.self, from: data)
        #expect(decoded.ticks == original.ticks)
        #expect(decoded.frequency == original.frequency)
        #expect(decoded == original) // Hashable equality
    }

    @Test("Decoding an Instant with zero frequency throws")
    func instantDecodeZeroFrequency() {
        let data = Data(#"{"ticks":1,"frequency":0}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(HardwareClock.Instant.self, from: data) }
    }

    @Test("Instants with equal ticks and different frequencies are ordered")
    func instantOrderingTieBreak() {
        let a = HardwareClock.Instant(ticks: 1, frequency: 1)
        let b = HardwareClock.Instant(ticks: 1, frequency: 2)
        #expect(a != b)
        #expect(a < b)
        #expect(!(b < a))
    }

    @Test("Instant rejects zero frequency")
    func instantZeroFrequencyTraps() async {
        await #expect(processExitsWith: .failure) {
            disableCoreDumps()
            _ = HardwareClock.Instant(ticks: 1, frequency: 0)
        }
    }

    @Test("elapsedNanoseconds(since:) rejects an instant of a different frequency")
    func elapsedFrequencyMismatchTraps() async {
        await #expect(processExitsWith: .failure) {
            disableCoreDumps()
            _ = HardwareClock(frequency: 1).elapsedNanoseconds(since: HardwareClock.Instant(ticks: 0, frequency: 2))
        }
    }

    #if canImport(Darwin)
    @Test("a trapping exit test leaves no core in the kern.corefile directory")
    func exitTestLeavesNoCore() async throws {
        var buffer = [CChar](repeating: 0, count: 1024)
        var size = buffer.count
        try #require(sysctlbyname("kern.corefile", &buffer, &size, nil, 0) == 0)
        let directory = URL(fileURLWithPath: String(cString: buffer)).deletingLastPathComponent().path
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
        await #expect(processExitsWith: .failure) {
            disableCoreDumps()
            _ = HardwareClock.Instant(ticks: 1, frequency: 0)
        }
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
        #expect(after.subtracting(before).isEmpty)
    }
    #endif

    @Test("advanced(by:) is monotonic and agrees with nanoseconds(fromTicks:) at a non-divisor frequency")
    func exactArithmeticAtOddFrequency() {
        let freq: UInt64 = 2_995_200_000
        let clock = HardwareClock(frequency: freq)
        let a = HardwareClock.Instant(ticks: 1_000, frequency: freq)
        let almostOneSecond = Duration(secondsComponent: 0, attosecondsComponent: 999_999_999_999_999_999)
        #expect(a.advanced(by: almostOneSecond).ticks <= a.advanced(by: .seconds(1)).ticks)
        #expect(a.advanced(by: .seconds(1)).ticks == 1_000 + freq)

        let b = HardwareClock.Instant(ticks: 1_000 + freq - 1, frequency: freq)
        let nanos = a.duration(to: b).components.attoseconds / 1_000_000_000
        #expect(UInt64(nanos) == clock.nanoseconds(fromTicks: freq - 1))
        #expect(a.advanced(by: a.duration(to: b)) == b)
        #expect(b.advanced(by: b.duration(to: a)) == a)
    }

    @Test("64-bit conversion paths match full-width arithmetic")
    func conversionPathsMatchFullWidth() {
        let e18 = HardwareClock.Instant.attosecondsPerSecond
        let frequencies: [UInt64] = [1, 3, 24_000_000, 54_000_000, 1_000_000_000, 2_995_200_000, UInt64(UInt32.max)]
        for frequency in frequencies {
            let tickSamples: [UInt64] = [0, 1, frequency / 3, frequency / 2, frequency - 1]
            for ticks in tickSamples where ticks < frequency {
                let expected = frequency.dividingFullWidth(ticks.multipliedFullWidth(by: e18)).quotient
                #expect(HardwareClock.Instant.attoseconds(fromTicks: ticks, frequency: frequency) == expected)
            }
            for atto: UInt64 in [0, 1, 499_999_999_999_999_999, 500_000_000_000_000_000, e18 / 3, e18 - 1] {
                let product = atto.multipliedFullWidth(by: frequency)
                let (low, carry) = product.low.addingReportingOverflow(e18 / 2)
                let expected = e18.dividingFullWidth((product.high + (carry ? 1 : 0), low)).quotient
                #expect(HardwareClock.Instant.ticks(fromAttoseconds: atto, frequency: frequency) == expected)
            }
        }
        let limit = UInt64.max / 1_000_000_000
        for frequency in [1, 3, 2_995_200_000, limit - 1, limit, limit + 1, UInt64.max] as [UInt64] {
            let clock = HardwareClock(frequency: frequency)
            for ticks in [0, 1, frequency - 1, frequency, frequency &+ frequency / 2, UInt64.max] as [UInt64] {
                let (seconds, remainder) = ticks.quotientAndRemainder(dividingBy: frequency)
                let fraction = frequency.dividingFullWidth(remainder.multipliedFullWidth(by: 1_000_000_000)).quotient
                let (whole, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
                let expected = overflow || whole > UInt64.max - fraction ? UInt64.max : whole + fraction
                #expect(clock.nanoseconds(fromTicks: ticks) == expected)
            }
        }
    }

    @Test("frequencies above Int64.max do not trap")
    func hugeFrequency() {
        let freq = UInt64.max
        let clock = HardwareClock(frequency: freq)
        #expect(clock.minimumResolution == .nanoseconds(1))
        let a = HardwareClock.Instant(ticks: 1, frequency: freq)
        let b = a.advanced(by: .nanoseconds(1))
        #expect(a.duration(to: b) > .zero)
        #expect(a.duration(to: a.advanced(by: .seconds(-1))) <= .zero)
    }

    @Test("duration(to:) handles Int64.min ticks at 1 Hz")
    func durationExtremes() {
        let a = HardwareClock.Instant(ticks: 1 << 63, frequency: 1)
        let b = HardwareClock.Instant(ticks: 0, frequency: 1)
        #expect(a.duration(to: b) == .seconds(Int64.min))
    }
}

// MARK: - Hardware-dependent tests (skipped when hardware clock unavailable)

@Suite("HardwareClock hardware tests", .enabled(if: HardwareClock.isAvailable))
struct HardwareClockHardwareTests {

    // MARK: - readCounter() basics

    @Test("readCounter() TSC is non-zero")
    func readTscNonZero() throws {
        let reading = HardwareClock.readCounter()
        #expect(reading.ticks > 0)
    }

    @Test("readCounter() TSC advances monotonically")
    func readTscMonotonic() async throws {
        let a = HardwareClock.readCounter()
        // Sleep 1 ms so the counter reliably advances regardless of optimizer.
        try await Task.sleep(for: .milliseconds(1))
        let b = HardwareClock.readCounter()
        #expect(b.ticks > a.ticks, "TSC did not advance: \(a.ticks) -> \(b.ticks)")
    }

    @Test("readCounter().ticks and now return comparable advancing values")
    func readTscMatchesNow() throws {
        let clock = HardwareClock(frequency: 1)
        let read1 = HardwareClock.readCounter()
        let nowTicks = clock.now.ticks
        let read2 = HardwareClock.readCounter()
        // now should fall between the two reads (all on same thread, monotonic counter)
        #expect(nowTicks >= read1.ticks, "now (\(nowTicks)) should be >= readCounter().ticks (\(read1.ticks))")
        #expect(read2.ticks >= nowTicks, "readCounter().ticks (\(read2.ticks)) should be >= now (\(nowTicks))")
    }

    // MARK: - now

    @Test("now is monotonic")
    func nowMonotonic() throws {
        let clock = HardwareClock(frequency: 1)
        let a = clock.now.ticks
        let b = clock.now.ticks
        #expect(b >= a)
    }

    // MARK: - elapsedNanoseconds

    @Test("elapsedNanoseconds(sinceTicks:) returns non-zero for back-to-back calls")
    func elapsedNonZero() async throws {
        let clock = HardwareClock(frequency: 3_000_000_000)
        let start = clock.now.ticks
        // Sleep 1 ms so elapsed is non-zero regardless of optimizer.
        try await Task.sleep(for: .milliseconds(1))
        let elapsed = clock.elapsedNanoseconds(sinceTicks: start)
        #expect(elapsed > 0, "elapsed should be non-zero after work")
    }

    // MARK: - Calibration

    #if os(Linux) && arch(x86_64)
    @Test("calibrated frequency is plausible (100 MHz - 10 GHz)")
    func frequencyRangeX86() throws {
        let clock = try #require(HardwareClock.calibrate())
        #expect(clock.frequency > 100_000_000, "frequency \(clock.frequency) too low")
        #expect(clock.frequency < 10_000_000_000, "frequency \(clock.frequency) too high")
    }

    #endif

    #if arch(arm64) && (canImport(Darwin) || os(Linux))
    @Test("calibrated frequency is plausible for arm64 (1 MHz - 2 GHz)")
    func frequencyRangeArm64() throws {
        let clock = try #require(HardwareClock.calibrate())
        #expect(clock.frequency >= 1_000_000, "frequency \(clock.frequency) too low")
        #expect(clock.frequency <= 2_000_000_000, "frequency \(clock.frequency) too high")
    }

    @Test("readCounter() returns processorID == 0 on arm64")
    func readCpuZeroOnArm64() {
        let reading = HardwareClock.readCounter()
        #expect(reading.processorID == 0, "arm64 should always report processorID == 0")
    }

    @Test("nanoseconds conversion accuracy on arm64")
    func nanosecondsAccuracyArm64() throws {
        let clock = try #require(HardwareClock.calibrate())
        // frequency ticks = 1 second
        let nanos = clock.nanoseconds(fromTicks: clock.frequency)
        #expect(nanos == 1_000_000_000, "frequency ticks should convert to 1 second, got \(nanos) ns")
    }

    #endif

    // MARK: - x86_64-specific tests

    #if os(Linux) && arch(x86_64)
    @Test("readCounter() returns a plausible IA32_TSC_AUX value")
    func readCpuIdPlausible() throws {
        let reading = HardwareClock.readCounter()
        // Linux encodes (numa_node << 12) | cpu_id in IA32_TSC_AUX.
        let cpuId = reading.processorID & 0xFFF
        let numaNode = (reading.processorID >> 12) & 0xFFF
        #expect(cpuId < 1024, "CPU ID \(cpuId) is unexpectedly large")
        #expect(numaNode < 64, "NUMA node \(numaNode) is unexpectedly large")
    }

    @Test("consecutive reads on same thread see same CPU ID (retry up to 10 times)")
    func consecutiveReadsSameCpu() throws {
        var matched = false
        for _ in 0..<10 {
            let a = HardwareClock.readCounter()
            let b = HardwareClock.readCounter()
            if a.processorID == b.processorID {
                matched = true
                break
            }
        }
        #expect(matched, "Could not observe two consecutive reads on the same CPU in 10 attempts")
    }

    #endif

    // MARK: - Cross-clock validation

    @Test("counter rate matches the OS clock over a 100 ms window (within 5%)")
    func crossClockRateAgreement() throws {
        let clock = try #require(HardwareClock.calibrate())

        let sleepNs: UInt64 = 100_000_000
        var req = timespec(tv_sec: 0, tv_nsec: Int(sleepNs))

        let hwStart = clock.now.ticks
        let osStart = monotonicNanos()
        nanosleep(&req, nil)
        let osEnd = monotonicNanos()
        let hwEnd = clock.now.ticks

        let hwElapsed = clock.nanoseconds(fromTicks: hwEnd &- hwStart)
        let osElapsed = osEnd &- osStart

        let hwTicks = hwEnd &- hwStart
        let impliedFreq = Double(hwTicks) / (Double(osElapsed) / 1e9)
        let calibratedFreq = Double(clock.frequency)

        let freqRatio = impliedFreq / calibratedFreq
        #expect(
            freqRatio > 0.95 && freqRatio < 1.05,
            "implied freq \(impliedFreq) vs calibrated \(calibratedFreq) (ratio \(freqRatio)), hw=\(hwElapsed) ns, os=\(osElapsed) ns"
        )
    }
    @Test("elapsedNanoseconds(since:) returns non-zero for back-to-back calls")
    func elapsedSinceInstant() async throws {
        let clock = try #require(HardwareClock.calibrate())
        let start = clock.now
        // Sleep 1 ms so elapsed is non-zero regardless of optimizer.
        try await Task.sleep(for: .milliseconds(1))
        let nanos = clock.elapsedNanoseconds(since: start)
        #expect(nanos > 0, "elapsedNanoseconds(since:) should be non-zero after work")
    }

    @Test("sleep(until:) returns immediately for past deadline")
    func sleepPastDeadline() async throws {
        let clock = try #require(HardwareClock.calibrate())
        let past = clock.now
        // Sleep 1 ms so `past` is definitely in the past regardless of optimizer.
        try await Task.sleep(for: .milliseconds(1))
        let before = monotonicNanos()
        try await clock.sleep(until: past)
        let elapsed = monotonicNanos() &- before
        // Should return almost immediately (< 50ms)
        #expect(elapsed < 50_000_000, "sleep(until: past) took \(elapsed) ns, expected < 50ms")
    }

    @Test("sleep(until:) past deadline throws when cancelled")
    func sleepPastDeadlineCancelled() async throws {
        let clock = try #require(HardwareClock.calibrate())
        let past = clock.now
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await clock.sleep(until: past)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
#endif
