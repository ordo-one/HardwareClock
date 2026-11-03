// swift-tools-version: 6.2

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

import PackageDescription

let package = Package(
    name: "Benchmarks",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.32.0"),
    ],
    targets: [
        .executableTarget(
            name: "HardwareClockBenchmarks",
            dependencies: [
                .product(name: "HardwareClock", package: "HardwareClock"),
                .product(name: "Benchmark", package: "package-benchmark"),
            ],
            path: "HardwareClockBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark"),
            ]
        ),
    ]
)
