import Foundation
import Logging

/// Service responsible for generating and caching vector embeddings.
///
/// Uses 384-dimensional BERT embeddings for code understanding.
/// Embeddings are cached to disk to avoid recomputation.
///
/// Responsibilities:
/// - Generate embeddings for code chunks using BERT model
/// - Cache embeddings to disk for persistence
/// - Retrieve cached embeddings
/// - Handle embedding model initialization and lifecycle
actor EmbeddingService: Sendable {
  // MARK: - Properties

  private let indexPath: String
  private let logger: Logger
  private let fileManager = FileManager.default

  /// Cache directory for embeddings
  private let embeddingsCacheDir: String

  /// BERT embedding model (384-dimensional)
  /// NOTE: This will be initialized when embeddings need to be generated
  private var embeddingModel: BERTEmbedding?

  // MARK: - Constants

  private let embeddingDimension = 384
  private let modelName = "bert-base-uncased"

  // MARK: - Initialization

  init(indexPath: String) {
    self.indexPath = indexPath
    self.embeddingsCacheDir = (indexPath as NSString).appendingPathComponent("embeddings")
    self.logger = Logger(label: "embedding-service")

    // Create embeddings cache directory
    try? fileManager.createDirectory(
      atPath: embeddingsCacheDir,
      withIntermediateDirectories: true,
      attributes: nil
    )

    logger.debug(
      "EmbeddingService initialized",
      metadata: [
        "dimension": "\(embeddingDimension)",
        "model": "\(modelName)",
        "cache_dir": "\(embeddingsCacheDir)",
      ])
  }

  // MARK: - Public Interface

  /// Generate embedding for a text string.
  ///
  /// First checks cache, then generates if needed using BERT model.
  ///
  /// - Parameter text: Text to embed (code snippet or description)
  /// - Returns: Array of 384 floating-point values representing the embedding
  /// - Throws: If embedding generation fails
  func generateEmbedding(for text: String) async throws -> [Float] {
    // Check cache first
    if let cached = try getCachedEmbedding(for: text) {
      logger.debug("Using cached embedding")
      return cached
    }

    // Generate new embedding
    logger.debug(
      "Generating new embedding",
      metadata: [
        "text_length": "\(text.count)"
      ])

    throw CodeSearchError.notYetImplemented(
      feature: "BERT embedding generation",
      issueNumber: nil
    )
  }

  /// Generate embeddings for multiple text strings in batch.
  ///
  /// More efficient than calling generateEmbedding individually.
  ///
  /// - Parameter texts: Array of texts to embed
  /// - Returns: Dictionary mapping text to embedding vectors
  /// - Throws: If batch embedding generation fails
  func generateEmbeddings(for texts: [String]) async throws -> [String: [Float]] {
    var embeddings: [String: [Float]] = [:]

    for text in texts {
      embeddings[text] = try await generateEmbedding(for: text)
    }

    return embeddings
  }

  // MARK: - Caching

  /// Retrieve a cached embedding for the given text.
  ///
  /// - Parameter text: Text to look up
  /// - Returns: Cached embedding if found, nil otherwise
  private func getCachedEmbedding(for text: String) throws -> [Float]? {
    let textHash = hashText(text)
    let cachePath = (embeddingsCacheDir as NSString).appendingPathComponent("\(textHash).embedding")

    guard fileManager.fileExists(atPath: cachePath) else {
      return nil
    }

    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: cachePath))
      let embedding = try JSONDecoder().decode([Float].self, from: data)
      logger.debug(
        "Retrieved cached embedding",
        metadata: [
          "size": "\(embedding.count)"
        ])
      return embedding
    } catch {
      logger.warning(
        "Failed to decode cached embedding",
        metadata: [
          "error": "\(error)"
        ])
      return nil
    }
  }

  /// Cache an embedding for the given text.
  ///
  /// - Parameters:
  ///   - embedding: Embedding vector to cache
  ///   - text: Original text that was embedded
  private func cacheEmbedding(_ embedding: [Float], for text: String) async throws {
    let textHash = hashText(text)
    let cachePath = (embeddingsCacheDir as NSString).appendingPathComponent("\(textHash).embedding")

    do {
      let data = try JSONEncoder().encode(embedding)
      try data.write(to: URL(fileURLWithPath: cachePath))
      logger.debug(
        "Cached embedding",
        metadata: [
          "hash": "\(textHash)",
          "size": "\(embedding.count)",
        ])
    } catch {
      logger.warning(
        "Failed to cache embedding",
        metadata: [
          "error": "\(error)"
        ])
      throw EmbeddingError.cachingFailed(error)
    }
  }

  // MARK: - Utilities

  /// Compute a stable hash for text content.
  ///
  /// - Parameter text: Text to hash
  /// - Returns: Hex string hash
  private func hashText(_ text: String) -> String {
    let hash = text.hashValue
    return String(format: "%08x", abs(hash))
  }

  /// Clear all cached embeddings.
  ///
  /// Useful for cache invalidation or cleanup.
  func clearCache() async throws {
    do {
      let files = try fileManager.contentsOfDirectory(atPath: embeddingsCacheDir)
      for file in files where file.hasSuffix(".embedding") {
        let path = (embeddingsCacheDir as NSString).appendingPathComponent(file)
        try fileManager.removeItem(atPath: path)
      }
      logger.info("Embedding cache cleared")
    } catch {
      logger.error(
        "Failed to clear embedding cache",
        metadata: [
          "error": "\(error)"
        ])
      throw EmbeddingError.cacheClearingFailed(error)
    }
  }
}

// MARK: - Error Types

enum EmbeddingError: Error, LocalizedError {
  case generationFailed(String)
  case cachingFailed(Error)
  case cacheClearingFailed(Error)
  case modelInitializationFailed

  var errorDescription: String? {
    switch self {
    case .generationFailed(let reason):
      return "Embedding generation failed: \(reason)"
    case .cachingFailed(let error):
      return "Failed to cache embedding: \(error)"
    case .cacheClearingFailed(let error):
      return "Failed to clear embedding cache: \(error)"
    case .modelInitializationFailed:
      return "Failed to initialize embedding model"
    }
  }
}

// MARK: - Placeholder Type

/// Placeholder for BERT embedding model integration.
///
/// This will be replaced with actual swift-embeddings integration.
struct BERTEmbedding: Sendable {
  let modelName: String
}
