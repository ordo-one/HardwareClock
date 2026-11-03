# ``HardwareClock``

A Swift `Clock` backed by the CPU's hardware counter, read inline.

## Overview

``HardwareClock/HardwareClock`` reads `CNTVCT_EL0` on arm64 (Darwin, Linux) and the TSC via `rdtscp` on x86_64 Linux. The read is header-only C, inlined into the caller as a single instruction; ticks convert to time only when asked: ``HardwareClock/HardwareClock/Instant/duration(to:)`` returns a `Duration`, ``HardwareClock/HardwareClock/elapsedNanoseconds(sinceTicks:)`` and ``HardwareClock/HardwareClock/nanoseconds(fromTicks:)`` return nanoseconds. The type is absent on other platforms (Intel macOS, Windows, 32-bit); guard uses with `#if (os(Linux) && arch(x86_64)) || (arch(arm64) && (canImport(Darwin) || os(Linux)))`.

Prefer `ContinuousClock` unless you have measured its read as a visible cost. Use this clock for timestamps and spans on hot paths. It is not a wall clock: the epoch is arbitrary, instants mean nothing across machines or reboots, and `Instant` arithmetic traps across clocks of different frequency.

The counter read is not ordered against surrounding instructions: an end timestamp can be taken before the timed work completes. For event timestamps this is noise of a few nanoseconds; for micro-benchmarks add a fence (`isb` before the read on arm64, `lfence` after `rdtscp` on x86_64). See ``HardwareClock/HardwareClock/readCounter()``.

Across system sleep the counter keeps running on Apple Silicon (measured) and on Linux arm64 unless the firmware declares `arm,no-tick-in-suspend`; on Linux x86_64 the TSC resets across S3 suspend on most parts. Treat it as `ContinuousClock`-like, and do not measure across suspend on x86_64.

```swift
import HardwareClock

func measure(_ work: () -> Void) -> Duration? {
    guard let clock = HardwareClock.calibrate() else { return nil }
    let start = clock.now
    work()
    return start.duration(to: clock.now)
}
```

On the hottest paths, keep raw ticks and convert later:

```swift
func elapsedNanoseconds(_ clock: HardwareClock, _ work: () -> Void) -> UInt64 {
    let start = HardwareClock.readCounter().ticks
    work()
    return clock.elapsedNanoseconds(sinceTicks: start)
}
```

### Calibration

Call ``HardwareClock/HardwareClock/calibrate()`` once at startup and keep the clock. It is instant when the CPU reports its frequency, as arm64 does unless firmware left `CNTFRQ_EL0` at 0. Otherwise, as on x86_64 without a CPU-reported crystal, it busy-spins the calling thread for 50 ms to 2 s and can return `nil`; do not call it from a cooperative-pool thread. There is no automatic fallback: when `calibrate()` returns `nil`, use `ContinuousClock` yourself. A known frequency can be passed to ``HardwareClock/HardwareClock/init(frequency:)``, which skips the availability check, so reading a clock made that way on an x86_64 CPU without `rdtscp` crashes.

### Core migration

``HardwareClock/HardwareClock/Reading/processorID`` identifies the core a read ran on (x86_64 only); compare it across two reads to detect a migration.

## Topics

### Essentials

- ``HardwareClock/HardwareClock``
