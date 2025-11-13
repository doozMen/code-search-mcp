import Foundation
import Logging

/// Service responsible for extracting and maintaining code metadata.
///
/// Builds and maintains dependency graphs, import relationships,
/// and other metadata about code structure.
///
/// Responsibilities:
/// - Extract import/dependency statements
/// - Build bidirectional dependency graphs
/// - Track file relationships and dependencies
/// - Support dependency traversal queries
actor CodeMetadataExtractor: Sendable {
  // MARK: - Properties

  private let indexPath: String
  private let logger: Logger
  private let fileManager = FileManager.default

  /// Dependency graph cache directory
  private let dependencyGraphDir: String

  /// In-memory dependency graph cache: projectName -> graph
  private var graphCache: [String: DependencyGraph] = [:]

  // MARK: - Initialization

  init(indexPath: String) {
    self.indexPath = indexPath
    self.dependencyGraphDir = (indexPath as NSString).appendingPathComponent("dependencies")
    self.logger = Logger(label: "code-metadata-extractor")

    // Create dependency graph directory
    try? fileManager.createDirectory(
      atPath: dependencyGraphDir,
      withIntermediateDirectories: true,
      attributes: nil
    )
  }

  // MARK: - Public Interface

  /// Find files related to a given file through imports/dependencies.
  ///
  /// - Parameters:
  ///   - filePath: Path to the file
  ///   - direction: Direction of search ("imports", "imports_from", or "both")
  /// - Returns: Array of related file paths
  /// - Throws: If dependency lookup fails
  func findRelatedFiles(
    filePath: String,
    direction: String = "both"
  ) async throws -> [String] {
    logger.debug(
      "Finding related files",
      metadata: [
        "file": "\(filePath)",
        "direction": "\(direction)",
      ])

    // Extract project name from file path
    let projectName = extractProjectNameFromPath(filePath)

    // Load dependency graph for project
    let graph = try await getDependencyGraph(for: projectName)

    var relatedFiles: [String] = []

    // Collect related files based on direction
    switch direction.lowercased() {
    case "imports":
      // Files that this file imports
      relatedFiles = graph.getImports(from: filePath)

    case "imports_from", "imported_by":
      // Files that import this file
      relatedFiles = graph.getImporters(of: filePath)

    case "both":
      // Both directions
      let imports = graph.getImports(from: filePath)
      let importers = graph.getImporters(of: filePath)
      relatedFiles = Array(Set(imports + importers)).sorted()

    default:
      logger.warning("Unknown direction", metadata: ["direction": "\(direction)"])
      throw MetadataError.invalidFilePath("Unknown direction: \(direction)")
    }

    logger.info(
      "Found related files",
      metadata: [
        "file": "\(filePath)",
        "direction": "\(direction)",
        "count": "\(relatedFiles.count)",
      ])

    return relatedFiles
  }

  /// Extract project name from file path using simple heuristics.
  ///
  /// - Parameter filePath: Full file path
  /// - Returns: Best guess at project name
  private func extractProjectNameFromPath(_ filePath: String) -> String {
    let components = (filePath as NSString).pathComponents
    let projectMarkers = [
      "Package.swift",
      ".git",
      "package.json",
      "pom.xml",
      "build.gradle",
      "Cargo.toml",
    ]

    // Try to find project root by walking up the path
    for i in (0..<components.count).reversed() {
      let pathUpToIndex = Array(components[0...i]).joined(separator: "/")
      for marker in projectMarkers {
        let markerPath = (pathUpToIndex as NSString).appendingPathComponent(marker)
        if fileManager.fileExists(atPath: markerPath) {
          return components[i]
        }
      }
    }

    // Fallback: use the topmost directory after root
    if components.count > 1 {
      return components[1]
    }

    return "Unknown"
  }

  /// Extract dependencies from a code file.
  ///
  /// Parses import/require statements based on language.
  ///
  /// - Parameters:
  ///   - filePath: Path to file
  ///   - content: File content
  ///   - language: Programming language
  /// - Returns: Array of dependency information
  /// - Throws: If extraction fails
  func extractDependencies(
    from filePath: String,
    content: String,
    language: String
  ) async throws -> [Dependency] {
    logger.debug(
      "Extracting dependencies",
      metadata: [
        "file": "\(filePath)",
        "language": "\(language)",
      ])

    switch language.lowercased() {
    case "swift":
      return extractSwiftDependencies(from: content, filePath: filePath)
    case "python":
      return extractPythonDependencies(from: content, filePath: filePath)
    case "javascript", "typescript":
      return extractJavaScriptDependencies(from: content, filePath: filePath)
    case "java":
      return extractJavaDependencies(from: content, filePath: filePath)
    default:
      return []
    }
  }

  // MARK: - Language-Specific Dependency Extraction

  /// Extract dependencies from Swift code.
  ///
  /// Looks for:
  /// - import statements
  private func extractSwiftDependencies(from content: String, filePath: String) -> [Dependency] {
    // TODO #26: Use regex to find "import X" statements for Python/JS/Java
    // https://github.com/doozMen/code-search-mcp/issues/26
    // Pattern: ^import\s+(\w+)
    var dependencies: [Dependency] = []

    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
    for (lineNumber, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("import ") {
        let moduleName = String(trimmed.dropFirst("import ".count))
          .trimmingCharacters(in: .whitespaces)
        dependencies.append(
          Dependency(
            kind: "module",
            target: moduleName,
            sourceFile: filePath,
            lineNumber: lineNumber + 1
          ))
      }
    }

    return dependencies
  }

  /// Extract dependencies from Python code.
  ///
  /// Looks for:
  /// - import statements
  /// - from ... import statements
  private func extractPythonDependencies(from content: String, filePath: String) -> [Dependency] {
    // Not yet implemented - requires regex for import and from...import statements
    return []
  }

  /// Extract dependencies from JavaScript/TypeScript code.
  ///
  /// Looks for:
  /// - import statements
  /// - require() calls
  private func extractJavaScriptDependencies(from content: String, filePath: String) -> [Dependency]
  {
    // Not yet implemented - requires regex for import and require statements
    return []
  }

  /// Extract dependencies from Java code.
  ///
  /// Looks for:
  /// - import statements
  private func extractJavaDependencies(from content: String, filePath: String) -> [Dependency] {
    // Not yet implemented - requires regex for import statements
    return []
  }

  // MARK: - Dependency Graph Management

  /// Build and cache the dependency graph for a project.
  ///
  /// Creates a bidirectional dependency graph from extracted dependencies.
  ///
  /// - Parameters:
  ///   - projectName: Project to build graph for
  ///   - dependencies: Array of dependencies extracted from project files
  /// - Throws: If graph building or storage fails
  func buildDependencyGraph(for projectName: String, dependencies: [Dependency]) async throws {
    logger.info(
      "Building dependency graph",
      metadata: [
        "project": "\(projectName)",
        "dependency_count": "\(dependencies.count)",
      ])

    // Build forward and reverse maps
    var importsMap: [String: Set<String>] = [:]
    var importedByMap: [String: Set<String>] = [:]

    for dep in dependencies {
      // Forward: sourceFile imports target
      importsMap[dep.sourceFile, default: []].insert(dep.target)

      // Reverse: target is imported by sourceFile
      importedByMap[dep.target, default: []].insert(dep.sourceFile)
    }

    // Convert Sets to sorted Arrays for consistent serialization
    let graph = DependencyGraph(
      projectName: projectName,
      importsMap: importsMap.mapValues { Array($0).sorted() },
      importedByMap: importedByMap.mapValues { Array($0).sorted() },
      lastUpdated: Date()
    )

    // Store to disk
    try await storeDependencyGraph(graph)

    logger.info(
      "Dependency graph built",
      metadata: [
        "project": "\(projectName)",
        "files_with_imports": "\(graph.importsMap.count)",
        "files_imported": "\(graph.importedByMap.count)",
      ])
  }

  /// Get the dependency graph for a project.
  ///
  /// - Parameter projectName: Project name
  /// - Returns: Dependency graph (empty if not found)
  /// - Throws: If graph loading fails
  func getDependencyGraph(for projectName: String) async throws -> DependencyGraph {
    // Check cache first
    if let cached = graphCache[projectName] {
      logger.debug("Dependency graph cache hit", metadata: ["project": "\(projectName)"])
      return cached
    }

    // Load from disk
    return try await loadDependencyGraph(for: projectName)
  }

  /// Store dependency graph to disk.
  ///
  /// - Parameter graph: Dependency graph to store
  /// - Throws: If storage fails
  private func storeDependencyGraph(_ graph: DependencyGraph) async throws {
    let graphPath = dependencyGraphPath(for: graph.projectName)

    logger.debug(
      "Storing dependency graph",
      metadata: [
        "project": "\(graph.projectName)",
        "path": "\(graphPath)",
      ])

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(graph)
    try data.write(to: URL(fileURLWithPath: graphPath), options: .atomic)

    // Update cache
    graphCache[graph.projectName] = graph

    logger.info(
      "Dependency graph stored",
      metadata: [
        "project": "\(graph.projectName)"
      ])
  }

  /// Load dependency graph from disk.
  ///
  /// - Parameter projectName: Project name
  /// - Returns: Dependency graph (empty if not found)
  /// - Throws: If loading fails
  private func loadDependencyGraph(for projectName: String) async throws -> DependencyGraph {
    let graphPath = dependencyGraphPath(for: projectName)

    // Check if file exists
    guard fileManager.fileExists(atPath: graphPath) else {
      logger.debug(
        "Dependency graph not found, returning empty",
        metadata: [
          "project": "\(projectName)"
        ])
      return DependencyGraph(
        projectName: projectName,
        importsMap: [:],
        importedByMap: [:],
        lastUpdated: Date()
      )
    }

    logger.debug(
      "Loading dependency graph from disk",
      metadata: [
        "project": "\(projectName)",
        "path": "\(graphPath)",
      ])

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let data = try Data(contentsOf: URL(fileURLWithPath: graphPath))
    let graph = try decoder.decode(DependencyGraph.self, from: data)

    // Update cache
    graphCache[projectName] = graph

    logger.info(
      "Dependency graph loaded",
      metadata: [
        "project": "\(projectName)",
        "files_with_imports": "\(graph.importsMap.count)",
        "last_updated": "\(graph.lastUpdated)",
      ])

    return graph
  }

  /// Get the file path for a project's dependency graph.
  ///
  /// - Parameter projectName: Project name
  /// - Returns: Full path to dependency graph file
  private func dependencyGraphPath(for projectName: String) -> String {
    (dependencyGraphDir as NSString).appendingPathComponent("\(projectName).graph.json")
  }

  /// Clear dependency graph for a project (both cache and disk).
  ///
  /// - Parameter projectName: Project name
  /// - Throws: If deletion fails
  func clearDependencyGraph(for projectName: String) async throws {
    graphCache.removeValue(forKey: projectName)

    let graphPath = dependencyGraphPath(for: projectName)
    if fileManager.fileExists(atPath: graphPath) {
      try fileManager.removeItem(atPath: graphPath)
      logger.info("Dependency graph cleared", metadata: ["project": "\(projectName)"])
    }
  }

  // MARK: - Reverse Dependency Lookup

  /// Find all files that import/reference a given file.
  ///
  /// - Parameter filePath: File path
  /// - Returns: Array of files that import this file
  /// - Throws: If lookup fails
  private func getImporters(of filePath: String) async throws -> [String] {
    throw CodeSearchError.notYetImplemented(
      feature: "Reverse dependency lookup (importers)",
      issueNumber: nil
    )
  }

  /// Find all files this file imports/references.
  ///
  /// - Parameter filePath: File path
  /// - Returns: Array of files imported by this file
  /// - Throws: If lookup fails
  private func getImports(from filePath: String) async throws -> [String] {
    throw CodeSearchError.notYetImplemented(
      feature: "Forward dependency lookup (imports)",
      issueNumber: nil
    )
  }
}

// MARK: - Data Models

/// Represents a dependency relationship between code elements.
struct Dependency: Sendable, Codable {
  /// Type of dependency: "module", "class", "function", "file"
  let kind: String

  /// Name or path of the dependency target
  let target: String

  /// File containing the import/dependency statement
  let sourceFile: String

  /// Line number where dependency is declared
  let lineNumber: Int
}

/// Represents the complete dependency graph for a project.
struct DependencyGraph: Sendable, Codable {
  /// Project name
  let projectName: String

  /// Map from file to files it imports
  let importsMap: [String: [String]]

  /// Map from file to files that import it
  let importedByMap: [String: [String]]

  /// Timestamp of last update
  let lastUpdated: Date

  enum CodingKeys: String, CodingKey {
    case projectName = "project_name"
    case importsMap = "imports_map"
    case importedByMap = "imported_by_map"
    case lastUpdated = "last_updated"
  }

  /// Get files imported by a file
  func getImports(from file: String) -> [String] {
    importsMap[file] ?? []
  }

  /// Get files that import a given file
  func getImporters(of file: String) -> [String] {
    importedByMap[file] ?? []
  }

  /// Get all files that transitively import a given file
  func getTransitiveImporters(of file: String) -> [String] {
    var result: Set<String> = []
    var queue = [file]

    while !queue.isEmpty {
      let current = queue.removeFirst()
      let importers = getImporters(of: current)

      for importer in importers where !result.contains(importer) {
        result.insert(importer)
        queue.append(importer)
      }
    }

    return Array(result).sorted()
  }
}

// MARK: - Error Types

enum MetadataError: Error, LocalizedError {
  case dependencyExtractionFailed(String)
  case graphBuildingFailed(Error)
  case invalidFilePath(String)

  var errorDescription: String? {
    switch self {
    case .dependencyExtractionFailed(let reason):
      return "Dependency extraction failed: \(reason)"
    case .graphBuildingFailed(let error):
      return "Failed to build dependency graph: \(error)"
    case .invalidFilePath(let path):
      return "Invalid file path: \(path)"
    }
  }
}
