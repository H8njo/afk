// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AFK",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AFK",
            path: "Sources/AFK",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ])
            ]
        )
    ]
)
