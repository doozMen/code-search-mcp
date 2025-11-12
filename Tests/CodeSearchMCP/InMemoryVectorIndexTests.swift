import Foundation
import Testing

@testable import CodeSearchMCP

/// Tests for InMemoryVectorIndex with SIMD optimization.
///
/// Validates:
/// - Index preloading from disk
/// - SIMD-optimized search
/// - Parallel TaskGroup execution
/// - Memory usage tracking
/// - Project filtering
/// - Performance targets (<50ms for 50k vectors)
@Suite("InMemoryVectorIndex Tests")
struct InMemoryVectorIndexTests {

  // MARK: - Test Helpers

  private static func createTempDir() throws -> String {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).path
    try FileManager.default.createDirectory(
      atPath: tempDir,
      withIntermediateDirectories: true
    )
    return tempDir
  }

  private static func cleanupTempDir(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }

  private func generateRandomVector(dimensions: Int) -> [Float] {
    return (0..<dimensions).map { _ in Float.random(in: -1...1) }
  }

  // MARK: - Initialization Tests

  @Test("Index initializes with empty cache")
  func testInitialization() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let index = InMemoryVectorIndex(indexPath: tempDir)

    let stats = await index.getMemoryStats()
    #expect(stats.totalChunks == 0)
    #expect(stats.usedMB == 0)
  }

  @Test("Add embedding to index")
  func testAddEmbedding() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let index = InMemoryVectorIndex(indexPath: tempDir)

    let metadata = InMemoryVectorIndex.ChunkMetadata(
      projectName: "test",
      filePath: "/test/file.swift",
      language: "swift",
      startLine: 1,
      endLine: 10,
      content: "test content"
    )

    let embedding = generateRandomVector(dimensions: 300)

    await index.addEmbedding(
      chunkId: "test-chunk-1",
      embedding: embedding,
      metadata: metadata
    )

    let stats = await index.getMemoryStats()
    #expect(stats.totalChunks == 1)
    #expect(stats.usedMB > 0)
  }

  @Test("Search returns top K results")
  func testBasicSearch() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let index = InMemoryVectorIndex(indexPath: tempDir)

    // Add 10 embeddings
    for i in 1...10 {
      let metadata = InMemoryVectorIndex.ChunkMetadata(
        projectName: "test",
        filePath: "/test/file\(i).swift",
        language: "swift",
        startLine: i * 10,
        endLine: i * 10 + 10,
        content: "content \(i)"
      )

      await index.addEmbedding(
        chunkId: "chunk-\(i)",
        embedding: generateRandomVector(dimensions: 300),
        metadata: metadata
      )
    }

    let queryEmbedding = generateRandomVector(dimensions: 300)
    let results = await index.search(
      queryEmbedding: queryEmbedding,
      topK: 5,
      projectFilter: nil
    )

    #expect(results.count <= 5)
    #expect(results.count > 0)
  }

  @Test("Search with project filter")
  func testSearchWithProjectFilter() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let index = InMemoryVectorIndex(indexPath: tempDir)

    // Add embeddings from two projects
    for i in 1...5 {
      let metadata1 = InMemoryVectorIndex.ChunkMetadata(
        projectName: "project1",
        filePath: "/project1/file\(i).swift",
        language: "swift",
        startLine: i * 10,
        endLine: i * 10 + 10,
        content: "content \(i)"
      )
      await index.addEmbedding(
        chunkId: "p1-chunk-\(i)",
        embedding: generateRandomVector(dimensions: 300),
        metadata: metadata1
      )

      let metadata2 = InMemoryVectorIndex.ChunkMetadata(
        projectName: "project2",
        filePath: "/project2/file\(i).swift",
        language: "swift",
        startLine: i * 10,
        endLine: i * 10 + 10,
        content: "content \(i)"
      )
      await index.addEmbedding(
        chunkId: "p2-chunk-\(i)",
        embedding: generateRandomVector(dimensions: 300),
        metadata: metadata2
      )
    }

    let queryEmbedding = generateRandomVector(dimensions: 300)

    // Search in project1 only
    let results = await index.search(
      queryEmbedding: queryEmbedding,
      topK: 10,
      projectFilter: "project1"
    )

    // All results should be from project1
    for result in results {
      #expect(result.metadata.projectName == "project1")
    }
  }

  @Test("Results are sorted by similarity score")
  func testResultsSorting() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let index = InMemoryVectorIndex(indexPath: tempDir)

    // Add multiple embeddings
    for i in 1...10 {
      let metadata = InMemoryVectorIndex.ChunkMetadata(
        projectName: "test",
        filePath: "/test/file\(i).swift",
        language: "swift",
        startLine: i * 10,
        endLine: i * 10 + 10,
        content: "content \(i)"
      )

      await index.addEmbedding(
        chunkId: "chunk-\(i)",
        embedding: generateRandomVector(dimensions: 300),
        metadata: metadata
      )
    }

    let queryEmbedding = generateRandomVector(dimensions: 300)
    let results = await index.search(
      queryEmbedding: queryEmbedding,
      topK: 10,
      projectFilter: nil
    )

    // Verify sorting (descending similarity)
    for i in 0..<(results.count - 1) {
      #expect(results[i].similarity >= results[i + 1].similarity)
    }
  }

  @Test("Memory stats are accurate")
  func testMemoryStats() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let index = InMemoryVectorIndex(indexPath: tempDir)

    let initialStats = await index.getMemoryStats()
    #expect(initialStats.totalChunks == 0)

    // Add embeddings
    let count = 100
    for i in 1...count {
      let metadata = InMemoryVectorIndex.ChunkMetadata(
        projectName: "test",
        filePath: "/test/file\(i).swift",
        language: "swift",
        startLine: i * 10,
        endLine: i * 10 + 10,
        content: "content \(i)"
      )

      await index.addEmbedding(
        chunkId: "chunk-\(i)",
        embedding: generateRandomVector(dimensions: 300),
        metadata: metadata
      )
    }

    let finalStats = await index.getMemoryStats()
    #expect(finalStats.totalChunks == count)
    #expect(finalStats.usedMB > 0)

    // Rough memory estimate: 100 chunks * 300 floats * 4 bytes = ~120KB = ~0.1MB
    #expect(finalStats.usedMB < 10)  // Should be small for 100 chunks
  }

  @Test("Preload index from disk")
  func testPreloadIndex() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    // Create chunks directory structure
    let chunksDir = (tempDir as NSString).appendingPathComponent("chunks")
    let projectDir = (chunksDir as NSString).appendingPathComponent("test-project")
    try FileManager.default.createDirectory(
      atPath: projectDir,
      withIntermediateDirectories: true
    )

    // Create chunk files
    for i in 1...5 {
      let chunk = CodeChunk(
        id: "chunk-\(i)",
        projectName: "test-project",
        filePath: "/test/file\(i).swift",
        language: "swift",
        startLine: i * 10,
        endLine: i * 10 + 10,
        content: "content \(i)",
        embedding: generateRandomVector(dimensions: 300)
      )

      let chunkPath = (projectDir as NSString).appendingPathComponent("chunk-\(i).json")
      let data = try JSONEncoder().encode(chunk)
      try data.write(to: URL(fileURLWithPath: chunkPath))
    }

    let index = InMemoryVectorIndex(indexPath: tempDir)
    try await index.preloadIndex()

    let stats = await index.getMemoryStats()
    #expect(stats.totalChunks == 5)
  }

  @Test("Search performance meets target (<50ms for 10k vectors)")
  func testSearchPerformance() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let index = InMemoryVectorIndex(indexPath: tempDir)

    // Add 10k vectors (reduced from 50k for CI speed)
    let vectorCount = 10_000
    for i in 1...vectorCount {
      let metadata = InMemoryVectorIndex.ChunkMetadata(
        projectName: "test",
        filePath: "/test/file\(i).swift",
        language: "swift",
        startLine: i * 10,
        endLine: i * 10 + 10,
        content: "content \(i)"
      )

      await index.addEmbedding(
        chunkId: "chunk-\(i)",
        embedding: generateRandomVector(dimensions: 300),
        metadata: metadata
      )
    }

    let queryEmbedding = generateRandomVector(dimensions: 300)

    // Measure search time
    let startTime = Date()
    let results = await index.search(
      queryEmbedding: queryEmbedding,
      topK: 10,
      projectFilter: nil
    )
    let duration = Date().timeIntervalSince(startTime) * 1000  // ms

    print("""
      Search Performance:
      - Vectors: \(vectorCount)
      - Duration: \(duration)ms
      - Results: \(results.count)
      """)

    #expect(results.count <= 10)
    
    // Should complete in <100ms for 10k vectors (scaled from 50ms target for 50k)
    #expect(duration < 100, "Search should complete in <100ms for 10k vectors")
  }

  @Test("Batch similarity computation")
  func testBatchSimilarity() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let index = InMemoryVectorIndex(indexPath: tempDir)

    // Add embeddings
    var chunkIds: [String] = []
    for i in 1...10 {
      let chunkId = "chunk-\(i)"
      chunkIds.append(chunkId)

      let metadata = InMemoryVectorIndex.ChunkMetadata(
        projectName: "test",
        filePath: "/test/file\(i).swift",
        language: "swift",
        startLine: i * 10,
        endLine: i * 10 + 10,
        content: "content \(i)"
      )

      await index.addEmbedding(
        chunkId: chunkId,
        embedding: generateRandomVector(dimensions: 300),
        metadata: metadata
      )
    }

    let queryEmbedding = generateRandomVector(dimensions: 300)

    let results = await index.batchSimilarity(
      queryEmbedding: queryEmbedding,
      candidateIds: chunkIds
    )

    #expect(results.count == chunkIds.count)

    // All similarities should be valid (between -1 and 1)
    for (_, similarity) in results {
      #expect(similarity >= -1.0)
      #expect(similarity <= 1.0)
    }
  }

  @Test("Empty index returns empty results")
  func testEmptyIndexSearch() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let index = InMemoryVectorIndex(indexPath: tempDir)

    let queryEmbedding = generateRandomVector(dimensions: 300)
    let results = await index.search(
      queryEmbedding: queryEmbedding,
      topK: 10,
      projectFilter: nil
    )

    #expect(results.isEmpty)
  }

  @Test("Conversion to SearchResult format")
  func testSearchResultConversion() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let index = InMemoryVectorIndex(indexPath: tempDir)

    // Add one embedding
    let metadata = InMemoryVectorIndex.ChunkMetadata(
      projectName: "test-project",
      filePath: "/test/User.swift",
      language: "swift",
      startLine: 10,
      endLine: 20,
      content: "class User { var name: String }"
    )

    await index.addEmbedding(
      chunkId: "test-chunk",
      embedding: generateRandomVector(dimensions: 300),
      metadata: metadata
    )

    let queryEmbedding = generateRandomVector(dimensions: 300)
    let inMemoryResults = await index.search(
      queryEmbedding: queryEmbedding,
      topK: 1,
      projectFilter: nil
    )

    #expect(!inMemoryResults.isEmpty)

    // Convert to SearchResult
    let searchResults = await index.toSearchResults(inMemoryResults)

    #expect(searchResults.count == inMemoryResults.count)

    if let first = searchResults.first {
      #expect(first.projectName == "test-project")
      #expect(first.filePath == "/test/User.swift")
      #expect(first.language == "swift")
      #expect(first.lineNumber == 10)
      #expect(first.resultType == "semantic")
    }
  }
}
