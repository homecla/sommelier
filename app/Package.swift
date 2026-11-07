// swift-tools-version:5.10
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla
import PackageDescription

let package = Package(
    name: "Sommelier",
    defaultLocalization: "it",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Sommelier", path: "Sources/Sommelier")
    ]
)
