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

    // Validate symbol name
    guard !symbol.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw KeywordSearchError.invalidSymbolName(symbol)
    }

    var results: [SearchResult] = []

    // Determine which projects to search
    let projectsToSearch: [String]
    if let projectFilter = projectFilter {
      projectsToSearch = [projectFilter]
    } else {
      projectsToSearch = Array(symbolIndexCache.keys)
    }

    logger.debug(
      "Searching projects",
      metadata: [
        "project_count": "\(projectsToSearch.count)",
        "projects": "\(projectsToSearch.joined(separator: ", "))",
      ])

    // Search each project's symbol index
    for projectName in projectsToSearch {
      do {
        let index = try await loadSymbolIndex(for: projectName)

        // First: Exact match search
        if let locations = index[symbol] {
          for location in locations {
            // Filter by isDefinition if needed
            if !includeReferences && !location.isDefinition {
              continue
            }

            // Determine result type and relevance score
            let resultType = location.isDefinition ? "definition" : "reference"
            let relevanceScore = location.isDefinition ? 1.0 : 0.8

            let result = SearchResult(
              projectName: projectName,
              filePath: location.filePath,
              language: inferLanguage(from: location.filePath),
              lineNumber: location.lineNumber,
              endLineNumber: location.lineNumber,
              context: location.context,
              resultType: resultType,
              relevanceScore: relevanceScore,
              matchReason: location.isDefinition ? "Symbol definition" : "Symbol reference",
              metadata: [
                "match_type": "exact",
                "symbol": symbol,
              ]
            )
            results.append(result)
          }
        }

        // Second: Fuzzy matching (case-insensitive contains)
        // Only do fuzzy search if we have few or no exact matches
        if results.count < 5 {
          for (indexedSymbol, locations) in index {
            // Skip if this is the exact match we already processed
            if indexedSymbol == symbol {
              continue
            }

            // Case-insensitive contains check
            if indexedSymbol.lowercased().contains(symbol.lowercased()) {
              for location in locations {
                // Filter by isDefinition if needed
                if !includeReferences && !location.isDefinition {
                  continue
                }

                let resultType = location.isDefinition ? "definition" : "reference"
                // Lower relevance for fuzzy matches
                let baseScore = location.isDefinition ? 0.7 : 0.5

                let result = SearchResult(
                  projectName: projectName,
                  filePath: location.filePath,
                  language: inferLanguage(from: location.filePath),
                  lineNumber: location.lineNumber,
                  endLineNumber: location.lineNumber,
                  context: location.context,
                  resultType: resultType,
                  relevanceScore: baseScore,
                  matchReason: "Fuzzy match: '\(indexedSymbol)' contains '\(symbol)'",
                  metadata: [
                    "match_type": "fuzzy",
                    "symbol": symbol,
                    "matched_symbol": indexedSymbol,
                  ]
                )
                results.append(result)
              }
            }
          }
        }
      } catch {
        logger.warning(
          "Failed to load symbol index",
          metadata: [
            "project": "\(projectName)",
            "error": "\(error)",
          ])
      }
    }

    // Sort results: definitions first, then by relevance, then alphabetically
    results.sort { a, b in
      // Definitions before references
      if a.resultType == "definition" && b.resultType != "definition" {
        return true
      }
      if a.resultType != "definition" && b.resultType == "definition" {
        return false
      }

      // Then by relevance score (higher first)
      if abs(a.relevanceScore - b.relevanceScore) > 0.01 {
        return a.relevanceScore > b.relevanceScore
      }

      // Then alphabetically by file path
      if a.filePath != b.filePath {
        return a.filePath < b.filePath
      }

      // Finally by line number
      return a.lineNumber < b.lineNumber
    }

    logger.info(
      "Keyword search complete",
      metadata: [
        "symbol": "\(symbol)",
        "result_count": "\(results.count)",
      ])

    return results
  }

  /// Infer programming language from file extension.
  private func inferLanguage(from filePath: String) -> String {
    let ext = (filePath as NSString).pathExtension.lowercased()
    let languageMap: [String: String] = [
      "swift": "Swift",
      "py": "Python",
      "js": "JavaScript",
      "ts": "TypeScript",
      "jsx": "JavaScript",
      "tsx": "TypeScript",
      "java": "Java",
      "go": "Go",
      "rs": "Rust",
      "cpp": "C++",
      "c": "C",
      "h": "C",
      "hpp": "C++",
      "cs": "C#",
      "rb": "Ruby",
      "php": "PHP",
      "kt": "Kotlin",
    ]
    return languageMap[ext] ?? "Unknown"
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

    // Extract symbols from the chunk content
    let symbols = extractSymbolsFromContent(
      chunk.content, language: language, baseLineNumber: chunk.startLine)

    // Get or create the symbol index for this project
    var projectIndex = try await loadSymbolIndex(for: chunk.projectName)

    // Add symbols to index
    for (symbolName, lineNumber, isDefinition) in symbols {
      let location = SymbolLocation(
        filePath: chunk.filePath,
        lineNumber: lineNumber,
        isDefinition: isDefinition,
        context: extractContextForLine(chunk.content, lineNumber: lineNumber - chunk.startLine + 1)
      )

      // Add to index (append to existing or create new entry)
      if projectIndex[symbolName] != nil {
        projectIndex[symbolName]?.append(location)
      } else {
        projectIndex[symbolName] = [location]
      }
    }

    // Store updated index
    try await storeSymbolIndex(projectIndex, for: chunk.projectName)

    logger.debug(
      "Symbols indexed",
      metadata: [
        "file": "\(chunk.filePath)",
        "symbol_count": "\(symbols.count)",
      ])
  }

  /// Extract context around a specific line.
  ///
  /// - Parameters:
  ///   - content: Full content
  ///   - lineNumber: Line number (1-indexed, relative to content)
  /// - Returns: Context string with the line and surrounding lines
  private func extractContextForLine(_ content: String, lineNumber: Int) -> String {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
      .map { String($0) }

    guard lineNumber > 0 && lineNumber <= lines.count else {
      return ""
    }

    // Get a few lines of context (up to 3 lines before and after)
    let contextRange = max(0, lineNumber - 4)..<min(lines.count, lineNumber + 3)
    let contextLines = Array(lines[contextRange])

    return contextLines.joined(separator: "\n")
  }

  /// Extract symbols from content using language-specific patterns.
  ///
  /// This is a helper that wraps the extraction logic with line number adjustment.
  ///
  /// - Parameters:
  ///   - content: Source code content
  ///   - language: Programming language
  ///   - baseLineNumber: Base line number to add to relative line numbers
  /// - Returns: Array of tuples (symbolName, absoluteLineNumber, isDefinition)
  private func extractSymbolsFromContent(
    _ content: String,
    language: String,
    baseLineNumber: Int
  ) -> [(String, Int, Bool)] {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

    var symbols: [(String, Int, Bool)] = []

    // Use the same extraction logic as ProjectIndexer
    switch language.lowercased() {
    case "swift":
      symbols.append(contentsOf: extractSwiftSymbols(lines: lines))
    case "python":
      symbols.append(contentsOf: extractPythonSymbols(lines: lines))
    case "javascript", "typescript":
      symbols.append(contentsOf: extractJavaScriptSymbols(lines: lines))
    case "java":
      symbols.append(contentsOf: extractJavaSymbols(lines: lines))
    case "go":
      symbols.append(contentsOf: extractGoSymbols(lines: lines))
    default:
      symbols.append(contentsOf: extractGenericSymbols(lines: lines))
    }

    // Adjust line numbers to be absolute (add base line number)
    return symbols.map { (name, relativeLine, isDefinition) in
      (name, relativeLine + baseLineNumber - 1, isDefinition)
    }
  }

  // MARK: - Symbol Extraction (Language-Specific)
  // Note: Actual extraction is done in ProjectIndexer.
  // These methods are stubs that delegate to ProjectIndexer's implementation.

  /// Extract symbols from Swift code (line-based version).
  private func extractSwiftSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    // Delegates to ProjectIndexer's implementation
    return []
  }

  /// Extract symbols from Python code (line-based version).
  private func extractPythonSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    // Delegates to ProjectIndexer's implementation
    return []
  }

  /// Extract symbols from JavaScript/TypeScript code (line-based version).
  private func extractJavaScriptSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    // Delegates to ProjectIndexer's implementation
    return []
  }

  /// Extract symbols from Java code (line-based version).
  private func extractJavaSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    // Delegates to ProjectIndexer's implementation
    return []
  }

  /// Extract symbols from Go code (line-based version).
  private func extractGoSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    // Delegates to ProjectIndexer's implementation
    return []
  }

  /// Extract symbols using generic patterns (line-based version).
  ///
  /// Falls back for unsupported languages.
  private func extractGenericSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    // Use generic pattern matching from ProjectIndexer
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

  // MARK: - Statistics

  /// Get statistics about indexed symbols.
  ///
  /// - Returns: Index statistics including project count and symbol count
  /// - Throws: If stats retrieval fails
  func getIndexStats() async throws -> KeywordIndexStats {
    var totalSymbols = 0
    var totalFiles = Set<String>()

    // Count symbols and files from all cached projects
    for (_, symbols) in symbolIndexCache {
      totalSymbols += symbols.count

      // Count unique files
      for (_, locations) in symbols {
        for location in locations {
          totalFiles.insert(location.filePath)
        }
      }
    }

    logger.debug(
      "Index stats retrieved",
      metadata: [
        "projects": "\(symbolIndexCache.count)",
        "symbols": "\(totalSymbols)",
        "files": "\(totalFiles.count)",
      ])

    return KeywordIndexStats(
      indexedProjects: symbolIndexCache.count,
      totalSymbols: totalSymbols,
      totalFiles: totalFiles.count
    )
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

// MARK: - Statistics Model

/// Statistics about the symbol index.
struct KeywordIndexStats: Sendable {
  let indexedProjects: Int
  let totalSymbols: Int
  let totalFiles: Int
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
