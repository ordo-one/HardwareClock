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
#if os(Linux) && arch(x86_64)
public import CHardwareClock
internal import CpuInfo

extension HardwareClock {
    /// Reads the TSC and the processor ID from `IA32_TSC_AUX`.
    ///
    /// `rdtscp` waits for earlier instructions to execute and earlier loads to be globally visible, but not earlier stores
    /// (`mfence` first if that matters); later instructions may start before the read (`lfence` after for end timestamps).
    @inlinable @inline(__always)
    public static func readCounter() -> Reading {
        // rdtscp over rdtsc + LSL: LSL takes a microcode assist, measured 2x slower.
        let raw = hwclock_rdtscp()
        return Reading(ticks: raw.ticks, processorID: raw.cpu)
    }

    /// Whether the CPU has `rdtscp` and an invariant TSC, evaluated once via CPUID.
    public static let isAvailable: Bool = ProcessorInfo.current.isa.x86.rdtscp && ProcessorInfo.current.isa.x86.invariantTSC

    /// TSC rate from CPUID leaf 0x15 when ECX reports the crystal; `nil` when the crystal is inferred, since that is
    /// the nominal rate, not this part's.
    static func _exactFrequency() -> UInt64? {
        guard let tsc = ProcessorInfo.current.tsc, tsc.crystalClockKnown else { return nil }
        return tsc.tscFrequencyHz
    }
}
#endif
