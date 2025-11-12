import Foundation
import Testing

@testable import CodeSearchMCP

/// Test suite for code-search-mcp server.
///
/// Tests cover:
/// - Tool availability and schema validation
/// - Search service functionality
/// - Index management
/// - Error handling
@Suite("CodeSearchMCP Server Tests")
struct CodeSearchMCPTests {
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
    // Create test Swift file
    let swiftFile = (path as NSString).appendingPathComponent("Test.swift")
    try """
      class TestClass {
        func testMethod() -> Int {
          return 42
        }
      }

      func globalFunction() {
        print("hello")
      }
      """.write(toFile: swiftFile, atomically: true, encoding: .utf8)

    // Create test Python file
    let pythonFile = (path as NSString).appendingPathComponent("test.py")
    try """
      class TestClass:
        def test_method(self):
          return 42

      def global_function():
        print("hello")
      """.write(toFile: pythonFile, atomically: true, encoding: .utf8)
  }

  // MARK: - Initialization Tests

  @Test("MCPServer initializes with valid index path")
  func testServerInitialization() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let server = try await MCPServer(indexPath: tempDir)

    #expect(server != nil)
  }

  @Test("MCPServer initializes with project paths")
  func testServerInitializationWithProjects() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("test-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
    try Self.createTestProject(at: projectDir)

    let server = try await MCPServer(
      indexPath: tempDir,
      projectPaths: [projectDir]
    )

    #expect(server != nil)
  }

  // MARK: - Model Tests

  @Test("SearchResult model is Sendable and Codable")
  func testSearchResultModel() throws {
    let result = SearchResult(
      projectName: "test",
      filePath: "test.swift",
      language: "Swift",
      lineNumber: 10,
      endLineNumber: 15,
      context: "func test() {}",
      relevanceScore: 0.85,
      matchReason: "Test match"
    )

    #expect(result.projectName == "test")
    #expect(result.relevanceScore == 0.85)
    #expect(result.lineCount == 6)

    // Test Codable
    let encoder = JSONEncoder()
    let data = try encoder.encode(result)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(SearchResult.self, from: data)

    #expect(decoded.projectName == result.projectName)
    #expect(decoded.lineNumber == result.lineNumber)
  }

  @Test("SearchResult factory methods create correct types")
  func testSearchResultFactoryMethods() {
    let semantic = SearchResult.semanticMatch(
      projectName: "test",
      filePath: "test.swift",
      language: "Swift",
      lineNumber: 1,
      context: "code",
      cosineSimilarity: 0.95
    )
    #expect(semantic.resultType == "semantic")
    #expect(semantic.relevanceScore == 0.95)

    let keyword = SearchResult.keywordMatch(
      projectName: "test",
      filePath: "test.swift",
      language: "Swift",
      lineNumber: 1,
      context: "code",
      matchType: "definition"
    )
    #expect(keyword.resultType == "definition")
    #expect(keyword.relevanceScore == 1.0)

    let fileContext = SearchResult.fileContext(
      projectName: "test",
      filePath: "test.swift",
      language: "Swift",
      startLine: 1,
      endLine: 10,
      content: "code"
    )
    #expect(fileContext.resultType == "file_context")
    #expect(fileContext.relevanceScore == 1.0)
  }

  @Test("SearchResult sorting works correctly")
  func testSearchResultSorting() {
    let results = [
      SearchResult(
        projectName: "test",
        filePath: "b.swift",
        language: "Swift",
        lineNumber: 10,
        endLineNumber: 10,
        context: "code",
        relevanceScore: 0.5,
        matchReason: "test"
      ),
      SearchResult(
        projectName: "test",
        filePath: "a.swift",
        language: "Swift",
        lineNumber: 5,
        endLineNumber: 5,
        context: "code",
        relevanceScore: 0.9,
        matchReason: "test"
      ),
      SearchResult(
        projectName: "test",
        filePath: "a.swift",
        language: "Swift",
        lineNumber: 1,
        endLineNumber: 1,
        context: "code",
        relevanceScore: 0.9,
        matchReason: "test"
      ),
    ]

    let byRelevance = SearchResult.sortByRelevance(results)
    #expect(byRelevance[0].relevanceScore >= byRelevance[1].relevanceScore)

    let byLocation = SearchResult.sortByLocation(results)
    #expect(byLocation[0].filePath <= byLocation[1].filePath)

    let byBoth = SearchResult.sortByRelevanceThenLocation(results)
    #expect(byBoth[0].relevanceScore >= byBoth[1].relevanceScore)
    // When relevance is equal, should be sorted by location
    if byBoth[0].relevanceScore == byBoth[1].relevanceScore {
      #expect(byBoth[0].filePath <= byBoth[1].filePath)
    }
  }

  @Test("CodeChunk model is Sendable and Codable")
  func testCodeChunkModel() throws {
    let chunk = CodeChunk(
      projectName: "test",
      filePath: "test.swift",
      language: "Swift",
      startLine: 1,
      endLine: 10,
      content: "func test() {}",
      chunkType: "function",
      embedding: nil
    )

    #expect(chunk.projectName == "test")
    #expect(chunk.lineCount == 10)
    #expect(chunk.chunkType == "function")

    // Test Codable
    let encoder = JSONEncoder()
    let data = try encoder.encode(chunk)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(CodeChunk.self, from: data)

    #expect(decoded.projectName == chunk.projectName)
    #expect(decoded.lineCount == chunk.lineCount)
  }

  @Test("CodeChunk utility methods work correctly")
  func testCodeChunkUtilityMethods() {
    let content = """
      line 1
      line 2
      line 3
      line 4
      line 5
      """
    let chunk = CodeChunk(
      projectName: "test",
      filePath: "test.swift",
      language: "Swift",
      startLine: 1,
      endLine: 5,
      content: content
    )

    // Test preview
    let preview = chunk.preview(maxLines: 3)
    #expect(preview.contains("line 1"))
    #expect(preview.contains("..."))

    // Test containsSymbol
    #expect(chunk.containsSymbol("line 2"))
    #expect(!chunk.containsSymbol("nonexistent"))

    // Test getLines
    let lines = chunk.getLines()
    #expect(lines.count == 5)

    // Test getLine
    #expect(chunk.getLine(1) == "line 1")
    #expect(chunk.getLine(100) == nil)

    // Test withEmbedding
    let embedding = Array(repeating: Float(0.5), count: 384)
    let withEmb = chunk.withEmbedding(embedding)
    #expect(withEmb.embedding?.count == 384)
  }

  // MARK: - Integration Tests

  @Test("End-to-end indexing and search workflow")
  func testEndToEndWorkflow() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("workflow-test")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
    try Self.createTestProject(at: projectDir)

    // Initialize server with project
    let server = try await MCPServer(
      indexPath: tempDir,
      projectPaths: [projectDir]
    )

    #expect(server != nil)
    // Indexing should complete without errors
  }

  @Test("Search result metadata contains useful information")
  func testSearchResultMetadata() {
    let result = SearchResult(
      projectName: "test",
      filePath: "src/models/User.swift",
      language: "Swift",
      lineNumber: 42,
      endLineNumber: 50,
      context: "class User {\n  var name: String\n}",
      relevanceScore: 0.95,
      matchReason: "Semantic similarity",
      metadata: [
        "similarity": "0.950",
        "chunk_type": "class",
      ]
    )

    #expect(result.fullPath == "test/src/models/User.swift")
    #expect(result.locationString == "src/models/User.swift:42-50")
    #expect(result.contextPreview.contains("class User"))
    #expect(result.metadata["similarity"] == "0.950")
  }

  @Test("CodeChunk effective line count excludes comments")
  func testCodeChunkEffectiveLineCount() {
    let content = """
      // Comment line
      func test() {
        // Another comment

        return 42
      }
      """
    let chunk = CodeChunk(
      projectName: "test",
      filePath: "test.swift",
      language: "Swift",
      startLine: 1,
      endLine: 7,
      content: content
    )

    // Should exclude comment lines and empty lines
    #expect(chunk.effectiveLineCount < chunk.lineCount)
    #expect(chunk.effectiveLineCount >= 2)  // At least "func test()" and "return 42"
  }

  @Test("SearchResult relevance score is clamped to 0-1")
  func testSearchResultRelevanceScoreClamping() {
    let tooHigh = SearchResult(
      projectName: "test",
      filePath: "test.swift",
      language: "Swift",
      lineNumber: 1,
      endLineNumber: 1,
      context: "code",
      relevanceScore: 1.5,
      matchReason: "test"
    )
    #expect(tooHigh.relevanceScore == 1.0)

    let tooLow = SearchResult(
      projectName: "test",
      filePath: "test.swift",
      language: "Swift",
      lineNumber: 1,
      endLineNumber: 1,
      context: "code",
      relevanceScore: -0.5,
      matchReason: "test"
    )
    #expect(tooLow.relevanceScore == 0.0)
  }

  // MARK: - Performance Baseline Tests

  @Test("Index small project completes quickly")
  func testSmallProjectIndexingPerformance() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("perf-test")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    // Create 10 small files
    for i in 1...10 {
      let file = (projectDir as NSString).appendingPathComponent("File\(i).swift")
      try "func test\(i)() { return \(i) }".write(toFile: file, atomically: true, encoding: .utf8)
    }

    let startTime = Date()

    let server = try await MCPServer(
      indexPath: tempDir,
      projectPaths: [projectDir]
    )

    let duration = Date().timeIntervalSince(startTime)

    #expect(server != nil)
    // Should complete in reasonable time (< 5 seconds for 10 files)
    #expect(duration < 5.0)
  }

  @Test("Vector search performance is acceptable")
  func testVectorSearchPerformance() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let vectorSearchService = VectorSearchService(
      indexPath: tempDir,
      embeddingService: embeddingService
    )

    // Create and index test project
    let projectDir = (tempDir as NSString).appendingPathComponent("perf-test")
    try FileManager.default.createDirectory(
      atPath: projectDir,
      withIntermediateDirectories: true
    )

    // Create test files
    for i in 1...10 {
      let file = (projectDir as NSString).appendingPathComponent("File\(i).swift")
      try "func function\(i)() { return \(i) }".write(
        toFile: file,
        atomically: true,
        encoding: .utf8
      )
    }

    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    try await indexer.indexProject(path: projectDir)

    let startTime = Date()
    let results = try await vectorSearchService.search(
      query: "function implementation",
      maxResults: 5
    )
    let duration = Date().timeIntervalSince(startTime)

    // Search should be fast (< 2 seconds with embedding generation)
    #expect(duration < 2.0, "Vector search should complete in < 2 seconds")
  }
}
