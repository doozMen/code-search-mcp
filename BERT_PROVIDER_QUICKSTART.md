# BERT Embedding Provider - Quick Start Guide

## Installation

### 1. Install Python Dependencies

```bash
cd /Users/stijnwillems/Developer/promptping-marketplace/code-search-mcp
./Scripts/install_python_deps.sh
```

This installs `sentence-transformers` (~2GB download, includes PyTorch and models).

### 2. Test Python Server

```bash
# Start server manually
python3 Scripts/bert_embedding_server.py

# In another terminal, test it
curl http://127.0.0.1:8765/health

# Should return:
# {"status": "healthy", "model": "all-MiniLM-L6-v2", "dimension": 384}

# Test embedding generation
curl -X POST http://127.0.0.1:8765/embed \
  -H "Content-Type: application/json" \
  -d '{"texts": ["hello world"]}'
```

## Usage in Swift

### Option 1: Automatic (Recommended)

```swift
import CodeSearchMCP

// Provider auto-starts server on first use
let provider = BERTEmbeddingProvider()

// Generate single embedding
let embedding = try await provider.generateEmbedding(
    for: "func calculateSum(a: Int, b: Int) -> Int"
)
print("Dimensions: \(embedding.count)")  // 384

// Batch processing (more efficient)
let code = [
    "func add(a: Int, b: Int) -> Int",
    "class User { var name: String }",
    "struct Point { let x, y: Double }",
]
let embeddings = try await provider.generateEmbeddings(for: code)
print("Generated \(embeddings.count) embeddings")
```

### Option 2: Manual Server Management

```bash
# Terminal 1: Start server
python3 Scripts/bert_embedding_server.py 8765

# Terminal 2: Use Swift code
swift run code-search-mcp --provider bert
```

## Integration with EmbeddingService

```swift
// Use BERT instead of CoreML
let bertProvider = BERTEmbeddingProvider()
let service = try await EmbeddingService(
    indexPath: "~/.cache/code-search-mcp",
    provider: bertProvider
)

// Now all embeddings use BERT
let embedding = try await service.generateEmbedding(for: "some code")
```

## Performance Tips

1. **Batch Processing**: Always use `generateEmbeddings(for:)` for multiple texts
   ```swift
   // ❌ Slow - multiple HTTP requests
   for text in texts {
       let emb = try await provider.generateEmbedding(for: text)
   }
   
   // ✅ Fast - single HTTP request
   let embs = try await provider.generateEmbeddings(for: texts)
   ```

2. **Keep Server Running**: Don't initialize multiple providers
   ```swift
   // ❌ Starts multiple servers
   func processText(_ text: String) async throws {
       let provider = BERTEmbeddingProvider()  // New server each time!
       return try await provider.generateEmbedding(for: text)
   }
   
   // ✅ Reuse single provider/server
   let provider = BERTEmbeddingProvider()
   func processText(_ text: String) async throws {
       return try await provider.generateEmbedding(for: text)
   }
   ```

3. **Cold Start Optimization**: Warm up the server
   ```swift
   let provider = BERTEmbeddingProvider()
   
   // Warm up (loads model)
   _ = try await provider.generateEmbedding(for: "warmup")
   
   // Now fast for subsequent calls
   let embeddings = try await provider.generateEmbeddings(for: largeDataset)
   ```

## Troubleshooting

### "Module 'sentence_transformers' not found"

```bash
pip3 install --upgrade sentence-transformers
```

### "Server script not found"

Check these locations:
- `./Scripts/bert_embedding_server.py` (development)
- `~/.swiftpm/bin/../Scripts/bert_embedding_server.py` (installed)

### "Server startup timeout"

- Check if port 8765 is already in use: `lsof -i :8765`
- Kill existing server: `pkill -f bert_embedding_server`
- Try different port: `BERTEmbeddingProvider(port: 8766)`

### "Server not healthy"

```bash
# Check server logs
python3 Scripts/bert_embedding_server.py
# Look for errors in output

# Test manually
curl http://127.0.0.1:8765/health
```

## Comparison: BERT vs CoreML

| Feature | BERT | CoreML |
|---------|------|--------|
| Dimensions | 384 | 300 |
| Model | sentence-transformers | NLEmbedding |
| Dependencies | Python, PyTorch | None (built-in) |
| Startup time | 2-5s | <100ms |
| Single embedding | 10-50ms | 5-20ms |
| Batch (100) | 500ms-2s | 200ms-800ms |
| Memory | ~500MB | ~100MB |
| Platforms | macOS, Linux, Windows | macOS only |

**When to use BERT**:
- Cross-platform development
- Need 384 dimensions
- Batch processing (comparable performance)
- Testing with Python models

**When to use CoreML**:
- Production macOS app
- Real-time embedding generation
- Lower memory footprint
- No Python dependencies

## Environment Variables

Control BERT provider behavior:

```bash
# Custom port
export BERT_SERVER_PORT=9999

# Disable auto-start (use manual server)
export BERT_AUTO_START=false

# Custom model (future)
export BERT_MODEL="sentence-transformers/all-mpnet-base-v2"
```

## Next Steps

- [ ] Run tests: `swift test --filter BERTEmbeddingProviderTests`
- [ ] Benchmark: Compare CoreML vs BERT on your use case
- [ ] Integrate: Wire up provider selection in main app
- [ ] Document: Add provider choice to user-facing docs
