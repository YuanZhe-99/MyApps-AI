// swift-tools-version: 5.9
// MyApps-AI's bridge to Apple's Foundation Models framework.
// See doc/en-us/on-device-ai.md in the app repository.

import PackageDescription

let package = Package(
    name: "myapps_ai_platform",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15"),
    ],
    products: [
        .library(name: "myapps-ai-platform", targets: ["myapps_ai_platform"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "myapps_ai_platform",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
            // No linker setting for FoundationModels: SwiftPM has no weak-link
            // option, and every reference is behind `@available(iOS 26.0,
            // macOS 26.0, *)`, so the linker weak-links the framework on its
            // own. CI verifies that with `otool -l`.
        )
    ]
)
