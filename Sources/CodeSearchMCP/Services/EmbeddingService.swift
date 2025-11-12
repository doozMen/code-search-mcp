import Foundation
import Logging

/// Service responsible for generating and caching vector embeddings.
///
/// Uses pluggable embedding providers:
/// - Primary: CoreML/NaturalLanguage (300-dimensional, native Swift)
/// - Fallback: BERT (384-dimensional, Python bridge) - future
///
/// Embeddings are cached to disk to avoid recomputation.
///
/// Responsibilities:
/// - Generate embeddings for code chunks using configured provider
/// - Cache embeddings to disk for persistence
/// - Retrieve cached embeddings
/// - Handle embedding model initialization and lifecycle
actor EmbeddingService: Sendable {
  // MARK: - Properties

  private let indexPath: String
  private let logger: Logger
  private let fileManager = FileManager.default

  /// Embedding provider (CoreML or BERT)
  private let provider: any EmbeddingProvider

  /// Cache directory for embeddings
  private let embeddingsCacheDir: String

  // MARK: - Computed Properties

  /// Current embedding dimensions from provider
  var embeddingDimension: Int {
    provider.dimensions
  }

  // MARK: - Initialization

  init(indexPath: String, provider: (any EmbeddingProvider)? = nil) async throws {
    self.indexPath = indexPath
    self.embeddingsCacheDir = (indexPath as NSString).appendingPathComponent("embeddings")
    self.logger = Logger(label: "embedding-service")

    // Use provided provider or create default (CoreML)
    if let provider = provider {
      self.provider = provider
    } else {
      // Default to CoreML provider
      self.provider = try CoreMLEmbeddingProvider()
    }

    // Create embeddings cache directory
    try? fileManager.createDirectory(
      atPath: embeddingsCacheDir,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let dimensions = self.provider.dimensions
    logger.info(
      "EmbeddingService initialized",
      metadata: [
        "dimensions": "\(dimensions)",
        "provider": "CoreML (NLEmbedding)",
        "cache_dir": "\(embeddingsCacheDir)",
      ])
  }

  // MARK: - Public Interface

  /// Generate embedding for a text string.
  ///
  /// First checks cache, then generates if needed using configured provider.
  ///
  /// - Parameter text: Text to embed (code snippet or description)
  /// - Returns: Array of floating-point values representing the embedding
  /// - Throws: If embedding generation fails
  func generateEmbedding(for text: String) async throws -> [Float] {
    // Check cache first
    if let cached = try getCachedEmbedding(for: text) {
      logger.debug("Using cached embedding")
      return cached
    }

    // Generate new embedding using provider
    logger.debug(
      "Generating new embedding",
      metadata: [
        "text_length": "\(text.count)"
      ])

    let embedding = try await provider.generateEmbedding(for: text)

    // Cache the result
    try await cacheEmbedding(embedding, for: text)

    logger.debug(
      "Generated and cached embedding",
      metadata: [
        "dimensions": "\(embedding.count)"
      ])

    return embedding
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

  // MARK: - Statistics

  /// Get cache statistics.
  ///
  /// - Returns: Cache statistics including hit rate and total embeddings
  /// - Throws: If stats retrieval fails
  func getCacheStats() async throws -> EmbeddingCacheStats {
    // Count cached embeddings
    let cacheFiles: [String]
    if let enumerator = fileManager.enumerator(atPath: embeddingsCacheDir) {
      cacheFiles = enumerator.allObjects as? [String] ?? []
    } else {
      cacheFiles = []
    }

    let totalEmbeddings = cacheFiles.filter { $0.hasSuffix(".embedding.json") }.count

    logger.debug(
      "Cache stats retrieved",
      metadata: [
        "total_embeddings": "\(totalEmbeddings)"
      ])

    // For now, return stats without hit/miss tracking
    // TODO: Add actual hit/miss tracking in future
    return EmbeddingCacheStats(
      indexPath: embeddingsCacheDir,
      totalEmbeddings: totalEmbeddings,
      cacheHits: 0,
      cacheMisses: 0
    )
  }
}

// MARK: - Statistics Model

/// Statistics about the embedding cache.
struct EmbeddingCacheStats: Sendable {
  let indexPath: String
  let totalEmbeddings: Int
  let cacheHits: Int
  let cacheMisses: Int

  var hitRate: Double {
    let total = cacheHits + cacheMisses
    return total > 0 ? Double(cacheHits) / Double(total) : 0.0
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

