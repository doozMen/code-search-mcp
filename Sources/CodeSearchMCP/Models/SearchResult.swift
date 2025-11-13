import Foundation

/// Represents a search result returned by any search service.
///
/// Unified result type used by semantic search and file context queries.
/// Includes the found code, its location, relevance score, and additional metadata.
///
/// Result Types:
/// - Semantic search: Ranked by cosine similarity (0-1 score)
/// - File context: Single result with specified line range
struct SearchResult: Sendable, Codable {
  /// Unique identifier for this result
  let id: String

  /// Project containing the result
  let projectName: String

  /// File path (relative to project root)
  let filePath: String

  /// Programming language
  let language: String

  /// Starting line number (1-indexed)
  let lineNumber: Int

  /// Ending line number (1-indexed, inclusive)
  let endLineNumber: Int

  /// The actual source code
  let context: String

  /// Type of result: "definition", "reference", "snippet", "file"
  let resultType: String

  /// Relevance score (0-1): how well this matches the query
  /// For semantic search: cosine similarity
  /// For keyword search: match quality score
  let relevanceScore: Double

  /// Reason why this result matches (for user explanation)
  let matchReason: String

  /// Optional metadata about the match
  let metadata: [String: String]

  // MARK: - Computed Properties

  /// Full file path including project
  var fullPath: String {
    "\(projectName)/\(filePath)"
  }

  /// Number of lines in result
  var lineCount: Int {
    endLineNumber - lineNumber + 1
  }

  /// Formatted location string for display
  var locationString: String {
    if lineNumber == endLineNumber {
      return "\(filePath):\(lineNumber)"
    } else {
      return "\(filePath):\(lineNumber)-\(endLineNumber)"
    }
  }

  /// Short context preview (first line)
  var contextPreview: String {
    let firstLine = context.split(separator: "\n").first.map(String.init) ?? ""
    if firstLine.count > 80 {
      return String(firstLine.prefix(77)) + "..."
    }
    return firstLine
  }

  // MARK: - Initialization

  init(
    id: String = UUID().uuidString,
    projectName: String,
    filePath: String,
    language: String,
    lineNumber: Int,
    endLineNumber: Int,
    context: String,
    resultType: String = "snippet",
    relevanceScore: Double,
    matchReason: String,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.projectName = projectName
    self.filePath = filePath
    self.language = language
    self.lineNumber = lineNumber
    self.endLineNumber = endLineNumber
    self.context = context
    self.resultType = resultType
    self.relevanceScore = max(0.0, min(1.0, relevanceScore))  // Clamp to 0-1
    self.matchReason = matchReason
    self.metadata = metadata
  }

  // MARK: - Factory Methods

  /// Create a semantic search result.
  ///
  /// - Parameters:
  ///   - projectName: Project containing result
  ///   - filePath: File path in project
  ///   - language: Programming language
  ///   - lineNumber: Starting line
  ///   - context: Code snippet
  ///   - cosineSimilarity: Similarity score (0-1)
  /// - Returns: SearchResult configured for semantic search
  static func semanticMatch(
    projectName: String,
    filePath: String,
    language: String,
    lineNumber: Int,
    context: String,
    cosineSimilarity: Double
  ) -> SearchResult {
    SearchResult(
      projectName: projectName,
      filePath: filePath,
      language: language,
      lineNumber: lineNumber,
      endLineNumber: lineNumber,
      context: context,
      resultType: "semantic",
      relevanceScore: cosineSimilarity,
      matchReason: "Semantically similar code pattern",
      metadata: ["similarity": String(format: "%.3f", cosineSimilarity)]
    )
  }

  /// Create a keyword search result.
  ///
  /// - Parameters:
  ///   - projectName: Project containing result
  ///   - filePath: File path in project
  ///   - language: Programming language
  ///   - lineNumber: Starting line
  ///   - context: Code snippet
  ///   - matchType: "definition" or "reference"
  /// - Returns: SearchResult configured for keyword search
  static func keywordMatch(
    projectName: String,
    filePath: String,
    language: String,
    lineNumber: Int,
    context: String,
    matchType: String = "reference"
  ) -> SearchResult {
    SearchResult(
      projectName: projectName,
      filePath: filePath,
      language: language,
      lineNumber: lineNumber,
      endLineNumber: lineNumber,
      context: context,
      resultType: matchType,
      relevanceScore: matchType == "definition" ? 1.0 : 0.8,
      matchReason: matchType == "definition" ? "Symbol definition" : "Symbol reference",
      metadata: ["match_type": matchType]
    )
  }

  /// Create a file context result.
  ///
  /// - Parameters:
  ///   - projectName: Project containing result
  ///   - filePath: File path in project
  ///   - language: Programming language
  ///   - startLine: Starting line
  ///   - endLine: Ending line
  ///   - content: Code snippet
  /// - Returns: SearchResult for file context query
  static func fileContext(
    projectName: String,
    filePath: String,
    language: String,
    startLine: Int,
    endLine: Int,
    content: String
  ) -> SearchResult {
    SearchResult(
      projectName: projectName,
      filePath: filePath,
      language: language,
      lineNumber: startLine,
      endLineNumber: endLine,
      context: content,
      resultType: "file_context",
      relevanceScore: 1.0,
      matchReason: "Requested file context"
    )
  }

  // MARK: - Sorting & Comparison

  /// Sort results by relevance score (highest first).
  static func sortByRelevance(_ results: [SearchResult]) -> [SearchResult] {
    results.sorted { $0.relevanceScore > $1.relevanceScore }
  }

  /// Sort results by file path then line number.
  static func sortByLocation(_ results: [SearchResult]) -> [SearchResult] {
    results.sorted { a, b in
      if a.filePath != b.filePath {
        return a.filePath < b.filePath
      }
      return a.lineNumber < b.lineNumber
    }
  }

  /// Sort results by relevance then location.
  static func sortByRelevanceThenLocation(_ results: [SearchResult]) -> [SearchResult] {
    results.sorted { a, b in
      if abs(a.relevanceScore - b.relevanceScore) > 0.01 {
        return a.relevanceScore > b.relevanceScore
      }
      if a.filePath != b.filePath {
        return a.filePath < b.filePath
      }
      return a.lineNumber < b.lineNumber
    }
  }
}

// MARK: - Codable Conformance

extension SearchResult {
  enum CodingKeys: String, CodingKey {
    case id
    case projectName = "project_name"
    case filePath = "file_path"
    case language
    case lineNumber = "line_number"
    case endLineNumber = "end_line_number"
    case context
    case resultType = "result_type"
    case relevanceScore = "relevance_score"
    case matchReason = "match_reason"
    case metadata
  }
}
