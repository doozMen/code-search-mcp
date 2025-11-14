import ArgumentParser
import Foundation
import Logging
import SwiftEmbeddings

/// Command to index project(s) in one-shot mode and exit (non-daemon).
///
/// This command initializes the indexing services, queues indexing jobs,
/// waits for them to complete, and exits cleanly. Unlike the main server
/// command, this does NOT start the stdio MCP server - it's pure CLI mode.
struct IndexCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "index",
    abstract: "Index project(s) and exit (non-daemon mode)",
    discussion: """
      Index codebases for semantic search without running as a daemon.

      This command:
      1. Initializes indexing services
      2. Queues indexing jobs for specified projects
      3. Waits for all jobs to complete
      4. Exits with status code (0 for success, 1 for failure)

      Examples:
        # Index current directory
        code-search-mcp index .
        
        # Index specific projects
        code-search-mcp index ~/project1 ~/project2
        
        # Index with custom cache location
        code-search-mcp index ~/myproject --index-path ~/.custom-cache
      """
  )

  // MARK: - Configuration Options

  /// Log level for debug output (debug, info, warn, error).
  @Option(
    name: .long,
    help: "Log level for debug output",
    completion: .list(["debug", "info", "warn", "error"])
  )
  var logLevel: String = "info"

  /// Path to the index directory where embeddings and metadata are stored.
  @Option(
    name: .long,
    help: "Path to index directory for embeddings and metadata"
  )
  var indexPath: String =
    "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cache/code-search-mcp"

  /// Project directories to index (positional arguments).
  @Argument(help: "Project directories to index")
  var projectPaths: [String] = []

  // MARK: - Command Execution

  func run() async throws {
    // Configure logging system
    configureLogging()

    let logger = Logger(label: "code-search-mcp-index")

    // Validate arguments
    guard !projectPaths.isEmpty else {
      print("Error: No project paths specified")
      print("")
      print("Usage: code-search-mcp index <project-path> [<project-path> ...]")
      print("")
      print("Examples:")
      print("  code-search-mcp index .")
      print("  code-search-mcp index ~/project1 ~/project2")
      throw ExitCode.failure
    }

    logger.info(
      "Starting one-shot indexing",
      metadata: [
        "version": "0.5.1-alpha.1",
        "log_level": "\(logLevel)",
        "index_path": "\(indexPath)",
        "project_count": "\(projectPaths.count)",
      ])

    // Initialize services (without starting MCP server)
    let embeddingService: EmbeddingService
    let projectIndexer: ProjectIndexer
    let indexingQueue: IndexingQueue

    do {
      embeddingService = try await EmbeddingService(indexPath: indexPath)
      projectIndexer = ProjectIndexer(
        indexPath: indexPath,
        embeddingService: embeddingService
      )
      indexingQueue = IndexingQueue(maxConcurrentJobs: 1)

      logger.info("Services initialized successfully")
    } catch {
      logger.error(
        "Failed to initialize services",
        metadata: [
          "error": "\(error)"
        ])
      throw ExitCode.failure
    }

    // Queue indexing jobs for all specified projects
    var jobIDs: [UUID] = []

    for projectPath in projectPaths {
      let resolvedPath = resolvePath(projectPath)
      let projectName = resolvedPath.lastPathComponent

      logger.info(
        "Queueing project for indexing",
        metadata: [
          "project": "\(projectName)",
          "path": "\(resolvedPath.path)",
        ])

      let jobID = await indexingQueue.enqueue(
        projectName: projectName,
        priority: .high  // High priority for one-shot indexing
      ) {
        // Perform indexing operation
        try await projectIndexer.indexProject(path: resolvedPath.path)

        // Get project info to return file/chunk counts
        if let projects = await projectIndexer.getIndexedProjects()
          .first(where: { $0.name == projectName })
        {
          return (fileCount: projects.fileCount, chunkCount: projects.chunkCount)
        }
        return (fileCount: 0, chunkCount: 0)
      }

      jobIDs.append(jobID)

      logger.info(
        "Job queued",
        metadata: [
          "project": "\(projectName)",
          "job_id": "\(jobID.uuidString)",
        ])
    }

    // Poll queue until all jobs complete
    print("")
    print("Indexing \(projectPaths.count) project(s)...")
    print("")

    var lastStatus: (pending: Int, active: Int, completed: Int) = (0, 0, 0)

    while true {
      let stats = await indexingQueue.getStats()

      // Print status update if changed
      if stats != lastStatus {
        let total = jobIDs.count
        let done = min(stats.completed, total)
        print(
          "[\(done)/\(total)] Projects completed (active: \(stats.active), pending: \(stats.pending))"
        )
        lastStatus = stats
      }

      // Check if all our jobs are complete
      var allComplete = true

      for jobID in jobIDs {
        if let status = await indexingQueue.getJobStatus(jobID) {
          switch status.status {
          case .queued, .inProgress:
            allComplete = false
          case .failed:
            logger.error(
              "Job failed",
              metadata: [
                "job_id": "\(jobID.uuidString)",
                "project": "\(status.projectName ?? "unknown")",
                "error": "\(status.error ?? "unknown error")",
              ])
          case .completed:
            break
          }
        }
      }

      if allComplete {
        break
      }

      // Wait a bit before polling again
      try await Task.sleep(for: .milliseconds(500))
    }

    // Print summary
    print("")
    print("Indexing Summary:")
    print("=================")

    var totalFiles = 0
    var totalChunks = 0
    var successCount = 0
    var failureCount = 0

    for jobID in jobIDs {
      if let status = await indexingQueue.getJobStatus(jobID) {
        let projectName = status.projectName ?? "unknown"
        switch status.status {
        case .completed:
          let files = status.fileCount ?? 0
          let chunks = status.chunkCount ?? 0
          print("  ✅ \(projectName): \(files) files, \(chunks) chunks")
          totalFiles += files
          totalChunks += chunks
          successCount += 1
        case .failed:
          print("  ❌ \(projectName): \(status.error ?? "unknown error")")
          failureCount += 1
        default:
          break
        }
      }
    }

    print("")
    print("Total: \(totalFiles) files, \(totalChunks) chunks")
    print("Success: \(successCount), Failed: \(failureCount)")

    logger.info("Indexing complete, exiting")

    if failureCount > 0 {
      throw ExitCode.failure
    }

    Foundation.exit(EXIT_SUCCESS)
  }

  // MARK: - Private Methods

  /// Configure the logging system with the specified log level.
  private func configureLogging() {
    LoggingSystem.bootstrap { label in
      var handler = StreamLogHandler.standardError(label: label)

      if let logLevelValue = Logger.Level(rawValue: logLevel) {
        handler.logLevel = logLevelValue
      } else {
        handler.logLevel = .info
      }

      return handler
    }
  }

  /// Resolve path to absolute URL, expanding ~ and relative paths
  private func resolvePath(_ path: String) -> URL {
    let nsPath = NSString(string: path)
    let expandedPath = nsPath.expandingTildeInPath

    if expandedPath.hasPrefix("/") {
      return URL(fileURLWithPath: expandedPath)
    } else {
      return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(expandedPath)
        .standardized
    }
  }
}
