#!/usr/bin/env bash
#
# Package Atlas Tune as a Swift Playgrounds App project (.swiftpm) that can be opened directly in
# Swift Playgrounds (iPad/Mac) or Xcode.
#
# It assembles a two-target package from the existing sources without modifying them:
#   - AtlasTuneCore : the engine library (+ the bundled S58 JSON definition resource)
#   - AtlasTuneApp  : the SwiftUI/Metal/SwiftData executable, depending on AtlasTuneCore
#
# Non-Playground files (Info.plist, entitlements, the precompiled .metal shader) are dropped — the
# .iOSApplication product supplies app metadata, and the renderer compiles its shader from
# SurfaceShaderSource.swift at runtime when no precompiled Metal library is present.
#
# Usage:  Tools/make_swiftpm.sh [output_dir]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
PKG="$OUT_DIR/AtlasTune.swiftpm"

rm -rf "$PKG"
mkdir -p "$PKG"

# 1. Engine library target (verbatim copy, including the JSON resource).
cp -R "$ROOT/Sources/AtlasTuneCore" "$PKG/AtlasTuneCore"

# 2. App executable target (verbatim copy, then strip non-Playground files).
cp -R "$ROOT/App/AtlasTune" "$PKG/App"
rm -rf "$PKG/App/Resources"   # Info.plist / entitlements / Shaders are not used in Playgrounds

# 3. Package manifest declaring the iOS app product.
cat > "$PKG/Package.swift" <<'SWIFT'
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
SWIFT

echo "Built $PKG"
echo "Swift files: $(find "$PKG" -name '*.swift' | wc -l | tr -d ' ')"
echo "Resource:    $(ls -1 "$PKG/AtlasTuneCore/Resources" 2>/dev/null || echo none)"

# 4. Zip for download (alongside the .swiftpm directory).
if command -v zip >/dev/null 2>&1; then
    (cd "$OUT_DIR" && rm -f AtlasTune.swiftpm.zip && zip -qr AtlasTune.swiftpm.zip AtlasTune.swiftpm)
    echo "Archive:     $OUT_DIR/AtlasTune.swiftpm.zip"
fi
