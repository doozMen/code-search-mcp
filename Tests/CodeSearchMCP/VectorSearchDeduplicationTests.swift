import Foundation
import Testing
@testable import CodeSearchMCP

/// Tests for duplicate result deduplication in semantic search.
///
/// Issue #19: semantic_search returns duplicate results when overlapping chunks
/// match the same file/line. This test suite ensures proper deduplication.
@Suite("VectorSearchService Deduplication")
struct VectorSearchDeduplicationTests {
  
  /// Test that semantic search deduplicates results by (filePath, startLine).
  ///
  /// When multiple chunks overlap the same code location, only the highest-scoring
  /// result should be returned.
  @Test("semantic_search deduplicates results by file and line")
  func testNoDuplicateResults() async throws {
    // Setup: Create temporary test index
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "vector-search-dedup-test-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(
      at: tempDir, 
      withIntermediateDirectories: true
    )
    
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    let indexPath = tempDir.path

    // Create embedding service with mock provider
    let mockProvider = MockEmbeddingProvider()
    let embeddingService = try await EmbeddingService(
      indexPath: indexPath,
      provider: mockProvider
    )

    // Create search service
    let searchService = VectorSearchService(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    
    // Create overlapping chunks from the same file/line
    let chunks = [
      // Chunk 1: Lines 10-60, high score (0.95)
      CodeChunk(
        id: "chunk-1",
        projectName: "TestProject",
        filePath: "TestFile.swift",
        language: "swift",
        startLine: 10,
        endLine: 60,
        content: "func calculateSum() { return 1 + 2 }",
        chunkType: "function",
        embedding: [0.9, 0.8, 0.7],  // Will score ~0.95 similarity
        description: nil
      ),

      // Chunk 2: Lines 10-60 (same as chunk 1), lower score (0.85)
      CodeChunk(
        id: "chunk-2",
        projectName: "TestProject",
        filePath: "TestFile.swift",
        language: "swift",
        startLine: 10,
        endLine: 60,
        content: "func calculateSum() { return 1 + 2 }",
        chunkType: "function",
        embedding: [0.8, 0.7, 0.6],  // Will score ~0.85 similarity
        description: nil
      ),

      // Chunk 3: Lines 100-150, different location (0.80)
      CodeChunk(
        id: "chunk-3",
        projectName: "TestProject",
        filePath: "TestFile.swift",
        language: "swift",
        startLine: 100,
        endLine: 150,
        content: "func calculateProduct() { return 3 * 4 }",
        chunkType: "function",
        embedding: [0.7, 0.6, 0.5],  // Will score ~0.80 similarity
        description: nil
      )
    ]
    
    // Save chunks to disk (needed for disk-based search path)
    let chunksDir = tempDir.appendingPathComponent("chunks/TestProject")
    try FileManager.default.createDirectory(
      at: chunksDir,
      withIntermediateDirectories: true
    )
    
    for chunk in chunks {
      let chunkFile = chunksDir.appendingPathComponent("\(chunk.id).json")
      let data = try JSONEncoder().encode(chunk)
      try data.write(to: chunkFile)
    }
    
    // Execute: Search with a query
    let results = try await searchService.search(
      query: "calculate sum",
      maxResults: 10,
      projectFilter: "TestProject"
    )
    
    // Verify: All results should be unique by (filePath, lineNumber)
    var seenLocations = Set<String>()
    var hasDuplicates = false
    
    for result in results {
      let locationKey = "\(result.filePath):\(result.lineNumber)"
      if seenLocations.contains(locationKey) {
        hasDuplicates = true
        break
      }
      seenLocations.insert(locationKey)
    }
    
    // Assert: No duplicates found
    #expect(
      !hasDuplicates,
      "Found duplicate results with same file and line number"
    )
    
    // Assert: Should return at most 2 unique results (line 10 and line 100)
    #expect(
      results.count <= 2,
      "Expected at most 2 unique results, got \(results.count)"
    )
    
    // Assert: If we have a result for line 10, it should be the highest scoring one
    if let line10Result = results.first(where: { $0.lineNumber == 10 }) {
      // Should be from chunk-1 (highest score)
      #expect(
        line10Result.relevanceScore >= 0.94,
        "Expected highest scoring chunk for line 10, got \(line10Result.relevanceScore)"
      )
    }
  }
  
  /// Test that maxResults respects deduplication.
  ///
  /// When maxResults=1 and multiple chunks point to same location,
  /// should return exactly 1 result (the highest scoring one).
  @Test("maxResults returns correct count after deduplication")
  func testMaxResultsAfterDeduplication() async throws {
    // Setup: Create temporary test index
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "vector-search-maxresults-test-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(
      at: tempDir,
      withIntermediateDirectories: true
    )
    
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    let indexPath = tempDir.path

    let mockProvider = MockEmbeddingProvider()
    let embeddingService = try await EmbeddingService(
      indexPath: indexPath,
      provider: mockProvider
    )

    let searchService = VectorSearchService(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    
    // Create 3 chunks, all pointing to same location
    let chunks = [
      CodeChunk(
        id: "chunk-1",
        projectName: "TestProject",
        filePath: "File.swift",
        language: "swift",
        startLine: 50,
        endLine: 100,
        content: "code",
        chunkType: "block",
        embedding: [0.9, 0.8, 0.7],
        description: nil
      ),
      CodeChunk(
        id: "chunk-2",
        projectName: "TestProject",
        filePath: "File.swift",
        language: "swift",
        startLine: 50,
        endLine: 100,
        content: "code",
        chunkType: "block",
        embedding: [0.8, 0.7, 0.6],
        description: nil
      ),
      CodeChunk(
        id: "chunk-3",
        projectName: "TestProject",
        filePath: "File.swift",
        language: "swift",
        startLine: 50,
        endLine: 100,
        content: "code",
        chunkType: "block",
        embedding: [0.7, 0.6, 0.5],
        description: nil
      )
    ]
    
    // Save chunks
    let chunksDir = tempDir.appendingPathComponent("chunks/TestProject")
    try FileManager.default.createDirectory(
      at: chunksDir,
      withIntermediateDirectories: true
    )
    
    for chunk in chunks {
      let chunkFile = chunksDir.appendingPathComponent("\(chunk.id).json")
      let data = try JSONEncoder().encode(chunk)
      try data.write(to: chunkFile)
    }
    
    // Execute: Request maxResults=1
    let results = try await searchService.search(
      query: "test",
      maxResults: 1,
      projectFilter: "TestProject"
    )
    
    // Verify: Should return exactly 1 unique result
    #expect(
      results.count == 1,
      "Expected exactly 1 result after deduplication, got \(results.count)"
    )
  }
}

// MARK: - Mock Embedding Provider

/// Mock embedding provider for testing that returns consistent embeddings.
struct MockEmbeddingProvider: EmbeddingProvider {
  var dimensions: Int { 3 }

  func generateEmbedding(for text: String) async throws -> [Float] {
    // Return a fixed query embedding that will match our test chunks
    return [1.0, 0.9, 0.8]
  }

  func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
    return texts.map { _ in [1.0, 0.9, 0.8] }
  }
}
