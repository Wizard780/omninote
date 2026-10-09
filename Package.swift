// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "omninote",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OmninoteCore"),
        .executableTarget(name: "omninote", dependencies: ["OmninoteCore"]),
        .testTarget(name: "OmninoteCoreTests", dependencies: ["OmninoteCore"]),
    ]
)
