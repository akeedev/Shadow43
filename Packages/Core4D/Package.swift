// swift-tools-version: 6.4
// Core4D: the 4D math and geometry of Shadow43. Imports only Foundation and simd.
import PackageDescription

let package = Package(
    name: "Core4D",
    platforms: [.macOS(.v27), .visionOS(.v27)],
    products: [.library(name: "Core4D", targets: ["Core4D"])],
    targets: [
        // The per-frame pipeline runs in Core4D and is ~40× slower unoptimised, so Core4D is
        // always compiled with -O, also in Debug builds of the app (allowed for local packages).
        .target(name: "Core4D", swiftSettings: [.unsafeFlags(["-O"])]),
        .testTarget(name: "Core4DTests", dependencies: ["Core4D"]),
    ]
)
