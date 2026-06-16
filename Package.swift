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
        .testTarget(
            name: "AtlasTuneCoreTests",
            dependencies: ["AtlasTuneCore"],
            path: "Tests/AtlasTuneCoreTests"
        ),
    ]
)
