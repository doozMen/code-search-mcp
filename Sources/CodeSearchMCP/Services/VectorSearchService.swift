import Foundation
import Logging

/// Service responsible for semantic search using vector similarity.
///
/// Performs cosine similarity matching between query embeddings
/// and indexed code chunk embeddings to find semantically similar code.
///
/// Responsibilities:
/// - Generate embeddings for search queries
/// - Compute cosine similarity scores
/// - Return ranked results by relevance
/// - Handle project filtering
actor VectorSearchService: Sendable {
  // MARK: - Properties

  private let indexPath: String
  private let logger: Logger
  private let embeddingService: EmbeddingService

  // MARK: - Initialization

  init(indexPath: String) {
    self.indexPath = indexPath
    self.embeddingService = EmbeddingService(indexPath: indexPath)
    self.logger = Logger(label: "vector-search-service")
  }

  // MARK: - Public Interface

  /// Perform semantic search for code chunks.
  ///
  /// Generates an embedding for the query and finds code chunks
  /// with highest cosine similarity scores.
  ///
  /// - Parameters:
  ///   - query: Natural language query or code snippet
  ///   - maxResults: Maximum number of results to return
  ///   - projectFilter: Optional project name to limit scope
  /// - Returns: Array of SearchResult objects sorted by relevance
  /// - Throws: If query embedding generation fails
  func search(
    query: String,
    maxResults: Int = 10,
    projectFilter: String? = nil
  ) async throws -> [SearchResult] {
    logger.debug(
      "Semantic search",
      metadata: [
        "query_length": "\(query.count)",
        "max_results": "\(maxResults)",
        "project_filter": "\(projectFilter ?? "none")",
      ])

    // Generate embedding for the query
    let queryEmbedding = try await embeddingService.generateEmbedding(for: query)

    logger.debug(
      "Generated query embedding",
      metadata: [
        "dimensions": "\(queryEmbedding.count)"
      ])

    // Load indexed chunks (with optional project filtering)
    let chunks = try await loadIndexedChunks(projectFilter: projectFilter)

    logger.debug(
      "Loaded chunks for search",
      metadata: [
        "total_chunks": "\(chunks.count)"
      ])

    // Filter chunks that have embeddings
    let chunksWithEmbeddings = chunks.filter { $0.embedding != nil }

    if chunksWithEmbeddings.isEmpty {
      logger.warning("No chunks with embeddings found")
      return []
    }

    logger.debug(
      "Chunks with embeddings",
      metadata: [
        "count": "\(chunksWithEmbeddings.count)"
      ])

    // Compute similarity scores for all chunks
    let scoredResults = chunksWithEmbeddings.compactMap { chunk -> ScoredChunk? in
      guard let embedding = chunk.embedding else { return nil }

      // Validate embedding dimensions
      guard embedding.count == queryEmbedding.count else {
        logger.warning(
          "Dimension mismatch",
          metadata: [
            "chunk_id": "\(chunk.id)",
            "expected": "\(queryEmbedding.count)",
            "actual": "\(embedding.count)",
          ])
        return nil
      }

      let similarity = cosineSimilarity(queryEmbedding, embedding)
      return ScoredChunk(chunk: chunk, score: similarity)
    }

    logger.debug(
      "Computed similarity scores",
      metadata: [
        "scored_results": "\(scoredResults.count)"
      ])

    // Sort by similarity score (highest first) and take top results
    let topResults =
      scoredResults
      .sorted { $0.score > $1.score }
      .prefix(maxResults)

    // Convert to SearchResult objects
    let searchResults = topResults.map { scored -> SearchResult in
      SearchResult.semanticMatch(
        projectName: scored.chunk.projectName,
        filePath: scored.chunk.filePath,
        language: scored.chunk.language,
        lineNumber: scored.chunk.startLine,
        context: scored.chunk.content,
        cosineSimilarity: Double(scored.score)
      )
    }

    logger.info(
      "Search completed",
      metadata: [
        "results_returned": "\(searchResults.count)",
        "top_score": searchResults.first.map { "\($0.relevanceScore)" } ?? "N/A",
      ])

    return searchResults
  }

  // MARK: - Similarity Computation

  /// Compute cosine similarity between two vectors.
  ///
  /// Measures angle between vectors; result ranges from -1 to 1
  /// where 1 indicates perfect similarity.
  ///
  /// - Parameters:
  ///   - vector1: First embedding vector
  ///   - vector2: Second embedding vector
  /// - Returns: Cosine similarity score
  private func cosineSimilarity(_ vector1: [Float], _ vector2: [Float]) -> Float {
    guard vector1.count == vector2.count, !vector1.isEmpty else {
      return 0.0
    }

    // Compute dot product
    var dotProduct: Float = 0.0
    for i in 0..<vector1.count {
      dotProduct += vector1[i] * vector2[i]
    }

    // Compute magnitudes
    let magnitude1 = sqrt(vector1.reduce(0) { $0 + ($1 * $1) })
    let magnitude2 = sqrt(vector2.reduce(0) { $0 + ($1 * $1) })

    guard magnitude1 > 0, magnitude2 > 0 else {
      return 0.0
    }

    return dotProduct / (magnitude1 * magnitude2)
  }

  // MARK: - Index Management

  /// Load indexed code chunks from storage with optional filtering.
  ///
  /// - Parameter projectFilter: Optional project name to filter results
  /// - Returns: Array of code chunks (all or project-specific)
  /// - Throws: If index loading fails
  private func loadIndexedChunks(projectFilter: String?) async throws -> [CodeChunk] {
    if let projectName = projectFilter {
      return try await loadProjectChunks(projectName: projectName)
    } else {
      return try await loadAllIndexedChunks()
    }
  }

  /// Load all indexed code chunks from storage.
  ///
  /// Scans the index directory for all project chunk files and loads them.
  ///
  /// - Returns: Array of all indexed code chunks
  /// - Throws: If index loading fails
  private func loadAllIndexedChunks() async throws -> [CodeChunk] {
    let chunksDir = (indexPath as NSString).appendingPathComponent("chunks")
    let fileManager = FileManager.default

    // Check if chunks directory exists
    guard fileManager.fileExists(atPath: chunksDir) else {
      logger.debug(
        "No chunks directory found",
        metadata: [
          "path": "\(chunksDir)"
        ])
      return []
    }

    var allChunks: [CodeChunk] = []

    do {
      // Get all project directories
      let projectDirs = try fileManager.contentsOfDirectory(atPath: chunksDir)

      for projectDir in projectDirs {
        let projectPath = (chunksDir as NSString).appendingPathComponent(projectDir)

        // Skip if not a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: projectPath, isDirectory: &isDirectory),
          isDirectory.boolValue
        else {
          continue
        }

        // Load chunks for this project
        let chunks = try await loadChunksFromDirectory(projectPath)
        allChunks.append(contentsOf: chunks)

        logger.debug(
          "Loaded project chunks",
          metadata: [
            "project": "\(projectDir)",
            "chunk_count": "\(chunks.count)",
          ])
      }

      logger.info(
        "Loaded all indexed chunks",
        metadata: [
          "total_chunks": "\(allChunks.count)",
          "project_count": "\(projectDirs.count)",
        ])

    } catch {
      logger.error(
        "Failed to load indexed chunks",
        metadata: [
          "error": "\(error)"
        ])
      throw VectorSearchError.indexLoadingFailed("Could not enumerate projects: \(error)")
    }

    return allChunks
  }

  /// Load chunks for a specific project.
  ///
  /// - Parameter projectName: Name of project to load
  /// - Returns: Array of code chunks from that project
  /// - Throws: If project index loading fails
  private func loadProjectChunks(projectName: String) async throws -> [CodeChunk] {
    let chunksDir = (indexPath as NSString).appendingPathComponent("chunks")
    let projectPath = (chunksDir as NSString).appendingPathComponent(projectName)
    let fileManager = FileManager.default

    guard fileManager.fileExists(atPath: projectPath) else {
      logger.warning(
        "Project not found in index",
        metadata: [
          "project": "\(projectName)",
          "path": "\(projectPath)",
        ])
      return []
    }

    let chunks = try await loadChunksFromDirectory(projectPath)

    logger.debug(
      "Loaded project chunks",
      metadata: [
        "project": "\(projectName)",
        "chunk_count": "\(chunks.count)",
      ])

    return chunks
  }

  /// Load all chunk files from a project directory.
  ///
  /// - Parameter directory: Path to project's chunk directory
  /// - Returns: Array of decoded CodeChunk objects
  /// - Throws: If file reading or decoding fails
  private func loadChunksFromDirectory(_ directory: String) async throws -> [CodeChunk] {
    let fileManager = FileManager.default
    var chunks: [CodeChunk] = []

    do {
      let files = try fileManager.contentsOfDirectory(atPath: directory)

      for file in files where file.hasSuffix(".json") {
        let filePath = (directory as NSString).appendingPathComponent(file)

        do {
          let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
          let chunk = try JSONDecoder().decode(CodeChunk.self, from: data)
          chunks.append(chunk)
        } catch {
          logger.warning(
            "Failed to decode chunk file",
            metadata: [
              "file": "\(file)",
              "error": "\(error)",
            ])
          // Continue loading other chunks even if one fails
        }
      }
    } catch {
      throw VectorSearchError.indexLoadingFailed("Could not read directory \(directory): \(error)")
    }

    return chunks
  }
}

// MARK: - Helper Types

/// Internal type for pairing chunks with their similarity scores.
private struct ScoredChunk: Sendable {
  let chunk: CodeChunk
  let score: Float
}

// MARK: - Error Types

enum VectorSearchError: Error, LocalizedError {
  case queryEmbeddingFailed(Error)
  case indexLoadingFailed(String)
  case invalidQueryDimensions

  var errorDescription: String? {
    switch self {
    case .queryEmbeddingFailed(let error):
      return "Failed to generate query embedding: \(error)"
    case .indexLoadingFailed(let reason):
      return "Failed to load index: \(reason)"
    case .invalidQueryDimensions:
      return "Query embedding dimensions do not match index"
    }
  }
}
