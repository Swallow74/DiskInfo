// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskInfo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DiskInfo",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        )
    ]
)
