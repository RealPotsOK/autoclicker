// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoClicker",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AutoClicker", targets: ["AutoClicker"])],
    targets: [
        .target(name: "AutoClickCore"),
        .executableTarget(name: "AutoClicker", dependencies: ["AutoClickCore"]),
        .testTarget(name: "AutoClickCoreTests", dependencies: ["AutoClickCore"])
    ]
)
