// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetInspector",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CPtySpawn",
            path: "Sources/CPtySpawn"
        ),
        .executableTarget(
            name: "NetInspector",
            dependencies: ["CPtySpawn"],
            path: "Sources/NetInspector"
        ),
    ]
)
