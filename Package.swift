// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Docko",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Docko",
            path: "Sources/Docko"
        )
    ]
)
