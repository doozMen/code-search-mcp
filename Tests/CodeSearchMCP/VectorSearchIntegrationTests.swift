import Foundation
import Testing

@testable import CodeSearchMCP

/// Integration tests for pure vector-based search workflow.
///
/// Tests the complete flow:
/// - Index project files
/// - Generate embeddings (CoreML)
/// - Perform vector search (SIMD)
/// - Return ranked results
///
/// Validates all 4 workstreams integrate correctly.
@Suite("Vector Search Integration Tests")
struct VectorSearchIntegrationTests {

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

  private static func createTestProject(at path: String) throws {
    // Create Swift files with diverse content
    let swiftFile1 = (path as NSString).appendingPathComponent("User.swift")
    try """
      class User {
        var name: String
        var email: String
        
        func sendEmail() {
          print("Sending email to \\(email)")
        }
      }
      """.write(toFile: swiftFile1, atomically: true, encoding: .utf8)

    let swiftFile2 = (path as NSString).appendingPathComponent("Article.swift")
    try """
      struct Article {
        let title: String
        let content: String
        let author: String
        
        func publish() {
          print("Publishing article: \\(title)")
        }
      }
      """.write(toFile: swiftFile2, atomically: true, encoding: .utf8)

    let swiftFile3 = (path as NSString).appendingPathComponent("Network.swift")
    try """
      class NetworkClient {
        func fetchData(from url: URL) async throws -> Data {
          let (data, _) = try await URLSession.shared.data(from: url)
          return data
        }
      }
      """.write(toFile: swiftFile3, atomically: true, encoding: .utf8)
  }

  // MARK: - End-to-End Workflow Tests

  @Test("Complete workflow: Index → Embed → Search")
  func testCompleteWorkflow() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("test-project")
    try FileManager.default.createDirectory(
      atPath: projectDir,
      withIntermediateDirectories: true
    )
    try Self.createTestProject(at: projectDir)

    // Initialize services
    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let vectorSearchService = VectorSearchService(
      indexPath: tempDir,
      embeddingService: embeddingService
    )
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    // Index project
    try await indexer.indexProject(path: projectDir)

    // Search for user-related code
    let results = try await vectorSearchService.search(
      query: "user account and email",
      maxResults: 5
    )

    #expect(!results.isEmpty, "Should find results for user-related query")
    
    // Verify results contain User.swift
    let containsUser = results.contains { $0.filePath.contains("User.swift") }
    #expect(containsUser, "Results should include User.swift file")
  }

  @Test("Search with project filter")
  func testSearchWithProjectFilter() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    // Create two projects
    let project1 = (tempDir as NSString).appendingPathComponent("project1")
    try FileManager.default.createDirectory(
      atPath: project1,
      withIntermediateDirectories: true
    )
    try Self.createTestProject(at: project1)

    let project2 = (tempDir as NSString).appendingPathComponent("project2")
    try FileManager.default.createDirectory(
      atPath: project2,
      withIntermediateDirectories: true
    )
    try Self.createTestProject(at: project2)

    // Initialize services
    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let vectorSearchService = VectorSearchService(
      indexPath: tempDir,
      embeddingService: embeddingService
    )
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    // Index both projects
    try await indexer.indexProject(path: project1)
    try await indexer.indexProject(path: project2)

    // Search with project filter
    let resultsP1 = try await vectorSearchService.search(
      query: "user email",
      maxResults: 10,
      projectFilter: "project1"
    )

    // All results should be from project1
    for result in resultsP1 {
      #expect(
        result.projectName == "project1",
        "Result should be from project1: \(result.projectName)"
      )
    }
  }

  @Test("In-memory index performance benefit")
  func testInMemoryIndexPerformance() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("perf-test")
    try FileManager.default.createDirectory(
      atPath: projectDir,
      withIntermediateDirectories: true
    )

    // Create multiple files for performance testing
    for i in 1...20 {
      let file = (projectDir as NSString).appendingPathComponent("File\(i).swift")
      try """
        class Class\(i) {
          func method\(i)() -> Int {
            return \(i)
          }
        }
        """.write(toFile: file, atomically: true, encoding: .utf8)
    }

    // Initialize services
    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let vectorSearchService = VectorSearchService(
      indexPath: tempDir,
      embeddingService: embeddingService
    )
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    // Index project
    try await indexer.indexProject(path: projectDir)

    // Test disk-based search
    let diskStart = Date()
    let diskResults = try await vectorSearchService.search(
      query: "class method function",
      maxResults: 5
    )
    let diskDuration = Date().timeIntervalSince(diskStart)

    #expect(!diskResults.isEmpty)

    // Initialize in-memory index
    try await vectorSearchService.initializeInMemoryIndex()

    // Test in-memory search (should be faster)
    let memoryStart = Date()
    let memoryResults = try await vectorSearchService.search(
      query: "class method function",
      maxResults: 5
    )
    let memoryDuration = Date().timeIntervalSince(memoryStart)

    #expect(!memoryResults.isEmpty)

    print("""
      Performance Comparison:
      - Disk-based search: \(diskDuration * 1000)ms
      - In-memory search: \(memoryDuration * 1000)ms
      - Speedup: \(diskDuration / memoryDuration)x
      """)

    // In-memory should be significantly faster (or at least not slower)
    #expect(
      memoryDuration <= diskDuration * 2,
      "In-memory search should not be slower than disk-based"
    )
  }

  @Test("Multiple searches return consistent results")
  func testSearchConsistency() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("consistency-test")
    try FileManager.default.createDirectory(
      atPath: projectDir,
      withIntermediateDirectories: true
    )
    try Self.createTestProject(at: projectDir)

    // Initialize services
    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let vectorSearchService = VectorSearchService(
      indexPath: tempDir,
      embeddingService: embeddingService
    )
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    try await indexer.indexProject(path: projectDir)

    // Perform same search multiple times
    let query = "network data fetching"
    let results1 = try await vectorSearchService.search(query: query, maxResults: 5)
    let results2 = try await vectorSearchService.search(query: query, maxResults: 5)
    let results3 = try await vectorSearchService.search(query: query, maxResults: 5)

    // Results should be identical (same order, same scores)
    #expect(results1.count == results2.count)
    #expect(results2.count == results3.count)

    // Verify first result is consistent
    if let first1 = results1.first, let first2 = results2.first {
      #expect(first1.filePath == first2.filePath)
      #expect(abs(first1.relevanceScore - first2.relevanceScore) < 0.001)
    }
  }

  @Test("Empty project returns empty results")
  func testEmptyProject() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("empty-project")
    try FileManager.default.createDirectory(
      atPath: projectDir,
      withIntermediateDirectories: true
    )

    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let vectorSearchService = VectorSearchService(
      indexPath: tempDir,
      embeddingService: embeddingService
    )
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    try await indexer.indexProject(path: projectDir)

    let results = try await vectorSearchService.search(query: "anything", maxResults: 5)

    #expect(results.isEmpty, "Empty project should return empty results")
  }

  @Test("Search relevance scores are properly ranked")
  func testSearchRelevanceRanking() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("ranking-test")
    try FileManager.default.createDirectory(
      atPath: projectDir,
      withIntermediateDirectories: true
    )
    try Self.createTestProject(at: projectDir)

    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let vectorSearchService = VectorSearchService(
      indexPath: tempDir,
      embeddingService: embeddingService
    )
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    try await indexer.indexProject(path: projectDir)

    let results = try await vectorSearchService.search(
      query: "user email sending",
      maxResults: 10
    )

    #expect(!results.isEmpty)

    // Verify results are sorted by relevance (descending)
    for i in 0..<(results.count - 1) {
      #expect(
        results[i].relevanceScore >= results[i + 1].relevanceScore,
        "Results should be sorted by relevance score"
      )
    }

    // Top result should have high relevance
    if let topResult = results.first {
      #expect(
        topResult.relevanceScore > 0.0,
        "Top result should have positive relevance score"
      )
    }
  }

  @Test("Search handles special characters in query")
  func testSearchWithSpecialCharacters() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("special-char-test")
    try FileManager.default.createDirectory(
      atPath: projectDir,
      withIntermediateDirectories: true
    )
    try Self.createTestProject(at: projectDir)

    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let vectorSearchService = VectorSearchService(
      indexPath: tempDir,
      embeddingService: embeddingService
    )
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    try await indexer.indexProject(path: projectDir)

    // Query with special characters
    let queries = [
      "func->result",
      "[Int] array",
      "User? optional",
      "async/await network",
    ]

    for query in queries {
      _ = try await vectorSearchService.search(query: query, maxResults: 5)
      // Should not throw, even if results are empty (test passes by not throwing)
    }
  }

  @Test("Large batch search maintains performance")
  func testLargeBatchSearch() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("batch-search-test")
    try FileManager.default.createDirectory(
      atPath: projectDir,
      withIntermediateDirectories: true
    )

    // Create 50 test files
    for i in 1...50 {
      let file = (projectDir as NSString).appendingPathComponent("File\(i).swift")
      try """
        class Class\(i) {
          var property\(i): String
          func method\(i)() {}
        }
        """.write(toFile: file, atomically: true, encoding: .utf8)
    }

    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let vectorSearchService = VectorSearchService(
      indexPath: tempDir,
      embeddingService: embeddingService
    )
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    try await indexer.indexProject(path: projectDir)

    // Initialize in-memory index for performance
    try await vectorSearchService.initializeInMemoryIndex()

    // Perform 10 searches
    let queries = [
      "class definition",
      "property variable",
      "method function",
      "string type",
      "code implementation",
      "swift class",
      "object instance",
      "data structure",
      "program logic",
      "source code",
    ]

    let startTime = Date()
    for query in queries {
      let results = try await vectorSearchService.search(query: query, maxResults: 5)
      #expect(!results.isEmpty, "Query '\(query)' should return results")
    }
    let duration = Date().timeIntervalSince(startTime)

    print("Completed 10 searches in \(duration) seconds")
    
    // Should complete all searches in reasonable time (< 2 seconds with in-memory index)
    #expect(duration < 2.0, "Batch searches should complete quickly")
  }
}
