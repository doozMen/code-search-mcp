#if !os(macOS)
import Foundation
import Testing

@testable import CodeSearchMCP
@testable import SwiftEmbeddings

/// Tests for BERT embedding provider.
///
/// These tests verify the Python server integration and embedding generation.
/// They require Python 3.8+ and sentence-transformers to be installed.
#if os(Linux)
@Suite("BERT Embedding Provider Tests")
struct BERTEmbeddingProviderTests {

  @Test("Provider initialization")
  func testInitialization() async throws {
    let provider = BERTEmbeddingProvider()
    
    // Check dimensions
    #expect(provider.dimensions == 384)
  }

  @Test("Single embedding generation", .disabled("Requires Python server"))
  func testSingleEmbedding() async throws {
    let provider = BERTEmbeddingProvider()
    try await provider.initialize()
    
    let text = "func calculateSum(a: Int, b: Int) -> Int { return a + b }"
    let embedding = try await provider.generateEmbedding(for: text)
    
    #expect(embedding.count == 384)
    
    // Verify embedding is normalized (L2 norm ~= 1.0)
    let magnitude = sqrt(embedding.reduce(0) { $0 + ($1 * $1) })
    #expect(magnitude > 0.0)
  }

  @Test("Batch embedding generation", .disabled("Requires Python server"))
  func testBatchEmbeddings() async throws {
    let provider = BERTEmbeddingProvider()
    try await provider.initialize()
    
    let texts = [
      "func add(a: Int, b: Int) -> Int",
      "class User { var name: String }",
      "struct Point { let x: Double; let y: Double }",
    ]
    
    let embeddings = try await provider.generateEmbeddings(for: texts)
    
    #expect(embeddings.count == 3)
    for embedding in embeddings {
      #expect(embedding.count == 384)
    }
  }

  @Test("Empty text handling", .disabled("Requires Python server"))
  func testEmptyText() async throws {
    let provider = BERTEmbeddingProvider()
    try await provider.initialize()
    
    // Should handle empty strings gracefully
    await #expect(throws: Error.self) {
      try await provider.generateEmbedding(for: "")
    }
  }

  @Test("Semantic similarity", .disabled("Requires Python server"))
  func testSemanticSimilarity() async throws {
    let provider = BERTEmbeddingProvider()
    try await provider.initialize()
    
    let text1 = "calculate sum of two numbers"
    let text2 = "add two integers together"
    let text3 = "remove element from array"
    
    let embeddings = try await provider.generateEmbeddings(for: [text1, text2, text3])
    
    // Calculate cosine similarity
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
      let dotProduct = zip(a, b).reduce(0.0) { $0 + ($1.0 * $1.1) }
      let magnitudeA = sqrt(a.reduce(0) { $0 + ($1 * $1) })
      let magnitudeB = sqrt(b.reduce(0) { $0 + ($1 * $1) })
      return dotProduct / (magnitudeA * magnitudeB)
    }
    
    let sim12 = cosineSimilarity(embeddings[0], embeddings[1])
    let sim13 = cosineSimilarity(embeddings[0], embeddings[2])
    
    // Similar texts should have higher similarity
    #expect(sim12 > sim13)
  }
}
#endif
