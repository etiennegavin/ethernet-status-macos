// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EthernetStatus",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "EthernetStatus",
            path: "Sources/EthernetStatus"
        )
    ]
)
