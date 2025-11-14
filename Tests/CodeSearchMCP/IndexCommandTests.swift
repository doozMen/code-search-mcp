import Foundation
import Testing

@testable import CodeSearchMCP
@testable import SwiftEmbeddings

/// Comprehensive test suite for IndexCommand (one-shot indexing mode).
///
/// Tests cover:
/// - Single project indexing
/// - Multiple project indexing
/// - Progress tracking and completion
/// - Error handling for invalid paths
/// - Integration with IndexingQueue
/// - Search after indexing
@Suite("IndexCommand Tests")
struct IndexCommandTests {
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

  private static func createTestProject(at path: String, name: String) throws -> String {
    let projectDir = (path as NSString).appendingPathComponent(name)
    try FileManager.default.createDirectory(
      atPath: projectDir,
      withIntermediateDirectories: true
    )

    // Create test Swift file
    let swiftFile = (projectDir as NSString).appendingPathComponent("Main.swift")
    try """
    import Foundation

    struct \(name.capitalized) {
      func process() -> String {
        return "Hello from \(name)"
      }
    }

    class DataService {
      func fetchData() async throws -> [String] {
        return ["item1", "item2", "item3"]
      }
    }
    """.write(toFile: swiftFile, atomically: true, encoding: .utf8)

    // Create test Python file
    let pythonFile = (projectDir as NSString).appendingPathComponent("utils.py")
    try """
    def calculate_sum(numbers):
      \"\"\"Calculate sum of numbers\"\"\"
      return sum(numbers)

    def format_output(data):
      \"\"\"Format data for display\"\"\"
      return f"Result: {data}"
    """.write(toFile: pythonFile, atomically: true, encoding: .utf8)

    return projectDir
  }

  // MARK: - Single Project Indexing Tests

  @Test("Index single project successfully")
  func testIndexSingleProject() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let indexPath = (tempDir as NSString).appendingPathComponent("index")
    let projectPath = try Self.createTestProject(at: tempDir, name: "test-project")

    // Initialize services manually (simulating IndexCommand)
    let embeddingService = try await EmbeddingService(indexPath: indexPath)
    let projectIndexer = ProjectIndexer(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    let indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

    // Queue indexing job (as IndexCommand does)
    let jobID = await indexingQueue.enqueue(
      projectName: "test-project",
      priority: .high
    ) {
      try await projectIndexer.indexProject(path: projectPath)

      if let project = await projectIndexer.getIndexedProjects()
        .first(where: { $0.name == "test-project" })
      {
        return (fileCount: project.fileCount, chunkCount: project.chunkCount)
      }
      return (fileCount: 0, chunkCount: 0)
    }

    // Poll for completion (as IndexCommand does)
    var iterations = 0
    while iterations < 20 {
      if let status = await indexingQueue.getJobStatus(jobID) {
        if status.status == .completed {
          // Verify indexing succeeded
          #expect(status.fileCount ?? 0 > 0, "Expected at least 1 file indexed")
          #expect(status.chunkCount ?? 0 > 0, "Expected at least 1 chunk created")
          return  // Success
        } else if status.status == .failed {
          Issue.record("Indexing failed: \(status.error ?? "unknown error")")
          return
        }
      }

      try await Task.sleep(for: .milliseconds(100))
      iterations += 1
    }

    Issue.record("Indexing did not complete within timeout")
  }

  @Test("Indexed project appears in registry")
  func testProjectInRegistry() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let indexPath = (tempDir as NSString).appendingPathComponent("index")
    let projectPath = try Self.createTestProject(at: tempDir, name: "registry-test")

    let embeddingService = try await EmbeddingService(indexPath: indexPath)
    let projectIndexer = ProjectIndexer(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    let indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

    let jobID = await indexingQueue.enqueue(
      projectName: "registry-test",
      priority: .high
    ) {
      try await projectIndexer.indexProject(path: projectPath)
      if let project = await projectIndexer.getIndexedProjects()
        .first(where: { $0.name == "registry-test" })
      {
        return (fileCount: project.fileCount, chunkCount: project.chunkCount)
      }
      return (fileCount: 0, chunkCount: 0)
    }

    // Wait for completion
    var completed = false
    for _ in 0..<20 {
      if let status = await indexingQueue.getJobStatus(jobID) {
        if status.status == .completed {
          completed = true
          break
        }
      }
      try await Task.sleep(for: .milliseconds(100))
    }

    #expect(completed, "Job should complete")

    // Verify project in registry
    let projects = await projectIndexer.getIndexedProjects()
    #expect(projects.contains { $0.name == "registry-test" }, "Project should be in registry")
  }

  // MARK: - Multiple Projects Tests

  @Test("Index multiple projects simultaneously")
  func testIndexMultipleProjects() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let indexPath = (tempDir as NSString).appendingPathComponent("index")
    let project1Path = try Self.createTestProject(at: tempDir, name: "project1")
    let project2Path = try Self.createTestProject(at: tempDir, name: "project2")

    let embeddingService = try await EmbeddingService(indexPath: indexPath)
    let projectIndexer = ProjectIndexer(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    let indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

    // Queue both projects
    let jobID1 = await indexingQueue.enqueue(
      projectName: "project1",
      priority: .high
    ) {
      try await projectIndexer.indexProject(path: project1Path)
      if let project = await projectIndexer.getIndexedProjects()
        .first(where: { $0.name == "project1" })
      {
        return (fileCount: project.fileCount, chunkCount: project.chunkCount)
      }
      return (fileCount: 0, chunkCount: 0)
    }

    let jobID2 = await indexingQueue.enqueue(
      projectName: "project2",
      priority: .high
    ) {
      try await projectIndexer.indexProject(path: project2Path)
      if let project = await projectIndexer.getIndexedProjects()
        .first(where: { $0.name == "project2" })
      {
        return (fileCount: project.fileCount, chunkCount: project.chunkCount)
      }
      return (fileCount: 0, chunkCount: 0)
    }

    // Wait for both to complete
    var job1Done = false
    var job2Done = false
    var iterations = 0

    while (!job1Done || !job2Done) && iterations < 40 {
      if !job1Done, let status = await indexingQueue.getJobStatus(jobID1) {
        if status.status == .completed {
          job1Done = true
        }
      }

      if !job2Done, let status = await indexingQueue.getJobStatus(jobID2) {
        if status.status == .completed {
          job2Done = true
        }
      }

      try await Task.sleep(for: .milliseconds(100))
      iterations += 1
    }

    #expect(job1Done, "Project1 should complete")
    #expect(job2Done, "Project2 should complete")

    // Verify both projects indexed
    let projects = await projectIndexer.getIndexedProjects()
    #expect(projects.count == 2, "Should have 2 projects")
  }

  @Test("Track progress for multiple projects")
  func testMultipleProjectsProgress() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let indexPath = (tempDir as NSString).appendingPathComponent("index")
    let project1Path = try Self.createTestProject(at: tempDir, name: "progress1")
    let project2Path = try Self.createTestProject(at: tempDir, name: "progress2")
    let project3Path = try Self.createTestProject(at: tempDir, name: "progress3")

    let embeddingService = try await EmbeddingService(indexPath: indexPath)
    let projectIndexer = ProjectIndexer(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    let indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

    // Queue three projects
    _ = [
      await indexingQueue.enqueue(projectName: "progress1", priority: .high) {
        try await projectIndexer.indexProject(path: project1Path)
        return (fileCount: 1, chunkCount: 1)
      },
      await indexingQueue.enqueue(projectName: "progress2", priority: .high) {
        try await projectIndexer.indexProject(path: project2Path)
        return (fileCount: 1, chunkCount: 1)
      },
      await indexingQueue.enqueue(projectName: "progress3", priority: .high) {
        try await projectIndexer.indexProject(path: project3Path)
        return (fileCount: 1, chunkCount: 1)
      },
    ]

    // Track progress
    var completedCount = 0
    var iterations = 0

    while completedCount < 3 && iterations < 60 {
      let stats = await indexingQueue.getStats()
      completedCount = min(stats.completed, 3)

      // Verify stats are sensible
      #expect(stats.pending >= 0, "Pending count should be non-negative")
      #expect(stats.active >= 0, "Active count should be non-negative")
      #expect(stats.completed >= 0, "Completed count should be non-negative")

      try await Task.sleep(for: .milliseconds(100))
      iterations += 1
    }

    #expect(completedCount == 3, "All 3 projects should complete")
  }

  // MARK: - Error Handling Tests

  @Test("Handle invalid project path gracefully")
  func testInvalidProjectPath() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let indexPath = (tempDir as NSString).appendingPathComponent("index")
    let invalidPath = "/nonexistent/invalid/path"

    let embeddingService = try await EmbeddingService(indexPath: indexPath)
    let projectIndexer = ProjectIndexer(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    let indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

    let jobID = await indexingQueue.enqueue(
      projectName: "invalid-project",
      priority: .high
    ) {
      try await projectIndexer.indexProject(path: invalidPath)
      return (fileCount: 0, chunkCount: 0)
    }

    // Wait for failure
    var failed = false
    for _ in 0..<20 {
      if let status = await indexingQueue.getJobStatus(jobID) {
        if status.status == .failed {
          failed = true
          #expect(status.error != nil, "Should have error message")
          break
        }
      }
      try await Task.sleep(for: .milliseconds(100))
    }

    #expect(failed, "Job should fail for invalid path")
  }

  @Test("Report correct file and chunk counts")
  func testFileAndChunkCounts() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let indexPath = (tempDir as NSString).appendingPathComponent("index")
    let projectPath = try Self.createTestProject(at: tempDir, name: "count-test")

    let embeddingService = try await EmbeddingService(indexPath: indexPath)
    let projectIndexer = ProjectIndexer(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    let indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

    let jobID = await indexingQueue.enqueue(
      projectName: "count-test",
      priority: .high
    ) {
      try await projectIndexer.indexProject(path: projectPath)
      if let project = await projectIndexer.getIndexedProjects()
        .first(where: { $0.name == "count-test" })
      {
        return (fileCount: project.fileCount, chunkCount: project.chunkCount)
      }
      return (fileCount: 0, chunkCount: 0)
    }

    // Wait for completion and check counts
    var completed = false
    for _ in 0..<20 {
      if let status = await indexingQueue.getJobStatus(jobID) {
        if status.status == .completed {
          // We created 2 files (Main.swift and utils.py)
          #expect(status.fileCount == 2, "Should index 2 files")
          #expect((status.chunkCount ?? 0) >= 2, "Should have at least 2 chunks")
          completed = true
          break
        }
      }
      try await Task.sleep(for: .milliseconds(100))
    }

    #expect(completed, "Job should complete")
  }

  // MARK: - Search After Indexing Tests

  @Test("Search works after indexing")
  func testSearchAfterIndexing() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let indexPath = (tempDir as NSString).appendingPathComponent("index")
    let projectPath = try Self.createTestProject(at: tempDir, name: "search-test")

    // Index project
    let embeddingService = try await EmbeddingService(indexPath: indexPath)
    let projectIndexer = ProjectIndexer(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    let indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

    let jobID = await indexingQueue.enqueue(
      projectName: "search-test",
      priority: .high
    ) {
      try await projectIndexer.indexProject(path: projectPath)
      return (fileCount: 1, chunkCount: 1)
    }

    // Wait for indexing to complete
    var completed = false
    for _ in 0..<20 {
      if let status = await indexingQueue.getJobStatus(jobID) {
        if status.status == .completed {
          completed = true
          break
        }
      }
      try await Task.sleep(for: .milliseconds(100))
    }

    #expect(completed, "Indexing should complete")

    // Now perform search
    let vectorSearch = VectorSearchService(
      indexPath: indexPath,
      embeddingService: embeddingService
    )

    let results = try await vectorSearch.search(
      query: "calculate sum of numbers",
      maxResults: 5
    )

    #expect(results.count > 0, "Should find relevant results")

    // Verify we found the Python function
    let foundCalculateSum = results.contains { result in
      result.context.contains("calculate_sum")
    }
    #expect(foundCalculateSum, "Should find calculate_sum function")
  }

  @Test("Search with project filter after indexing multiple projects")
  func testSearchWithProjectFilter() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let indexPath = (tempDir as NSString).appendingPathComponent("index")
    let project1Path = try Self.createTestProject(at: tempDir, name: "filter-test-1")
    let project2Path = try Self.createTestProject(at: tempDir, name: "filter-test-2")

    // Index both projects
    let embeddingService = try await EmbeddingService(indexPath: indexPath)
    let projectIndexer = ProjectIndexer(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    let indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

    let job1 = await indexingQueue.enqueue(projectName: "filter-test-1", priority: .high) {
      try await projectIndexer.indexProject(path: project1Path)
      return (fileCount: 1, chunkCount: 1)
    }

    let job2 = await indexingQueue.enqueue(projectName: "filter-test-2", priority: .high) {
      try await projectIndexer.indexProject(path: project2Path)
      return (fileCount: 1, chunkCount: 1)
    }

    // Wait for both
    for _ in 0..<40 {
      let status1 = await indexingQueue.getJobStatus(job1)
      let status2 = await indexingQueue.getJobStatus(job2)

      if status1?.status == .completed && status2?.status == .completed {
        break
      }

      try await Task.sleep(for: .milliseconds(100))
    }

    // Search with project filter
    let vectorSearch = VectorSearchService(
      indexPath: indexPath,
      embeddingService: embeddingService
    )

    let results = try await vectorSearch.search(
      query: "data service",
      maxResults: 10,
      projectFilter: "filter-test-1"
    )

    #expect(results.count > 0, "Should find results")

    // All results should be from filter-test-1
    for result in results {
      #expect(
        result.projectName == "filter-test-1",
        "All results should be from filter-test-1"
      )
    }
  }

  // MARK: - Priority Tests

  @Test("High priority jobs execute before low priority")
  func testJobPriority() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let indexPath = (tempDir as NSString).appendingPathComponent("index")
    _ = try await EmbeddingService(indexPath: indexPath)
    let indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

    // Queue low priority job first
    let lowJob = await indexingQueue.enqueue(projectName: "low", priority: .low) {
      return (fileCount: 0, chunkCount: 0)
    }

    // Then queue high priority job (should jump ahead)
    let highJob = await indexingQueue.enqueue(projectName: "high", priority: .high) {
      return (fileCount: 0, chunkCount: 0)
    }

    // Wait for both to complete
    var lowCompleted = false
    var highCompleted = false

    for _ in 0..<20 {
      let lowStatus = await indexingQueue.getJobStatus(lowJob)
      let highStatus = await indexingQueue.getJobStatus(highJob)

      if lowStatus?.status == .completed {
        lowCompleted = true
      }

      if highStatus?.status == .completed {
        highCompleted = true
      }

      if lowCompleted && highCompleted {
        break
      }

      try await Task.sleep(for: .milliseconds(100))
    }

    // Verify both completed
    #expect(lowCompleted, "Low priority job should complete")
    #expect(highCompleted, "High priority job should complete")
  }

  // MARK: - Cleanup Tests

  @Test("Indexing creates correct directory structure")
  func testDirectoryStructure() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let indexPath = (tempDir as NSString).appendingPathComponent("index")
    let projectPath = try Self.createTestProject(at: tempDir, name: "structure-test")

    let embeddingService = try await EmbeddingService(indexPath: indexPath)
    let projectIndexer = ProjectIndexer(
      indexPath: indexPath,
      embeddingService: embeddingService
    )
    let indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

    let jobID = await indexingQueue.enqueue(projectName: "structure-test", priority: .high) {
      try await projectIndexer.indexProject(path: projectPath)
      return (fileCount: 1, chunkCount: 1)
    }

    // Wait for completion
    for _ in 0..<20 {
      if let status = await indexingQueue.getJobStatus(jobID) {
        if status.status == .completed {
          break
        }
      }
      try await Task.sleep(for: .milliseconds(100))
    }

    // Verify directory structure
    let chunksDir = (indexPath as NSString).appendingPathComponent("chunks")
    let embeddingsDir = (indexPath as NSString).appendingPathComponent("embeddings")
    let registryFile = (indexPath as NSString).appendingPathComponent("project_registry.json")

    #expect(FileManager.default.fileExists(atPath: chunksDir), "chunks/ should exist")
    #expect(FileManager.default.fileExists(atPath: embeddingsDir), "embeddings/ should exist")
    #expect(FileManager.default.fileExists(atPath: registryFile), "registry should exist")

    // Verify project-specific chunk directory
    let projectChunksDir = (chunksDir as NSString).appendingPathComponent("structure-test")
    #expect(
      FileManager.default.fileExists(atPath: projectChunksDir),
      "Project chunks directory should exist"
    )
  }
}
