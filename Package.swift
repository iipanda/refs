// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Refs",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Refs", targets: ["Refs"]),
        .executable(name: "refs-mcp", targets: ["refs-mcp"]),
    ],
    targets: [
        .target(name: "RefsCore"),
        .target(name: "RefsMCP", dependencies: ["RefsCore"]),
        .executableTarget(name: "refs-mcp", dependencies: ["RefsMCP"]),
        .executableTarget(
            name: "Refs",
            dependencies: ["RefsCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "RefsCoreTests", dependencies: ["RefsCore"]),
        .testTarget(name: "RefsMCPTests", dependencies: ["RefsMCP"]),
    ],
    swiftLanguageModes: [.v5]
)
