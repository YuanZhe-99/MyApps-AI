// swift-tools-version: 6.0
// Purpose: The Neural Engine bridge: FluidAudio behind five C functions, as
// one dynamic library the app binds from Dart.
// Inputs: FluidAudio, pinned by exact version.
// Returns: The `LasrApple` dynamic library product.
// Side effects: None; SwiftPM resolves and builds it.
// Notes: Built only by `.github/workflows/asr-apple-prebuild.yml`, never in the
// app build (decision D21 of the local-models plan). The C interface is
// `lasr_apple.h` beside this file.
import PackageDescription

let package = Package(
    name: "LasrApple",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "LasrApple", type: .dynamic, targets: ["LasrApple"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4"),
    ],
    targets: [
        .target(
            name: "LasrApple",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/LasrApple"
        ),
    ],
    swiftLanguageModes: [.v5]
)
