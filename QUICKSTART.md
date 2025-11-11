# Quick Start Guide for code-search-mcp

Get code-search-mcp running in 5 minutes!

## Installation

### 1. Clone or Navigate to Project

```bash
cd /Users/stijnwillems/Developer/code-search-mcp
```

### 2. Run Installation Script

```bash
./install.sh
```

This will:
- Build the project in release mode
- Install to `~/.swiftpm/bin/`
- Verify the installation

### 3. Verify Installation

```bash
code-search-mcp --help
```

You should see the help message with available options.

## Configuration

### Add to Claude Desktop

1. Open configuration file:
```bash
nano ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

2. Add this server block (inside `mcpServers`):
```json
"code-search-mcp": {
  "command": "code-search-mcp",
  "args": ["--log-level", "info"],
  "env": {
    "PATH": "$HOME/.swiftpm/bin:/usr/local/bin:/usr/bin:/bin"
  }
}
```

3. Restart Claude Desktop

## First Use

Once Claude Desktop restarts, you should see code-search-mcp is available!

### Try These Examples

#### Example 1: Semantic Search

Ask Claude:
> "Find code that validates email addresses"

Claude will use the `semantic_search` tool to look for related code.

#### Example 2: Find a Symbol

Ask Claude:
> "Where is the `main` function defined?"

Claude will use the `keyword_search` tool to locate it.

#### Example 3: Get File Context

Ask Claude:
> "Show me lines 10-20 from Sources/MyFile.swift"

Claude will use the `file_context` tool to retrieve it.

#### Example 4: Find Related Files

Ask Claude:
> "What files import this module?"

Claude will use the `find_related` tool to show dependencies.

## Project Structure

```
code-search-mcp/
├── Sources/CodeSearchMCP/     # Main implementation
│   ├── Services/              # Core services
│   └── Models/                # Data models
├── Tests/                     # Test suite
├── Package.swift              # Project definition
├── README.md                  # Full documentation
├── ARCHITECTURE.md            # Design docs
└── DEVELOPMENT.md             # Development guide
```

## Development

### Build

```bash
swift build
```

### Test

```bash
swift test
```

### Run Locally (with debug logging)

```bash
swift run code-search-mcp --log-level debug
```

### Format Code

```bash
swift format format -p -r -i Sources Tests Package.swift
```

## Troubleshooting

### "Command not found: code-search-mcp"

Make sure `~/.swiftpm/bin` is in your PATH:
```bash
export PATH="$HOME/.swiftpm/bin:$PATH"
echo $PATH  # Verify
```

### Code not appearing in search results

The server needs to index your projects. Currently, projects are indexed on startup if passed via `--project-paths` option. This is a TODO for future development.

### Debug Logging

To see detailed logs:
```bash
swift run code-search-mcp --log-level debug
```

Or restart Claude with debug enabled to see server logs in Claude Desktop logs:
```bash
tail -f ~/Library/Logs/Claude/mcp-server-code-search-mcp.log
```

### Cache Issues

Clear the embedding cache if needed:
```bash
rm -rf ~/.cache/code-search-mcp/embeddings
```

Rebuild the full index:
```bash
rm -rf ~/.cache/code-search-mcp
```

## Next Steps

1. **Read Full Documentation**: See `README.md` for complete tool descriptions
2. **Understand Architecture**: Read `ARCHITECTURE.md` for design decisions
3. **Development**: Check `DEVELOPMENT.md` for development guide
4. **Implementation**: Look at Phase 1 TODOs to understand remaining work

## Key Components

### Services (Actors)
- **ProjectIndexer**: Crawls directories and extracts code
- **EmbeddingService**: Generates BERT embeddings
- **VectorSearchService**: Semantic search using vectors
- **KeywordSearchService**: Fast symbol lookup
- **CodeMetadataExtractor**: Tracks dependencies

### Models
- **CodeChunk**: Unit of indexed code
- **SearchResult**: Search result with metadata
- **ProjectMetadata**: Project information and stats

### MCP Tools
1. `semantic_search` - Find similar code by meaning
2. `keyword_search` - Find symbols by name
3. `file_context` - Extract file content
4. `find_related` - Find dependent files
5. `index_status` - See indexing stats

## Implementation Status

### Current (Phase 1 - Scaffold)
- ✅ Project structure
- ✅ Service skeletons
- ✅ Model definitions
- ✅ MCP server initialization
- ✅ Tool definitions

### TODO (Phase 1 - Core)
- ⏳ BERT embedding integration (swift-embeddings)
- ⏳ Vector search implementation
- ⏳ Index persistence
- ⏳ Keyword/symbol indexing

### TODO (Phase 2+)
- ⏳ Dependency graph building
- ⏳ Performance optimization
- ⏳ Advanced features

## Files by Purpose

| File | Purpose |
|------|---------|
| `CodeSearchMCP.swift` | Entry point, CLI config |
| `MCPServer.swift` | MCP protocol implementation, tool handlers |
| `ProjectIndexer.swift` | Directory crawling, code extraction |
| `EmbeddingService.swift` | Vector embedding generation |
| `VectorSearchService.swift` | Cosine similarity search |
| `KeywordSearchService.swift` | Symbol indexing and lookup |
| `CodeMetadataExtractor.swift` | Dependency graph building |
| `CodeChunk.swift` | Indexed code unit model |
| `SearchResult.swift` | Unified search result type |
| `ProjectMetadata.swift` | Project registry and statistics |

## Command Line Usage

```bash
# Show help
code-search-mcp --help

# Run with debug logging
code-search-mcp --log-level debug

# Specify custom index directory
code-search-mcp --index-path /custom/path

# Index projects on startup (future)
code-search-mcp --project-paths /path/to/project1 /path/to/project2
```

## Tips & Tricks

### Get Index Status
Ask Claude: "What's in the index?"
→ Uses `index_status` tool

### Search Specific Project
Ask Claude: "Find `function` in my project"
→ Uses `projectFilter` parameter

### Find Function Implementations
Ask Claude: "Show me all implementations of `doWork`"
→ Uses `keyword_search` with `includeReferences: true`

### See File Dependencies
Ask Claude: "What files depend on utils.swift?"
→ Uses `find_related` with `direction: "imports"`

## Resources

- **MCP Documentation**: https://modelcontextprotocol.io
- **Swift Concurrency**: https://www.swift.org/documentation/concurrency
- **Project README**: `/Users/stijnwillems/Developer/code-search-mcp/README.md`
- **Architecture**: `/Users/stijnwillems/Developer/code-search-mcp/ARCHITECTURE.md`
- **Development**: `/Users/stijnwillems/Developer/code-search-mcp/DEVELOPMENT.md`

## Getting Help

1. Check troubleshooting section above
2. Read DEVELOPMENT.md for common issues
3. Enable debug logging
4. Check Claude Desktop logs
5. Create GitHub issue with:
   - Error output
   - Debug logs
   - Steps to reproduce
   - Your environment (Swift version, macOS version)

---

Ready to go! Start searching code with semantic understanding!
