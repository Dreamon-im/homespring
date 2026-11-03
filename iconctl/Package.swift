// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iconctl",
    // Release builds link the static libraries from scripts/build-deps.sh, which
    // target macOS 13. Dev builds against Homebrew still work (with a linker
    // warning when the bottles target a newer macOS).
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "iconctl", targets: ["iconctl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // libimobiledevice C API (Homebrew), resolved through pkg-config.
        .systemLibrary(
            name: "CIMobileDevice",
            pkgConfig: "libimobiledevice-1.0",
            providers: [.brew(["libimobiledevice"])]
        ),
        // Device I/O only: connect, get/set icon state, metrics, plist conversion.
        .target(name: "DeviceKit", dependencies: ["CIMobileDevice"]),
        // Pure layout logic, no device access; fully unit-testable.
        .target(name: "IconCore"),
        .executableTarget(
            name: "iconctl",
            dependencies: [
                "DeviceKit",
                "IconCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "IconCoreTests", dependencies: ["IconCore"]),
    ]
)
