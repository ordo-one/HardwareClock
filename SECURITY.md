# Security Policy

## Scope

HardwareClock reads CPU counter registers (`CNTVCT_EL0`, `CNTFRQ_EL0`, `RDTSCP`) and CPUID, and converts ticks to durations in memory. It has no network access, file I/O, or persistent storage, and processes no external input.

## Potential Concerns

- **Timing side channels**: a high-resolution counter is a precise timer. That is the purpose of the library; callers running untrusted code in-process should treat it like any other fine-grained timer.
- **Calibration busy-spin**: on x86_64 without a CPU-reported crystal clock, `calibrate()` spins for up to 2 s.
- **Unsupported hardware**: `calibrate()` traps when `isAvailable` is `false`. Check `isAvailable` first.

## Reporting a Vulnerability

If you discover a security issue, please open a GitHub issue on the project describing the concern.

We aim to respond within 30 days for confirmed vulnerabilities.
