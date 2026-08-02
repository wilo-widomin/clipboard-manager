// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipboardManager",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "ClipboardManagerKit",
            targets: ["ClipboardManagerKit"]
        ),
    ],
    targets: [
        .target(
            name: "ClipboardManagerKit",
            path: "Sources/ClipboardManagerKit"
        ),
    ]
)
