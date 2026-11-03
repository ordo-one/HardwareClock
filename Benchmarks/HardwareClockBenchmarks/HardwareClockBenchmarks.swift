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

import Benchmark
import HardwareClock
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.throughput, .wallClock, .instructions],
        warmupIterations: 10,
        scalingFactor: .mega,
        maxDuration: .seconds(3),
        maxIterations: 1_000_000
    )

    #if (os(Linux) && arch(x86_64)) || (arch(arm64) && (canImport(Darwin) || os(Linux)))
    Benchmark("HardwareClock.readCounter") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(HardwareClock.readCounter())
        }
    }

    Benchmark("HardwareClock.now") { benchmark in
        let clock = HardwareClock(frequency: 1)
        for _ in benchmark.scaledIterations {
            blackHole(clock.now)
        }
    }

    Benchmark("Instant.duration(to:)") { benchmark in
        // Fixed odd rate where calibration is unavailable, e.g. KVM guests without invariant TSC.
        let clock = HardwareClock.calibrate() ?? HardwareClock(frequency: 2_995_200_000)
        let start = clock.now
        for i in benchmark.scaledIterations {
            let end = HardwareClock.Instant(ticks: start.ticks &+ UInt64(i) &* 7919, frequency: clock.frequency)
            blackHole(start.duration(to: end))
        }
    }

    Benchmark("Instant.advanced(by:)") { benchmark in
        // Fixed odd rate where calibration is unavailable, e.g. KVM guests without invariant TSC.
        let clock = HardwareClock.calibrate() ?? HardwareClock(frequency: 2_995_200_000)
        let start = clock.now
        for i in benchmark.scaledIterations {
            blackHole(start.advanced(by: .nanoseconds(i &* 7919)))
        }
    }
    #endif

    #if canImport(Darwin)
    Benchmark("mach_continuous_time") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(mach_continuous_time())
        }
    }
    #endif

    Benchmark("ContinuousClock.now") { benchmark in
        let clock = ContinuousClock()
        for _ in benchmark.scaledIterations {
            blackHole(clock.now)
        }
    }

    Benchmark("clock_gettime(CLOCK_MONOTONIC)") { benchmark in
        var ts = timespec()
        for _ in benchmark.scaledIterations {
            clock_gettime(CLOCK_MONOTONIC, &ts)
            blackHole(ts)
        }
    }
}
