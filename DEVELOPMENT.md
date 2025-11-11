# Development Guide for code-search-mcp

## Project Structure

```
code-search-mcp/
├── Package.swift                 # Swift Package definition
├── Sources/CodeSearchMCP/
│   ├── CodeSearchMCP.swift       # Entry point and CLI
│   ├── MCPServer.swift           # MCP protocol implementation
│   ├── Services/
│   │   ├── ProjectIndexer.swift        # Directory crawling and chunk extraction
│   │   ├── EmbeddingService.swift      # BERT embedding generation
│   │   ├── VectorSearchService.swift   # Semantic search implementation
│   │   ├── KeywordSearchService.swift  # Symbol search implementation
│   │   └── CodeMetadataExtractor.swift # Dependency tracking
│   └── Models/
│       ├── CodeChunk.swift        # Indexed code unit
│       ├── SearchResult.swift     # Unified search result
│       └── ProjectMetadata.swift  # Project information
├── Tests/CodeSearchMCP/
│   └── CodeSearchMCPTests.swift   # Test suite (Swift Testing)
├── README.md                      # User documentation
├── ARCHITECTURE.md                # Architecture overview
├── DEVELOPMENT.md                 # This file
├── install.sh                     # Installation script
├── .gitignore
├── .swiftformat                   # Code formatting config
└── LICENSE                        # MIT License
```

## Setup

### Prerequisites

- Swift 6.0 or later
- Xcode 16.0+ (for IDE development, optional)
- macOS 15.0+

### Initial Setup

```bash
cd /Users/stijnwillems/Developer/code-search-mcp

# Build the project
swift build

# Run tests
swift test

# Check formatting
swift format lint -s -p -r Sources Tests Package.swift
```

## Building

### Development Build

```bash
swift build
```

Output: `.build/debug/code-search-mcp`

### Release Build

```bash
swift build -c release
```

Output: `.build/release/code-search-mcp`

### Run Directly

```bash
swift run code-search-mcp --log-level debug
```

## Testing

### Run All Tests

```bash
swift test
```

### Run Specific Test Suite

```bash
swift test CodeSearchMCPTests
```

### Run with Verbose Output

```bash
swift test --verbose
```

### Test Coverage

```bash
swift test --code-coverage
```

Tests are located in `/Tests/CodeSearchMCP/CodeSearchMCPTests.swift`

## Code Standards

### Swift 6 Strict Concurrency

All code must:
- Use actors for shared state
- Implement `Sendable` for types crossing actor boundaries
- Use `async/await` for concurrent operations
- Avoid `@unchecked Sendable` unless justified

Example:
```swift
actor MyService: Sendable {
    func doWork() async throws {
        // Implementation
    }
}
```

### Error Handling

Use specific error types:
```swift
enum MyServiceError: Error, LocalizedError {
    case operationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        }
    }
}
```

For MCP responses:
```swift
throw MCP.Error.invalidParams("Missing parameter: name")
throw MCP.Error.internalError("Service unavailable")
```

### Logging

Use swift-log:
```swift
import Logging

let logger = Logger(label: "service-name")

logger.debug("Debug message", metadata: ["key": "value"])
logger.info("Info message")
logger.warning("Warning message")
logger.error("Error message", metadata: ["error": "\(error)"])
```

### Comments and Documentation

```swift
/// Perform semantic search for code chunks.
///
/// Generates an embedding for the query and finds code chunks
/// with highest cosine similarity scores.
///
/// - Parameters:
///   - query: Natural language query or code snippet
///   - maxResults: Maximum number of results to return
/// - Returns: Array of SearchResult objects sorted by relevance
/// - Throws: If query embedding generation fails
func search(
    query: String,
    maxResults: Int = 10
) async throws -> [SearchResult] {
    // Implementation
}
```

## Code Formatting

### Check Formatting

```bash
swift format lint -s -p -r Sources Tests Package.swift
```

### Auto-Fix Formatting

```bash
swift format format -p -r -i Sources Tests Package.swift
```

## Common Development Tasks

### Add a New Tool

1. Define tool in `MCPServer.getTools()`:
```swift
Tool(
    name: "my_tool",
    description: "Description",
    inputSchema: .object(
        properties: [
            "param": .string(description: "Parameter description")
        ],
        required: ["param"]
    )
)
```

2. Add handler in `handleCallTool()`:
```swift
case "my_tool":
    return try await handleMyTool(request.params.arguments ?? [:])
```

3. Implement handler method:
```swift
private func handleMyTool(_ args: [String: Value]) async throws -> CallTool.Result {
    guard let param = args["param"]?.stringValue else {
        throw MCP.Error.invalidParams("Missing parameter: param")
    }
    // Implementation
    return CallTool.Result(content: [...])
}
```

### Add a New Service

1. Create file in `Sources/CodeSearchMCP/Services/`:
```swift
actor MyNewService: Sendable {
    private let logger = Logger(label: "my-service")
    
    init() {
        logger.debug("Service initialized")
    }
    
    func doSomething() async throws {
        // Implementation
    }
}
```

2. Add to MCPServer initialization:
```swift
let myService = MyNewService()
```

3. Use in tool handlers:
```swift
let result = try await myService.doSomething()
```

### Add a New Data Model

1. Create file in `Sources/CodeSearchMCP/Models/`:
```swift
struct MyModel: Sendable, Codable {
    let id: String
    let name: String
    
    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

extension MyModel {
    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}
```

2. Use in services and tools as needed

### Add Tests

Create test functions in `Tests/CodeSearchMCP/CodeSearchMCPTests.swift`:

```swift
@Test("Description of test")
func testSomething() async throws {
    // Setup
    let service = MyService()
    
    // Execute
    let result = try await service.doSomething()
    
    // Verify
    #expect(result == expectedValue)
}
```

## Debugging

### Run with Debug Logging

```bash
swift run code-search-mcp --log-level debug
```

### Attach Debugger in Xcode

```bash
# Build for debugging
swift build

# Open in Xcode
open Package.swift
```

Then select Run > Run with Breakpoints or press Cmd+Opt+B

### Print Debugging

Use `logger.debug()` instead of `print()`:
```swift
logger.debug("Value: \(myValue)", metadata: ["key": "\(myValue)"])
```

### Memory Issues

Check for memory leaks with `swift test` output or use Instruments.app

## CI/CD

### GitHub Actions Setup

Create `.github/workflows/swift.yml`:
```yaml
name: Swift CI

on: [push, pull_request]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: swift-actions/setup-swift@v1
        with:
          swift-version: "6.0"
      - run: swift build
      - run: swift test
      - run: swift format lint -s -p -r Sources Tests Package.swift
```

## Performance Optimization

### Profile with Instruments

```bash
# Build with profiling enabled
swift build -c release -Xswiftc -g

# Run and profile
instruments -t "System Trace" .build/release/code-search-mcp
```

### Batch Operations

For large-scale operations, use batch methods:
```swift
// Slow
for item in items {
    let embedding = try await embeddingService.generateEmbedding(for: item)
}

// Fast
let embeddings = try await embeddingService.generateEmbeddings(for: items)
```

## Common Issues

### Build Failures

**Issue**: `error: could not find package with name 'SomePackage'`

**Solution**: Check Package.swift dependencies and run:
```bash
swift package update
rm -rf .build
swift build
```

### Test Failures

**Issue**: `error: *** Thread 1: EXC_BAD_ACCESS`

**Solution**: Likely actor isolation issue. Check for:
- Non-Sendable types crossing actor boundaries
- Missing `await` for actor methods
- Shared mutable state

### Slow Indexing

**Issue**: Project indexing is slow

**Solutions**:
- Use `.build`, `.git`, `node_modules` in exclusion list
- Process files in parallel (if concurrent)
- Add file type filters to limit processing

## Dependencies

### Current Dependencies

- **MCP SDK**: `0.9.0+` - Protocol implementation
- **swift-embeddings**: `0.0.23+` - BERT embeddings
- **swift-log**: `1.5.0+` - Logging
- **swift-argument-parser**: `1.3.0+` - CLI arguments
- **swift-nio**: `2.60.0+` - Networking utilities

### Adding New Dependencies

1. Add to `Package.swift`:
```swift
.package(
    url: "https://github.com/user/package.git",
    from: "1.0.0"
)
```

2. Add to target dependencies:
```swift
.product(name: "PackageName", package: "package")
```

3. Update code and tests

## Release Process

1. Update version in Package.swift and CodeSearchMCP.swift
2. Run full test suite: `swift test`
3. Check formatting: `swift format lint -s -p -r Sources Tests Package.swift`
4. Create release tag: `git tag v0.1.0`
5. Push: `git push origin v0.1.0`
6. Build release: `swift build -c release`
7. Create GitHub release with binary

## Resources

- [Swift 6 Concurrency](https://www.swift.org/documentation/concurrency)
- [MCP Protocol](https://modelcontextprotocol.io)
- [swift-log Documentation](https://github.com/apple/swift-log)
- [ArgumentParser Guide](https://github.com/apple/swift-argument-parser)
- [Swift Testing Framework](https://swift.org/testing)

## Support

For issues or questions:
1. Check this development guide
2. Review architecture document
3. Check existing GitHub issues
4. Create detailed issue with:
   - Swift version
   - Error messages/logs
   - Steps to reproduce
   - Expected vs actual behavior
