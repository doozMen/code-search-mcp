import Foundation

/// Protocol for embedding generation providers.
///
/// Supports multiple embedding backends (CoreML, Foundation Models, BERT Python server).
/// All implementations must be actor-safe and Sendable.
///
/// API matches CoreMLEmbeddingProvider for compatibility.
protocol EmbeddingProvider: Sendable {
  /// Dimensionality of embeddings produced by this provider.
  var dimensions: Int { get }

  /// Generate embedding for a single text string.
  ///
  /// - Parameter text: Text to embed (code snippet or description)
  /// - Returns: Array of floating-point values representing the embedding
  /// - Throws: If embedding generation fails
  func generateEmbedding(for text: String) async throws -> [Float]

  /// Generate embeddings for multiple text strings in batch.
  ///
  /// More efficient than calling generateEmbedding individually.
  /// Implementations should optimize batch processing where possible.
  ///
  /// - Parameter texts: Array of texts to embed
  /// - Returns: Array of embedding vectors (same order as input)
  /// - Throws: If batch generation fails
  func generateEmbeddings(for texts: [String]) async throws -> [[Float]]
}

/// Error types for embedding providers.
enum EmbeddingProviderError: Error, LocalizedError {
  case modelNotAvailable(String)
  case invalidInput(String)
  case generationFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelNotAvailable(let model):
      return "Embedding model not available: \(model)"
    case .invalidInput(let reason):
      return "Invalid input: \(reason)"
    case .generationFailed(let reason):
      return "Embedding generation failed: \(reason)"
    }
  }
}
