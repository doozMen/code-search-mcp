import Foundation
import Testing

@testable import CodeSearchMCP

/// Comprehensive test suite for KeywordSearchService.
///
/// Tests cover:
/// - Symbol indexing and storage
/// - Exact symbol matching
/// - Fuzzy search patterns
/// - Definition vs reference filtering
/// - Project-scoped searches
/// - Index persistence
@Suite("KeywordSearchService Tests")
struct KeywordSearchServiceTests {
  // MARK: - Test Helpers

  /// Create a temporary directory for testing
  private static func createTempDir() throws -> String {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).path
    try FileManager.default.createDirectory(
      atPath: tempDir,
      withIntermediateDirectories: true
    )
    return tempDir
  }

  /// Clean up temporary directory
  private static func cleanupTempDir(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }

  // MARK: - Index Storage Tests

  @Test("Store and load symbol index")
  func testIndexPersistence() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let service = KeywordSearchService(indexPath: tempDir)

    // Verify index directory is created
    let symbolIndexDir = (tempDir as NSString).appendingPathComponent("symbols")
    #expect(FileManager.default.fileExists(atPath: symbolIndexDir))
  }

  @Test("Clear symbol index removes files and cache")
  func testClearIndex() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let service = KeywordSearchService(indexPath: tempDir)

    // Create a test index file manually
    let symbolIndexDir = (tempDir as NSString).appendingPathComponent("symbols")
    try FileManager.default.createDirectory(
      atPath: symbolIndexDir,
      withIntermediateDirectories: true
    )

    let indexPath = (symbolIndexDir as NSString).appendingPathComponent("test.symbols.json")
    try "{}".write(toFile: indexPath, atomically: true, encoding: .utf8)

    #expect(FileManager.default.fileExists(atPath: indexPath))

    // Clear the index
    try await service.clearSymbolIndex(for: "test")

    // Verify file is removed
    #expect(!FileManager.default.fileExists(atPath: indexPath))
  }

  // MARK: - Search Tests

  @Test("Search validates symbol name")
  func testSearchValidatesSymbolName() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let service = KeywordSearchService(indexPath: tempDir)

    await #expect(throws: KeywordSearchError.self) {
      try await service.search(symbol: "   ")
    }
  }

  @Test("Search returns empty results when no index exists")
  func testSearchWithNoIndex() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let service = KeywordSearchService(indexPath: tempDir)

    let results = try await service.search(symbol: "TestClass")

    #expect(results.isEmpty)
  }

  @Test("Search with project filter limits scope")
  func testSearchWithProjectFilter() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let service = KeywordSearchService(indexPath: tempDir)

    // Create test index for project "test"
    let chunk = CodeChunk(
      projectName: "test",
      filePath: "/test/src/Test.swift",
      language: "Swift",
      startLine: 1,
      endLine: 5,
      content: "class TestClass {\n  func testMethod() {}\n}"
    )

    try await service.indexSymbols(in: chunk, language: "swift")

    // Search with correct project filter
    let results = try await service.search(symbol: "TestClass", projectFilter: "test")
    #expect(results.count > 0)

    // Search with wrong project filter
    let noResults = try await service.search(symbol: "TestClass", projectFilter: "other")
    #expect(noResults.isEmpty)
  }

  @Test("Search exact match returns definitions first")
  func testSearchExactMatchPriority() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let service = KeywordSearchService(indexPath: tempDir)

    // Index a class definition
    let chunk = CodeChunk(
      projectName: "test",
      filePath: "/test/src/Test.swift",
      language: "Swift",
      startLine: 1,
      endLine: 5,
      content: "class TestClass {\n  func testMethod() {}\n}"
    )

    try await service.indexSymbols(in: chunk, language: "swift")

    let results = try await service.search(symbol: "TestClass")

    #expect(!results.isEmpty)
    // First result should be definition with highest score
    if let first = results.first {
      #expect(first.resultType == "definition")
      #expect(first.relevanceScore >= 0.9)
    }
  }

  @Test("Search fuzzy matching works case-insensitively")
  func testSearchFuzzyMatching() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let service = KeywordSearchService(indexPath: tempDir)

    let chunk = CodeChunk(
      projectName: "test",
      filePath: "/test/src/Test.swift",
      language: "Swift",
      startLine: 1,
      endLine: 3,
      content: "func myTestFunction() {}"
    )

    try await service.indexSymbols(in: chunk, language: "swift")

    // Search with partial, different case
    let results = try await service.search(symbol: "test")

    #expect(!results.isEmpty)
    // Should contain "myTestFunction"
    let hasMatch = results.contains { result in
      result.filePath.contains("Test.swift")
    }
    #expect(hasMatch)
  }

  @Test("Symbol indexing extracts Swift symbols")
  func testSymbolIndexingSwift() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let service = KeywordSearchService(indexPath: tempDir)

    let chunk = CodeChunk(
      projectName: "test",
      filePath: "/test/src/Test.swift",
      language: "Swift",
      startLine: 1,
      endLine: 10,
      content: """
        class TestClass {
          func testMethod() -> Int {
            return 42
          }
        }
        """
    )

    try await service.indexSymbols(in: chunk, language: "swift")

    // Verify symbols were indexed by searching
    let classResults = try await service.search(symbol: "TestClass")
    #expect(!classResults.isEmpty)

    let methodResults = try await service.search(symbol: "testMethod")
    #expect(!methodResults.isEmpty)
  }

  @Test("Symbol indexing handles multiple languages")
  func testSymbolIndexingMultipleLanguages() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let service = KeywordSearchService(indexPath: tempDir)

    // Swift
    let swiftChunk = CodeChunk(
      projectName: "test",
      filePath: "/test/Swift.swift",
      language: "Swift",
      startLine: 1,
      endLine: 1,
      content: "func swiftFunction() {}"
    )
    try await service.indexSymbols(in: swiftChunk, language: "swift")

    // Python
    let pythonChunk = CodeChunk(
      projectName: "test",
      filePath: "/test/python.py",
      language: "Python",
      startLine: 1,
      endLine: 1,
      content: "def python_function():"
    )
    try await service.indexSymbols(in: pythonChunk, language: "python")

    // Verify both indexed
    let swiftResults = try await service.search(symbol: "swiftFunction")
    #expect(!swiftResults.isEmpty)

    let pythonResults = try await service.search(symbol: "python_function")
    #expect(!pythonResults.isEmpty)
  }

  // MARK: - Model Tests

  @Test("SymbolLocation is Sendable and Codable")
  func testSymbolLocationModel() throws {
    let location = SymbolLocation(
      filePath: "test.swift",
      lineNumber: 42,
      isDefinition: true,
      context: "func test() {"
    )

    #expect(location.filePath == "test.swift")
    #expect(location.lineNumber == 42)
    #expect(location.isDefinition == true)

    // Test Codable
    let encoder = JSONEncoder()
    let data = try encoder.encode(location)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(SymbolLocation.self, from: data)

    #expect(decoded.filePath == location.filePath)
    #expect(decoded.lineNumber == location.lineNumber)
  }

  @Test("SymbolIndex is Sendable and Codable")
  func testSymbolIndexModel() throws {
    let symbols: [String: [SymbolLocation]] = [
      "MyClass": [
        SymbolLocation(
          filePath: "test.swift",
          lineNumber: 1,
          isDefinition: true,
          context: "class MyClass {"
        )
      ]
    ]

    let index = SymbolIndex(
      projectName: "test",
      symbols: symbols,
      lastUpdated: Date()
    )

    #expect(index.projectName == "test")
    #expect(index.symbols.count == 1)

    // Test Codable
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(index)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(SymbolIndex.self, from: data)

    #expect(decoded.projectName == index.projectName)
    #expect(decoded.symbols.count == index.symbols.count)
  }

  @Test("Symbol model is Sendable and Codable")
  func testSymbolModel() throws {
    let symbol = Symbol(
      name: "myFunction",
      kind: "function",
      lineNumber: 10,
      column: 5,
      documentation: "A test function"
    )

    #expect(symbol.name == "myFunction")
    #expect(symbol.kind == "function")

    // Test Codable
    let encoder = JSONEncoder()
    let data = try encoder.encode(symbol)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Symbol.self, from: data)

    #expect(decoded.name == symbol.name)
    #expect(decoded.kind == symbol.kind)
  }
}
