import Foundation
import Logging
import MCP

/// Main MCP server actor that manages the protocol implementation.
///
/// Responsibilities:
/// - Initialize and manage the MCP server lifecycle
/// - Register and handle all MCP tool calls
/// - Coordinate between search services
/// - Maintain server state and configuration
actor MCPServer: Sendable {
  // MARK: - Properties

  private let server: Server
  private let logger: Logger
  private let projectIndexer: ProjectIndexer
  private let embeddingService: EmbeddingService
  private let vectorSearchService: VectorSearchService
  private let codeMetadataExtractor: CodeMetadataExtractor
  private let defaultProjectFilter: String?

  // MARK: - Initialization

  /// Initialize the MCP server with project paths and index configuration.
  ///
  /// - Parameters:
  ///   - indexPath: Path to store embeddings and metadata
  ///   - projectPaths: Optional list of project directories to index
  init(
    indexPath: String,
    projectPaths: [String] = []
  ) async throws {
    self.logger = Logger(label: "mcp-server")

    // Initialize server metadata
    self.server = Server(
      name: "code-search-mcp",
      version: "0.3.2",
      capabilities: .init(
        prompts: nil,
        resources: nil,
        tools: .init(listChanged: false)
      )
    )

    // Initialize services
    self.embeddingService = try await EmbeddingService(indexPath: indexPath)
    self.vectorSearchService = VectorSearchService(
      indexPath: indexPath, embeddingService: self.embeddingService)
    self.codeMetadataExtractor = CodeMetadataExtractor(indexPath: indexPath)
    self.projectIndexer = ProjectIndexer(
      indexPath: indexPath, embeddingService: self.embeddingService)

    // Read default project filter from environment
    self.defaultProjectFilter = ProcessInfo.processInfo.environment["CODE_SEARCH_PROJECT_NAME"]

    if let projectFilter = defaultProjectFilter {
      self.logger.info(
        "Default project filter from environment",
        metadata: [
          "project": "\(projectFilter)"
        ])
    }

    self.logger.info(
      "MCP server initialized",
      metadata: [
        "index_path": "\(indexPath)"
      ])

    // Read projects to index from environment (colon-separated list)
    var allProjectPaths = projectPaths
    if let envProjects = ProcessInfo.processInfo.environment["CODE_SEARCH_PROJECTS"] {
      let envPaths = envProjects.split(separator: ":").map(String.init)
      allProjectPaths.append(contentsOf: envPaths)
      self.logger.info(
        "Projects from environment",
        metadata: [
          "count": "\(envPaths.count)",
          "projects": "\(envProjects)"
        ])
    }

    // Index initial projects if provided
    if !allProjectPaths.isEmpty {
      self.logger.info(
        "Indexing projects",
        metadata: [
          "count": "\(allProjectPaths.count)"
        ])
      for projectPath in allProjectPaths {
        do {
          try await self.projectIndexer.indexProject(path: projectPath)
          self.logger.info(
            "Project indexed",
            metadata: [
              "path": "\(projectPath)"
            ])
        } catch {
          self.logger.warning(
            "Failed to index project",
            metadata: [
              "path": "\(projectPath)",
              "error": "\(error)",
            ])
        }
      }
    }
  }

  // MARK: - Server Lifecycle

  /// Run the MCP server with stdio transport.
  ///
  /// This method starts the server and processes incoming JSON-RPC requests
  /// from Claude via stdin/stdout.
  func run() async throws {
    // Register tool list handler
    await server.withMethodHandler(ListTools.self) { _ in
      await self.handleListTools()
    }

    // Register tool call handler
    await server.withMethodHandler(CallTool.self) { params in
      try await self.handleCallTool(params)
    }

    // Create and start stdio transport
    let transport = StdioTransport()
    try await server.start(transport: transport)

    // Wait for completion
    await server.waitUntilCompleted()
  }

  // MARK: - Tool Handlers

  /// Handle ListTools request - return all available tools.
  private func handleListTools() -> ListTools.Result {
    let tools = [
      // Semantic search tool
      Tool(
        name: "semantic_search",
        description:
          "Search for code patterns using semantic similarity with 384-dimensional embeddings",
        inputSchema: .object([
          "type": "object",
          "properties": .object([
            "query": .object([
              "type": "string",
              "description": "Natural language query or code snippet to search for",
            ]),
            "maxResults": .object([
              "type": "integer",
              "description": "Maximum number of results to return (default: 10)",
            ]),
            "projectFilter": .object([
              "type": "string",
              "description": "Optional project name to limit search scope",
            ]),
          ]),
          "required": .array([.string("query")]),
        ])
      ),

      // File context tool
      Tool(
        name: "file_context",
        description: "Extract code context from a specific file with line range",
        inputSchema: .object([
          "type": "object",
          "properties": .object([
            "filePath": .object([
              "type": "string",
              "description": "Path to the file (relative to project root)",
            ]),
            "startLine": .object([
              "type": "integer",
              "description": "Start line number (1-indexed)",
            ]),
            "endLine": .object([
              "type": "integer",
              "description": "End line number (1-indexed, inclusive)",
            ]),
            "contextLines": .object([
              "type": "integer",
              "description": "Number of context lines around range (default: 3)",
            ]),
          ]),
          "required": .array([.string("filePath")]),
        ])
      ),

      // Find related files tool
      Tool(
        name: "find_related",
        description: "Find files that import, depend on, or are related to the given file",
        inputSchema: .object([
          "type": "object",
          "properties": .object([
            "filePath": .object([
              "type": "string",
              "description": "Path to the file (relative to project root)",
            ]),
            "direction": .object([
              "type": "string",
              "description":
                "Direction of dependency search: 'imports' (files importing this), 'imports_from' (files this imports), or 'both' (default: both)",
            ]),
          ]),
          "required": .array([.string("filePath")]),
        ])
      ),

      // Index status tool
      Tool(
        name: "index_status",
        description: "Get metadata and statistics about indexed projects and the current index",
        inputSchema: .object([
          "type": "object",
          "properties": .object([:]),
        ])
      ),

      // Reload index tool
      Tool(
        name: "reload_index",
        description:
          "Reload (re-index) a specific project or all projects. Use when code has changed or index is stale.",
        inputSchema: .object([
          "type": "object",
          "properties": .object([
            "projectName": .object([
              "type": "string",
              "description": "Name of project to reload (omit to reload all projects)",
            ])
          ]),
        ])
      ),

      // Clear index tool
      Tool(
        name: "clear_index",
        description:
          "Clear all indexed data (destructive operation). Removes all chunks, embeddings, and project metadata. Cannot be undone.",
        inputSchema: .object([
          "type": "object",
          "properties": .object([
            "confirm": .object([
              "type": "boolean",
              "description": "Must be true to confirm destructive operation",
            ])
          ]),
          "required": .array([.string("confirm")]),
        ])
      ),

      // List projects tool
      Tool(
        name: "list_projects",
        description: "List all indexed projects with their metadata and statistics",
        inputSchema: .object([
          "type": "object",
          "properties": .object([:]),
        ])
      ),
    ]

    return ListTools.Result(tools: tools)
  }

  /// Handle CallTool requests - dispatch to appropriate service.
  ///
  /// - Parameter params: The tool call parameters from MCP
  /// - Returns: Tool execution result
  private func handleCallTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
    let logger = self.logger
    logger.debug(
      "Tool call received",
      metadata: [
        "tool": "\(params.name)"
      ])

    switch params.name {
    case "semantic_search":
      return try await handleSemanticSearch(params.arguments ?? [:])

    case "file_context":
      return try await handleFileContext(params.arguments ?? [:])

    case "find_related":
      return try await handleFindRelated(params.arguments ?? [:])

    case "index_status":
      return try await handleIndexStatus()

    case "reload_index":
      return try await handleReloadIndex(params.arguments ?? [:])

    case "clear_index":
      return try await handleClearIndex(params.arguments ?? [:])

    case "list_projects":
      return try await handleListProjects()

    default:
      logger.warning(
        "Unknown tool requested",
        metadata: [
          "tool": "\(params.name)"
        ])
      throw MCPError.invalidRequest("Unknown tool: \(params.name)")
    }
  }

  // MARK: - Tool Implementation Delegates

  /// Handle semantic_search tool call.
  private func handleSemanticSearch(_ args: [String: Value]) async throws -> CallTool.Result {
    guard let queryValue = args["query"] else {
      throw MCPError.invalidParams("Missing required parameter: query")
    }
    guard let query = queryValue.stringValue else {
      throw MCPError.invalidParams("Parameter 'query' must be a string")
    }

    let maxResults = args["maxResults"]?.intValue ?? 10
    // Use environment default if no explicit filter provided
    let projectFilter = args["projectFilter"]?.stringValue ?? self.defaultProjectFilter

    logger.debug(
      "Semantic search",
      metadata: [
        "query": "\(query)",
        "max_results": "\(maxResults)",
        "project_filter": "\(projectFilter ?? "none")",
      ])

    // Delegate to vector search service
    let results = try await vectorSearchService.search(
      query: query,
      maxResults: maxResults,
      projectFilter: projectFilter
    )

    return formatSearchResults(results)
  }

  /// Handle file_context tool call.
  private func handleFileContext(_ args: [String: Value]) async throws -> CallTool.Result {
    guard let filePathValue = args["filePath"] else {
      throw MCPError.invalidParams("Missing required parameter: filePath")
    }
    guard let filePath = filePathValue.stringValue else {
      throw MCPError.invalidParams("Parameter 'filePath' must be a string")
    }

    let startLine = args["startLine"]?.intValue
    let endLine = args["endLine"]?.intValue
    let contextLines = args["contextLines"]?.intValue ?? 3

    logger.debug(
      "File context requested",
      metadata: [
        "file_path": "\(filePath)",
        "start_line": "\(startLine ?? 0)",
        "end_line": "\(endLine ?? 0)",
        "context_lines": "\(contextLines)",
      ])

    // Delegate to project indexer for file context extraction
    let result = try await projectIndexer.extractFileContext(
      filePath: filePath,
      startLine: startLine,
      endLine: endLine,
      contextLines: contextLines
    )

    // Format the result
    let output = """
      File: \(result.filePath)
      Language: \(result.language)
      Lines: \(result.lineNumber)-\(result.endLineNumber)

      \(result.context)
      """

    logger.info(
      "File context extracted",
      metadata: [
        "file": "\(result.filePath)",
        "lines": "\(result.lineCount)",
      ])

    return CallTool.Result(
      content: [
        .text(output)
      ]
    )
  }

  /// Handle find_related tool call.
  private func handleFindRelated(_ args: [String: Value]) async throws -> CallTool.Result {
    guard let filePathValue = args["filePath"] else {
      throw MCPError.invalidParams("Missing required parameter: filePath")
    }
    guard let filePath = filePathValue.stringValue else {
      throw MCPError.invalidParams("Parameter 'filePath' must be a string")
    }

    let direction = args["direction"]?.stringValue ?? "both"

    logger.debug(
      "Finding related files",
      metadata: [
        "file_path": "\(filePath)",
        "direction": "\(direction)",
      ])

    // Delegate to metadata extractor
    let relatedFiles = try await codeMetadataExtractor.findRelatedFiles(
      filePath: filePath,
      direction: direction
    )

    let resultText = formatRelatedFiles(relatedFiles)
    return CallTool.Result(
      content: [
        .text(resultText)
      ]
    )
  }

  /// Handle index_status tool call.
  private func handleIndexStatus() async throws -> CallTool.Result {
    logger.debug("Index status requested")

    // Get metadata from services
    let embeddingStats = try await embeddingService.getCacheStats()

    // Build status report
    let statusLines: [String] = [
      "Index Status",
      "============",
      "",
      "Embedding Cache:",
      "  - Total embeddings: \(embeddingStats.totalEmbeddings)",
      "  - Cache hits: \(embeddingStats.cacheHits)",
      "  - Cache misses: \(embeddingStats.cacheMisses)",
      "  - Hit rate: \(String(format: "%.1f%%", embeddingStats.hitRate * 100))",
      "",
      "Configuration:",
      "  - Embedding model: BERT (384-dimensional)",
      "  - Search type: Vector-based semantic search only",
      "  - Index path: \(embeddingStats.indexPath)",
      "  - Status: Active",
    ]

    logger.info(
      "Index status retrieved",
      metadata: [
        "embeddings": "\(embeddingStats.totalEmbeddings)"
      ])

    return CallTool.Result(
      content: [
        .text(statusLines.joined(separator: "\n"))
      ]
    )
  }

  /// Handle reload_index tool call.
  private func handleReloadIndex(_ args: [String: Value]) async throws -> CallTool.Result {
    let projectName = args["projectName"]?.stringValue

    if let project = projectName {
      // Reload specific project
      logger.info("Reloading project", metadata: ["project": "\(project)"])

      do {
        try await projectIndexer.reindexProject(projectName: project)
        logger.info("Project reloaded successfully", metadata: ["project": "\(project)"])

        return CallTool.Result(
          content: [
            .text("Successfully reloaded project: \(project)")
          ]
        )
      } catch {
        logger.error(
          "Failed to reload project",
          metadata: [
            "project": "\(project)",
            "error": "\(error)",
          ])
        throw MCPError.internalError("Failed to reload project \(project): \(error)")
      }
    } else {
      // Reload all projects
      logger.info("Reloading all projects")

      do {
        try await projectIndexer.reindexAllProjects()
        logger.info("All projects reloaded successfully")

        return CallTool.Result(
          content: [
            .text("Successfully reloaded all projects")
          ]
        )
      } catch {
        logger.error("Failed to reload all projects", metadata: ["error": "\(error)"])
        throw MCPError.internalError("Failed to reload all projects: \(error)")
      }
    }
  }

  /// Handle clear_index tool call.
  private func handleClearIndex(_ args: [String: Value]) async throws -> CallTool.Result {
    guard let confirmValue = args["confirm"] else {
      throw MCPError.invalidParams("Missing required parameter: confirm")
    }
    guard let confirm = confirmValue.boolValue else {
      throw MCPError.invalidParams("Parameter 'confirm' must be a boolean")
    }

    guard confirm else {
      return CallTool.Result(
        content: [
          .text("Index clear cancelled. Set confirm=true to proceed with destructive operation.")
        ]
      )
    }

    logger.warning("Clearing all indexes - destructive operation")

    do {
      try await projectIndexer.clearAllIndexes()
      logger.info("All indexes cleared successfully")

      return CallTool.Result(
        content: [
          .text(
            "Successfully cleared all indexes. All chunks, embeddings, and project metadata have been removed."
          )
        ]
      )
    } catch {
      logger.error("Failed to clear indexes", metadata: ["error": "\(error)"])
      throw MCPError.internalError("Failed to clear indexes: \(error)")
    }
  }

  /// Handle list_projects tool call.
  private func handleListProjects() async throws -> CallTool.Result {
    logger.debug("Listing indexed projects")

    let projects = await projectIndexer.getIndexedProjects()

    guard !projects.isEmpty else {
      return CallTool.Result(
        content: [
          .text("No projects have been indexed yet.")
        ]
      )
    }

    var output = "Indexed Projects (\(projects.count)):\n\n"
    for project in projects {
      let languages = project.languages.sorted { $0.value > $1.value }
        .prefix(3)
        .map { "\($0.key) (\($0.value))" }
        .joined(separator: ", ")

      output += """
        Project: \(project.name)
        Path: \(project.rootPath)
        Status: \(project.indexStatus.rawValue)
        Files: \(project.fileCount)
        Chunks: \(project.chunkCount)
        Lines: \(project.lineCount)
        Languages: \(languages)
        Last Updated: \(formatDate(project.lastUpdatedAt))

        """
    }

    logger.info("Listed projects", metadata: ["count": "\(projects.count)"])

    return CallTool.Result(
      content: [
        .text(output)
      ]
    )
  }

  // MARK: - Result Formatting

  /// Format search results for MCP response.
  private func formatSearchResults(_ results: [SearchResult]) -> CallTool.Result {
    guard !results.isEmpty else {
      return CallTool.Result(
        content: [
          .text("No results found.")
        ]
      )
    }

    var output = "Found \(results.count) result(s):\n\n"
    for (index, result) in results.enumerated() {
      output += """
        Result \(index + 1):
        File: \(result.filePath)
        Line: \(result.lineNumber)
        Language: \(result.language)
        Relevance: \(String(format: "%.2f", result.relevanceScore))

        \(result.context)

        """
    }

    return CallTool.Result(
      content: [
        .text(output)
      ]
    )
  }

  /// Format related files for MCP response.
  private func formatRelatedFiles(_ files: [String]) -> String {
    guard !files.isEmpty else {
      return "No related files found."
    }

    var output = "Found \(files.count) related file(s):\n\n"
    for file in files {
      output += "- \(file)\n"
    }

    return output
  }

  /// Format date for display.
  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}
