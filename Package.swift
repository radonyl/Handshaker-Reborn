// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ADBPullPhotos",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ADBPullPhotos",
            targets: ["ADBPullPhotos"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ADBPullPhotos",
            path: "Sources/ADBPullPhotos"
        )
    ]
)
