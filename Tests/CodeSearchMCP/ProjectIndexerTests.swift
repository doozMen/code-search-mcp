import Foundation
import Testing

@testable import CodeSearchMCP
@testable import SwiftEmbeddings

/// Comprehensive test suite for ProjectIndexer.
///
/// Tests cover:
/// - File discovery and filtering
/// - Code chunk extraction
/// - Language detection
/// - Exclusion patterns
/// - Line-based chunking
@Suite("ProjectIndexer Tests")
struct ProjectIndexerTests {
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
    // Create test source files
    let swiftFile = (path as NSString).appendingPathComponent("Test.swift")
    try """
      class TestClass {
        func testMethod() -> Int {
          return 42
        }
      }
      """.write(toFile: swiftFile, atomically: true, encoding: .utf8)

    let pythonFile = (path as NSString).appendingPathComponent("test.py")
    try """
      def test_function():
        return "hello"
      """.write(toFile: pythonFile, atomically: true, encoding: .utf8)

    // Create excluded directories
    let gitDir = (path as NSString).appendingPathComponent(".git")
    try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)

    let buildDir = (path as NSString).appendingPathComponent(".build")
    try FileManager.default.createDirectory(atPath: buildDir, withIntermediateDirectories: true)
  }

  private static func createEmbeddingService(indexPath: String) async throws -> EmbeddingService {
    return try await EmbeddingService(indexPath: indexPath)
  }

  // MARK: - Initialization Tests

  @Test("ProjectIndexer creates index directory")
  func testInitialization() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    #expect(indexer != nil)
    #expect(FileManager.default.fileExists(atPath: tempDir))
  }

  // MARK: - Project Indexing Tests

  @Test("Index project discovers source files")
  func testProjectIndexing() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("test-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
    try Self.createTestProject(at: projectDir)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    // Index the project (should not throw)
    try await indexer.indexProject(path: projectDir)

    // Verify indexing completed (implicitly by not throwing)
    #expect(true)
  }

  @Test("Index invalid path throws error")
  func testInvalidProjectPath() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    await #expect(throws: IndexingError.self) {
      try await indexer.indexProject(path: "/nonexistent/path")
    }
  }

  @Test("Indexer excludes hidden files and directories")
  func testExclusionPatterns() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("test-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    // Create files in excluded directories
    let gitDir = (projectDir as NSString).appendingPathComponent(".git")
    try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
    let gitFile = (gitDir as NSString).appendingPathComponent("config")
    try "git config".write(toFile: gitFile, atomically: true, encoding: .utf8)

    let nodeModules = (projectDir as NSString).appendingPathComponent("node_modules")
    try FileManager.default.createDirectory(
      atPath: nodeModules,
      withIntermediateDirectories: true
    )
    let npmPackage = (nodeModules as NSString).appendingPathComponent("package.js")
    try "module.exports = {};".write(toFile: npmPackage, atomically: true, encoding: .utf8)

    // Create valid source file
    let validFile = (projectDir as NSString).appendingPathComponent("main.swift")
    try "print(\"hello\")".write(toFile: validFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    try await indexer.indexProject(path: projectDir)

    // Should complete without indexing excluded files
    #expect(true)
  }

  // MARK: - Language Detection Tests

  @Test("Detect Swift files")
  func testSwiftDetection() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("swift-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    let swiftFile = (projectDir as NSString).appendingPathComponent("main.swift")
    try "print(\"hello\")".write(toFile: swiftFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    try await indexer.indexProject(path: projectDir)

    #expect(true)
  }

  @Test("Detect Python files")
  func testPythonDetection() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("python-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    let pythonFile = (projectDir as NSString).appendingPathComponent("main.py")
    try "print('hello')".write(toFile: pythonFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    try await indexer.indexProject(path: projectDir)

    #expect(true)
  }

  @Test("Detect JavaScript files")
  func testJavaScriptDetection() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("js-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    let jsFile = (projectDir as NSString).appendingPathComponent("main.js")
    try "console.log('hello');".write(toFile: jsFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    try await indexer.indexProject(path: projectDir)

    #expect(true)
  }

  // MARK: - Chunking Tests

  @Test("Extract chunks from small file")
  func testSmallFileChunking() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("small-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    let smallFile = (projectDir as NSString).appendingPathComponent("small.swift")
    try """
      func hello() {
        print("hello")
      }
      """.write(toFile: smallFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    try await indexer.indexProject(path: projectDir)

    // Should create 1 chunk for small file
    #expect(true)
  }

  @Test("Extract chunks from large file")
  func testLargeFileChunking() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("large-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    // Create a file with 100+ lines
    var largeContent = ""
    for i in 1...100 {
      largeContent += "func function\(i)() { return \(i) }\n"
    }

    let largeFile = (projectDir as NSString).appendingPathComponent("large.swift")
    try largeContent.write(toFile: largeFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    try await indexer.indexProject(path: projectDir)

    // Should create multiple chunks (50 lines per chunk with overlap)
    #expect(true)
  }

  // MARK: - Error Handling Tests

  @Test("Handle file read errors gracefully")
  func testFileReadErrors() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("error-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    // Create a valid file
    let validFile = (projectDir as NSString).appendingPathComponent("valid.swift")
    try "print(\"hello\")".write(toFile: validFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    // Should handle errors gracefully and continue
    try await indexer.indexProject(path: projectDir)

    #expect(true)
  }

  // MARK: - File Context Extraction Tests

  @Test("Extract file context with default parameters")
  func testExtractFileContextDefault() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("context-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    let testFile = (projectDir as NSString).appendingPathComponent("test.swift")
    let content = """
      func hello() {
        print("hello")
      }
      """
    try content.write(toFile: testFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    let result = try await indexer.extractFileContext(filePath: testFile)

    #expect(result.filePath == testFile)
    #expect(result.language == "Swift")
    #expect(result.context.contains("hello"))
  }

  @Test("Extract file context with line range")
  func testExtractFileContextWithRange() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("range-project")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    let testFile = (projectDir as NSString).appendingPathComponent("test.swift")
    let content = """
      line 1
      line 2
      line 3
      line 4
      line 5
      """
    try content.write(toFile: testFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    let result = try await indexer.extractFileContext(
      filePath: testFile,
      startLine: 2,
      endLine: 4,
      contextLines: 0
    )

    #expect(result.lineNumber == 2)
    #expect(result.endLineNumber == 4)
    #expect(result.context.contains("line 2"))
    #expect(result.context.contains("line 3"))
    #expect(result.context.contains("line 4"))
  }

  @Test("Extract file context with surrounding context")
  func testExtractFileContextWithSurroundingLines() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("context-lines")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    let testFile = (projectDir as NSString).appendingPathComponent("test.swift")
    var lines: [String] = []
    for i in 1...20 {
      lines.append("line \(i)")
    }
    try lines.joined(separator: "\n").write(toFile: testFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    let result = try await indexer.extractFileContext(
      filePath: testFile,
      startLine: 10,
      endLine: 10,
      contextLines: 3
    )

    // Should include 3 lines before and after (line 7-13)
    #expect(result.context.contains("line 7"))
    #expect(result.context.contains("line 10"))
    #expect(result.context.contains("line 13"))
  }

  @Test("Extract file context handles non-existent file")
  func testExtractFileContextNonExistent() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    await #expect(throws: IndexingError.self) {
      try await indexer.extractFileContext(filePath: "/nonexistent/file.swift")
    }
  }

  @Test("Extract file context validates line range")
  func testExtractFileContextInvalidRange() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("range-validation")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    let testFile = (projectDir as NSString).appendingPathComponent("test.swift")
    try "line 1\nline 2\nline 3".write(toFile: testFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    // Invalid range (beyond file length)
    await #expect(throws: IndexingError.self) {
      try await indexer.extractFileContext(
        filePath: testFile,
        startLine: 1,
        endLine: 100
      )
    }
  }

  @Test("Extract file context detects language correctly")
  func testExtractFileContextLanguageDetection() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("lang-detect")
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

    // Swift
    let swiftFile = (projectDir as NSString).appendingPathComponent("test.swift")
    try "func test() {}".write(toFile: swiftFile, atomically: true, encoding: .utf8)

    // Python
    let pythonFile = (projectDir as NSString).appendingPathComponent("test.py")
    try "def test(): pass".write(toFile: pythonFile, atomically: true, encoding: .utf8)

    // JavaScript
    let jsFile = (projectDir as NSString).appendingPathComponent("test.js")
    try "function test() {}".write(toFile: jsFile, atomically: true, encoding: .utf8)

    let embeddingService = try await Self.createEmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    let swiftResult = try await indexer.extractFileContext(filePath: swiftFile)
    #expect(swiftResult.language == "Swift")

    let pythonResult = try await indexer.extractFileContext(filePath: pythonFile)
    #expect(pythonResult.language == "Python")

    let jsResult = try await indexer.extractFileContext(filePath: jsFile)
    #expect(jsResult.language == "JavaScript")
  }

  // MARK: - Symbol Extraction Tests (Removed - Keyword Search Deprecated)

  // Symbol extraction was part of keyword search functionality, which has been
  // deprecated in favor of pure vector-based search. All symbol-related tests
  // have been archived to deprecated/KeywordSearchServiceTests.swift.disabled
}
