// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Archaive",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Archaive", targets: ["Archaive"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .executableTarget(
            name: "Archaive",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources/Wordmark.png")]
        )
    ]
)
