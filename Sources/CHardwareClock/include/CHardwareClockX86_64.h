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

#ifndef C_HARDWARE_CLOCK_X86_64_H
#define C_HARDWARE_CLOCK_X86_64_H

// References:
// - RDTSCP: Intel SDM Vol. 2
//     https://www.intel.com/content/www/us/en/content-details/812389/intel-64-and-ia-32-architectures-software-developer-s-manual-combined-volumes-2a-2b-2c-and-2d-instruction-set-reference-a-z.html

#if defined(__x86_64__) && defined(__linux__)
#include <stdint.h>

typedef struct {
    uint64_t ticks;
    uint32_t cpu;
} hwclock_rdtscp_reading_t;

/// Read the TSC and IA32_TSC_AUX via `rdtscp`.
static inline __attribute__((always_inline)) hwclock_rdtscp_reading_t hwclock_rdtscp(void) {
    uint32_t aux;
    uint64_t rax, rdx;
    // "memory" stops the compiler moving timed loads and stores across the read.
    __asm__ __volatile__("rdtscp" : "=a"(rax), "=d"(rdx), "=c"(aux) : : "memory");
    return (hwclock_rdtscp_reading_t){ .ticks = (rdx << 32) | rax, .cpu = aux };
}
#endif

#endif
