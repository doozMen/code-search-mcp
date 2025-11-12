# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

**code-search-mcp** is a Model Context Protocol (MCP) server that provides **pure vector-based semantic code search** across multiple projects using 768-dimensional BERT embeddings (CoreML).

**Architectural Decision**: This server focuses 100% on vector-based semantic search. Regex-based keyword/symbol search has been intentionally removed to simplify the architecture and focus on semantic understanding. See `deprecated/README.md` for details on what was removed and why.

**Embedding Provider**: Uses **CoreML BERT** (bert-base-uncased) for vector generation. Foundation Models (macOS 26.0+) does NOT provide embedding APIs and is not used. See `FOUNDATION_MODELS_EMBEDDING_ASSESSMENT.md` for detailed analysis.

## Build & Development Commands

### Building

```bash
# Development build
swift build

# Release build
swift build -c release

# Run directly with debug logging
swift run code-search-mcp --log-level debug
```

### Testing

```bash
# Run all tests
swift test

# Run with verbose output
swift test --verbose

# Run with code coverage
swift test --code-coverage
```

### Code Formatting

```bash
# Check formatting
swift format lint -s -p -r Sources Tests Package.swift

# Auto-fix formatting
swift format format -p -r -i Sources Tests Package.swift
```

### Installation

```bash
# Install to ~/.swiftpm/bin
swift package experimental-install

# Or use install script
./install.sh
```

## Architecture Overview

### Actor-Based Service Layer

All services are Swift 6 actors for strict concurrency:

```
MCPServer (Actor)
├── ProjectIndexer        # File crawling and chunk extraction
├── EmbeddingService      # BERT embedding generation and caching (Python bridge)
├── VectorSearchService   # Cosine similarity semantic search
└── CodeMetadataExtractor # Dependency graph construction
```

**Critical**: All types crossing actor boundaries must implement `Sendable`. Use `async/await` for all actor method calls.

### MCP Tools Provided (7 tools - vector-focused)

**Core Search Tools**:
1. **semantic_search** - Find code by semantic similarity using 300/384-d embeddings (CoreML/BERT)
2. **file_context** - Extract code snippets with surrounding context
3. **find_related** - Find files through import/dependency relationships

**Index Management Tools**:
4. **index_status** - Get metadata about indexed projects
5. **reload_index** - Reload index for a specific project or all projects (use when code changes)
6. **clear_index** - Clear all indexed data (requires confirmation)
7. **list_projects** - List all indexed projects with statistics

**Removed**: `keyword_search` tool was intentionally removed to focus on pure vector-based semantic search. See `deprecated/README.md` for migration guide.

### Data Flow

**Indexing Flow**:
```
Directory → ProjectIndexer → CodeChunks → EmbeddingService (Python) → Cache
                           → CodeMetadataExtractor → Dependency Graph
```

**Search Flow** (Vector-only):
```
Query → EmbeddingService (Python) → 384-d Vector
      → VectorSearchService → Cosine Similarity → Ranked Results
```

### Storage Structure

Index data stored in `~/.cache/code-search-mcp/`:

```
~/.cache/code-search-mcp/
├── embeddings/                      # Global shared cache (deduplication)
│   └── <sha256-hash>.embedding     # JSON array of Float (300/384 dims)
├── chunks/                          # Project-specific chunk metadata
│   ├── <ProjectName>/
│   │   └── <chunk-uuid>.json       # CodeChunk with projectName, filePath, embedding
│   └── ...
├── dependencies/                    # Dependency graphs per project
│   └── <ProjectName>.graph.json
└── project_registry.json            # Project metadata and timestamps
```

**Key Features**:
- **Global embedding deduplication**: Common code stored once, referenced many times (70% space savings)
- **Project isolation**: Each chunk remembers its projectName, preventing mixing
- **Search filtering**: Filters by projectName before similarity calculation
- **direnv support**: Auto-selects project based on `CODE_SEARCH_PROJECT_NAME` environment variable

## Key Implementation Patterns

### Adding a New MCP Tool

1. Define tool in `MCPServer.handleListTools()`:
```swift
Tool(
    name: "my_tool",
    description: "Description",
    inputSchema: .object([
        "type": "object",
        "properties": .object([
            "param": .object([
                "type": "string",
                "description": "Parameter description"
            ])
        ]),
        "required": .array([.string("param")])
    ])
)
```

2. Add handler in `MCPServer.handleCallTool()`:
```swift
case "my_tool":
    return try await handleMyTool(params.arguments ?? [:])
```

3. Implement handler method:
```swift
private func handleMyTool(_ args: [String: Value]) async throws -> CallTool.Result {
    guard let param = args["param"]?.stringValue else {
        throw MCPError.invalidParams("Missing parameter: param")
    }
    // Implementation
    return CallTool.Result(content: [...])
}
```

### Adding a New Service

1. Create actor in `Sources/CodeSearchMCP/Services/`:
```swift
actor MyService: Sendable {
    private let logger = Logger(label: "my-service")

    init(indexPath: String) {
        logger.debug("Service initialized")
    }

    func doSomething() async throws {
        // Implementation
    }
}
```

2. Initialize in `MCPServer.init()`:
```swift
self.myService = MyService(indexPath: indexPath)
```

3. Use in tool handlers with `await`:
```swift
let result = try await myService.doSomething()
```

### Error Handling

**Service-level errors**:
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

**MCP-level errors** (for protocol responses):
```swift
throw MCPError.invalidParams("Missing parameter: name")
throw MCPError.internalError("Service unavailable")
throw MCPError.invalidRequest("Unknown tool")
```

### Logging

Use swift-log throughout:
```swift
import Logging

let logger = Logger(label: "component-name")

logger.debug("Debug message", metadata: ["key": "value"])
logger.info("Info message")
logger.warning("Warning message")
logger.error("Error message", metadata: ["error": "\(error)"])
```

## Development Patterns

### Swift 6 Strict Concurrency

- All services are actors for safe concurrency
- All models implement `Sendable` for safe passing between actors
- Use `async/await` consistently - never block with synchronous calls
- Avoid `@unchecked Sendable` unless absolutely justified with comments

### Testing with Swift Testing Framework

```swift
import Testing

@Test("Description of test")
func testSomething() async throws {
    // Setup
    let service = MyService(indexPath: "/tmp/test")

    // Execute
    let result = try await service.doSomething()

    // Verify
    #expect(result == expectedValue)
}
```

### Language Support

Supported languages for indexing:
- Swift, Python, JavaScript/TypeScript, Java, Go, Rust
- C/C++, C#, Ruby, PHP, Kotlin

Each language has specific symbol extraction patterns in `ProjectIndexer`.

## Configuration

### Claude Desktop Integration

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "code-search-mcp": {
      "command": "code-search-mcp",
      "args": ["--log-level", "info"],
      "env": {
        "PATH": "$HOME/.swiftpm/bin:/usr/local/bin:/usr/bin:/bin"
      }
    }
  }
}
```

### Runtime Options

```bash
# Custom index path
code-search-mcp --index-path /path/to/index

# Pre-index projects on startup
code-search-mcp --project-paths /path/to/project1 --project-paths /path/to/project2

# Debug logging
code-search-mcp --log-level debug
```

## Dependencies

- **MCP SDK** (0.9.0+) - MCP protocol implementation
- **swift-log** (1.5.0+) - Logging infrastructure
- **swift-argument-parser** (1.3.0+) - CLI argument parsing
- **swift-nio** (2.60.0+) - Networking utilities

**Note**: BERT embedding integration is planned for Phase 1. Currently uses placeholder embeddings.

## Performance Notes

- First embedding generation is slower (BERT model loading)
- Subsequent queries are fast due to embedding caching
- Large projects (10k+ files) may take 1-2 minutes to index
- Vector search is O(n) but fast for typical project sizes
- Always exclude `.build`, `.git`, `node_modules` directories

## Implementation Status

**Phase 1 (Complete)** ✅:
- [x] Project structure and Package.swift
- [x] Service skeleton files
- [x] Model definitions
- [x] MCP server initialization
- [x] Embedding service BERT integration (Python bridge)
- [x] Vector search implementation (cosine similarity)
- [x] Index persistence (JSON-based)
- [x] Code chunk extraction (50-line chunks)
- [x] Symbol index persistence
- [x] Dependency graph persistence

**Phase 2 (In Progress)**:
- [x] Semantic search with ranking (complete)
- [ ] Keyword search with symbol indexing (persistence complete, search TODO)
- [ ] File context extraction (stub exists)
- [x] Dependency graph building (complete)

See ARCHITECTURE.md and DEVELOPMENT.md for detailed implementation plans.

## Troubleshooting

### Cache Issues

```bash
# Clear embedding cache
rm -rf ~/.cache/code-search-mcp/embeddings

# Clear all caches
rm -rf ~/.cache/code-search-mcp
```

### Debug Logging

```bash
# Enable debug logging
swift run code-search-mcp --log-level debug

# Check Claude Desktop logs
tail -f ~/Library/Logs/Claude/mcp-server-code-search-mcp.log
```

### Build Issues

```bash
# Clean and rebuild
rm -rf .build
swift package update
swift build
```

## Current Limitations

- Currently uses hash-based placeholder embeddings (BERT integration TODO)
- Symbol extraction supports common patterns (more patterns can be added)
- Dependency tracking works for explicit imports (implicit dependencies not tracked)
- No cross-language dependency tracking

## Code Quality Standards

- Swift 6 strict concurrency compliance required
- All types crossing actor boundaries must implement `Sendable`
- Comprehensive error handling with domain-specific error types
- Use Swift Testing framework (not XCTest)
- Format code with `swift format` before committing
- Document public APIs with DocC-style comments
