// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "txtxt",
    platforms: [.macOS(.v15)],
    dependencies: [
        // GitHub-flavored Markdown → HTML for the preview pane.
        .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "txtxt",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]
        ),
        .testTarget(name: "txtxtTests", dependencies: ["txtxt"]),
    ]
)
