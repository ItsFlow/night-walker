// swift-tools-version:5.9
import PackageDescription

// Pure Swift + system frameworks only. No third-party dependencies.
// Builds with `swift build` on Command Line Tools (no full Xcode required).
let package = Package(
    name: "color-filter-scheduler",
    platforms: [.macOS(.v11)],
    targets: [
        // Thin C shim that declares the MediaAccessibility SPI we call.
        // The symbols themselves live in the system framework (linked below).
        .target(name: "CMediaAccessibility"),

        .executableTarget(
            name: "color-filter-scheduler",
            dependencies: ["CMediaAccessibility"],
            linkerSettings: [
                .linkedFramework("MediaAccessibility"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
    ]
)
