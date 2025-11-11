// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "code-search-mcp",
    platforms: [.macOS(.v15)],
    products: [
        .executable(
            name: "code-search-mcp",
            targets: ["CodeSearchMCP"]
        )
    ],
    dependencies: [
        // MCP Protocol Support
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk.git",
            from: "0.9.0"
        ),
        // Vector Embeddings (BERT 384-d)
        .package(
            url: "https://github.com/apple/swift-embeddings.git",
            from: "0.0.23"
        ),
        // Logging Infrastructure
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.5.0"
        ),
        // CLI Argument Parsing
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.3.0"
        ),
        // JSON Serialization
        .package(
            url: "https://github.com/apple/swift-nio.git",
            from: "2.60.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "CodeSearchMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Embeddings", package: "swift-embeddings"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "NIO", package: "swift-nio"),
            ],
            path: "Sources/CodeSearchMCP"
        ),
        .testTarget(
            name: "CodeSearchMCPTests",
            dependencies: [
                "CodeSearchMCP",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Tests/CodeSearchMCP"
        ),
    ]
)
