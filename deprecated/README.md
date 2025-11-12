# Deprecated Code

This directory contains code that has been removed from the active codebase but preserved for reference.

## KeywordSearchService.swift (815 lines)

**Removed**: 2025-11-12  
**Reason**: Architectural decision to focus 100% on vector-based semantic search

### Why It Was Removed

The `KeywordSearchService` implemented regex-based symbol extraction and keyword matching across Swift, Python, JavaScript, Java, Go, and other languages. While functional, this approach had several limitations:

1. **Regex Fragility**: Language-specific regex patterns were brittle and required constant maintenance
2. **False Positives**: Pattern matching produced noisy results with low precision
3. **Limited Semantic Understanding**: Keyword matching couldn't understand code meaning or context
4. **Duplication**: Overlapped with vector search capabilities
5. **Maintenance Burden**: Required updating patterns for each language evolution

### What Replaced It

Pure vector-based semantic search using 384-dimensional BERT embeddings provides:

- **Semantic Understanding**: Finds code by meaning, not just string matching
- **Language Agnostic**: Works across all languages without custom patterns
- **Better Precision**: Higher quality results through similarity scoring
- **Simpler Architecture**: Single unified search mechanism
- **Foundation Models Integration**: Native support for Apple Intelligence and local LLMs

### MCP Tools Affected

**Removed**:
- `keyword_search` - Symbol and function name search

**Retained**:
- `semantic_search` - Natural language code search with vectors
- `file_context` - Extract code snippets with context
- `index_status` - View indexing statistics

### What Symbol Extraction Supported

The service extracted and indexed:
- **Swift**: class, struct, enum, protocol, actor, func, var, let, init
- **Python**: class, def, async def
- **JavaScript/TypeScript**: class, function, const, arrow functions
- **Java**: class, interface, enum, methods
- **Go**: func, type, struct, interface, const, var
- **Generic fallback**: Basic keyword detection for unsupported languages

### Search Modes Removed

1. **Exact Match**: Case-sensitive symbol name lookup
2. **Fuzzy Match**: Case-insensitive substring matching
3. **Definition vs Reference**: Tracked symbol definitions and usages
4. **Project Scoping**: Filter results by project name

### Symbol Index Format

The service persisted `SymbolIndex` as JSON in `~/.cache/code-search-mcp/symbols/`:

```json
{
  "project_name": "example-project",
  "symbols": {
    "MyClass": [
      {
        "filePath": "/path/to/file.swift",
        "lineNumber": 42,
        "isDefinition": true,
        "context": "class MyClass { ... }"
      }
    ]
  },
  "last_updated": "2025-11-12T10:00:00Z"
}
```

### Migration Path

Users relying on keyword search should transition to semantic search:

**Before** (keyword search):
```json
{
  "name": "keyword_search",
  "arguments": {
    "symbol": "validateEmail",
    "includeReferences": true
  }
}
```

**After** (semantic search):
```json
{
  "name": "semantic_search",
  "arguments": {
    "query": "function that validates email addresses",
    "maxResults": 10
  }
}
```

### Code Statistics

- **Total Lines**: 815
- **Actors**: 1 (KeywordSearchService)
- **Models**: 4 (Symbol, SymbolLocation, SymbolIndex, KeywordIndexStats)
- **Error Types**: 1 (KeywordSearchError)
- **Language Extractors**: 6 (Swift, Python, JS/TS, Java, Go, Generic)
- **Regex Patterns**: ~30 across all languages

### Related Changes

- `MCPServer.swift`: Removed keyword_search tool and handler
- `ProjectIndexer.swift`: Removed symbol extraction method calls
- `README.md`: Updated to show only 3 MCP tools
- `CLAUDE.md`: Clarified vector-only focus

### Future Considerations

If keyword search capabilities are needed in the future, consider:

1. **Tree-sitter Integration**: Use proper AST parsing instead of regex
2. **LSP Protocol**: Leverage Language Server Protocol for accurate symbol information
3. **Hybrid Approach**: Combine vector search with structured metadata from LSP
4. **Foundation Models**: Use on-device LLMs for code understanding

This approach was removed to simplify the architecture and focus on the superior vector-based search mechanism that provides semantic understanding without language-specific pattern maintenance.
