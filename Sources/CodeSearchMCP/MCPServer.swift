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
  private let keywordSearchService: KeywordSearchService
  private let codeMetadataExtractor: CodeMetadataExtractor

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
      version: "0.1.0",
      capabilities: .init(
        prompts: nil,
        resources: nil,
        tools: .init(listChanged: false)
      )
    )

    // Initialize services
    self.projectIndexer = ProjectIndexer(indexPath: indexPath)
    self.embeddingService = EmbeddingService(indexPath: indexPath)
    self.vectorSearchService = VectorSearchService(indexPath: indexPath)
    self.keywordSearchService = KeywordSearchService(indexPath: indexPath)
    self.codeMetadataExtractor = CodeMetadataExtractor(indexPath: indexPath)

    self.logger.info(
      "MCP server initialized",
      metadata: [
        "index_path": "\(indexPath)"
      ])

    // Index initial projects if provided
    if !projectPaths.isEmpty {
      self.logger.info(
        "Indexing projects",
        metadata: [
          "count": "\(projectPaths.count)"
        ])
      for projectPath in projectPaths {
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

      // Keyword search tool
      Tool(
        name: "keyword_search",
        description:
          "Search for symbols, function names, or class definitions using keyword matching",
        inputSchema: .object([
          "type": "object",
          "properties": .object([
            "symbol": .object([
              "type": "string",
              "description": "Symbol name, function name, or class name to search for",
            ]),
            "includeReferences": .object([
              "type": "boolean",
              "description": "Include all references to this symbol (default: false)",
            ]),
            "projectFilter": .object([
              "type": "string",
              "description": "Optional project name to limit search scope",
            ]),
          ]),
          "required": .array([.string("symbol")]),
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

    case "keyword_search":
      return try await handleKeywordSearch(params.arguments ?? [:])

    case "file_context":
      return try await handleFileContext(params.arguments ?? [:])

    case "find_related":
      return try await handleFindRelated(params.arguments ?? [:])

    case "index_status":
      return try await handleIndexStatus()

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
    let projectFilter = args["projectFilter"]?.stringValue

    logger.debug(
      "Semantic search",
      metadata: [
        "query": "\(query)",
        "max_results": "\(maxResults)",
      ])

    // Delegate to vector search service
    let results = try await vectorSearchService.search(
      query: query,
      maxResults: maxResults,
      projectFilter: projectFilter
    )

    return formatSearchResults(results)
  }

  /// Handle keyword_search tool call.
  private func handleKeywordSearch(_ args: [String: Value]) async throws -> CallTool.Result {
    guard let symbolValue = args["symbol"] else {
      throw MCPError.invalidParams("Missing required parameter: symbol")
    }
    guard let symbol = symbolValue.stringValue else {
      throw MCPError.invalidParams("Parameter 'symbol' must be a string")
    }

    let includeReferences = args["includeReferences"]?.boolValue ?? false
    let projectFilter = args["projectFilter"]?.stringValue

    logger.debug(
      "Keyword search",
      metadata: [
        "symbol": "\(symbol)",
        "include_references": "\(includeReferences)",
      ])

    // Delegate to keyword search service
    let results = try await keywordSearchService.search(
      symbol: symbol,
      includeReferences: includeReferences,
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
      ])

    // TODO: Implement file context extraction
    let contextText = "File context extraction not yet implemented"

    return CallTool.Result(
      content: [
        .text(contextText)
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

    let statusText = """
      Index Status
      ============

      Indexed Projects: 0
      Total Code Chunks: 0
      Total Files: 0
      Embedding Model: BERT (384-dimensional)
      Index Path: ~/.cache/code-search-mcp

      Status: Initializing
      """

    return CallTool.Result(
      content: [
        .text(statusText)
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
}
