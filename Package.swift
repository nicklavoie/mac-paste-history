// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PasteHistory",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PasteHistory", targets: ["PasteHistory"])
    ],
    targets: [
        .executableTarget(
            name: "PasteHistory",
            path: "Sources/PasteHistory"
        )
    ]
)
