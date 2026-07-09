// swift-tools-version: 5.9

// Atlas Tune — Swift Playgrounds App project.
// Open this folder in Swift Playgrounds (iPad/Mac) or Xcode 15+.
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "AtlasTune",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "AtlasTune",
            targets: ["AtlasTuneApp"],
            bundleIdentifier: "com.atlastune.app",
            teamIdentifier: "",
            displayVersion: "0.1.0",
            bundleVersion: "1",
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .target(
            name: "AtlasTuneCore",
            path: "AtlasTuneCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "AtlasTuneApp",
            dependencies: ["AtlasTuneCore"],
            path: "App"
        )
    ]
)
