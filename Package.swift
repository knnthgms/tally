// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tally",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TallyEngine", path: "Sources/TallyEngine"),
        .executableTarget(name: "TallyApp", dependencies: ["TallyEngine"], path: "Sources/TallyApp"),
        .testTarget(name: "TallyEngineTests", dependencies: ["TallyEngine"], path: "Tests/TallyEngineTests"),
    ]
)
