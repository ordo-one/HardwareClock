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
#if arch(arm64) && (canImport(Darwin) || os(Linux))
public import CHardwareClock

extension HardwareClock {
    /// Reads the virtual counter `CNTVCT_EL0`, which ticks at ``frequency``; ``Reading/processorID`` is always 0.
    ///
    /// The read is not ordered against surrounding instructions: an end timestamp can be taken before the timed
    /// work completes. For micro-benchmarks put an `isb` before it, as the OS clocks do.
    @inlinable @inline(__always)
    public static func readCounter() -> Reading {
        Reading(ticks: hwclock_cntvct(), processorID: 0)
    }

    /// Whether the hardware counter is available. Always `true`: `CNTVCT_EL0` is always present.
    public static let isAvailable = true

    /// `CNTFRQ_EL0`, or `nil` when firmware left it 0.
    static func _exactFrequency() -> UInt64? {
        let frequency = hwclock_cntfrq()
        return frequency > 0 ? frequency : nil
    }
}
#endif
