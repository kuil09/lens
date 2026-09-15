// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lens",
    defaultLocalization: "en",
    platforms: [.macOS("26.4")],
    products: [.executable(name: "Lens", targets: ["Lens"])],
    targets: [
        .executableTarget(name: "Lens", path: "Sources/Lens", resources: [.process("Resources")]),
        .testTarget(name: "LensTests", dependencies: ["Lens"], path: "Tests/LensTests")
    ],
    swiftLanguageModes: [.v6]
)
