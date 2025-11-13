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

## Automatic Subproject Detection (v0.5.0+)

### Problem Solved
Previously, indexing parent directories (e.g., `~/Developer`) created massive single projects with 87k+ files, causing:
- Poor search relevance (results from unrelated projects mixed together)
- Slow performance (searching 100k+ chunks)
- Confusing UX (what project am I actually searching?)

### Solution: Smart Detection
**ProjectIndexer** now automatically detects and indexes subprojects:

**1. Multiple Git Repositories**
```bash
~/Developer/
├── project-a/  (.git)
├── project-b/  (.git)
└── project-c/  (.git)
```
→ Indexes as 3 separate projects: `project-a`, `project-b`, `project-c`

**2. Swift Packages with Multiple Products**
```bash
~/MyPackage/
└── Package.swift  (defines: App, Library, CLI)
```
→ Runs `swift package dump-package`, indexes each product separately

**3. Automatic Migration**
Legacy indexes (>5,000 files) are automatically re-indexed at server startup with new detection logic. No user intervention needed.

### How It Works

1. **Detection** (`detectSubprojects()`):
   - Checks if directory has `Package.swift` → Parses products with `SwiftPackageParser`
   - Checks if directory has `.git` → Scans subdirectories for multiple repos
   - If neither → Indexes as single project

2. **Swift Package Parsing** (`SwiftPackageParser`):
   - Runs: `swift package --package-path <path> dump-package`
   - Parses JSON output for products array
   - Creates one subproject per product (executable, library, plugin)
   - Single-product packages indexed as single project

3. **Indexing Flow**:
   ```
   indexProject(path)
     ├─> detectSubprojects(path)
     │     ├─> If Package.swift: Parse products
     │     ├─> If multiple .git: Return subdirs
     │     └─> Else: Return []
     ├─> If subprojects.isEmpty: indexSingleProject(path)
     └─> Else: For each subproject: indexSingleProject(subproject.path)
   ```

4. **Auto-Migration**:
   - At server startup: `autoMigrateLegacyIndexes()`
   - Detects projects with >5,000 files
   - Clears old chunks, re-runs `indexProject()` with new logic
   - Silent operation (logs progress, non-fatal errors)

### Future Monorepo Support
**Not yet implemented** (create GitHub issues):
- npm/yarn workspaces (`package.json` with `workspaces: []`)
- Go workspaces (`go.work` file)
- Gradle multi-module (`settings.gradle`)
- Python Poetry workspaces
- Lerna monorepos

Use **git subprojects** or **Swift multi-product packages** for now.

## MCP Tools

**Search** (3):
1. `semantic_search(query, maxResults, projectFilter)` - Vector similarity search
2. `file_context(filePath, startLine, endLine)` - Extract code
3. `find_related(filePath, direction)` - Dependency navigation

**Management** (5):
4. `index_status()` - Cache stats
5. `reload_index(projectName)` - Queue background re-index
6. `clear_index(confirm)` - Clear all data
7. `list_projects()` - Show indexed projects
8. `indexing_progress(jobId)` - Check background job status

## Background Indexing (v0.5.0+)

### Problem Solved
Previously, when git hooks triggered indexing via the `reload_index` tool, the entire MCP server would block until indexing completed, making the server unresponsive to queries.

### Solution: Async Job Queue
**IndexingQueue** actor manages background indexing tasks:

**1. Non-Blocking Re-indexing**
```swift
// Before v0.5.0: Blocked for 30+ seconds
try await projectIndexer.reindexProject(projectName: project)

// v0.5.0+: Returns immediately with job ID
let jobID = await indexingQueue.enqueue(...operation...)
// Indexing happens in background
```

**2. Priority-Based Scheduling**
- `low` - Hook-triggered background indexing
- `normal` - User-initiated re-indexing via MCP tool
- `high` - Emergency re-index after migration failures

**3. Checking Progress**
```bash
# Check specific job
indexing_progress(jobId: "550e8400-e29b-41d4-a716-446655440000")

# Check all jobs
indexing_progress()  # Shows queued, active, completed
```

**4. Resource Limits**
- Default: 1 concurrent job (prevents lock contention on index files)
- Server continues accepting search queries while indexing in background
- Max 100 completed jobs kept in history for debugging

### How It Works
1. Tool handler receives `reload_index` call
2. Enqueues operation to `IndexingQueue` with priority
3. Returns immediately with job ID and progress tracking info
4. Background task processes job when slots available
5. User checks progress with `indexing_progress` tool
6. On completion: logs file/chunk counts, processes next queued job

## CLI Commands

### Daemon Mode (MCP Server)

```bash
# Run MCP server (long-running, stdio protocol)
code-search-mcp

# Run MCP server with auto-indexing on startup
code-search-mcp --project-paths ~/project1 --project-paths ~/project2
```

### One-Shot Indexing Mode (v0.5.1+)

Index projects and exit cleanly without starting the MCP server. Useful for:
- Manual indexing from command line
- CI/CD pipelines
- Batch indexing scripts
- Testing indexing performance

```bash
# Index current directory
code-search-mcp index .

# Index multiple projects
code-search-mcp index ~/project1 ~/project2

# Debug mode
code-search-mcp index ~/myproject --log-level debug

# Custom cache location
code-search-mcp index ~/myproject --index-path ~/.custom-cache
```

**Key Features**:
- Returns immediately with job IDs
- Polls IndexingQueue until all jobs complete
- Shows progress (active/pending/completed)
- Prints summary with file/chunk counts
- Exits with proper status code (0=success, 1=failure)
- Never starts stdio MCP server (pure CLI mode)

### Auto-Indexing Setup

```bash
# Setup git hooks and direnv
code-search-mcp setup-hooks --install-hooks
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

**Parent directory indexed as single project**: Fixed automatically in v0.5.0+ with subproject detection. Legacy indexes (>5k files) are migrated silently at startup.

**Search results mixing projects**: If you indexed `~/Developer` before v0.5.0, the auto-migration will fix this automatically on next server start. Check logs for "Migrating legacy index" messages.

**Swift package shows as single project**: If your Package.swift has multiple products, they'll be indexed separately. Single-product packages remain as one project (intentional).

**Duplicate results**: Fixed in v0.3.2 with deduplication logic

**Project not indexed**: Use `CODE_SEARCH_PROJECTS` env var or `--project-paths` CLI arg

**Stale results**: Run `reload_index` tool or setup auto-indexing with `setup-hooks`. In v0.5.0+, returns immediately - check progress with `indexing_progress` tool

**Indexing hangs the server**: Fixed in v0.5.0+ with background job queue. `reload_index` now returns immediately with job ID. Server continues accepting queries during indexing.

**How to check indexing progress**: Use `indexing_progress()` to see queued/active/completed jobs. Get specific job status with `indexing_progress(jobId: "...")`. Returns formatted status including timestamps and error messages.

**PATH not configured**: install.sh auto-configures PATH (v0.4.1+), or manually add `export PATH="$HOME/.swiftpm/bin:$PATH"` to shell config

**Git hooks not triggering**: Use `code-search-mcp setup-hooks --install-hooks` which generates hooks with full paths (works in SSH/non-interactive shells)

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
