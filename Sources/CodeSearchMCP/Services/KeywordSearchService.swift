import Foundation
import Logging

/// Service responsible for keyword-based code search.
///
/// Enables fast symbol, function, and class name searching
/// using indexed keyword metadata and file content scanning.
///
/// Responsibilities:
/// - Index symbols and identifiers from code
/// - Support case-sensitive and case-insensitive search
/// - Track symbol definitions and references
/// - Return results with file locations and line numbers
actor KeywordSearchService: Sendable {
  // MARK: - Properties

  private let indexPath: String
  private let logger: Logger
  private let fileManager = FileManager.default

  /// Symbol index cache directory
  private let symbolIndexDir: String

  /// In-memory symbol index cache: projectName -> symbolName -> locations
  private var symbolIndexCache: [String: [String: [SymbolLocation]]] = [:]

  // MARK: - Initialization

  init(indexPath: String) {
    self.indexPath = indexPath
    self.symbolIndexDir = (indexPath as NSString).appendingPathComponent("symbols")
    self.logger = Logger(label: "keyword-search-service")

    // Create symbol index directory
    try? fileManager.createDirectory(
      atPath: symbolIndexDir,
      withIntermediateDirectories: true,
      attributes: nil
    )
  }

  // MARK: - Public Interface

  /// Search for a symbol by keyword.
  ///
  /// Returns locations where the symbol is defined or referenced.
  ///
  /// - Parameters:
  ///   - symbol: Symbol name to search for
  ///   - includeReferences: If true, include all references (not just definitions)
  ///   - projectFilter: Optional project name to limit scope
  /// - Returns: Array of SearchResult objects with matching locations
  /// - Throws: If search fails
  func search(
    symbol: String,
    includeReferences: Bool = false,
    projectFilter: String? = nil
  ) async throws -> [SearchResult] {
    logger.debug(
      "Keyword search",
      metadata: [
        "symbol": "\(symbol)",
        "include_references": "\(includeReferences)",
      ])

    throw CodeSearchError.notYetImplemented(
      feature: "Symbol keyword search with index querying",
      issueNumber: nil
    )
  }

  // MARK: - Symbol Indexing

  /// Index symbols in a code chunk.
  ///
  /// Extracts identifiers like function names, class names, and variables.
  ///
  /// - Parameters:
  ///   - chunk: Code chunk to index
  ///   - language: Programming language of the code
  /// - Throws: If indexing fails
  func indexSymbols(in chunk: CodeChunk, language: String) async throws {
    logger.debug(
      "Indexing symbols",
      metadata: [
        "file": "\(chunk.filePath)",
        "language": "\(language)",
      ])

    throw CodeSearchError.notYetImplemented(
      feature: "Symbol indexing with language-specific parsing",
      issueNumber: nil
    )
  }

  // MARK: - Symbol Extraction (Language-Specific)

  /// Extract symbols from code based on language.
  ///
  /// - Parameters:
  ///   - content: Source code content
  ///   - language: Programming language
  /// - Returns: Array of extracted symbols with metadata
  private func extractSymbols(content: String, language: String) -> [Symbol] {
    switch language.lowercased() {
    case "swift":
      return extractSwiftSymbols(content)
    case "python":
      return extractPythonSymbols(content)
    case "javascript", "typescript":
      return extractJavaScriptSymbols(content)
    case "java":
      return extractJavaSymbols(content)
    default:
      return extractGenericSymbols(content)
    }
  }

  /// Extract symbols from Swift code.
  private func extractSwiftSymbols(_ content: String) -> [Symbol] {
    // Not yet implemented - requires regex pattern matching
    // for func, class, struct, enum, protocol definitions
    return []
  }

  /// Extract symbols from Python code.
  private func extractPythonSymbols(_ content: String) -> [Symbol] {
    // Not yet implemented - requires regex for def and class definitions
    return []
  }

  /// Extract symbols from JavaScript/TypeScript code.
  private func extractJavaScriptSymbols(_ content: String) -> [Symbol] {
    // Not yet implemented - requires regex for function, class, const declarations
    return []
  }

  /// Extract symbols from Java code.
  private func extractJavaSymbols(_ content: String) -> [Symbol] {
    // Not yet implemented - requires regex for public methods and classes
    return []
  }

  /// Extract symbols using generic patterns.
  ///
  /// Falls back for unsupported languages.
  private func extractGenericSymbols(_ content: String) -> [Symbol] {
    // Not yet implemented - requires generic identifier pattern matching
    return []
  }

  // MARK: - Index Storage

  /// Store symbol index to disk for a specific project.
  ///
  /// - Parameters:
  ///   - symbols: Dictionary of symbol name to locations
  ///   - projectName: Name of the project
  /// - Throws: If storage fails
  private func storeSymbolIndex(_ symbols: [String: [SymbolLocation]], for projectName: String)
    async throws
  {
    let indexPath = symbolIndexPath(for: projectName)

    logger.debug(
      "Storing symbol index",
      metadata: [
        "project": "\(projectName)",
        "path": "\(indexPath)",
        "symbol_count": "\(symbols.count)",
      ])

    let index = SymbolIndex(
      projectName: projectName,
      symbols: symbols,
      lastUpdated: Date()
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(index)
    try data.write(to: URL(fileURLWithPath: indexPath), options: .atomic)

    // Update in-memory cache
    symbolIndexCache[projectName] = symbols

    logger.info(
      "Symbol index stored",
      metadata: [
        "project": "\(projectName)",
        "symbols": "\(symbols.count)",
      ])
  }

  /// Load symbol index from disk for a specific project.
  ///
  /// - Parameter projectName: Name of the project
  /// - Returns: Dictionary of symbol name to locations, or empty if not found
  /// - Throws: If loading fails
  private func loadSymbolIndex(for projectName: String) async throws -> [String: [SymbolLocation]] {
    // Check in-memory cache first
    if let cached = symbolIndexCache[projectName] {
      logger.debug("Symbol index cache hit", metadata: ["project": "\(projectName)"])
      return cached
    }

    let indexPath = symbolIndexPath(for: projectName)

    // Check if file exists
    guard fileManager.fileExists(atPath: indexPath) else {
      logger.debug(
        "Symbol index not found, returning empty",
        metadata: [
          "project": "\(projectName)"
        ])
      return [:]
    }

    logger.debug(
      "Loading symbol index from disk",
      metadata: [
        "project": "\(projectName)",
        "path": "\(indexPath)",
      ])

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let data = try Data(contentsOf: URL(fileURLWithPath: indexPath))
    let index = try decoder.decode(SymbolIndex.self, from: data)

    // Update cache
    symbolIndexCache[projectName] = index.symbols

    logger.info(
      "Symbol index loaded",
      metadata: [
        "project": "\(projectName)",
        "symbols": "\(index.symbols.count)",
        "last_updated": "\(index.lastUpdated)",
      ])

    return index.symbols
  }

  /// Get the file path for a project's symbol index.
  ///
  /// - Parameter projectName: Project name
  /// - Returns: Full path to symbol index file
  private func symbolIndexPath(for projectName: String) -> String {
    (symbolIndexDir as NSString).appendingPathComponent("\(projectName).symbols.json")
  }

  /// Clear symbol index for a project (both cache and disk).
  ///
  /// - Parameter projectName: Project name
  /// - Throws: If deletion fails
  func clearSymbolIndex(for projectName: String) async throws {
    symbolIndexCache.removeValue(forKey: projectName)

    let indexPath = symbolIndexPath(for: projectName)
    if fileManager.fileExists(atPath: indexPath) {
      try fileManager.removeItem(atPath: indexPath)
      logger.info("Symbol index cleared", metadata: ["project": "\(projectName)"])
    }
  }
}

// MARK: - Data Models

/// Represents a symbol (function, class, variable, etc.) extracted from code.
struct Symbol: Sendable, Codable {
  /// Name of the symbol
  let name: String

  /// Type of symbol: "function", "class", "variable", "type", etc.
  let kind: String

  /// Line number where symbol is defined
  let lineNumber: Int

  /// Column where symbol starts
  let column: Int

  /// Optional documentation or docstring
  let documentation: String?
}

/// Represents a location where a symbol is defined or referenced.
struct SymbolLocation: Sendable, Codable, Hashable {
  /// Path to file containing symbol
  let filePath: String

  /// Line number
  let lineNumber: Int

  /// Is this a definition (true) or reference (false)
  let isDefinition: Bool

  /// Code context around the symbol
  let context: String
}

/// Persisted symbol index for a project.
struct SymbolIndex: Sendable, Codable {
  /// Project name
  let projectName: String

  /// Map from symbol name to locations
  let symbols: [String: [SymbolLocation]]

  /// Timestamp of last update
  let lastUpdated: Date

  enum CodingKeys: String, CodingKey {
    case projectName = "project_name"
    case symbols
    case lastUpdated = "last_updated"
  }
}

// MARK: - Error Types

enum KeywordSearchError: Error, LocalizedError {
  case symbolIndexingFailed(String)
  case indexLoadingFailed(Error)
  case invalidSymbolName(String)

  var errorDescription: String? {
    switch self {
    case .symbolIndexingFailed(let reason):
      return "Symbol indexing failed: \(reason)"
    case .indexLoadingFailed(let error):
      return "Failed to load symbol index: \(error)"
    case .invalidSymbolName(let name):
      return "Invalid symbol name: \(name)"
    }
  }
}
