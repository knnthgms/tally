// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tally",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "TallyEngine", path: "Sources/TallyEngine"),
        .executableTarget(name: "TallyApp", dependencies: ["TallyEngine"], path: "Sources/TallyApp"),
        .testTarget(name: "TallyEngineTests", dependencies: ["TallyEngine"], path: "Tests/TallyEngineTests"),
        .testTarget(name: "TallyAppTests", dependencies: ["TallyApp"], path: "Tests/TallyAppTests"),
    ],
    swiftLanguageModes: [.v5]
)
