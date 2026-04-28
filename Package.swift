// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Reflex",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Reflex",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Reflex",
            resources: [
                .process("Resources/MediaAppDefinitions.json")
            ],
            plugins: [
                .plugin(name: "GenerateSpotifySecrets")
            ]
        ),
        .plugin(
            name: "GenerateSpotifySecrets",
            capability: .buildTool(),
            path: "Plugins/GenerateSpotifySecrets"
        )
    ]
)
