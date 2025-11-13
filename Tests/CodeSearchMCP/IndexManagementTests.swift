import Foundation
import Testing

@testable import CodeSearchMCP
@testable import SwiftEmbeddings

/// Tests for index management functionality.
///
/// Validates:
/// - Project metadata tracking
/// - Project registry persistence
/// - Reindexing projects
/// - Clearing indexes
/// - Listing projects
struct IndexManagementTests {

  // MARK: - Test Helpers

  /// Create a temporary directory for testing.
  private func createTempDirectory() throws -> String {
    let tempDir = (NSTemporaryDirectory() as NSString).appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.createDirectory(
      atPath: tempDir, withIntermediateDirectories: true, attributes: nil)
    return tempDir
  }

  /// Create a simple test project with one file.
  private func createTestProject(at path: String) throws {
    let testFile = (path as NSString).appendingPathComponent("test.swift")
    let content = """
      func testFunction() {
        print("Hello, world!")
      }
      """
    try content.write(toFile: testFile, atomically: true, encoding: .utf8)
  }

  // MARK: - Tests

  @Test("Project metadata is tracked after indexing")
  func testProjectMetadataTracking() async throws {
    let tempDir = try createTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("test-project")
    try FileManager.default.createDirectory(
      atPath: projectDir, withIntermediateDirectories: true, attributes: nil)
    try createTestProject(at: projectDir)

    // Create indexer with mock embedding service
    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    // Index project
    try await indexer.indexProject(path: projectDir)

    // Verify project is tracked
    let projects = await indexer.getIndexedProjects()
    #expect(projects.count == 1)
    #expect(projects[0].name == "test-project")
    #expect(projects[0].fileCount == 1)
    #expect(projects[0].chunkCount > 0)
  }

  @Test("Project registry persists to disk")
  func testProjectRegistryPersistence() async throws {
    let tempDir = try createTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("test-project")
    try FileManager.default.createDirectory(
      atPath: projectDir, withIntermediateDirectories: true, attributes: nil)
    try createTestProject(at: projectDir)

    // Create indexer and index project
    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    var indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    try await indexer.indexProject(path: projectDir)

    // Create new indexer (should load persisted registry)
    indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)
    let projects = await indexer.getIndexedProjects()

    #expect(projects.count == 1)
    #expect(projects[0].name == "test-project")
  }

  @Test("Reindex project clears old chunks")
  func testReindexProject() async throws {
    let tempDir = try createTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("test-project")
    try FileManager.default.createDirectory(
      atPath: projectDir, withIntermediateDirectories: true, attributes: nil)
    try createTestProject(at: projectDir)

    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    // Index initially
    try await indexer.indexProject(path: projectDir)
    let initialProjects = await indexer.getIndexedProjects()
    #expect(initialProjects.count == 1)

    // Reindex
    try await indexer.reindexProject(projectName: "test-project")

    // Verify project still exists
    let reindexedProjects = await indexer.getIndexedProjects()
    #expect(reindexedProjects.count == 1)
    #expect(reindexedProjects[0].name == "test-project")
  }

  @Test("Clear all indexes removes all data")
  func testClearAllIndexes() async throws {
    let tempDir = try createTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let projectDir = (tempDir as NSString).appendingPathComponent("test-project")
    try FileManager.default.createDirectory(
      atPath: projectDir, withIntermediateDirectories: true, attributes: nil)
    try createTestProject(at: projectDir)

    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    // Index project
    try await indexer.indexProject(path: projectDir)
    let initialProjects = await indexer.getIndexedProjects()
    #expect(initialProjects.count == 1)

    // Clear all indexes
    try await indexer.clearAllIndexes()

    // Verify all data cleared
    let clearedProjects = await indexer.getIndexedProjects()
    #expect(clearedProjects.count == 0)

    // Verify chunks directory removed
    let chunksDir = (tempDir as NSString).appendingPathComponent("chunks")
    #expect(!FileManager.default.fileExists(atPath: chunksDir))
  }

  @Test("Reindex nonexistent project throws error")
  func testReindexNonexistentProject() async throws {
    let tempDir = try createTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let embeddingService = try await EmbeddingService(indexPath: tempDir)
    let indexer = ProjectIndexer(indexPath: tempDir, embeddingService: embeddingService)

    // Try to reindex nonexistent project
    do {
      try await indexer.reindexProject(projectName: "nonexistent")
      Issue.record("Expected error for nonexistent project")
    } catch {
      // Expected error
      #expect(error is IndexingError)
    }
  }
}
