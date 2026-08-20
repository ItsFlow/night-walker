// swift-tools-version:5.9
import PackageDescription

// Pure Swift + system frameworks only. No third-party dependencies.
// Builds with `swift build` on Command Line Tools (no full Xcode required).
let package = Package(
    name: "color-filter-scheduler",
    platforms: [.macOS(.v13)],
    targets: [
        // Thin C shim that declares the MediaAccessibility SPI we call.
        // The symbols themselves live in the system framework (linked below).
        .target(name: "CMediaAccessibility"),

        // Pure solar math + persisted settings. Extracted so `swift test` can
        // characterize the engine without importing AppKit or the SPI wrapper.
        .target(name: "ColorFilterEngine"),

        .executableTarget(
            name: "color-filter-scheduler",
            dependencies: ["CMediaAccessibility", "ColorFilterEngine"],
            linkerSettings: [
                .linkedFramework("MediaAccessibility"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreLocation"),
            ]
        ),

        .testTarget(
            name: "color-filter-schedulerTests",
            dependencies: ["ColorFilterEngine", "color-filter-scheduler"]
        ),
    ]
)
