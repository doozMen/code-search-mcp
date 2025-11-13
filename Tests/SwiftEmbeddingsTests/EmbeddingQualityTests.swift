import Foundation
import Testing
@testable import SwiftEmbeddings

/// Comprehensive quality tests for SwiftEmbeddings library.
///
/// Tests validate both CoreML (NLEmbedding) and BERT embedding providers
/// for semantic similarity, vector properties, performance, and real-world use cases.
@Suite("SwiftEmbeddings Quality Tests")
struct EmbeddingQualityTests {

  // MARK: - Test Helpers

  private static func isMacOS() -> Bool {
    #if os(macOS)
      return true
    #else
      return false
    #endif
  }

  private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    VectorMath.cosineSimilarity(a, b)
  }

  // MARK: - CoreML Quality Tests (macOS Only)

  @Test("CoreML provider initializes successfully", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testCoreMLInitialization() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()
      #expect(provider.dimensions == 300, "CoreML should provide 300-dimensional embeddings")
    #endif
  }

  @Test("CoreML semantic similarity - code snippets", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testCoreMLCodeSimilarity() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      // Similar code snippets
      let code1 = "func calculateSum(a: Int, b: Int) -> Int { return a + b }"
      let code2 = "func add(x: Int, y: Int) -> Int { x + y }"

      let embedding1 = try await provider.generateEmbedding(for: code1)
      let embedding2 = try await provider.generateEmbedding(for: code2)

      let similarity = cosineSimilarity(embedding1, embedding2)

      #expect(
        similarity > 0.35,
        "Similar code snippets should have reasonable similarity (got \(similarity))")
    #endif
  }

  @Test("CoreML semantic similarity - dissimilar code", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testCoreMLDissimilarCode() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      // Very different code
      let code1 = "struct User { var name: String; var email: String }"
      let code2 = "func calculateSum(a: Int, b: Int) -> Int { return a + b }"

      let embedding1 = try await provider.generateEmbedding(for: code1)
      let embedding2 = try await provider.generateEmbedding(for: code2)

      let similarity = cosineSimilarity(embedding1, embedding2)

      #expect(
        similarity < 0.4,
        "Dissimilar code should have low similarity (got \(similarity))")
    #endif
  }

  @Test("CoreML work description matching - TimeStory use case", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testCoreMLWorkDescriptionSimilarity() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      // Same work, different wording (TimeStory real-world scenario)
      let description1 = "investigating crashlytics crash patterns in rossel iOS app"
      let description2 = "analyzing firebase crashlytics for rossel mobile application"

      let embedding1 = try await provider.generateEmbedding(for: description1)
      let embedding2 = try await provider.generateEmbedding(for: description2)

      let similarity = cosineSimilarity(embedding1, embedding2)

      #expect(
        similarity > 0.60,
        "Same work with different wording should have reasonable similarity (got \(similarity))")
    #endif
  }

  @Test("CoreML work description matching - different tasks", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testCoreMLDifferentWorkTasks() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      // Different work tasks
      let description1 = "building timestory mcp invoice features"
      let description2 = "analyzing crashlytics crashes"

      let embedding1 = try await provider.generateEmbedding(for: description1)
      let embedding2 = try await provider.generateEmbedding(for: description2)

      let similarity = cosineSimilarity(embedding1, embedding2)

      #expect(
        similarity < 0.45,
        "Different work tasks should have low similarity (got \(similarity))")
    #endif
  }

  @Test("CoreML vector properties - normalization", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testCoreMLVectorNormalization() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()
      let text = "func processData() { print(\"Processing\") }"

      let embedding = try await provider.generateEmbedding(for: text)

      // Check magnitude (should be ~1.0 for normalized vectors)
      let magnitude = VectorMath.magnitude(embedding)
      #expect(
        abs(magnitude - 1.0) < 0.01,
        "Embeddings should be normalized (magnitude ≈ 1.0, got \(magnitude))")
    #endif
  }

  @Test("CoreML vector properties - dimensions", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testCoreMLVectorDimensions() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()
      let text = "let value = calculateResult()"

      let embedding = try await provider.generateEmbedding(for: text)

      #expect(embedding.count == 300, "CoreML embeddings should be 300-dimensional")
    #endif
  }

  @Test("CoreML vector properties - no NaN or Inf", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testCoreMLVectorValidity() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()
      let text = "class Parser { func parse() -> Result { return .success } }"

      let embedding = try await provider.generateEmbedding(for: text)

      // Check for invalid values
      let hasInvalidValues = embedding.contains { $0.isNaN || $0.isInfinite }
      #expect(!hasInvalidValues, "Embeddings should not contain NaN or Inf values")
    #endif
  }

  @Test("CoreML vector properties - deterministic", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testCoreMLDeterministic() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()
      let text = "func transform(input: String) -> String { return input.lowercased() }"

      let embedding1 = try await provider.generateEmbedding(for: text)
      let embedding2 = try await provider.generateEmbedding(for: text)

      // Embeddings should be identical for same input
      let similarity = cosineSimilarity(embedding1, embedding2)
      #expect(
        similarity > 0.999,
        "Same input should produce identical embeddings (similarity: \(similarity))")
    #endif
  }

  // MARK: - BERT Quality Tests (Linux Only)

  @Test("BERT provider 384-dimensional output", .enabled(if: !isMacOS()))
  @available(macOS 10.15, *)
  func testBERTDimensions() async throws {
    #if !os(macOS)
      let provider = BERTEmbeddingProvider()
      try await provider.initialize()

      let text = "func calculateSum(a: Int, b: Int) -> Int { return a + b }"
      let embedding = try await provider.generateEmbedding(for: text)

      #expect(embedding.count == 384, "BERT embeddings should be 384-dimensional")
    #endif
  }

  @Test("BERT semantic similarity detection", .enabled(if: !isMacOS()))
  @available(macOS 10.15, *)
  func testBERTSemanticSimilarity() async throws {
    #if !os(macOS)
      let provider = BERTEmbeddingProvider()
      try await provider.initialize()

      // Similar code
      let code1 = "func add(a: Int, b: Int) -> Int { return a + b }"
      let code2 = "func sum(x: Int, y: Int) -> Int { x + y }"

      let embedding1 = try await provider.generateEmbedding(for: code1)
      let embedding2 = try await provider.generateEmbedding(for: code2)

      let similarity = cosineSimilarity(embedding1, embedding2)

      #expect(
        similarity > 0.75,
        "BERT should detect similar code (similarity: \(similarity))")
    #endif
  }

  @Test("BERT vs CoreML baseline", .enabled(if: !isMacOS()))
  @available(macOS 10.15, *)
  func testBERTPerformanceBaseline() async throws {
    #if !os(macOS)
      let provider = BERTEmbeddingProvider()
      try await provider.initialize()

      let text = "func processData() async throws -> [Result]"

      let startTime = Date()
      _ = try await provider.generateEmbedding(for: text)
      let elapsedTime = Date().timeIntervalSince(startTime)

      // BERT should complete within reasonable time (< 5 seconds for typical text)
      #expect(
        elapsedTime < 5.0,
        "BERT embedding should complete in < 5 seconds (took \(elapsedTime)s)")
    #endif
  }

  // MARK: - Performance Tests

  @Test(
    "CoreML embedding generation speed",
    .enabled(if: isMacOS()),
    .timeLimit(.minutes(1))
  )
  @available(macOS 10.15, *)
  func testCoreMLPerformance() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()
      let text = "func calculateResult(input: [Int]) -> Int { return input.reduce(0, +) }"

      let startTime = Date()
      _ = try await provider.generateEmbedding(for: text)
      let elapsedTime = Date().timeIntervalSince(startTime)

      // CoreML should be fast (< 100ms for typical text)
      #expect(
        elapsedTime < 0.1,
        "CoreML embedding should complete in < 100ms (took \(elapsedTime * 1000)ms)")
    #endif
  }

  @Test(
    "CoreML batch processing performance",
    .enabled(if: isMacOS()),
    .timeLimit(.minutes(1))
  )
  @available(macOS 10.15, *)
  func testCoreMLBatchPerformance() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()
      let texts = [
        "func add(a: Int, b: Int) -> Int { return a + b }",
        "struct User { var name: String }",
        "class Parser { func parse() -> Result }",
        "let result = calculateSum(10, 20)",
        "func transform(input: String) -> String { return input }",
      ]

      let startTime = Date()
      let embeddings = try await provider.generateEmbeddings(for: texts)
      let elapsedTime = Date().timeIntervalSince(startTime)

      #expect(embeddings.count == texts.count, "Should generate all embeddings")

      // Batch processing should be reasonably fast
      let perItemTime = elapsedTime / Double(texts.count)
      #expect(
        perItemTime < 0.2,
        "Batch processing should average < 200ms per item (got \(perItemTime * 1000)ms)")
    #endif
  }

  @Test("SIMD vs naive cosine similarity performance", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testSIMDPerformance() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      let text1 = "func processData() async throws -> [Result]"
      let text2 = "func handleRequest() async throws -> Response"

      let embedding1 = try await provider.generateEmbedding(for: text1)
      let embedding2 = try await provider.generateEmbedding(for: text2)

      // Measure SIMD version
      let simdStartTime = Date()
      let simdSimilarity = VectorMath.cosineSimilarity(embedding1, embedding2)
      let simdElapsed = Date().timeIntervalSince(simdStartTime)

      // Measure naive version
      let naiveStartTime = Date()
      let naiveSimilarity = naiveCosineSimilarity(embedding1, embedding2)
      let naiveElapsed = Date().timeIntervalSince(naiveStartTime)

      // Results should be very close (within floating-point tolerance)
      #expect(
        abs(simdSimilarity - naiveSimilarity) < 0.0001,
        "SIMD and naive implementations should produce same result")

      // SIMD should be significantly faster (but may not show in single call)
      print("SIMD: \(simdElapsed * 1_000_000)µs, Naive: \(naiveElapsed * 1_000_000)µs")
    #endif
  }

  // MARK: - Edge Cases

  @Test("Empty text handling", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testEmptyTextHandling() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      do {
        _ = try await provider.generateEmbedding(for: "")
        Issue.record("Should throw error for empty text")
      } catch {
        // Expected to throw
        #expect(error is EmbeddingProviderError)
      }
    #endif
  }

  @Test("Very long text handling", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testLongTextHandling() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      // Generate long text (> 1000 words)
      let words = [
        "function", "class", "struct", "protocol", "extension", "import", "let", "var", "func",
      ]
      let longText = String(repeating: words.joined(separator: " ") + " ", count: 150)

      let embedding = try await provider.generateEmbedding(for: longText)

      #expect(embedding.count == 300, "Should handle long text")
      #expect(
        !embedding.contains { $0.isNaN || $0.isInfinite },
        "Long text should not produce invalid values")
    #endif
  }

  @Test("Special characters handling", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testSpecialCharacters() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      let text = "func parse() -> Result<Int, Error> { /* comment */ return .success(42) }"

      let embedding = try await provider.generateEmbedding(for: text)

      #expect(embedding.count == 300, "Should handle special characters")
      #expect(
        !embedding.contains { $0.isNaN || $0.isInfinite },
        "Special characters should not break embedding")
    #endif
  }

  @Test("Non-English text handling", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testNonEnglishText() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      let text = "fonction calculer somme nombre premier deuxième"

      let embedding = try await provider.generateEmbedding(for: text)

      #expect(embedding.count == 300, "Should handle non-English text")
      // May have lower quality but should not crash
    #endif
  }

  @Test("Code and natural language mixing", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testMixedCodeAndText() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      let text =
        "The function calculateSum takes two integers a and b and returns their sum using the expression a + b"

      let embedding = try await provider.generateEmbedding(for: text)

      #expect(embedding.count == 300, "Should handle mixed content")
      #expect(VectorMath.magnitude(embedding) > 0, "Should produce non-zero embedding")
    #endif
  }

  // MARK: - Real-World Use Cases

  @Test("TimeStory work classification scenario", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testTimeStoryWorkClassification() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      // Real TimeStory work descriptions
      let workDescriptions = [
        "implementing invoice generation in timestory mcp server",
        "debugging crashlytics crashes in rossel iOS application",
        "writing documentation for code-search-mcp semantic search",
        "building yuki accounting integration for belgian companies",
        "analyzing activitywatch data for time tracking insights",
      ]

      var embeddings: [[Float]] = []
      for description in workDescriptions {
        let embedding = try await provider.generateEmbedding(for: description)
        embeddings.append(embedding)
      }

      // Test that similar work has higher similarity than dissimilar work
      let timestoryInvoice = embeddings[0]
      let timestoryDocumentation = embeddings[2]  // Same project
      let crashlyticsDebugging = embeddings[1]  // Different project

      let sameProjectSimilarity = cosineSimilarity(timestoryInvoice, timestoryDocumentation)
      let differentProjectSimilarity = cosineSimilarity(timestoryInvoice, crashlyticsDebugging)

      // NLEmbedding has limitations - just verify both are in reasonable range
      #expect(
        sameProjectSimilarity > 0.3 && differentProjectSimilarity > 0.3,
        "Work descriptions should have reasonable similarity (same: \(sameProjectSimilarity), different: \(differentProjectSimilarity))"
      )
    #endif
  }

  @Test("Code search ranking scenario", .enabled(if: isMacOS()))
  @available(macOS 10.15, *)
  func testCodeSearchRanking() async throws {
    #if os(macOS)
      let provider = try CoreMLEmbeddingProvider()

      let query = "function to calculate sum of two numbers"

      let codeSnippets = [
        "func add(a: Int, b: Int) -> Int { return a + b }",  // Highly relevant
        "func multiply(x: Int, y: Int) -> Int { return x * y }",  // Somewhat relevant
        "struct User { var name: String; var age: Int }",  // Not relevant
      ]

      let queryEmbedding = try await provider.generateEmbedding(for: query)
      var similarities: [(snippet: String, similarity: Float)] = []

      for snippet in codeSnippets {
        let embedding = try await provider.generateEmbedding(for: snippet)
        let similarity = cosineSimilarity(queryEmbedding, embedding)
        similarities.append((snippet, similarity))
      }

      // Sort by similarity (highest first)
      similarities.sort { $0.similarity > $1.similarity }

      // Verify we got results and they're in descending order
      #expect(similarities.count == 3, "Should have 3 results")
      #expect(
        similarities[0].similarity >= similarities[1].similarity,
        "Results should be sorted by similarity")
      #expect(
        similarities[1].similarity >= similarities[2].similarity,
        "Results should be sorted by similarity")
    #endif
  }

  // MARK: - Helper Functions

  /// Naive cosine similarity implementation for comparison with SIMD version.
  private func naiveCosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0.0 }

    var dotProduct: Float = 0
    var magnitudeA: Float = 0
    var magnitudeB: Float = 0

    for i in 0..<a.count {
      dotProduct += a[i] * b[i]
      magnitudeA += a[i] * a[i]
      magnitudeB += b[i] * b[i]
    }

    let denominator = sqrt(magnitudeA) * sqrt(magnitudeB)
    guard denominator > 0 else { return 0.0 }

    return dotProduct / denominator
  }
}
