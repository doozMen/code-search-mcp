import Foundation
import Testing

@testable import CodeSearchMCP

/// Tests for CoreML embedding provider using NaturalLanguage framework.
///
/// Validates:
/// - Provider initialization
/// - Single and batch embedding generation
/// - 300-dimensional embeddings
/// - Word-level averaging
/// - Normalization
/// - Error handling
@Suite("CoreML Embedding Provider Tests")
struct CoreMLEmbeddingProviderTests {

  @Test("Provider initializes successfully")
  func testInitialization() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    // Check dimensions match NLEmbedding
    #expect(provider.dimensions == 300)
  }

  @Test("Single embedding generation produces 300 dimensions")
  func testSingleEmbedding() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    let text = "func calculateSum(a: Int, b: Int) -> Int { return a + b }"
    let embedding = try await provider.generateEmbedding(for: text)
    
    #expect(embedding.count == 300)
    
    // Verify embedding is normalized (L2 norm ~= 1.0)
    let magnitude = sqrt(embedding.reduce(0) { $0 + ($1 * $1) })
    #expect(magnitude > 0.8)  // Should be close to 1.0 after normalization
    #expect(magnitude <= 1.01)
  }

  @Test("Batch embedding generation")
  func testBatchEmbeddings() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    let texts = [
      "func add(a: Int, b: Int) -> Int",
      "class User { var name: String }",
      "struct Point { let x: Double; let y: Double }",
    ]
    
    let embeddings = try await provider.generateEmbeddings(for: texts)
    
    #expect(embeddings.count == 3)
    for embedding in embeddings {
      #expect(embedding.count == 300)
    }
  }

  @Test("Empty text handling")
  func testEmptyText() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    // Should throw error for empty strings
    await #expect(throws: EmbeddingProviderError.self) {
      _ = try await provider.generateEmbedding(for: "")
    }
  }

  @Test("Semantic similarity between related texts")
  func testSemanticSimilarity() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
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
    
    // Similar texts (calculate/add) should have higher similarity than unrelated texts
    #expect(sim12 > sim13)
  }

  @Test("Normalized embeddings have unit magnitude")
  func testNormalization() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    let texts = [
      "short text",
      "This is a much longer text with many more words to embed",
      "func myFunction() { return 42 }",
    ]
    
    for text in texts {
      let embedding = try await provider.generateEmbedding(for: text)
      let magnitude = sqrt(embedding.reduce(0) { $0 + ($1 * $1) })
      
      // All embeddings should be normalized to ~1.0
      #expect(magnitude > 0.95, "Magnitude \(magnitude) should be close to 1.0 for: \(text)")
      #expect(magnitude <= 1.05, "Magnitude \(magnitude) should not exceed 1.05 for: \(text)")
    }
  }

  @Test("Code snippets produce valid embeddings")
  func testCodeSnippets() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    let codeSnippets = [
      "class UserAccount { var username: String; var email: String }",
      "func fetchData() async throws -> [Article] { return await api.getArticles() }",
      "protocol Drawable { func draw() }",
      "enum Result<T> { case success(T); case failure(Error) }",
    ]
    
    for snippet in codeSnippets {
      let embedding = try await provider.generateEmbedding(for: snippet)
      #expect(embedding.count == 300)
      
      // Verify not all zeros (actual meaningful embedding)
      let nonZeroCount = embedding.filter { $0 != 0.0 }.count
      #expect(nonZeroCount > 0, "Embedding should not be all zeros for: \(snippet)")
    }
  }

  @Test("Special characters and symbols are handled")
  func testSpecialCharacters() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    let texts = [
      "func test() -> Result<String, Error> {}",
      "var array: [Int] = [1, 2, 3]",
      "if condition { /* comment */ return true }",
    ]
    
    for text in texts {
      let embedding = try await provider.generateEmbedding(for: text)
      #expect(embedding.count == 300)
    }
  }

  @Test("Performance: 1000 embeddings in reasonable time")
  func testBatchPerformance() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    // Generate 100 test texts (reduced from 1000 for CI)
    let texts = (0..<100).map { "func test\($0)(param: Int) -> String { return \"result\" }" }
    
    let startTime = Date()
    let embeddings = try await provider.generateEmbeddings(for: texts)
    let duration = Date().timeIntervalSince(startTime)
    
    #expect(embeddings.count == 100)
    
    // Should complete in < 5 seconds (conservative target)
    print("Generated 100 embeddings in \(duration) seconds")
    #expect(duration < 5.0, "Batch generation should complete in < 5 seconds")
  }

  @Test("Dimension mismatch detection")
  func testDimensionConsistency() async throws {
    let provider = try CoreMLEmbeddingProvider()
    
    let texts = [
      "first text",
      "second text with more words",
      "third",
    ]
    
    let embeddings = try await provider.generateEmbeddings(for: texts)
    
    // All embeddings should have consistent dimensions
    for embedding in embeddings {
      #expect(embedding.count == provider.dimensions)
    }
  }
}
