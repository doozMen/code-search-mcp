import Foundation

/// Represents an indexed unit of code.
///
/// A code chunk is a logical block of code (function, class, block, or entire file)
/// that has been extracted from source code and enriched with metadata including
/// vector embeddings for semantic search.
///
/// Structure:
/// - Metadata: project, file path, language, line numbers
/// - Content: the actual source code
/// - Embedding: vector embedding (300-dim CoreML or 384-dim BERT)
/// - Classification: chunk type (function, class, block, etc.)
struct CodeChunk: Sendable, Codable {
  /// Unique identifier for this chunk
  let id: String

  /// Name of the project this chunk belongs to
  let projectName: String

  /// Path to the file containing this chunk (relative to project root)
  let filePath: String

  /// Programming language of the code
  let language: String

  /// Starting line number (1-indexed)
  let startLine: Int

  /// Ending line number (1-indexed, inclusive)
  let endLine: Int

  /// The actual source code content
  let content: String

  /// Type of chunk: "function", "class", "struct", "method", "block", "file"
  let chunkType: String

  /// Vector embedding (300-dim CoreML on macOS, 384-dim BERT on Linux, nil until computed)
  let embedding: [Float]?

  /// Optional human-readable description of the chunk
  let description: String?

  // MARK: - Computed Properties

  /// Number of lines in this chunk
  var lineCount: Int {
    endLine - startLine + 1
  }

  /// Number of lines of code (excluding empty lines and comments)
  var effectiveLineCount: Int {
    let lines = content.split(separator: "\n")
    return lines.filter { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      return !trimmed.isEmpty && !trimmed.hasPrefix("//") && !trimmed.hasPrefix("#")
    }.count
  }

  /// First non-empty line that could serve as a name
  var displayName: String {
    let lines = content.split(separator: "\n")
    for line in lines {
      let trimmed = String(line).trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty && !trimmed.hasPrefix("//") {
        return String(trimmed.prefix(80))  // Truncate long lines
      }
    }
    return "Unnamed chunk"
  }

  // MARK: - Initialization

  init(
    id: String = UUID().uuidString,
    projectName: String,
    filePath: String,
    language: String,
    startLine: Int,
    endLine: Int,
    content: String,
    chunkType: String = "code",
    embedding: [Float]? = nil,
    description: String? = nil
  ) {
    self.id = id
    self.projectName = projectName
    self.filePath = filePath
    self.language = language
    self.startLine = startLine
    self.endLine = endLine
    self.content = content
    self.chunkType = chunkType
    self.embedding = embedding
    self.description = description
  }

  // MARK: - Utility Methods

  /// Create a chunk with embedding already computed.
  ///
  /// - Parameter embedding: The embedding vector (must be 384 dimensions)
  /// - Returns: New chunk with embedding set
  func withEmbedding(_ embedding: [Float]) -> CodeChunk {
    CodeChunk(
      id: id,
      projectName: projectName,
      filePath: filePath,
      language: language,
      startLine: startLine,
      endLine: endLine,
      content: content,
      chunkType: chunkType,
      embedding: embedding,
      description: description
    )
  }

  /// Get a preview of the chunk content with limited lines.
  ///
  /// - Parameter maxLines: Maximum lines to include in preview
  /// - Returns: Truncated content with ellipsis if needed
  func preview(maxLines: Int = 5) -> String {
    let lines = content.split(separator: "\n")
    if lines.count <= maxLines {
      return content
    }

    let previewLines = lines.prefix(maxLines)
    return previewLines.joined(separator: "\n") + "\n... (\(lines.count - maxLines) more lines)"
  }

  /// Check if this chunk contains a specific symbol.
  ///
  /// - Parameter symbol: Symbol name to search for
  /// - Returns: True if symbol appears in chunk
  func containsSymbol(_ symbol: String) -> Bool {
    content.contains(symbol)
  }

  /// Extract all lines of code as an array.
  ///
  /// - Returns: Array of code lines
  func getLines() -> [String] {
    content.split(separator: "\n", omittingEmptySubsequences: false)
      .map { String($0) }
  }

  /// Get a specific line by number.
  ///
  /// - Parameter lineNumber: Line number (1-indexed, relative to chunk)
  /// - Returns: The line content if valid, nil otherwise
  func getLine(_ lineNumber: Int) -> String? {
    guard lineNumber >= 1, lineNumber <= lineCount else { return nil }
    let lines = getLines()
    return lines[lineNumber - 1]
  }
}

// MARK: - Codable Conformance

extension CodeChunk {
  enum CodingKeys: String, CodingKey {
    case id
    case projectName = "project_name"
    case filePath = "file_path"
    case language
    case startLine = "start_line"
    case endLine = "end_line"
    case content
    case chunkType = "chunk_type"
    case embedding
    case description
  }
}
