// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lens",
    platforms: [.macOS("26.4")],
    products: [.executable(name: "Lens", targets: ["Lens"])],
    targets: [
        .executableTarget(name: "Lens", path: "Sources/Lens"),
        .testTarget(name: "LensTests", dependencies: ["Lens"], path: "Tests/LensTests")
    ],
    swiftLanguageModes: [.v6]
)
