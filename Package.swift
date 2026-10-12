// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Signaloryx",
    platforms: [.iOS(.v13), .macOS(.v12)],
    products: [.library(name: "Signaloryx", targets: ["Signaloryx"])],
    targets: [
        .target(name: "Signaloryx", path: "Sources/Signaloryx"),
        .testTarget(name: "SignaloryxTests", dependencies: ["Signaloryx"], path: "Tests/SignaloryxTests")
    ]
)
