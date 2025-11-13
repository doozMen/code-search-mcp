// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "code-search-mcp",
  platforms: [.macOS(.v15)],
  products: [
    .executable(
      name: "code-search-mcp",
      targets: ["CodeSearchMCP"]
    ),
    .library(
      name: "SwiftEmbeddings",
      targets: ["SwiftEmbeddings"]
    ),
  ],
  dependencies: [
    // MCP Protocol Support
    .package(
      url: "https://github.com/modelcontextprotocol/swift-sdk.git",
      from: "0.9.0"
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
    .target(
      name: "SwiftEmbeddings",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
      ],
      path: "Sources/SwiftEmbeddings"
    ),
    .executableTarget(
      name: "CodeSearchMCP",
      dependencies: [
        "SwiftEmbeddings",
        .product(name: "MCP", package: "swift-sdk"),
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
