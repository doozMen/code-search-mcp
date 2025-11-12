import Foundation
import Logging

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

  init(indexPath: String) {
    self.indexPath = indexPath
    self.logger = Logger(label: "project-indexer")

    // Ensure index directory exists
    try? fileManager.createDirectory(
      atPath: indexPath,
      withIntermediateDirectories: true,
      attributes: nil
    )
  }

  // MARK: - Public Interface

  /// Index an entire project directory.
  ///
  /// Recursively scans the directory for supported source files,
  /// extracts code chunks, and generates embeddings.
  ///
  /// - Parameter path: Path to the project root directory
  /// - Throws: If directory access or indexing fails
  func indexProject(path: String) async throws {
    let projectName = (path as NSString).lastPathComponent

    logger.info(
      "Starting project indexing",
      metadata: [
        "project": "\(projectName)",
        "path": "\(path)",
      ])

    // Validate path
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue
    else {
      throw IndexingError.invalidProjectPath(path)
    }

    // Recursively find all source files
    let sourceFiles = try findSourceFiles(in: path)
    logger.info(
      "Found source files",
      metadata: [
        "count": "\(sourceFiles.count)"
      ])

    // Extract code chunks from each file
    var totalChunks = 0
    for filePath in sourceFiles {
      do {
        let chunks = try extractCodeChunks(from: filePath, projectName: projectName)
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

    logger.info(
      "Project indexing complete",
      metadata: [
        "project": "\(projectName)",
        "total_chunks": "\(totalChunks)",
      ])
  }

  // MARK: - Private Methods

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
    // TODO: Add language-specific AST-based chunking for better structure detection
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
}

// MARK: - Error Types

enum IndexingError: Error, LocalizedError {
  case invalidProjectPath(String)
  case directoryEnumerationFailed(String)
  case fileReadingFailed(String, Error)

  var errorDescription: String? {
    switch self {
    case .invalidProjectPath(let path):
      return "Invalid project path: \(path)"
    case .directoryEnumerationFailed(let directory):
      return "Failed to enumerate directory: \(directory)"
    case .fileReadingFailed(let file, let error):
      return "Failed to read file \(file): \(error)"
    }
  }
}
