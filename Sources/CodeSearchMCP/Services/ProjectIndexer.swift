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
  private let keywordSearchService: KeywordSearchService?

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

  init(indexPath: String, keywordSearchService: KeywordSearchService? = nil) {
    self.indexPath = indexPath
    self.keywordSearchService = keywordSearchService
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

        // Index symbols from chunks if service available
        if let keywordService = keywordSearchService {
          for chunk in chunks {
            try await keywordService.indexSymbols(in: chunk, language: chunk.language)
          }
        }

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

  // MARK: - Symbol Extraction

  /// Extract symbols from code content for indexing.
  ///
  /// Uses regex patterns to identify definitions like functions, classes, methods, etc.
  ///
  /// - Parameters:
  ///   - content: Source code content
  ///   - language: Programming language
  ///   - filePath: Path to the file (for context)
  /// - Returns: Array of symbol names found in the code
  func extractSymbols(from content: String, language: String, filePath: String) -> [(
    String, Int, Bool
  )] {
    // Returns tuples of (symbolName, lineNumber, isDefinition)
    var symbols: [(String, Int, Bool)] = []
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

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

    return symbols
  }

  /// Extract Swift symbols using regex patterns.
  private func extractSwiftSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    var symbols: [(String, Int, Bool)] = []

    let patterns = [
      // class, struct, protocol, enum, actor (definitions)
      (
        pattern:
          #"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:final\s+)?(?:class|struct|protocol|enum|actor)\s+(\w+)"#,
        isDefinition: true
      ),
      // functions (definitions)
      (
        pattern:
          #"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:static\s+)?func\s+(\w+)"#,
        isDefinition: true
      ),
      // var/let properties (definitions)
      (
        pattern:
          #"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:static\s+)?(?:var|let)\s+(\w+)"#,
        isDefinition: true
      ),
      // init methods
      (
        pattern: #"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?init\s*\("#,
        isDefinition: true
      ),
    ]

    for (lineIndex, line) in lines.enumerated() {
      let lineString = String(line)
      for (patternString, isDefinition) in patterns {
        if let regex = try? NSRegularExpression(pattern: patternString, options: []),
          let match = regex.firstMatch(
            in: lineString, options: [], range: NSRange(lineString.startIndex..., in: lineString))
        {
          if match.numberOfRanges > 1 {
            let range = match.range(at: 1)
            if let swiftRange = Range(range, in: lineString) {
              let symbolName = String(lineString[swiftRange])
              symbols.append((symbolName, lineIndex + 1, isDefinition))
            }
          } else if lineString.contains("init") {
            // Special case for init
            symbols.append(("init", lineIndex + 1, true))
          }
        }
      }
    }

    return symbols
  }

  /// Extract Python symbols using regex patterns.
  private func extractPythonSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    var symbols: [(String, Int, Bool)] = []

    let patterns = [
      // class definitions
      (pattern: #"^\s*class\s+(\w+)"#, isDefinition: true),
      // function definitions
      (pattern: #"^\s*def\s+(\w+)"#, isDefinition: true),
      // async function definitions
      (pattern: #"^\s*async\s+def\s+(\w+)"#, isDefinition: true),
    ]

    for (lineIndex, line) in lines.enumerated() {
      let lineString = String(line)
      for (patternString, isDefinition) in patterns {
        if let regex = try? NSRegularExpression(pattern: patternString, options: []),
          let match = regex.firstMatch(
            in: lineString, options: [], range: NSRange(lineString.startIndex..., in: lineString))
        {
          if match.numberOfRanges > 1 {
            let range = match.range(at: 1)
            if let swiftRange = Range(range, in: lineString) {
              let symbolName = String(lineString[swiftRange])
              symbols.append((symbolName, lineIndex + 1, isDefinition))
            }
          }
        }
      }
    }

    return symbols
  }

  /// Extract JavaScript/TypeScript symbols using regex patterns.
  private func extractJavaScriptSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    var symbols: [(String, Int, Bool)] = []

    let patterns = [
      // class definitions
      (pattern: #"^\s*(?:export\s+)?(?:default\s+)?class\s+(\w+)"#, isDefinition: true),
      // function declarations
      (pattern: #"^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)"#, isDefinition: true),
      // const/let function expressions
      (pattern: #"^\s*(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s+)?\("#, isDefinition: true),
      // arrow functions
      (pattern: #"^\s*(?:export\s+)?const\s+(\w+)\s*=\s*\([^)]*\)\s*=>"#, isDefinition: true),
      // method definitions in classes
      (pattern: #"^\s*(?:async\s+)?(\w+)\s*\([^)]*\)\s*\{"#, isDefinition: true),
    ]

    for (lineIndex, line) in lines.enumerated() {
      let lineString = String(line)
      for (patternString, isDefinition) in patterns {
        if let regex = try? NSRegularExpression(pattern: patternString, options: []),
          let match = regex.firstMatch(
            in: lineString, options: [], range: NSRange(lineString.startIndex..., in: lineString))
        {
          if match.numberOfRanges > 1 {
            let range = match.range(at: 1)
            if let swiftRange = Range(range, in: lineString) {
              let symbolName = String(lineString[swiftRange])
              symbols.append((symbolName, lineIndex + 1, isDefinition))
            }
          }
        }
      }
    }

    return symbols
  }

  /// Extract Java symbols using regex patterns.
  private func extractJavaSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    var symbols: [(String, Int, Bool)] = []

    let patterns = [
      // class/interface definitions
      (
        pattern:
          #"^\s*(?:public\s+|private\s+|protected\s+)?(?:abstract\s+)?(?:class|interface|enum)\s+(\w+)"#,
        isDefinition: true
      ),
      // method definitions
      (
        pattern:
          #"^\s*(?:public\s+|private\s+|protected\s+)?(?:static\s+)?(?:\w+)\s+(\w+)\s*\([^)]*\)"#,
        isDefinition: true
      ),
    ]

    for (lineIndex, line) in lines.enumerated() {
      let lineString = String(line)
      for (patternString, isDefinition) in patterns {
        if let regex = try? NSRegularExpression(pattern: patternString, options: []),
          let match = regex.firstMatch(
            in: lineString, options: [], range: NSRange(lineString.startIndex..., in: lineString))
        {
          if match.numberOfRanges > 1 {
            let range = match.range(at: 1)
            if let swiftRange = Range(range, in: lineString) {
              let symbolName = String(lineString[swiftRange])
              symbols.append((symbolName, lineIndex + 1, isDefinition))
            }
          }
        }
      }
    }

    return symbols
  }

  /// Extract Go symbols using regex patterns.
  private func extractGoSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    var symbols: [(String, Int, Bool)] = []

    let patterns = [
      // function definitions
      (pattern: #"^\s*func\s+(?:\([^)]+\)\s+)?(\w+)"#, isDefinition: true),
      // type definitions
      (pattern: #"^\s*type\s+(\w+)\s+(?:struct|interface)"#, isDefinition: true),
      // const/var declarations
      (pattern: #"^\s*(?:const|var)\s+(\w+)"#, isDefinition: true),
    ]

    for (lineIndex, line) in lines.enumerated() {
      let lineString = String(line)
      for (patternString, isDefinition) in patterns {
        if let regex = try? NSRegularExpression(pattern: patternString, options: []),
          let match = regex.firstMatch(
            in: lineString, options: [], range: NSRange(lineString.startIndex..., in: lineString))
        {
          if match.numberOfRanges > 1 {
            let range = match.range(at: 1)
            if let swiftRange = Range(range, in: lineString) {
              let symbolName = String(lineString[swiftRange])
              symbols.append((symbolName, lineIndex + 1, isDefinition))
            }
          }
        }
      }
    }

    return symbols
  }

  /// Extract generic symbols using simple patterns.
  private func extractGenericSymbols(lines: [Substring]) -> [(String, Int, Bool)] {
    var symbols: [(String, Int, Bool)] = []

    // Very generic pattern: look for identifier-looking names after common keywords
    let pattern = #"^\s*(?:function|def|class|struct|enum|interface|type)\s+(\w+)"#

    for (lineIndex, line) in lines.enumerated() {
      let lineString = String(line)
      if let regex = try? NSRegularExpression(pattern: pattern, options: []),
        let match = regex.firstMatch(
          in: lineString, options: [], range: NSRange(lineString.startIndex..., in: lineString))
      {
        if match.numberOfRanges > 1 {
          let range = match.range(at: 1)
          if let swiftRange = Range(range, in: lineString) {
            let symbolName = String(lineString[swiftRange])
            symbols.append((symbolName, lineIndex + 1, true))
          }
        }
      }
    }

    return symbols
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
    startLine: Int? = nil,
    endLine: Int? = nil,
    contextLines: Int = 3
  ) async throws -> SearchResult {
    logger.debug(
      "Extracting file context",
      metadata: [
        "file": "\(filePath)",
        "start": "\(startLine ?? 0)",
        "end": "\(endLine ?? 0)",
        "context": "\(contextLines)",
      ])

    // Validate file exists
    guard fileManager.fileExists(atPath: filePath) else {
      logger.warning("File not found", metadata: ["path": "\(filePath)"])
      throw IndexingError.invalidProjectPath(filePath)
    }

    // Read file content
    let content: String
    do {
      content = try String(contentsOfFile: filePath, encoding: .utf8)
    } catch {
      logger.error("Failed to read file", metadata: ["path": "\(filePath)", "error": "\(error)"])
      throw IndexingError.fileReadingFailed(filePath, error)
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

    // Detect language and extract project name
    let language = detectLanguage(from: filePath)
    let projectName = extractProjectName(from: filePath)

    logger.debug(
      "File context extracted",
      metadata: [
        "total_lines": "\(totalLines)",
        "extracted_lines": "\(extractedLines.count)",
        "language": "\(language)",
      ])

    // Return as SearchResult
    return SearchResult.fileContext(
      projectName: projectName,
      filePath: filePath,
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
