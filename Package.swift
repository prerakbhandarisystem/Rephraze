// swift-tools-version: 6.0
import PackageDescription

// Swift 5 language mode on purpose: the CGEventTap callback is a C function
// pointer and the Accessibility APIs are unannotated C. Strict Swift 6
// concurrency fights both. Worth tightening once the app works end to end.
let mode: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Rephraze",
    platforms: [.macOS(.v14)],
    targets: [
        // All the real logic, so it can be unit tested.
        .target(name: "RephrazeKit", path: "Sources/RephrazeKit", swiftSettings: mode),

        // Thin shell that just boots the app.
        .executableTarget(
            name: "Rephraze",
            dependencies: ["RephrazeKit"],
            path: "Sources/Rephraze",
            swiftSettings: mode
        ),

        .testTarget(
            name: "RephrazeKitTests",
            dependencies: ["RephrazeKit"],
            path: "Tests/RephrazeKitTests",
            swiftSettings: mode
        ),
    ]
)
