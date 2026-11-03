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

import Foundation
import PackageDescription

// Library evolution: `LibraryEvolution` trait (SwiftPM) or `ROBE_LIBRARY_EVOLUTION` env var (xcodebuild has no `-traits`).
let isLibraryEvolution = ProcessInfo.processInfo.environment["ROBE_LIBRARY_EVOLUTION"] != nil

let libraryEvolutionFlags: [SwiftSetting] = {
    // SwiftPM 6.2's interface verifier cannot find the CHardwareClock clang module; consumers enabling the trait fail without this.
    let flags = ["-enable-library-evolution", "-emit-module-interface", "-no-verify-emitted-module-interface"]
    if isLibraryEvolution {
        return [.unsafeFlags(flags)]
    } else {
        return [.unsafeFlags(flags, .when(traits: ["LibraryEvolution"]))]
    }
}()

let cpuinfoDep: Package.Dependency = isLibraryEvolution
    ? .package(url: "https://github.com/ordo-one/cpuinfo", from: "2.0.0", traits: [.trait(name: "LibraryEvolution")])
    : .package(
        url: "https://github.com/ordo-one/cpuinfo",
        from: "2.0.0",
        traits: [.trait(name: "LibraryEvolution", condition: .when(traits: ["LibraryEvolution"]))]
    )

let package = Package(
    name: "HardwareClock",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "HardwareClock", targets: ["HardwareClock"]),
        // Header-only counter reads, for modules whose @inlinable code must not name HardwareClock types.
        .library(name: "CHardwareClock", targets: ["CHardwareClock"]),
    ],
    traits: [
        Trait(
            name: "LibraryEvolution",
            description: "Build `HardwareClock` with `-enable-library-evolution` and `-emit-module-interface`."
        ),
    ],
    dependencies: [
        cpuinfoDep,
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(name: "CHardwareClock"),
        .target(
            name: "HardwareClock",
            dependencies: [
                "CHardwareClock",
                .product(name: "CpuInfo", package: "cpuinfo"),
            ],
            swiftSettings: libraryEvolutionFlags + [
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "HardwareClockTests",
            dependencies: ["HardwareClock"]
        ),
    ]
)
