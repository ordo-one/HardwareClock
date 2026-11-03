# Contributing

Contributions are welcome. Bug reports, performance improvements, and quality enhancements are particularly valued.

## Getting Started

```bash
swift build              # Debug build
swift test               # Run all tests
cd Benchmarks && swift package --disable-sandbox benchmark  # Run benchmark suite (release build)
```

## Before Submitting a PR

1. **All tests pass** - `swift test` must be green on arm64 and x86_64 Linux. The x86_64 `rdtscp` and calibration paths only compile on Linux x86_64.
2. **Benchmarks checked** - If your change touches a counter read, run `cd Benchmarks && swift package --disable-sandbox benchmark` before and after. Include the comparison in your PR description.
3. **Lint clean** - Run `swiftlint` locally.
4. **Focused scope** - One concern per PR. Bug fix, feature, or refactor - not all three.

## Testing

Tests use the **Swift Testing** framework (`@Test` macro, `#expect()` assertions) and live in `Tests/HardwareClockTests/`. Hardware-dependent suites are gated with `.enabled(if: HardwareClock.isAvailable)`.

Run a specific test suite:

```bash
swift test --filter CalibrationTests
```

## Documentation

All public APIs must have DocC documentation (`///` comments).

```bash
swift package generate-documentation --target HardwareClock
```

## Code Style

- SwiftLint is configured in the repo. Follow the existing patterns.
- Don't add comments for self-evident code. Do add comments for non-obvious hardware behaviour.
- Don't add features or abstractions beyond what's needed for the current change.
- Counter reads stay `static inline` C in `CHardwareClock` and `@inlinable` Swift, so they inline into every importer with no exported symbol.

## ABI

Hot-path reads are inlined into clients. Changing an inlined body or the layout of a `@frozen` type is a breaking change: clients carry the old instructions until rebuilt.

## Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add a raw rdtsc read for callers that do not need the CPU ID
fix: reject calibration samples where the counter went backwards
perf: drop a redundant frequency division from elapsed(since:)
```

Breaking changes append `!`: `feat!: rename Reading.cpu to Reading.processorID`

## Questions

Open an issue for discussion before starting large changes. This saves everyone time.
