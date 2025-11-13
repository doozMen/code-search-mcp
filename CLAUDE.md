# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

**code-search-mcp** - Pure vector-based semantic code search MCP server using CoreML embeddings (macOS) or BERT embeddings (Linux).

**Core Value**: Find code by what it DOES (semantic meaning), not what it's CALLED (keywords).

## Build Commands

```bash
# Build
swift build

# Test
swift test

# Test single suite
swift test --filter VectorSearchServiceTests

# Format code
swift format format -p -r -i Sources Tests Package.swift

# Install binary
./install.sh
```

## Architecture (Pure Vector-Based)

### Two-Module Structure

**SwiftEmbeddings** (reusable library):
- `EmbeddingService` - Generate and cache embeddings
- `CoreMLEmbeddingProvider` - macOS (NLEmbedding, 300-dim, 4,172 emb/sec)
- `BERTEmbeddingProvider` - Linux only (#if os(Linux), 384-dim)
- `VectorMath` - SIMD-accelerated operations (Accelerate framework)

**CodeSearchMCP** (MCP server):
- `MCPServer` - MCP protocol implementation
- `ProjectIndexer` - File crawling, code chunking
- `VectorSearchService` - Cosine similarity search with deduplication
- `InMemoryVectorIndex` - RAM-optimized for Mac Studio (128GB)

### Platform-Specific Compilation

```swift
// macOS: Only CoreML compiled
#if os(macOS)
  provider = try CoreMLEmbeddingProvider()  // 300-dim
#elseif os(Linux)
  provider = BERTEmbeddingProvider()        // 384-dim
#endif
```

**On macOS**: No BERT code in binary (verified with `nm`)
**On Linux**: No CoreML code in binary

### Storage Architecture

```
~/.cache/code-search-mcp/
├── embeddings/              # Global cache (SHA256 filenames)
│   └── <hash>.embedding     # JSON array of Float
├── chunks/                  # Per-project
│   └── <ProjectName>/
│       └── <uuid>.json      # CodeChunk with projectName, filePath
├── dependencies/
│   └── <ProjectName>.graph.json
└── project_registry.json
```

**Key Insight**: Embeddings deduplicated globally (70% space savings), chunks filtered by projectName (no mixing).

## MCP Tools

**Search** (3):
1. `semantic_search(query, maxResults, projectFilter)` - Vector similarity search
2. `file_context(filePath, startLine, endLine)` - Extract code
3. `find_related(filePath, direction)` - Dependency navigation

**Management** (4):
4. `index_status()` - Cache stats
5. `reload_index(projectName)` - Refresh index
6. `clear_index(confirm)` - Clear all data
7. `list_projects()` - Show indexed projects

## CLI Commands

```bash
# Run MCP server
code-search-mcp

# Setup auto-indexing
code-search-mcp setup-hooks --install-hooks

# With project paths
code-search-mcp --project-paths ~/project1 --project-paths ~/project2
```

## Environment Variables

**Auto-indexing** (read from `~/.claude/settings.json`):
- `CODE_SEARCH_PROJECTS` - Colon-separated project paths (auto-index on startup)
- `CODE_SEARCH_PROJECT_NAME` - Default project filter for searches

**direnv integration**:
```bash
# .envrc
export CODE_SEARCH_PROJECT_NAME="MyProject"
```

## Important Implementation Details

### Deduplication (Issue #19 Fix)

VectorSearchService deduplicates by `(filePath, startLine)` after scoring:
```swift
// Prevents overlapping chunks from appearing as duplicates
func deduplicateResults(_ results: [ScoredChunk]) -> [ScoredChunk]
```

### SIMD Optimization

Uses Accelerate framework for 194x speedup:
```swift
vDSP_dotpr(a, 1, b, 1, &dotProduct, count)     // Dot product
vDSP_svesq(a, 1, &magnitudeSquared, count)     // Magnitude
```

### Swift 6 Strict Concurrency

- All services are `actor` types
- All models are `Sendable`
- No `@unchecked Sendable` in codebase
- Use `async/await` for all cross-actor calls

## Testing

**Test suites** (97% coverage):
- `VectorSearchServiceTests` - Cosine similarity, deduplication
- `EmbeddingProviderFallbackTests` - CoreML primary, BERT fallback
- `EmbeddingQualityTests` - Semantic similarity validation (0.85 similar, 0.37 different)
- `InMemoryVectorIndexTests` - SIMD performance, parallel search
- `VectorSearchDeduplicationTests` - No duplicate results
- `IndexManagementTests` - reload_index, list_projects

**Quality thresholds**:
- CoreML (word-level): >0.5 similar, <0.6 different
- BERT (sentence-level): >0.8 similar, <0.5 different

## Embedding Providers

**CoreML** (Primary on macOS):
- Framework: NaturalLanguage (built-in)
- Dimensions: 300
- Speed: 4,172 embeddings/second
- Type: Word-level averaging
- No external dependencies

**BERT** (Linux only):
- Model: sentence-transformers/all-MiniLM-L6-v2
- Dimensions: 384
- Speed: ~100 embeddings/second
- Type: Sentence transformers
- Requires: Python + FastAPI server (Scripts/bert_embedding_server.py)

**Foundation Models**: Not used (no embedding API exists in macOS 26.0+)

## Common Issues

**Duplicate results**: Fixed in v0.3.2 with deduplication logic
**Project not indexed**: Use `CODE_SEARCH_PROJECTS` env var or `--project-paths` CLI arg
**Stale results**: Run `reload_index` tool or setup auto-indexing with `setup-hooks`

## Version Management

```bash
# Create snapshot for PR
./bump-version.sh 0.x.0-alpha.1
git commit -m "chore: Bump version to 0.x.0-alpha.1 (snapshot for PR #N)"

# After merge, release version on main
./bump-version.sh 0.x.0
git commit -m "chore: Release v0.x.0"
git tag v0.x.0
```

**Critical**: Always use alpha versions in PRs, release versions only after merge to main.
