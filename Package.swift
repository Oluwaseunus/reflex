// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Reflex",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "Reflex",
            path: "Reflex",
            resources: [
                .process("Resources/MediaAppDefinitions.json")
            ]
        )
    ]
)
