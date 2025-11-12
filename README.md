# code-search-mcp

An MCP server for pure vector-based semantic code search across multiple projects using 384-dimensional BERT embeddings.

## Features

- **Semantic Search**: Find code with similar meaning using 384-dimensional BERT vector embeddings
- **File Context Extraction**: Get code snippets with surrounding context
- **Dependency Analysis**: Find files that import or depend on a given file
- **Multi-Project Support**: Index and search across multiple codebases
- **Language Support**: Swift, Python, JavaScript/TypeScript, Java, Go, Rust, C/C++, C#, Ruby, PHP, Kotlin
- **Smart Caching**: Cache embeddings to avoid recomputation
- **Pure Vector Search**: No regex patterns, no keyword matching - 100% semantic understanding

## Requirements

- macOS 15.0+
- Swift 6.0+
- Python 3.8+ with pip
- Xcode 16.0+ (for development)

## Installation

### Option 1: From PromptPing Marketplace (Recommended)

```bash
# Add marketplace
/plugin marketplace add /Users/stijnwillems/Developer/promptping-marketplace

# Install plugin
/plugin install code-search-mcp

# Restart Claude Code
```

### Option 2: From Source

```bash
git clone https://github.com/doozMen/code-search-mcp.git
cd code-search-mcp

# Install Python dependencies (required for BERT embeddings)
./Scripts/install_python_deps.sh

# Build and install
./install.sh
```

### Option 3: Manual Build

```bash
# Install Python dependencies first
./Scripts/install_python_deps.sh

# Build and install
swift build -c release
swift package experimental-install
```

## Configuration

### For Marketplace Installation (Option 1)

The plugin is automatically configured when installed from the marketplace. Ensure your `~/.claude/settings.json` includes the PATH:

```json
{
  "env": {
    "PATH": "/Users/<YOUR_USERNAME>/.swiftpm/bin:/usr/local/bin:/usr/bin:/bin"
  }
}
```

### For Manual Installation (Options 2 & 3)

Add to Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

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

### direnv Integration (Automatic Project Selection)

Use direnv to automatically scope searches to your current project directory:

```bash
# 1. Copy template to your project
cd ~/Developer/MyApp
cp ~/.swiftpm/share/code-search-mcp/.envrc.template .envrc

# 2. Edit .envrc to set your project name
export CODE_SEARCH_PROJECT_NAME="MyApp"

# 3. Allow direnv to load it
direnv allow

# 4. Now searches auto-scope to MyApp!
# In Claude Code: "Find auth code" → searches MyApp only
```

**Environment Variables**:
- `CODE_SEARCH_PROJECT_NAME`: Auto-filter searches to this project
- Explicit `projectFilter` parameter overrides environment

**Benefits**:
- No manual project filtering needed
- Context-aware search based on current directory
- Works seamlessly with multi-project workflows

---

## Usage

### Tool: semantic_search

Search for code with similar meaning to your query.

**Parameters**:
- `query` (required): Natural language query or code snippet
- `maxResults` (optional): Maximum results to return (default: 10)
- `projectFilter` (optional): Limit search to specific project

**Example**:
```json
{
  "name": "semantic_search",
  "arguments": {
    "query": "function that validates email addresses",
    "maxResults": 5
  }
}
```

### Tool: file_context

Extract code from a file with optional line range.

**Parameters**:
- `filePath` (required): Path to file (relative to project root)
- `startLine` (optional): Start line number (1-indexed)
- `endLine` (optional): End line number (1-indexed)
- `contextLines` (optional): Context lines around range (default: 3)

**Example**:
```json
{
  "name": "file_context",
  "arguments": {
    "filePath": "Sources/Core/Utils.swift",
    "startLine": 42,
    "endLine": 50,
    "contextLines": 5
  }
}
```

### Tool: find_related

Find files that import, depend on, or are related to a file.

**Parameters**:
- `filePath` (required): Path to file (relative to project root)
- `direction` (optional): "imports", "imports_from", or "both" (default: "both")

**Example**:
```json
{
  "name": "find_related",
  "arguments": {
    "filePath": "Sources/Core/Database.swift",
    "direction": "both"
  }
}
```

### Tool: index_status

Get metadata and statistics about indexed projects.

**Parameters**: None

**Example**:
```json
{
  "name": "index_status"
}
```

## Architecture

### Services

- **ProjectIndexer**: Crawls directories and extracts code chunks
- **EmbeddingService**: Generates and caches 384-d BERT embeddings (via Python bridge)
- **VectorSearchService**: Performs cosine similarity search on vector embeddings
- **CodeMetadataExtractor**: Builds dependency graphs and extracts metadata

### Models

- **CodeChunk**: Represents indexed code with location and embedding
- **SearchResult**: Unified search result type
- **ProjectMetadata**: Project information and statistics
- **DependencyGraph**: Inter-file dependency relationships

### Storage

Index data stored in `~/.cache/code-search-mcp/`:

```
~/.cache/code-search-mcp/
├── embeddings/          # Cached BERT embeddings (one file per unique text hash)
└── dependencies/        # Dependency graphs (one file per project)
```

## Development

### Building

```bash
swift build
```

### Testing

```bash
swift test
```

### Running with Debug Logging

```bash
swift run code-search-mcp --log-level debug
```

### Code Formatting

```bash
# Check formatting
swift format lint -s -p -r Sources Tests Package.swift

# Auto-fix formatting
swift format format -p -r -i Sources Tests Package.swift
```

## Implementation Roadmap

Current state: Scaffold complete with services and models defined

### Phase 1: Core Infrastructure (In Progress)
- [x] Project structure and Package.swift
- [x] Service skeleton files
- [x] Model definitions
- [x] MCP server initialization
- [ ] Embedding service BERT integration
- [ ] Vector search implementation
- [ ] Index persistence (JSON/SQLite)

### Phase 2: Search Capabilities
- [ ] Semantic search with ranking
- [ ] Keyword search with symbol indexing
- [ ] File context extraction
- [ ] Dependency graph building
- [ ] Related file discovery

### Phase 3: Optimization
- [ ] Batch embedding generation
- [ ] Index compression
- [ ] Incremental indexing
- [ ] Performance benchmarking

### Phase 4: Enterprise Features
- [ ] Project-level access control
- [ ] Search result caching
- [ ] Custom embedding models
- [ ] Search analytics

## Troubleshooting

### Cache Issues

Clear embedding cache:
```bash
rm -rf ~/.cache/code-search-mcp/embeddings
```

### Logging

Enable debug logging to troubleshoot:
```bash
swift run code-search-mcp --log-level debug
```

Check Claude Desktop logs:
- macOS: `~/Library/Logs/Claude/mcp-server-code-search-mcp.log`

### Index Not Updating

Rebuild the index:
```bash
rm -rf ~/.cache/code-search-mcp
# Re-index projects by restarting Claude
```

## Performance Notes

- First embedding generation takes longer (BERT model loading)
- Subsequent queries are fast due to embedding caching
- Large projects (10k+ files) may take 1-2 minutes to index
- Vector search is O(n) but fast for typical project sizes

## Limitations

- Dependency tracking works for explicit imports only (implicit dependencies not tracked)
- No support for cross-language dependency tracking
- Vector search is O(n) - performance scales linearly with index size

## License

MIT

## Contributing

Contributions welcome! Please ensure:
- Swift 6 strict concurrency compliance
- All types conform to Sendable
- Comprehensive error handling
- Swift Testing framework for tests
- Code formatted with swift-format

## Support

For issues or questions:
1. Check the troubleshooting section
2. Enable debug logging and check logs
3. Open an issue on GitHub with:
   - Log output (with debug logging enabled)
   - Steps to reproduce
   - Expected vs actual behavior
