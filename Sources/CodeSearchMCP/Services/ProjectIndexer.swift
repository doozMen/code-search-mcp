import Foundation
import Logging
import SwiftEmbeddings

/// Service responsible for crawling project directories and extracting code chunks.
///
/// Responsibilities:
/// - Scan project directories for source files
/// - Parse files to extract logical code chunks (functions, classes, blocks)
/// - Build initial metadata about project structure
/// - Trigger embedding generation for discovered chunks
actor ProjectIndexer: Sendable {
  // MARK: - Properties

  private let indexPath: String
  private let logger: Logger
  private let fileManager = FileManager.default
  private let embeddingService: EmbeddingService

  /// Registry tracking all indexed projects
  private var projectRegistry: ProjectRegistry

  /// File extensions to index by language
  private let supportedExtensions: [String: String] = [
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

  // MARK: - Initialization

  init(indexPath: String, embeddingService: EmbeddingService) {
    self.indexPath = indexPath
    self.embeddingService = embeddingService
    self.logger = Logger(label: "project-indexer")

    // Ensure index directory exists
    try? fileManager.createDirectory(
      atPath: indexPath,
      withIntermediateDirectories: true,
      attributes: nil
    )

    // Load existing project registry
    let registryPath = (indexPath as NSString).appendingPathComponent("project_registry.json")
    if fileManager.fileExists(atPath: registryPath),
      let data = try? Data(contentsOf: URL(fileURLWithPath: registryPath))
    {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      if let registry = try? decoder.decode(ProjectRegistry.self, from: data) {
        self.projectRegistry = registry
        logger.info("Loaded project registry", metadata: ["project_count": "\(registry.count)"])
      } else {
        self.projectRegistry = ProjectRegistry()
        logger.info("Initialized empty project registry")
      }
    } else {
      self.projectRegistry = ProjectRegistry()
      logger.info("Initialized empty project registry")
    }
  }

  // MARK: - Public Interface

  /// Index an entire project directory.
  ///
  /// Automatically detects if the directory contains multiple sub-projects with
  /// project markers (.git, Package.swift, package.json, etc.) and indexes each
  /// separately. If no sub-projects are found, indexes as a single project.
  ///
  /// - Parameter path: Path to the project root directory
  /// - Throws: If directory access or indexing fails
  func indexProject(path: String) async throws {
    // Validate path
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue
    else {
      throw IndexingError.invalidProjectPath(path)
    }

    // Detect subprojects in the directory
    let subprojects = try await detectSubprojects(in: path)

    if subprojects.isEmpty {
      // No subprojects found - index as a single project
      try await indexSingleProject(path: path)
    } else {
      // Multiple subprojects found - index each separately
      logger.info(
        "Detected multiple subprojects",
        metadata: [
          "parent_directory": "\((path as NSString).lastPathComponent)",
          "subproject_count": "\(subprojects.count)",
          "subprojects": "\(subprojects.map { $0.name }.joined(separator: ", "))",
        ])

      for subproject in subprojects {
        do {
          try await indexSingleProject(path: subproject.path)
        } catch {
          logger.error(
            "Failed to index subproject",
            metadata: [
              "subproject": "\(subproject.name)",
              "path": "\(subproject.path)",
              "error": "\(error)",
            ])
          // Continue with other subprojects
        }
      }

      logger.info(
        "Completed indexing all subprojects",
        metadata: [
          "parent_directory": "\((path as NSString).lastPathComponent)",
          "successful_count": "\(subprojects.count)",
        ])
    }
  }

  /// Index a single project directory without subproject detection.
  ///
  /// This is the core indexing logic that processes all files in a single project.
  ///
  /// - Parameter path: Path to the project root directory
  /// - Throws: If directory access or indexing fails
  private func indexSingleProject(path: String) async throws {
    let projectName = (path as NSString).lastPathComponent

    logger.info(
      "Starting project indexing",
      metadata: [
        "project": "\(projectName)",
        "path": "\(path)",
      ])

    // Recursively find all source files
    let sourceFiles = try findSourceFiles(in: path)
    logger.info(
      "Found source files",
      metadata: [
        "project": "\(projectName)",
        "count": "\(sourceFiles.count)",
      ])

    // Extract code chunks from each file
    var totalChunks = 0
    var chunksWithEmbeddings: [CodeChunk] = []

    for filePath in sourceFiles {
      do {
        var chunks = try extractCodeChunks(from: filePath, projectName: projectName)

        // Generate embeddings for each chunk
        for i in 0..<chunks.count {
          do {
            let embedding = try await embeddingService.generateEmbedding(for: chunks[i].content)
            chunks[i] = chunks[i].withEmbedding(embedding)

            logger.debug(
              "Generated embedding for chunk",
              metadata: [
                "file": "\((filePath as NSString).lastPathComponent)",
                "chunk_id": "\(chunks[i].id)",
                "embedding_size": "\(embedding.count)",
              ])
          } catch {
            logger.warning(
              "Failed to generate embedding for chunk, skipping",
              metadata: [
                "file": "\(filePath)",
                "chunk_id": "\(chunks[i].id)",
                "error": "\(error)",
              ])
            // Continue without embedding for this chunk
          }
        }

        chunksWithEmbeddings.append(contentsOf: chunks)
        totalChunks += chunks.count

        logger.debug(
          "Extracted chunks",
          metadata: [
            "file": "\((filePath as NSString).lastPathComponent)",
            "chunk_count": "\(chunks.count)",
          ])
      } catch {
        logger.warning(
          "Failed to extract chunks from file",
          metadata: [
            "file": "\(filePath)",
            "error": "\(error)",
          ])
      }
    }

    // Save chunks to disk for vector search
    try await saveChunks(chunksWithEmbeddings, projectName: projectName)

    // Update project metadata in registry
    let languageCounts = chunksWithEmbeddings.reduce(into: [String: Int]()) { counts, chunk in
      counts[chunk.language, default: 0] += 1
    }
    let totalLines = chunksWithEmbeddings.reduce(0) { $0 + $1.lineCount }

    let metadata = ProjectMetadata(
      name: projectName,
      rootPath: path,
      fileCount: sourceFiles.count,
      chunkCount: chunksWithEmbeddings.count,
      lineCount: totalLines,
      languages: languageCounts,
      indexStatus: .complete
    )
    projectRegistry.register(metadata)
    try saveProjectRegistry()

    logger.info(
      "Project indexing complete",
      metadata: [
        "project": "\(projectName)",
        "total_chunks": "\(totalChunks)",
      ])
  }

  // MARK: - Index Management

  /// Reload (re-index) a specific project by name.
  ///
  /// Clears existing chunks and embeddings for the project, then re-indexes from scratch.
  ///
  /// - Parameter projectName: Name of project to reload
  /// - Throws: IndexingError if project not found or reindexing fails
  func reindexProject(projectName: String) async throws {
    guard let metadata = projectRegistry.project(named: projectName) else {
      logger.warning("Project not found in registry", metadata: ["project": "\(projectName)"])
      throw IndexingError.projectNotFound(projectName)
    }

    logger.info("Reindexing project", metadata: ["project": "\(projectName)"])

    // Clear existing chunks for this project
    let chunksDir = (indexPath as NSString).appendingPathComponent("chunks/\(projectName)")
    if fileManager.fileExists(atPath: chunksDir) {
      try fileManager.removeItem(atPath: chunksDir)
      logger.debug("Cleared existing chunks", metadata: ["project": "\(projectName)"])
    }

    // Re-index the project
    try await indexProject(path: metadata.rootPath)
  }

  /// Reload all indexed projects.
  ///
  /// Re-indexes every project currently in the registry.
  ///
  /// - Throws: IndexingError if any project fails to reindex
  func reindexAllProjects() async throws {
    let projects = projectRegistry.allProjects()

    logger.info("Reindexing all projects", metadata: ["count": "\(projects.count)"])

    for project in projects {
      do {
        try await reindexProject(projectName: project.name)
      } catch {
        logger.error(
          "Failed to reindex project",
          metadata: [
            "project": "\(project.name)",
            "error": "\(error)",
          ])
        throw error
      }
    }

    logger.info("All projects reindexed successfully")
  }

  /// Clear all indexed data (destructive operation).
  ///
  /// Removes all chunks, embeddings, and project metadata. This cannot be undone.
  ///
  /// - Throws: IndexingError if clearing fails
  func clearAllIndexes() async throws {
    logger.warning("Clearing all indexes - this cannot be undone")

    // Clear chunks directory
    let chunksDir = (indexPath as NSString).appendingPathComponent("chunks")
    if fileManager.fileExists(atPath: chunksDir) {
      try fileManager.removeItem(atPath: chunksDir)
      logger.debug("Cleared chunks directory")
    }

    // Clear project registry
    projectRegistry = ProjectRegistry()
    try saveProjectRegistry()

    // Clear embeddings cache (delegate to embedding service)
    try await embeddingService.clearCache()

    logger.info("All indexes cleared successfully")
  }

  /// Get list of all indexed projects.
  ///
  /// - Returns: Array of project metadata
  func getIndexedProjects() -> [ProjectMetadata] {
    projectRegistry.allProjects()
  }

  // MARK: - Auto-Migration

  /// Detect legacy indexes that may need migration.
  ///
  /// Identifies projects with unusually large file counts (>5,000) which may indicate
  /// indexing of parent directories instead of individual projects.
  ///
  /// - Returns: Array of project metadata for potential legacy indexes
  func detectLegacyIndexes() -> [ProjectMetadata] {
    let legacyThreshold = 5_000
    return projectRegistry.allProjects().filter { $0.fileCount > legacyThreshold }
  }

  /// Migrate a single project by clearing its old chunks and re-indexing.
  ///
  /// This is useful for background migration jobs. Clears old chunks, unregisters
  /// the project from the registry, and re-indexes with current detection logic.
  ///
  /// - Parameters:
  ///   - projectName: Name of the project to migrate
  ///   - rootPath: Root path of the project
  /// - Returns: Tuple of (fileCount, chunkCount) after re-indexing
  /// - Throws: IndexingError if migration fails
  func migrateProject(name projectName: String, rootPath: String) async throws -> (
    fileCount: Int, chunkCount: Int
  ) {
    logger.info(
      "Migrating project",
      metadata: [
        "project": "\(projectName)",
        "path": "\(rootPath)",
      ])

    // Clear old chunks
    let chunksDir = (indexPath as NSString).appendingPathComponent("chunks/\(projectName)")
    if fileManager.fileExists(atPath: chunksDir) {
      try fileManager.removeItem(atPath: chunksDir)
      logger.debug("Cleared old chunks", metadata: ["project": "\(projectName)"])
    }

    // Unregister old project
    projectRegistry.unregister(projectName)
    try saveProjectRegistry()

    // Re-index with new detection logic
    try await indexProject(path: rootPath)

    // Get new project stats
    if let newProject = projectRegistry.allProjects().first(where: { $0.name == projectName }) {
      logger.info(
        "Project migration complete",
        metadata: [
          "project": "\(projectName)",
          "files": "\(newProject.fileCount)",
          "chunks": "\(newProject.chunkCount)",
        ])
      return (fileCount: newProject.fileCount, chunkCount: newProject.chunkCount)
    }

    return (fileCount: 0, chunkCount: 0)
  }

  /// Automatically migrate legacy indexes by re-indexing with subproject detection.
  ///
  /// This is called silently at startup to fix indexes created before subproject detection
  /// was implemented. Projects are only migrated if their rootPath still exists.
  ///
  /// - Throws: IndexingError if migration fails
  func autoMigrateLegacyIndexes() async throws {
    let legacyProjects = detectLegacyIndexes()

    guard !legacyProjects.isEmpty else {
      logger.debug("No legacy indexes detected")
      return
    }

    logger.info(
      "Detected legacy indexes, starting automatic migration",
      metadata: [
        "legacy_count": "\(legacyProjects.count)",
        "projects": "\(legacyProjects.map { $0.name }.joined(separator: ", "))",
      ])

    for project in legacyProjects {
      // Verify root path still exists
      guard fileManager.fileExists(atPath: project.rootPath) else {
        logger.warning(
          "Skipping migration for project with inaccessible path",
          metadata: [
            "project": "\(project.name)",
            "path": "\(project.rootPath)",
          ])
        continue
      }

      logger.info(
        "Migrating legacy index",
        metadata: [
          "project": "\(project.name)",
          "old_file_count": "\(project.fileCount)",
          "path": "\(project.rootPath)",
        ])

      do {
        // Clear old chunks
        let chunksDir = (indexPath as NSString).appendingPathComponent("chunks/\(project.name)")
        if fileManager.fileExists(atPath: chunksDir) {
          try fileManager.removeItem(atPath: chunksDir)
          logger.debug("Cleared old chunks", metadata: ["project": "\(project.name)"])
        }

        // Unregister old project
        projectRegistry.unregister(project.name)
        try saveProjectRegistry()

        // Re-index with new detection logic
        try await indexProject(path: project.rootPath)

        logger.info(
          "Successfully migrated legacy index",
          metadata: [
            "project": "\(project.name)",
            "path": "\(project.rootPath)",
          ])
      } catch {
        logger.error(
          "Failed to migrate legacy index",
          metadata: [
            "project": "\(project.name)",
            "path": "\(project.rootPath)",
            "error": "\(error)",
          ])
        // Continue with other projects
      }
    }

    logger.info(
      "Legacy index migration complete",
      metadata: ["migrated_count": "\(legacyProjects.count)"])
  }

  // MARK: - Private Methods

  /// Detect subprojects within a directory.
  ///
  /// Scans immediate subdirectories for project markers (.git, Package.swift, etc.)
  /// and returns a list of detected subprojects. Special handling for Swift packages:
  /// if Package.swift is found, parses products and returns them as subprojects.
  ///
  /// - Parameter directory: Parent directory to scan
  /// - Returns: Array of detected subprojects (empty if none found or if directory itself is a simple project)
  /// - Throws: If directory enumeration or Swift package parsing fails
  private func detectSubprojects(in directory: String) async throws -> [Subproject] {
    let projectMarkers: Set<String> = [
      ".git",
      "Package.swift",
      "package.json",
      "pom.xml",
      "build.gradle",
      "Cargo.toml",
      "pyproject.toml",
      "setup.py",
      "go.mod",
      "Gemfile",
      "composer.json",
    ]

    // Special handling for Swift packages - parse products as subprojects
    let packageSwiftPath = (directory as NSString).appendingPathComponent("Package.swift")
    if fileManager.fileExists(atPath: packageSwiftPath) {
      logger.debug(
        "Directory contains Package.swift, parsing Swift package products",
        metadata: ["path": "\(directory)"])

      do {
        let parser = SwiftPackageParser()
        let products = try await parser.parsePackage(at: directory)

        // If package has multiple products, treat each as a subproject
        if products.count > 1 {
          logger.info(
            "Detected Swift package with multiple products",
            metadata: [
              "path": "\(directory)",
              "product_count": "\(products.count)",
              "products": "\(products.map { $0.name }.joined(separator: ", "))",
            ])
          return products
        } else {
          // Single product package - index as single project
          logger.debug(
            "Swift package has single product, indexing as single project",
            metadata: ["path": "\(directory)"])
          return []
        }
      } catch {
        logger.warning(
          "Failed to parse Swift package, treating as single project",
          metadata: [
            "path": "\(directory)",
            "error": "\(error)",
          ])
        return []
      }
    }

    // Check if directory itself is a project (non-Swift)
    for marker in projectMarkers where marker != "Package.swift" {
      let markerPath = (directory as NSString).appendingPathComponent(marker)
      if fileManager.fileExists(atPath: markerPath) {
        // This directory is itself a project, don't look for subprojects
        logger.debug(
          "Directory is a project itself (found \(marker))",
          metadata: ["path": "\(directory)"])
        return []
      }
    }

    // Scan immediate subdirectories for project markers
    var subprojects: [Subproject] = []

    guard
      let contents = try? fileManager.contentsOfDirectory(atPath: directory)
    else {
      return []
    }

    for item in contents {
      // Skip hidden directories and common non-project directories
      if item.hasPrefix(".") || isExcludedPath(item) {
        continue
      }

      let itemPath = (directory as NSString).appendingPathComponent(item)
      var isDirectory: ObjCBool = false

      guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        continue
      }

      // Check if this subdirectory contains any project markers
      for marker in projectMarkers {
        let markerPath = (itemPath as NSString).appendingPathComponent(marker)
        if fileManager.fileExists(atPath: markerPath) {
          subprojects.append(Subproject(name: item, path: itemPath))
          logger.debug(
            "Detected subproject",
            metadata: [
              "name": "\(item)",
              "path": "\(itemPath)",
              "marker": "\(marker)",
            ])
          break  // Found a marker, no need to check others for this directory
        }
      }
    }

    return subprojects
  }

  /// Recursively find all supported source files in a directory.
  ///
  /// - Parameter directory: Directory to search
  /// - Returns: Array of file paths to source files
  /// - Throws: If directory enumeration fails
  private func findSourceFiles(in directory: String) throws -> [String] {
    var sourceFiles: [String] = []

    guard let enumerator = fileManager.enumerator(atPath: directory) else {
      throw IndexingError.directoryEnumerationFailed(directory)
    }

    for case let file as String in enumerator {
      let fullPath = (directory as NSString).appendingPathComponent(file)
      let pathExtension = (file as NSString).pathExtension.lowercased()

      // Skip hidden files and known exclusions
      if file.hasPrefix(".") || isExcludedPath(file) {
        if file.hasPrefix(".") {
          enumerator.skipDescendants()
        }
        continue
      }

      // Check if this is a supported file
      if supportedExtensions.keys.contains(pathExtension) {
        sourceFiles.append(fullPath)
      }
    }

    return sourceFiles
  }

  /// Check if a path should be excluded from indexing.
  ///
  /// - Parameter path: File or directory path
  /// - Returns: True if path should be excluded
  private func isExcludedPath(_ path: String) -> Bool {
    let excludedPatterns = [
      "node_modules",
      ".git",
      ".build",
      "build",
      "dist",
      "target",
      ".venv",
      "venv",
      "__pycache__",
      ".pytest_cache",
      "coverage",
      ".DS_Store",
    ]

    return excludedPatterns.contains { pattern in
      path.contains("/\(pattern)/") || path.hasPrefix(pattern)
    }
  }

  /// Extract code chunks from a single file.
  ///
  /// Parses the file to identify logical chunks (functions, classes, blocks)
  /// and creates CodeChunk objects with metadata.
  ///
  /// - Parameters:
  ///   - filePath: Path to the source file
  ///   - projectName: Name of the project this file belongs to
  /// - Returns: Array of extracted code chunks
  /// - Throws: If file reading or parsing fails
  private func extractCodeChunks(from filePath: String, projectName: String) throws -> [CodeChunk] {
    let content = try String(contentsOfFile: filePath, encoding: .utf8)
    let pathExtension = (filePath as NSString).pathExtension.lowercased()
    let language = supportedExtensions[pathExtension] ?? "Unknown"

    // For now, implement simple line-based chunking
    // TODO #25: Add language-specific AST-based chunking for better structure detection
    // https://github.com/doozMen/code-search-mcp/issues/25
    let chunks = createLineBasedChunks(
      content: content,
      filePath: filePath,
      projectName: projectName,
      language: language
    )

    logger.debug(
      "Extracted chunks",
      metadata: [
        "file": "\((filePath as NSString).lastPathComponent)",
        "chunk_count": "\(chunks.count)",
      ])

    return chunks
  }

  /// Create chunks using simple line-based approach.
  ///
  /// Splits file into fixed-size chunks with overlap for context.
  /// This is a fallback approach until AST-based parsing is implemented.
  ///
  /// - Parameters:
  ///   - content: File content
  ///   - filePath: File path
  ///   - projectName: Project name
  ///   - language: Programming language
  /// - Returns: Array of code chunks
  private func createLineBasedChunks(
    content: String,
    filePath: String,
    projectName: String,
    language: String
  ) -> [CodeChunk] {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
      .map { String($0) }

    // Configuration for chunking
    let chunkSize = 50  // Lines per chunk
    let overlapSize = 10  // Lines of overlap between chunks

    var chunks: [CodeChunk] = []
    var startLine = 0

    while startLine < lines.count {
      let endLine = min(startLine + chunkSize, lines.count)
      let chunkLines = Array(lines[startLine..<endLine])
      let chunkContent = chunkLines.joined(separator: "\n")

      // Skip empty or whitespace-only chunks
      if !chunkContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let chunk = CodeChunk(
          projectName: projectName,
          filePath: filePath,
          language: language,
          startLine: startLine + 1,  // 1-indexed
          endLine: endLine,
          content: chunkContent,
          chunkType: inferChunkType(from: chunkContent, language: language)
        )
        chunks.append(chunk)
      }

      // Move to next chunk with overlap
      startLine += chunkSize - overlapSize
    }

    return chunks
  }

  /// Infer chunk type from content using simple heuristics.
  ///
  /// - Parameters:
  ///   - content: Code content
  ///   - language: Programming language
  /// - Returns: Chunk type string
  private func inferChunkType(from content: String, language: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

    switch language.lowercased() {
    case "swift":
      if trimmed.contains("func ") { return "function" }
      if trimmed.contains("class ") { return "class" }
      if trimmed.contains("struct ") { return "struct" }
      if trimmed.contains("enum ") { return "enum" }
      if trimmed.contains("protocol ") { return "protocol" }
    case "python":
      if trimmed.contains("def ") { return "function" }
      if trimmed.contains("class ") { return "class" }
    case "javascript", "typescript":
      if trimmed.contains("function ") { return "function" }
      if trimmed.contains("class ") { return "class" }
      if trimmed.contains("const ") || trimmed.contains("let ") { return "declaration" }
    case "java":
      if trimmed.contains("public class ") || trimmed.contains("class ") { return "class" }
      if trimmed.contains("public void ") || trimmed.contains("private void ") { return "method" }
    default:
      break
    }

    return "block"
  }

  // MARK: - File Context Extraction

  /// Extract code context from a file with optional line range.
  ///
  /// Reads the specified file and returns the requested line range with surrounding context.
  /// If no line range is specified, returns the entire file.
  ///
  /// - Parameters:
  ///   - filePath: Path to the file (absolute path or path to validate)
  ///   - startLine: Optional starting line (1-indexed)
  ///   - endLine: Optional ending line (1-indexed, inclusive)
  ///   - contextLines: Number of context lines before and after range (default: 3)
  /// - Returns: SearchResult containing the extracted context
  /// - Throws: IndexingError if file doesn't exist or read fails
  func extractFileContext(
    filePath: String,
    projectName: String? = nil,
    startLine: Int? = nil,
    endLine: Int? = nil,
    contextLines: Int = 3
  ) async throws -> SearchResult {
    logger.debug(
      "Extracting file context",
      metadata: [
        "file": "\(filePath)",
        "project": "\(projectName ?? "auto-detect")",
        "start": "\(startLine ?? 0)",
        "end": "\(endLine ?? 0)",
        "context": "\(contextLines)",
      ])

    // Resolve file path (supports both absolute and relative paths)
    let resolvedPath: String
    let detectedProjectName: String

    if filePath.hasPrefix("/") {
      // Absolute path - use as-is
      resolvedPath = filePath
      detectedProjectName = extractProjectName(from: filePath)

      logger.debug("Using absolute path", metadata: ["path": "\(resolvedPath)"])
    } else {
      // Relative path - resolve against project root
      if let project = projectName {
        // Project specified - resolve against its root
        guard let projectMeta = projectRegistry.project(named: project) else {
          throw IndexingError.invalidProjectPath(
            "Project '\(project)' not found. Use list_projects to see available projects.")
        }

        resolvedPath = (projectMeta.rootPath as NSString).appendingPathComponent(filePath)
        detectedProjectName = project

        logger.debug(
          "Resolved relative path",
          metadata: [
            "relative": "\(filePath)",
            "project": "\(project)",
            "absolute": "\(resolvedPath)",
          ])
      } else {
        // No project specified - search all projects for a match
        let allProjects = projectRegistry.allProjects()
        var matches: [(project: String, path: String)] = []

        for projectMeta in allProjects {
          let candidatePath = (projectMeta.rootPath as NSString).appendingPathComponent(filePath)
          if fileManager.fileExists(atPath: candidatePath) {
            matches.append((projectMeta.name, candidatePath))
          }
        }

        if matches.isEmpty {
          throw IndexingError.invalidProjectPath(
            "File '\(filePath)' not found in any indexed project. Provide projectName parameter or use an absolute path.")
        } else if matches.count > 1 {
          let projectList = matches.map { $0.project }.joined(separator: ", ")
          throw IndexingError.invalidProjectPath(
            "File '\(filePath)' found in multiple projects: \(projectList). Specify projectName parameter to disambiguate.")
        } else {
          resolvedPath = matches[0].path
          detectedProjectName = matches[0].project

          logger.debug(
            "Auto-detected project",
            metadata: [
              "relative": "\(filePath)",
              "project": "\(detectedProjectName)",
              "absolute": "\(resolvedPath)",
            ])
        }
      }
    }

    // Validate file exists
    guard fileManager.fileExists(atPath: resolvedPath) else {
      logger.warning("File not found", metadata: ["path": "\(resolvedPath)"])
      throw IndexingError.invalidProjectPath(resolvedPath)
    }

    // Read file content
    let content: String
    do {
      content = try String(contentsOfFile: resolvedPath, encoding: .utf8)
    } catch {
      logger.error("Failed to read file", metadata: ["path": "\(resolvedPath)", "error": "\(error)"])
      throw IndexingError.fileReadingFailed(resolvedPath, error)
    }

    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
      .map { String($0) }
    let totalLines = lines.count

    // Calculate actual range with context
    let requestedStart = startLine ?? 1
    let requestedEnd = endLine ?? totalLines

    // Validate requested range
    guard requestedStart >= 1, requestedEnd >= requestedStart, requestedEnd <= totalLines else {
      logger.warning(
        "Invalid line range",
        metadata: [
          "start": "\(requestedStart)",
          "end": "\(requestedEnd)",
          "total": "\(totalLines)",
        ])
      throw IndexingError.invalidProjectPath(
        "Invalid line range: \(requestedStart)-\(requestedEnd)")
    }

    // Calculate range with context (0-indexed)
    let actualStart = max(0, requestedStart - 1 - contextLines)
    let actualEnd = min(totalLines, requestedEnd + contextLines)

    // Extract lines with line numbers
    let extractedLines = lines[actualStart..<actualEnd].enumerated().map { idx, line in
      let lineNum = actualStart + idx + 1
      let marker = (lineNum >= requestedStart && lineNum <= requestedEnd) ? "→" : " "
      return "\(marker) \(String(format: "%4d", lineNum)): \(line)"
    }

    let extractedContent = extractedLines.joined(separator: "\n")

    // Detect language from resolved path
    let language = detectLanguage(from: resolvedPath)

    logger.debug(
      "File context extracted",
      metadata: [
        "total_lines": "\(totalLines)",
        "extracted_lines": "\(extractedLines.count)",
        "language": "\(language)",
        "project": "\(detectedProjectName)",
      ])

    // Return as SearchResult with resolved absolute path
    return SearchResult.fileContext(
      projectName: detectedProjectName,
      filePath: resolvedPath,
      language: language,
      startLine: actualStart + 1,
      endLine: actualEnd,
      content: extractedContent
    )
  }

  /// Detect programming language from file extension.
  ///
  /// - Parameter filePath: Path to file
  /// - Returns: Language name or "Unknown"
  private func detectLanguage(from filePath: String) -> String {
    let ext = (filePath as NSString).pathExtension.lowercased()
    return supportedExtensions[ext] ?? "Unknown"
  }

  /// Extract project name from file path.
  ///
  /// Uses heuristics to find project root based on common markers.
  ///
  /// - Parameter filePath: Full file path
  /// - Returns: Best guess at project name
  private func extractProjectName(from filePath: String) -> String {
    // Look for common project root indicators
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

  // MARK: - Chunk Persistence

  /// Save code chunks to disk for vector search.
  ///
  /// Stores chunks in project-specific directory for efficient loading.
  ///
  /// - Parameters:
  ///   - chunks: Code chunks to save
  ///   - projectName: Project name for organization
  /// - Throws: If file writing fails
  private func saveChunks(_ chunks: [CodeChunk], projectName: String) async throws {
    let chunksDir = (indexPath as NSString).appendingPathComponent("chunks")
    let projectChunksDir = (chunksDir as NSString).appendingPathComponent(projectName)

    // Create project chunks directory
    try fileManager.createDirectory(
      atPath: projectChunksDir,
      withIntermediateDirectories: true,
      attributes: nil
    )

    // Save each chunk as a separate JSON file
    for chunk in chunks {
      let chunkFileName = "\(chunk.id).json"
      let chunkFilePath = (projectChunksDir as NSString).appendingPathComponent(chunkFileName)

      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(chunk)
        try data.write(to: URL(fileURLWithPath: chunkFilePath))
      } catch {
        logger.warning(
          "Failed to save chunk",
          metadata: [
            "chunk_id": "\(chunk.id)",
            "error": "\(error)",
          ])
        throw IndexingError.fileReadingFailed(chunkFilePath, error)
      }
    }

    logger.info(
      "Saved chunks to disk",
      metadata: [
        "project": "\(projectName)",
        "chunk_count": "\(chunks.count)",
        "directory": "\(projectChunksDir)",
      ])
  }

  // MARK: - Registry Persistence

  /// Save project registry to disk.
  ///
  /// - Throws: If file writing fails
  private func saveProjectRegistry() throws {
    let registryPath = (indexPath as NSString).appendingPathComponent("project_registry.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(projectRegistry)
    try data.write(to: URL(fileURLWithPath: registryPath))

    logger.debug("Project registry saved", metadata: ["path": "\(registryPath)"])
  }
}

// MARK: - Supporting Types

/// Type of monorepo or project structure detected.
enum MonorepoType: String, Sendable, Codable {
  case swiftPackageManager
  case npmWorkspaces
  case goWorkspace
  case gradleMultiModule
  case pythonPoetry
}

/// Represents a detected subproject within a parent directory.
struct Subproject: Sendable {
  /// Name of the subproject (directory name or product name)
  let name: String

  /// Full path to the subproject directory
  let path: String

  /// Type of monorepo or project structure (optional)
  let type: MonorepoType?

  /// Whether this is a root-level project in a monorepo
  let isRoot: Bool

  init(name: String, path: String, type: MonorepoType? = nil, isRoot: Bool = false) {
    self.name = name
    self.path = path
    self.type = type
    self.isRoot = isRoot
  }
}

// MARK: - Error Types

enum IndexingError: Error, LocalizedError {
  case invalidProjectPath(String)
  case directoryEnumerationFailed(String)
  case fileReadingFailed(String, Error)
  case projectNotFound(String)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .invalidProjectPath(let path):
      return "Invalid project path: \(path)"
    case .directoryEnumerationFailed(let directory):
      return "Failed to enumerate directory: \(directory)"
    case .fileReadingFailed(let file, let error):
      return "Failed to read file \(file): \(error)"
    case .projectNotFound(let name):
      return "Project not found in registry: \(name)"
    case .cancelled:
      return "Indexing operation was cancelled"
    }
  }
}
