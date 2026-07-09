// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AtlasTuneCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AtlasTuneCore", targets: ["AtlasTuneCore"]),
        // Native macOS build of the full app: `swift run AtlasTune`. No Xcode project or
        // signing required — the Metal shader compiles from source at runtime and SwiftData
        // falls back from CloudKit to a local store.
        .executable(name: "AtlasTune", targets: ["AtlasTuneMac"]),
    ],
    targets: [
        .target(
            name: "AtlasTuneCore",
            path: "Sources/AtlasTuneCore",
            resources: [
                // Generated from the MHD+ XDF by Tools/xdf_to_definition.py.
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "AtlasTuneMac",
            dependencies: ["AtlasTuneCore"],
            path: "App/AtlasTune",
            exclude: [
                // Xcode-target artefacts: plist, entitlements and the precompiled-shader source
                // (the renderer falls back to SurfaceShaderSource at runtime).
                "Resources",
            ]
        ),
        .testTarget(
            name: "AtlasTuneCoreTests",
            dependencies: ["AtlasTuneCore"],
            path: "Tests/AtlasTuneCoreTests"
        ),
    ]
)
