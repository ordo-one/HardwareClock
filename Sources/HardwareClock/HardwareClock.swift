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
/// A clock backed by the CPU's hardware counter, read inline.
///
/// Call ``calibrate()`` once, then use ``now`` or ``readCounter()`` for low-overhead timestamps.
/// The clock is immutable and `Sendable`; every member is safe to call from any thread.
@frozen
public struct HardwareClock: Clock, Sendable {
    /// A tick count with its frequency, so `InstantProtocol` arithmetic needs no clock.
    @frozen
    public struct Instant: Sendable, Codable, Hashable {
        /// Raw counter ticks since an arbitrary epoch.
        public let ticks: UInt64
        /// Counter ticks per second (copied from the originating ``HardwareClock``).
        public let frequency: UInt64

        /// Creates an instant from a raw tick count and the counter frequency in ticks per second.
        ///
        /// - Precondition: `frequency` must be greater than zero.
        @inlinable
        public init(ticks: UInt64, frequency: UInt64) {
            precondition(frequency > 0, "HardwareClock.Instant frequency must be > 0")
            self.init(uncheckedTicks: ticks, frequency: frequency)
        }

        // Callers pass a frequency already validated by `HardwareClock.init` or a checked `Instant`.
        @usableFromInline
        init(uncheckedTicks ticks: UInt64, frequency: UInt64) {
            self.ticks = ticks
            self.frequency = frequency
        }

        /// Decodes an instant from its `ticks` and `frequency` keys.
        ///
        /// - Throws: `DecodingError.dataCorrupted` if `frequency` is zero, or any error from `decoder`.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let frequency = try container.decode(UInt64.self, forKey: .frequency)
            guard frequency > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .frequency, in: container, debugDescription: "frequency must be > 0")
            }
            self.init(uncheckedTicks: try container.decode(UInt64.self, forKey: .ticks), frequency: frequency)
        }
    }

    /// A single counter reading: tick value and processor ID.
    @frozen
    public struct Reading: Sendable {
        /// The 64-bit counter value.
        public let ticks: UInt64
        /// `IA32_TSC_AUX` on x86_64, which Linux sets to `(numa_node << 12) | cpu_id`; always 0 on arm64.
        ///
        /// Compare across two reads to detect a core migration; `processorID & 0xFFF` is the bare CPU index.
        /// See [Linux vdso/processor.h](https://github.com/torvalds/linux/blob/v6.12/arch/x86/include/asm/vdso/processor.h).
        public let processorID: UInt32

        /// Creates a reading from a tick value and processor ID.
        @inlinable
        public init(ticks: UInt64, processorID: UInt32) {
            self.ticks = ticks
            self.processorID = processorID
        }
    }

    // MARK: - Public API

    /// Counter ticks per second, determined during calibration.
    public let frequency: UInt64

    /// Creates a clock with a known counter frequency (ticks per second), skipping the ``isAvailable`` check.
    ///
    /// - Precondition: `frequency` must be greater than zero.
    public init(frequency: UInt64) {
        precondition(frequency > 0, "HardwareClock frequency must be > 0")
        self.frequency = frequency
    }

    // MARK: - Clock protocol

    /// The current instant from the hardware counter, stamped with this clock's ``frequency``.
    @inlinable
    public var now: Instant {
        Instant(uncheckedTicks: Self.readCounter().ticks, frequency: frequency)
    }

    /// One counter tick, rounded up to a whole nanosecond.
    public var minimumResolution: Duration {
        .nanoseconds(frequency >= 1_000_000_000 ? 1 : Int64((1_000_000_000 + frequency - 1) / frequency))
    }

    /// Suspends until `deadline`, timing the wait with `ContinuousClock` via `Task.sleep(for:tolerance:)`.
    ///
    /// - Precondition: `deadline.frequency` equals this clock's ``frequency``.
    /// - Throws: `CancellationError` if the task is cancelled, even when `deadline` has passed.
    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let remaining = now.duration(to: deadline)
        // A past-deadline Task.sleep took over 50 ms on Linux CI (Swift 6.2); return at once, keeping its cancellation check.
        guard remaining > .zero else { return try Task.checkCancellation() }
        try await Task.sleep(for: remaining, tolerance: tolerance)
    }

    // MARK: - Reading & conversion

    /// Converts a tick delta to whole nanoseconds, truncating, and saturating at `UInt64.max`
    /// (e.g. a wrapped ``elapsedNanoseconds(sinceTicks:)`` delta).
    @inlinable
    public func nanoseconds(fromTicks ticks: UInt64) -> UInt64 {
        let seconds = ticks / frequency
        let remainderTicks = ticks % frequency
        // remainderTicks < frequency, so the product fits 64 bits up to ~18.4 GHz, avoiding the 128-bit divide.
        let nanosecondRemainder = frequency <= UInt64.max / 1_000_000_000
            ? remainderTicks * 1_000_000_000 / frequency
            : frequency.dividingFullWidth(remainderTicks.multipliedFullWidth(by: 1_000_000_000)).quotient
        let (wholeNanoseconds, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflow, wholeNanoseconds <= UInt64.max - nanosecondRemainder else { return UInt64.max }
        return wholeNanoseconds + nanosecondRemainder
    }

    /// Nanoseconds elapsed since a raw tick value from ``readCounter()``.
    ///
    /// A `start` later than the current reading (e.g. from an unsynchronized core) wraps to a huge
    /// tick delta rather than a negative one.
    @inlinable
    public func elapsedNanoseconds(sinceTicks start: UInt64) -> UInt64 {
        nanoseconds(fromTicks: Self.readCounter().ticks &- start)
    }

    /// Nanoseconds elapsed since a previous instant; wraps like ``elapsedNanoseconds(sinceTicks:)``.
    ///
    /// - Precondition: `start.frequency` equals this clock's ``frequency``.
    @inlinable
    public func elapsedNanoseconds(since start: Instant) -> UInt64 {
        precondition(start.frequency == frequency, "Cannot measure elapsed time from an instant of a different frequency (\(start.frequency) vs \(frequency))")
        return nanoseconds(fromTicks: Self.readCounter().ticks &- start.ticks)
    }
}

// MARK: - HardwareClock.Instant + InstantProtocol

extension HardwareClock.Instant: InstantProtocol {
    /// The instant `duration` later (earlier if negative), rounded to the nearest tick.
    ///
    /// Clamps to tick 0 and `UInt64.max`; a duration overflowing `Int64` ticks lands at tick 0 if negative,
    /// else `Int64.max` ticks ahead.
    public func advanced(by duration: Duration) -> HardwareClock.Instant {
        let (seconds, attoseconds) = duration.components
        let fractionTicks = Int128(Self.ticks(fromAttoseconds: attoseconds.magnitude, frequency: frequency))
        let (sum, overflow) = (Int128(seconds) * Int128(frequency))
            .addingReportingOverflow(attoseconds < 0 ? -fractionTicks : fractionTicks)
        let delta = overflow ? (seconds < 0 ? Int128.min : Int128.max) : sum
        let target: Int128 = if delta > Int128(Int64.max) {
            // Cap at Int64.max ticks ahead so duration(to:) still reads the result as positive.
            Int128(ticks) + Int128(Int64.max)
        } else if delta < Int128(Int64.min) {
            0
        } else {
            Int128(ticks) + delta
        }
        return HardwareClock.Instant(uncheckedTicks: UInt64(clamping: target), frequency: frequency)
    }

    /// The signed duration from this instant to `other`, reading the tick difference as a wrapping `Int64`,
    /// truncated to whole attoseconds.
    ///
    /// - Precondition: Both instants have the same ``frequency``.
    public func duration(to other: HardwareClock.Instant) -> Duration {
        precondition(frequency == other.frequency,
                     "Cannot compute duration between instants with different frequencies (\(frequency) vs \(other.frequency))")
        let delta = Int64(bitPattern: other.ticks &- ticks)
        let (seconds, remainder) = delta.magnitude.quotientAndRemainder(dividingBy: frequency)
        let attoseconds = Int64(Self.attoseconds(fromTicks: remainder, frequency: frequency))
        // seconds is 2^63 only for Int64.min ticks at 1 Hz, which the wrapping negation maps to Int64.min.
        return delta < 0
            ? Duration(secondsComponent: Int64(truncatingIfNeeded: 0 &- seconds), attosecondsComponent: -attoseconds)
            : Duration(secondsComponent: Int64(seconds), attosecondsComponent: attoseconds)
    }

    static let attosecondsPerSecond: UInt64 = 1_000_000_000_000_000_000

    // Up to 2^32 Hz the products below fit 64 bits, avoiding the 128-bit divide (a runtime call on arm64).

    /// `ticks * 1e18 / frequency`, truncated, for `ticks < frequency`.
    static func attoseconds(fromTicks ticks: UInt64, frequency: UInt64) -> UInt64 {
        guard frequency <= UInt64(UInt32.max) else {
            return frequency.dividingFullWidth(ticks.multipliedFullWidth(by: attosecondsPerSecond)).quotient
        }
        let (perTick, leftover) = attosecondsPerSecond.quotientAndRemainder(dividingBy: frequency)
        return ticks * perTick + ticks * leftover / frequency
    }

    /// `attoseconds * frequency / 1e18`, rounded to the nearest tick, for `attoseconds < 1e18`.
    ///
    /// Rounding, not truncation, keeps `advanced(by: a.duration(to: b)) == b`.
    static func ticks(fromAttoseconds attoseconds: UInt64, frequency: UInt64) -> UInt64 {
        let half: UInt64 = 500_000_000_000_000_000
        guard frequency <= UInt64(UInt32.max) else {
            let product = attoseconds.multipliedFullWidth(by: frequency)
            let (low, carry) = product.low.addingReportingOverflow(half)
            return attosecondsPerSecond.dividingFullWidth((product.high + (carry ? 1 : 0), low)).quotient
        }
        let (high, low) = attoseconds.quotientAndRemainder(dividingBy: 1_000_000_000)
        let (whole, part) = (high * frequency).quotientAndRemainder(dividingBy: 1_000_000_000)
        return whole + (part * 1_000_000_000 + low * frequency + half) / attosecondsPerSecond
    }
}

extension HardwareClock.Instant: Comparable {
    /// Orders by raw ticks, then by frequency.
    @inlinable
    public static func < (lhs: HardwareClock.Instant, rhs: HardwareClock.Instant) -> Bool {
        // Frequency breaks ties so ordering agrees with synthesized equality.
        (lhs.ticks, lhs.frequency) < (rhs.ticks, rhs.frequency)
    }
}
#endif
