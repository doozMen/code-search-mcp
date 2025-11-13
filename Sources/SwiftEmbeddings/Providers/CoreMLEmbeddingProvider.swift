import Foundation
import NaturalLanguage
import Logging

/// CoreML-based embedding provider using NaturalLanguage framework.
///
/// Primary embedding provider for code-search-mcp. Uses Apple's built-in
/// word embeddings (300-dimensional) for semantic similarity.
///
/// Features:
/// - Native Swift implementation (no Python bridge)
/// - 300-dimensional word embeddings
/// - Fast, on-device processing
/// - Suitable for code semantic search
///
/// Limitations:
/// - Word-level embeddings (not sentence transformers)
/// - Fixed 300 dimensions (not configurable)
/// - Best for shorter code snippets (< 500 words)
actor CoreMLEmbeddingProvider: EmbeddingProvider {
    // MARK: - Properties

    private let embedding: NLEmbedding
    private let logger: Logger

    /// Number of dimensions in embeddings (300 for NLEmbedding)
    nonisolated let dimensions: Int = 300

    // MARK: - Initialization

    init() throws {
        self.logger = Logger(label: "coreml-embedding-provider")

        // Attempt to load English word embeddings
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            logger.error("Failed to load NLEmbedding model")
            throw EmbeddingProviderError.modelNotAvailable("NLEmbedding for English")
        }

        self.embedding = embedding

        logger.info(
            "CoreML embedding provider initialized",
            metadata: [
                "dimensions": "\(dimensions)",
                "model": "NLEmbedding (English)",
            ])
    }
    
    // MARK: - EmbeddingProvider Implementation
    
    /// Generate embedding for text by averaging word vectors.
    ///
    /// Strategy:
    /// 1. Tokenize text into words
    /// 2. Get embedding vector for each word
    /// 3. Average all word vectors
    /// 4. Normalize the result
    ///
    /// - Parameter text: Text to embed (code or natural language)
    /// - Returns: 300-dimensional embedding vector
    /// - Throws: If embedding generation fails
    func generateEmbedding(for text: String) async throws -> [Float] {
        logger.debug(
            "Generating embedding",
            metadata: [
                "text_length": "\(text.count)"
            ])
        
        guard !text.isEmpty else {
            throw EmbeddingProviderError.invalidInput("Empty text")
        }
        
        // Tokenize text into words
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text.lowercased()
        
        var wordVectors: [[Double]] = []
        
        // Extract word embeddings
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            
            // Skip very short words and common code symbols
            guard word.count > 1, !word.allSatisfy({ $0.isPunctuation }) else {
                return true
            }
            
            // Get embedding for this word
            if let vector = embedding.vector(for: word) {
                wordVectors.append(vector)
            }
            
            return true
        }
        
        guard !wordVectors.isEmpty else {
            logger.warning("No word embeddings found for text")
            // Return zero vector for texts with no recognizable words
            return Array(repeating: 0.0, count: dimensions)
        }
        
        logger.debug(
            "Word vectors extracted",
            metadata: [
                "word_count": "\(wordVectors.count)"
            ])
        
        // Average all word vectors
        let averaged = averageVectors(wordVectors)
        
        // Normalize the result
        let normalized = normalizeVector(averaged)
        
        logger.debug(
            "Embedding generated",
            metadata: [
                "dimensions": "\(normalized.count)",
                "magnitude": "\(vectorMagnitude(normalized))",
            ])
        
        return normalized
    }
    
    /// Generate embeddings for multiple texts in batch.
    ///
    /// Currently processes sequentially. Future optimization:
    /// parallelize with TaskGroup.
    ///
    /// - Parameter texts: Array of texts to embed
    /// - Returns: Array of embedding vectors
    /// - Throws: If batch generation fails
    func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
        logger.debug(
            "Batch embedding generation",
            metadata: [
                "batch_size": "\(texts.count)"
            ])
        
        var embeddings: [[Float]] = []
        
        for text in texts {
            let embedding = try await generateEmbedding(for: text)
            embeddings.append(embedding)
        }
        
        logger.info(
            "Batch embeddings generated",
            metadata: [
                "count": "\(embeddings.count)"
            ])
        
        return embeddings
    }
    
    // MARK: - Vector Operations
    
    /// Average multiple vectors element-wise.
    ///
    /// - Parameter vectors: Array of vectors (all same length)
    /// - Returns: Averaged vector
    private func averageVectors(_ vectors: [[Double]]) -> [Float] {
        guard !vectors.isEmpty else {
            return Array(repeating: 0.0, count: dimensions)
        }
        
        let dimensionCount = vectors[0].count
        var averaged = Array(repeating: 0.0, count: dimensionCount)
        
        // Sum all vectors
        for vector in vectors {
            for (i, value) in vector.enumerated() {
                averaged[i] += value
            }
        }
        
        // Divide by count
        let count = Double(vectors.count)
        for i in 0..<dimensionCount {
            averaged[i] /= count
        }
        
        // Convert to Float
        return averaged.map { Float($0) }
    }
    
    /// Normalize a vector to unit length.
    ///
    /// - Parameter vector: Input vector
    /// - Returns: Normalized vector (magnitude = 1.0)
    private func normalizeVector(_ vector: [Float]) -> [Float] {
        let magnitude = vectorMagnitude(vector)
        
        guard magnitude > 0 else {
            return vector
        }
        
        return vector.map { $0 / magnitude }
    }
    
    /// Calculate vector magnitude (L2 norm).
    ///
    /// - Parameter vector: Input vector
    /// - Returns: Magnitude
    private func vectorMagnitude(_ vector: [Float]) -> Float {
        sqrt(vector.reduce(0) { $0 + ($1 * $1) })
    }
}
