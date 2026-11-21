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
        // Solo para `swift test`. El proyecto de Xcode no lo ve: su target de
        // tests apunta a otra carpeta (`tests/ClipboardManagerTests`).
        .testTarget(
            name: "ClipboardManagerKitTests",
            dependencies: ["ClipboardManagerKit"],
            path: "Tests/ClipboardManagerKitTests"
        ),
    ]
)
