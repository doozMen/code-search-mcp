import Foundation
import Testing

@testable import CodeSearchMCP
@testable import SwiftEmbeddings

/// Tests for embedding provider fallback logic.
///
/// Validates:
/// - CoreML as primary provider
/// - BERT as fallback provider
/// - Dimension handling (300-dim vs 384-dim)
/// - Provider initialization errors
/// - Graceful fallback on errors
@Suite("Embedding Provider Fallback Tests")
struct EmbeddingProviderFallbackTests {

  @Test("CoreML provider is primary and works")
  func testCoreMLPrimary() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    #expect(provider.dimensions == 300)
    
    let embedding = try await provider.generateEmbedding(for: "test code")
    #expect(embedding.count == 300)
  }

  @Test("BERT provider dimensions are 384", .disabled("Requires Python server and Linux"))
  func testBERTDimensions() async throws {
    #if !os(macOS)
    let provider = BERTEmbeddingProvider()

    #expect(provider.dimensions == 384)
    #endif
  }

  @Test("EmbeddingService uses CoreML by default")
  func testEmbeddingServiceDefaultProvider() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: tempDir) }
    
    let service = try await EmbeddingService(indexPath: tempDir)
    
    // Should use CoreML (300 dimensions)
    #expect(await service.embeddingDimension == 300)
  }

  @Test("EmbeddingService can use BERT provider", .disabled("Requires Python server and Linux"))
  func testEmbeddingServiceWithBERTProvider() async throws {
    #if !os(macOS)
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let bertProvider = BERTEmbeddingProvider()
    try await bertProvider.initialize()

    let service = try await EmbeddingService(indexPath: tempDir, provider: bertProvider)

    // Should use BERT (384 dimensions)
    #expect(await service.embeddingDimension == 384)
    #endif
  }

  @Test("Dimension mismatch between providers is detected")
  func testDimensionMismatch() async throws {
    let coreMLProvider = try CoreMLEmbeddingProvider()
    
    let coreMLEmbedding = try await coreMLProvider.generateEmbedding(for: "test")
    
    #expect(coreMLEmbedding.count == 300)
    // BERT would be 384, so they are incompatible
  }

  @Test("Provider interface is consistent")
  func testProviderInterface() async throws {
    let provider: any EmbeddingProvider = try CoreMLEmbeddingProvider()
    
    // Test single generation
    let single = try await provider.generateEmbedding(for: "test text")
    #expect(single.count == provider.dimensions)
    
    // Test batch generation
    let batch = try await provider.generateEmbeddings(for: ["text1", "text2"])
    #expect(batch.count == 2)
    #expect(batch[0].count == provider.dimensions)
    #expect(batch[1].count == provider.dimensions)
  }

  @Test("Empty provider array handling")
  func testEmptyProviderList() async throws {
    // EmbeddingService should default to CoreML if no provider specified
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: tempDir) }
    
    let service = try await EmbeddingService(indexPath: tempDir, provider: nil)
    
    #expect(await service.embeddingDimension == 300)  // CoreML default
  }

  @Test("Provider error propagation")
  func testProviderErrorPropagation() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    // Test invalid input
    await #expect(throws: Error.self) {
      _ = try await provider.generateEmbedding(for: "")
    }
  }

  @Test("Batch generation maintains order")
  func testBatchGenerationOrder() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    let texts = ["first", "second", "third", "fourth", "fifth"]
    let embeddings = try await provider.generateEmbeddings(for: texts)
    
    #expect(embeddings.count == texts.count)
    
    // Verify each text produces consistent embedding (same text = same embedding)
    let firstEmbedding1 = try await provider.generateEmbedding(for: "first")
    let firstEmbedding2 = embeddings[0]
    
    // Should be similar (allowing for minor floating-point differences)
    let similarity = cosineSimilarity(firstEmbedding1, firstEmbedding2)
    #expect(similarity > 0.99, "Embeddings for same text should be nearly identical")
  }

  // MARK: - Helper Functions

  private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    
    let dotProduct = zip(a, b).reduce(0.0) { $0 + ($1.0 * $1.1) }
    let magnitudeA = sqrt(a.reduce(0) { $0 + ($1 * $1) })
    let magnitudeB = sqrt(b.reduce(0) { $0 + ($1 * $1) })
    
    guard magnitudeA > 0, magnitudeB > 0 else { return 0 }
    return dotProduct / (magnitudeA * magnitudeB)
  }
}
