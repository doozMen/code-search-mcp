# code-search-mcp Architecture

This document describes the architecture and design of the code-search-mcp MCP server.

## Overview

code-search-mcp is a Model Context Protocol server that provides **pure vector-based semantic code search** across multiple projects. It uses:

- **Vector Embeddings**: 300/384-dimensional embeddings (CoreML/BERT) for semantic understanding
- **Cosine Similarity**: Geometric proximity in vector space for ranking
- **Dependency Tracking**: Import/dependency relationship mapping
- **Multi-Project Support**: Index and search across multiple codebases with automatic project selection via direnv
- **Mac Studio Optimized**: SIMD acceleration (Accelerate framework) and in-memory indexing for 128GB RAM systems

**Architectural Decision**: This tool focuses exclusively on vector-based semantic search. Traditional keyword/symbol search has been intentionally removed to simplify the architecture and provide superior semantic understanding. See `deprecated/README.md` for migration details.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Claude Desktop                           │
│                   (JSON-RPC Client)                         │
└──────────────────────────┬──────────────────────────────────┘
                           │ stdio (JSON-RPC 2.0)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   MCPServer (Actor)                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ • Tool Registration (ListTools)                      │  │
│  │ • Tool Call Dispatch (CallTool)                      │  │
│  │ • Result Formatting                                 │  │
│  └──────────────────────────────────────────────────────┘  │
└────────┬───────────────┬──────────────┬──────────────┬──────┘
         │               │              │              │
         ▼               ▼              ▼              ▼
    ┌────────────┐  ┌──────────────┐  ┌────────────┐  ┌──────────┐
    │ProjectIndex│  │ Embedding    │  │ Vector     │  │ Keyword  │
    │ (Actor)    │  │ Service      │  │ Search     │  │ Search   │
    │            │  │ (Actor)      │  │ (Actor)    │  │ (Actor)  │
    │ • Crawl    │  │              │  │            │  │          │
    │ • Extract  │  │ • Generate   │  │ • Cosine   │  │ • Index  │
    │ • Parse    │  │ • Cache      │  │ • Rank     │  │ • Lookup │
    └────────────┘  └──────────────┘  └────────────┘  └──────────┘
         │                                  │               │
         └──────────────┬────────────────────┴───────────────┘
                        │
         ┌──────────────┴──────────────────┐
         ▼                                 ▼
    ┌─────────────────────────┐   ┌──────────────────────┐
    │  CodeMetadataExtractor  │   │  File Storage        │
    │  (Actor)                │   │   ~/.cache/code-     │
    │                         │   │  search-mcp/        │
    │  • Build dependency     │   │                      │
    │    graph                │   │  ├── embeddings/     │
    │  • Find related files   │   │  ├── symbols/        │
    │  • Track imports        │   │  └── dependencies/   │
    └─────────────────────────┘   └──────────────────────┘
```

## Actor Architecture

All services are implemented as Swift 6 actors for strict concurrency:

```
MCPServer
├── ProjectIndexer       # File crawling and code chunking
├── EmbeddingService     # CoreML/BERT embedding generation with provider pattern
├── VectorSearchService  # SIMD-accelerated cosine similarity search
├── InMemoryVectorIndex  # 128GB RAM-optimized vector index
└── CodeMetadataExtractor # Dependency graph construction

All types crossing actor boundaries implement Sendable
```

### Actor Isolation

Each service is responsible for:

1. **ProjectIndexer**
   - File system access and directory traversal
   - Code chunk extraction and parsing
   - Language-specific parsing logic

2. **EmbeddingService**
   - BERT model management
   - Embedding generation
   - Cache management

3. **VectorSearchService**
   - Vector similarity computation
   - Result ranking by relevance
   - Index querying

4. **InMemoryVectorIndex**
   - Pre-loads embeddings into RAM (leverages 128GB)
   - SIMD-accelerated similarity computation (194x speedup)
   - Parallel search with TaskGroup
   - LRU eviction (100GB memory limit)

5. **CodeMetadataExtractor**
   - Dependency graph construction
   - Import statement parsing
   - File relationship tracking

## Data Flow

### Indexing Flow

```
Project Directory
        │
        ▼
ProjectIndexer.indexProject(_)
        │
        ├─ Find all source files
        │
        ├─ For each file:
        │  ├─ Extract code chunks
        │  │  (functions, classes, blocks)
        │  │
        │  ├─ Extract symbols
        │  │  (for keyword search)
        │  │
        │  └─ Extract dependencies
        │     (for relationship tracking)
        │
        ▼
Create CodeChunk objects
        │
        ├─ Generate embeddings (EmbeddingService)
        │
        ├─ Build symbol index (KeywordSearchService)
        │
        ├─ Build dependency graph (CodeMetadataExtractor)
        │
        ▼
Store to ~/.cache/code-search-mcp/
```

### Semantic Search Flow

```
User Query
        │
        ▼
semantic_search tool called
        │
        ├─ Generate embedding for query
        │  (EmbeddingService)
        │
        ├─ Load indexed code chunks
        │
        ├─ Compute cosine similarity
        │  scores (VectorSearchService)
        │
        ├─ Rank by relevance
        │
        ▼
Return SearchResult objects
```

### Keyword Search Flow

```
User Query
        │
        ▼
keyword_search tool called
        │
        ├─ Look up symbol in index
        │  (KeywordSearchService)
        │
        ├─ Find all definitions
        │
        ├─ If includeReferences=true:
        │  Find all references
        │
        ▼
Return SearchResult objects
```

## Models

### CodeChunk

```swift
struct CodeChunk {
    let id: String              // Unique identifier
    let projectName: String     // Project name
    let filePath: String        // File path in project
    let language: String        // Programming language
    let startLine: Int         // Start line (1-indexed)
    let endLine: Int           // End line (1-indexed)
    let content: String        // Source code
    let chunkType: String      // "function", "class", etc.
    let embedding: [Float]?    // 384-d BERT embedding
}
```

### SearchResult

```swift
struct SearchResult {
    let id: String
    let projectName: String
    let filePath: String
    let language: String
    let lineNumber: Int
    let endLineNumber: Int
    let context: String
    let resultType: String     // "semantic", "definition", "reference"
    let relevanceScore: Double // 0.0 - 1.0
    let matchReason: String
}
```

### ProjectMetadata

```swift
struct ProjectMetadata {
    let id: String
    let name: String
    let rootPath: String
    let fileCount: Int
    let chunkCount: Int
    let lineCount: Int
    let languages: [String: Int]
    let statistics: ProjectStatistics
    let indexStatus: IndexStatus
}
```

## MCP Tools

### 1. semantic_search

**Purpose**: Find code with similar semantic meaning

```
Input:
  - query (string): Natural language query or code snippet
  - maxResults (int, optional): Max results (default: 10)
  - projectFilter (string, optional): Project name filter

Output:
  - SearchResult array sorted by relevance score
  - Each result includes code context and line numbers
```

**Implementation**:
- Generate embedding for query text
- Compute cosine similarity with all indexed embeddings
- Rank results by similarity score
- Return top N results

### 2. keyword_search

**Purpose**: Find symbol definitions and references

```
Input:
  - symbol (string): Symbol name to find
  - includeReferences (bool, optional): Include all references
  - projectFilter (string, optional): Project name filter

Output:
  - SearchResult array with definitions first, then references
  - Organized by file and line number
```

**Implementation**:
- Look up symbol in index
- Find all definitions (definition=true)
- If includeReferences, find all references
- Sort by file and line number

### 3. file_context

**Purpose**: Extract code from a file with context

```
Input:
  - filePath (string): File path in project
  - startLine (int, optional): Start line
  - endLine (int, optional): End line
  - contextLines (int, optional): Context lines around range

Output:
  - Single SearchResult with requested code and context
```

**Implementation**:
- Read file content
- Extract requested line range
- Add context lines before/after
- Return as SearchResult

### 4. find_related

**Purpose**: Find related files through imports/dependencies

```
Input:
  - filePath (string): File path
  - direction (string, optional): "imports" | "imports_from" | "both"

Output:
  - Array of related file paths
```

**Implementation**:
- Load dependency graph
- If direction="imports": files that import this file
- If direction="imports_from": files this file imports
- If direction="both": union of both directions

### 5. index_status

**Purpose**: Get index metadata and statistics

```
Input: None

Output:
  - Text status report with:
    - Indexed projects and counts
    - Total chunks and files
    - Languages found
    - Index path and size
    - Status: "Initializing" | "Ready" | "Indexing"
```

## Storage

### Cache Directory Structure

```
~/.cache/code-search-mcp/
├── embeddings/                      # Global shared cache (deduplication)
│   ├── a3f2b8...embedding          # Hash-based filenames
│   ├── d9e4c1...embedding          # JSON array of Float (300 or 384 dims)
│   └── ...
├── chunks/                          # Project-specific chunk metadata
│   ├── MyApp/
│   │   ├── chunk-uuid1.json        # CodeChunk with projectName, filePath, embedding
│   │   ├── chunk-uuid2.json
│   │   └── ...
│   ├── MyLib/
│   │   └── ...
│   └── ...
├── dependencies/                    # Dependency graphs per project
│   ├── MyApp.graph.json
│   └── MyLib.graph.json
└── project_registry.json            # Project metadata and timestamps
```
    ├── project2.graph.json
    └── ...
```

### Index Formats

#### Embeddings (JSON)
```json
[0.123, 0.456, ..., -0.789]  // 384 floating-point values
```

#### Symbols (JSON)
```json
{
  "symbols": {
    "functionName": [
      {"file": "path/to/file.swift", "line": 42, "isDefinition": true},
      {"file": "path/to/other.swift", "line": 100, "isDefinition": false}
    ]
  }
}
```

#### Dependencies (JSON)
```json
{
  "projectName": "MyProject",
  "importsMap": {
    "src/main.swift": ["src/utils.swift", "src/models.swift"],
    "src/utils.swift": ["Foundation"]
  },
  "importedByMap": {
    "src/utils.swift": ["src/main.swift"],
    "Foundation": ["src/main.swift", "src/utils.swift"]
  }
}
```

## Language Support

Supported languages and their chunk types:

- **Swift**: Function, Struct, Class, Enum, Protocol, Extension
- **Python**: Function, Class, Method
- **JavaScript/TypeScript**: Function, Class, Arrow Function
- **Java**: Class, Method, Interface
- **Go**: Function, Struct, Interface
- **Rust**: Function, Struct, Impl Block
- **C/C++**: Function, Struct, Class
- **C#**: Class, Method, Property
- **Ruby**: Method, Class
- **PHP**: Function, Class, Method
- **Kotlin**: Function, Class, Object

## Performance Characteristics

### Time Complexity

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| Index project | O(n·m) | n files, m avg lines per file |
| Generate embedding | O(1) | Cached after first generation |
| Semantic search | O(k·d) | k chunks, d=384 dimensions |
| Keyword search | O(1) | Hash table lookup |
| Find related files | O(e) | e edges in dependency graph |

### Space Complexity

| Component | Space | Notes |
|-----------|-------|-------|
| Code chunks | O(n) | n = total lines of code |
| Embeddings | O(n·384·4B) | ~1.5MB per 1000 lines |
| Symbol index | O(s) | s = number of unique symbols |
| Dependency graph | O(e) | e = number of import relationships |

## Error Handling

### Service-Level Errors

Each service defines domain-specific errors:

```swift
enum IndexingError: Error {
    case invalidProjectPath(String)
    case directoryEnumerationFailed(String)
    case fileReadingFailed(String, Error)
}

enum EmbeddingError: Error {
    case generationFailed(String)
    case cachingFailed(Error)
    case modelInitializationFailed
}
```

### MCP-Level Errors

Converted to MCP.Error for protocol response:

```swift
throw MCP.Error.invalidRequest("Unknown tool")
throw MCP.Error.invalidParams("Missing required parameter")
throw MCP.Error.internalError("Service failed")
```

## Future Enhancements

### Phase 2: Optimization
- Batch embedding generation
- Incremental indexing
- Index compression
- Parallel file processing

### Phase 3: Advanced Features
- Custom embedding models
- Multi-language relationships
- Search result ranking customization
- Project-level access control

### Phase 4: Integration
- Database backend (SQLite/PostgreSQL)
- REST API interface
- Web UI for index management
- Metrics and monitoring

## Testing Strategy

### Unit Tests
- Service initialization
- Model serialization/deserialization
- Error handling paths

### Integration Tests
- End-to-end search workflows
- Multi-project indexing
- Index persistence and loading

### Performance Tests
- Large project indexing
- Batch search operations
- Memory usage and cache efficiency
