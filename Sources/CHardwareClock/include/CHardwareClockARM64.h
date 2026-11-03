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

#ifndef C_HARDWARE_CLOCK_ARM64_H
#define C_HARDWARE_CLOCK_ARM64_H

// References:
// - CNTVCT_EL0: https://developer.arm.com/documentation/ddi0601/2022-09/AArch64-Registers/CNTVCT-EL0--Counter-timer-Virtual-Count-register
// - CNTFRQ_EL0: https://developer.arm.com/documentation/ddi0601/2022-09/AArch64-Registers/CNTFRQ-EL0--Counter-timer-Frequency-register

#if defined(__aarch64__)
#include <stdint.h>

/// Read the ARM generic timer counter (CNTVCT_EL0). Rate is CNTFRQ_EL0: 24-54 MHz on older cores, 1 GHz on Armv8.6+.
static inline __attribute__((always_inline)) uint64_t hwclock_cntvct(void) {
    uint64_t val;
    // "memory" stops the compiler moving timed loads and stores across the read.
    __asm__ __volatile__("mrs %0, cntvct_el0" : "=r"(val) : : "memory");
    return val;
}

/// Read the ARM generic timer frequency (CNTFRQ_EL0) in Hz.
static inline __attribute__((always_inline)) uint64_t hwclock_cntfrq(void) {
    uint64_t val;
    __asm__ __volatile__("mrs %0, cntfrq_el0" : "=r"(val));
    return val;
}
#endif

#endif
