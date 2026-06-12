// swift-tools-version: 5.9
import PackageDescription

// MarkdownCore — the pure (non-UI) logic of md-fire: incremental tree-sitter parsing,
// byte<->NSRange mapping, SyntaxNode model, and the cmark export oracle. Lives in a local
// SwiftPM package so it can be unit-tested with `swift test` (no app host, fast iteration).
// The app target depends on this package; see ARCHITECTURE.md §2 (local SPM for app-internal logic).
let package = Package(
    name: "MarkdownCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.8.0"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown", branch: "split_parser"),
        .package(url: "https://github.com/swiftlang/swift-markdown", branch: "main"),
    ],
    targets: [
        .target(
            name: "MarkdownCore",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .testTarget(
            name: "MarkdownCoreTests",
            dependencies: ["MarkdownCore"]
        ),
    ]
)
