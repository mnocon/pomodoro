// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PomodoroBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "PomodoroBar", path: "Sources/PomodoroBar")
    ]
)
