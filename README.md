# HardwareClock

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fordo-one%2FHardwareClock%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ordo-one/HardwareClock)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fordo-one%2FHardwareClock%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ordo-one/HardwareClock)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE.txt)
[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue.svg)](https://swiftpackageindex.com/ordo-one/HardwareClock/documentation)
[![codecov](https://codecov.io/gh/ordo-one/HardwareClock/branch/main/graph/badge.svg)](https://codecov.io/gh/ordo-one/HardwareClock)

A Swift `Clock` that reads the CPU's hardware counter directly. It exists for one job: timestamping hot paths where the cost of reading the clock itself shows up in your measurements.

## Should you use it?

Probably not. For almost all code, use [`ContinuousClock`](https://docs.swift.org/latest/documentation/swift/continuousclock) from the standard library. It is portable and needs no setup.

Reach for `HardwareClock` only when both of these are true:

- Timing is critical - you are timestamping events, spans or latencies in code where nanoseconds matter, such as a trading path, a tracer or a profiler.
- You want the lowest possible overhead per read, and you have measured that the standard clock is a visible cost.

In exchange you take on some constraints:

- It only exists on arm64 Darwin and Linux (reads [`CNTVCT_EL0`](https://developer.arm.com/documentation/ddi0601/2022-09/AArch64-Registers/CNTVCT-EL0--Counter-timer-Virtual-Count-register)) and x86_64 Linux (reads the TSC via `rdtscp`, [Intel SDM Vol. 2](https://www.intel.com/content/www/us/en/content-details/812389/intel-64-and-ia-32-architectures-software-developer-s-manual-combined-volumes-2a-2b-2c-and-2d-instruction-set-reference-a-z.html)). On other platforms the type is not compiled at all, so you need a fallback.
- You must calibrate it once before use. On x86_64 this can busy-spin a CPU core for up to 2 seconds, and can fail.
- On x86_64 it needs a CPU with `rdtscp` and an [invariant TSC](https://www.intel.com/content/www/us/en/content-details/843856/intel-64-and-ia-32-architectures-software-developer-s-manual-volume-3a-system-programming-guide-part-1.html) (Intel SDM Vol. 3A section 18.17.1). Otherwise `calibrate()` returns `nil`. There is no automatic fallback to `ContinuousClock`; your code chooses.
- Instants carry their counter frequency, so they are 16 bytes and only comparable with instants from a clock of the same frequency.
- A read is not ordered against the surrounding code, so the CPU may take it slightly before or after the work you are timing. Fine for timestamps; for micro-benchmarks add a fence (`isb` before the read on arm64, `lfence` after it on x86_64).
- On x86_64 Linux the TSC usually resets across suspend to RAM, so do not measure across a system sleep there.
- It is a measuring clock, not a scheduling one. `sleep(until:)` hands off to `Task.sleep`.

## How much faster?

Typical cost of one read, median, in nanoseconds:

| CPU | OS | `HardwareClock.now` | OS clock (`ContinuousClock.now`, `clock_gettime`) | `mach_continuous_time()` |
|---|---|---:|---:|---:|
| Apple M4 | macOS | ~1 * | ~15 | ~5 |
| Intel Core Ultra 7 265 | Linux | ~10 | ~17 | - |
| AMD EPYC 9454P ** | Linux | ~18 | ~30 | - |

\* An unordered read: reads overlap each other. With the `isb` the OS clocks use it measured about 9 ns on an Apple M5 Max.

\*\* A KVM guest that hides the invariant TSC flag, so `isAvailable` is false there; the row is the cost of the read alone. Check `/proc/cpuinfo` for `constant_tsc` and `nonstop_tsc` on virtual machines.

The operating system clocks read the same hardware counter, but each read goes through a function call, a consistency check and a conversion to nanoseconds. `HardwareClock` inlines the read into your code as a single instruction and only converts to time when you ask for a duration.

## Usage

```swift
import HardwareClock

func measure(_ work: () -> Void) -> Duration? {
    // nil: fall back to ContinuousClock.
    guard let clock = HardwareClock.calibrate() else { return nil }
    let start = clock.now
    work()
    return start.duration(to: clock.now)
}
```

Calibrate once at startup and keep the clock around; it is a small `Sendable` value.

For the tightest loops, skip `Instant` and work with raw ticks, converting later:

```swift
let start = HardwareClock.readCounter().ticks
work()
let nanoseconds = clock.elapsedNanoseconds(sinceTicks: start)
```

On x86_64, `readCounter()` also returns the CPU the read ran on, so you can spot a thread that migrated between two reads. On arm64 the CPU is always 0.

## How calibration works

- arm64: reads the counter frequency register [`CNTFRQ_EL0`](https://developer.arm.com/documentation/ddi0601/2022-09/AArch64-Registers/CNTFRQ-EL0--Counter-timer-Frequency-register). Exact and instant, unless firmware left it 0; then it is measured as on x86_64.
- x86_64: uses CPUID leaf 0x15 ([Intel SDM Vol. 2](https://www.intel.com/content/www/us/en/content-details/812389/intel-64-and-ia-32-architectures-software-developer-s-manual-combined-volumes-2a-2b-2c-and-2d-instruction-set-reference-a-z.html), CPUID entry) when the CPU reports its crystal clock. Otherwise it measures the counter against `CLOCK_MONOTONIC_RAW`, sampling every 10 ms until 5 samples agree within 0.1%, and returns `nil` if that has not happened after 2 seconds. For comparison, see the [Linux kernel TSC calibration](https://github.com/torvalds/linux/blob/v6.12/arch/x86/kernel/tsc.c).

## Library evolution

Only needed when HardwareClock ends up inside a binary framework (xcframework), which requires every dependency to ship a module interface. Enable with the `LibraryEvolution` trait, or the `ROBE_LIBRARY_EVOLUTION` environment variable for xcodebuild, which has no `--traits`.

## Tests and benchmarks

```bash
swift test --build-system native
cd Benchmarks && swift package --disable-sandbox benchmark --no-progress
```
