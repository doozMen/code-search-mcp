import ArgumentParser
import Foundation
import Logging
import MCP

/// Main entry point for the code-search-mcp server.
///
/// This command-line tool initializes and runs an MCP server that provides
/// pure vector-based semantic code search across multiple codebases.
///
/// Features:
/// - Semantic search using 300-dimensional CoreML embeddings (macOS) or 384-dimensional BERT embeddings (Linux)
/// - File context extraction with dependency tracking
/// - Related file discovery through import analysis
/// - Index metadata and statistics
/// - Auto-indexing setup with git hooks and direnv
@main
struct CodeSearchMCP: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "code-search-mcp",
    abstract: "MCP server for semantic code search across multiple projects",
    discussion: """
      Provides MCP tools for pure vector-based semantic search, file context extraction,
      and dependency graph analysis across indexed codebases.
      """,
    version: "0.4.3",
    subcommands: [SetupHooksCommand.self]
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

  /// Optional project directories to index (can be specified multiple times).
  @Option(
    name: .long,
    help: "Project directory to index (can be specified multiple times)"
  )
  var projectPaths: [String] = []

  // MARK: - Async Command Execution

  func run() async throws {
    // Configure logging system
    configureLogging()

    let logger = Logger(label: "code-search-mcp")
    logger.info(
      "Starting code-search-mcp server",
      metadata: [
        "version": "0.2.0",
        "log_level": "\(logLevel)",
        "index_path": "\(indexPath)",
      ])

    // Initialize MCP server
    do {
      let server = try await MCPServer(
        indexPath: indexPath,
        projectPaths: projectPaths
      )
      try await server.run()
    } catch {
      logger.error(
        "Failed to start server",
        metadata: [
          "error": "\(error)"
        ])
      throw ExitCode.failure
    }
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
}
