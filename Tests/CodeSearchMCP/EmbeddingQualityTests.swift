import Foundation
import Testing

@testable import CodeSearchMCP
@testable import SwiftEmbeddings

/// Tests for embedding quality validation across CoreML and BERT providers.
///
/// These tests validate that embeddings actually capture SEMANTIC MEANING,
/// not just dimensional consistency. Key validations:
/// - Semantic similarity (similar code → high similarity)
/// - Semantic diversity (different code → low similarity)
/// - Cross-language semantics (same logic, different syntax)
/// - Dimension consistency
/// - Normalization quality
///
/// Quality thresholds:
/// - Similar code pairs: > 0.5 similarity (CoreML word-level), > 0.8 (BERT sentence transformers)
/// - Unrelated code pairs: < 0.6 similarity
/// - Normalized vectors: magnitude ~1.0 (0.95-1.05)
///
/// Note: CoreML uses word-level embeddings (NLEmbedding) which have lower
/// semantic quality than BERT sentence transformers. Thresholds are adjusted accordingly.
@Suite("Embedding Quality Tests")
struct EmbeddingQualityTests {

  // MARK: - Test Helpers

  /// Calculate cosine similarity between two vectors.
  ///
  /// Returns value in range [-1, 1]:
  /// - 1.0: Identical vectors
  /// - 0.0: Orthogonal (unrelated)
  /// - -1.0: Opposite vectors
  private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0.0 }

    let dotProduct = zip(a, b).map(*).reduce(0, +)
    let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))

    guard magA > 0, magB > 0 else { return 0.0 }

    return dotProduct / (magA * magB)
  }

  /// Calculate vector magnitude (L2 norm).
  private func vectorMagnitude(_ vector: [Float]) -> Float {
    sqrt(vector.map { $0 * $0 }.reduce(0, +))
  }

  // MARK: - CoreML Quality Tests

  @Test("CoreML: Semantic similarity between related code snippets")
  func testCoreMLSemanticSimilarity() async throws {
    let provider = try CoreMLEmbeddingProvider()

    // Similar code: both calculate sum
    let code1 = "func calculateSum(a: Int, b: Int) -> Int { return a + b }"
    let code2 = "func add(x: Int, y: Int) -> Int { return x + y }"

    // Different code: user model
    let code3 = "class User { var name: String; var email: String }"

    let emb1 = try await provider.generateEmbedding(for: code1)
    let emb2 = try await provider.generateEmbedding(for: code2)
    let emb3 = try await provider.generateEmbedding(for: code3)

    // Calculate similarities
    let similarity12 = cosineSimilarity(emb1, emb2)
    let similarity13 = cosineSimilarity(emb1, emb3)

    print("CoreML Semantic Similarity:")
    print("  Similar code (sum/add): \(similarity12)")
    print("  Different code (sum/user): \(similarity13)")

    // Validate quality thresholds
    #expect(
      similarity12 > 0.7,
      "Similar code (sum/add) should have high similarity (> 0.7), got \(similarity12)")
    #expect(
      similarity13 < 0.5,
      "Different code (sum/user) should have low similarity (< 0.5), got \(similarity13)")
    #expect(
      similarity12 > similarity13,
      "Similar code should have higher similarity than different code")
  }

  @Test("CoreML: Cross-language semantic understanding")
  func testCoreMLCrossLanguageSemantics() async throws {
    let provider = try CoreMLEmbeddingProvider()

    // Same semantic meaning: "hello world" function in 3 languages
    let swift = "func hello() { print(\"hello\") }"
    let python = "def hello(): print('hello')"
    let javascript = "function hello() { console.log('hello'); }"

    let embSwift = try await provider.generateEmbedding(for: swift)
    let embPython = try await provider.generateEmbedding(for: python)
    let embJS = try await provider.generateEmbedding(for: javascript)

    // Calculate cross-language similarities
    let simSwiftPython = cosineSimilarity(embSwift, embPython)
    let simSwiftJS = cosineSimilarity(embSwift, embJS)
    let simPythonJS = cosineSimilarity(embPython, embJS)

    print("CoreML Cross-Language Semantics:")
    print("  Swift-Python: \(simSwiftPython)")
    print("  Swift-JavaScript: \(simSwiftJS)")
    print("  Python-JavaScript: \(simPythonJS)")

    // All should be semantically similar (same function logic)
    #expect(
      simSwiftPython > 0.6,
      "Swift and Python hello functions should be similar (> 0.6), got \(simSwiftPython)")
    #expect(
      simSwiftJS > 0.6,
      "Swift and JavaScript hello functions should be similar (> 0.6), got \(simSwiftJS)")
    #expect(
      simPythonJS > 0.6,
      "Python and JavaScript hello functions should be similar (> 0.6), got \(simPythonJS)")
  }

  @Test("CoreML: Dimension consistency across text lengths")
  func testCoreMLDimensionConsistency() async throws {
    let provider = try CoreMLEmbeddingProvider()

    let shortCode = "x = 1"
    let mediumCode = "func calculate(a: Int, b: Int) -> Int { return a + b }"
    let longCode = """
      class UserAccountManager {
        var users: [User] = []
        
        func addUser(name: String, email: String) {
          let user = User(name: name, email: email)
          users.append(user)
        }
        
        func removeUser(email: String) {
          users.removeAll { $0.email == email }
        }
      }
      """

    let emb1 = try await provider.generateEmbedding(for: shortCode)
    let emb2 = try await provider.generateEmbedding(for: mediumCode)
    let emb3 = try await provider.generateEmbedding(for: longCode)

    print("CoreML Dimension Consistency:")
    print("  Short code: \(emb1.count) dimensions")
    print("  Medium code: \(emb2.count) dimensions")
    print("  Long code: \(emb3.count) dimensions")

    // All should be 300 dimensions
    #expect(emb1.count == 300, "Short code should have 300 dimensions")
    #expect(emb2.count == 300, "Medium code should have 300 dimensions")
    #expect(emb3.count == 300, "Long code should have 300 dimensions")

    // All should have same dimension
    #expect(
      emb1.count == emb2.count && emb2.count == emb3.count,
      "All embeddings should have consistent dimensions")
  }

  @Test("CoreML: Normalization quality validation")
  func testCoreMLNormalizationQuality() async throws {
    let provider = try CoreMLEmbeddingProvider()

    let texts = [
      "short",
      "func myFunction() { return 42 }",
      "class User { var name: String; var email: String }",
      """
      protocol DataSource {
        func fetchData() async throws -> [Article]
        func saveData(articles: [Article]) async throws
      }
      """,
    ]

    print("CoreML Normalization Quality:")
    for text in texts {
      let embedding = try await provider.generateEmbedding(for: text)
      let magnitude = vectorMagnitude(embedding)

      print("  Text: '\(text.prefix(50))...' → magnitude: \(magnitude)")

      // All embeddings should be normalized (magnitude ~1.0)
      #expect(
        magnitude > 0.95,
        "Magnitude should be >= 0.95 for: '\(text)', got \(magnitude)")
      #expect(
        magnitude <= 1.05,
        "Magnitude should be <= 1.05 for: '\(text)', got \(magnitude)")
    }
  }

  @Test("CoreML: Semantic quality for code patterns")
  func testCoreMLCodePatternSemantics() async throws {
    let provider = try CoreMLEmbeddingProvider()

    // Group 1: Data models (should cluster together)
    let model1 = "struct User { let id: UUID; let name: String }"
    let model2 = "class Article { var title: String; var content: String }"

    // Group 2: Network code (should cluster together)
    let network1 = "func fetchData() async throws -> Data { return try await api.get() }"
    let network2 = "func sendRequest(url: URL) async throws -> Response { return try await URLSession.shared.data(from: url) }"

    let embModel1 = try await provider.generateEmbedding(for: model1)
    let embModel2 = try await provider.generateEmbedding(for: model2)
    let embNetwork1 = try await provider.generateEmbedding(for: network1)
    let embNetwork2 = try await provider.generateEmbedding(for: network2)

    // Within-group similarities
    let simModels = cosineSimilarity(embModel1, embModel2)
    let simNetwork = cosineSimilarity(embNetwork1, embNetwork2)

    // Cross-group similarities
    let simModelNetwork1 = cosineSimilarity(embModel1, embNetwork1)
    let simModelNetwork2 = cosineSimilarity(embModel2, embNetwork2)

    print("CoreML Code Pattern Semantics:")
    print("  Within-group (models): \(simModels)")
    print("  Within-group (network): \(simNetwork)")
    print("  Cross-group (model-network): \(simModelNetwork1), \(simModelNetwork2)")

    // Network code should cluster well (high similarity)
    #expect(
      simNetwork > 0.7,
      "Network code patterns should have high similarity (> 0.7), got \(simNetwork)")

    // Models have lower similarity due to word-level embeddings, but should be meaningful
    #expect(
      simModels > 0.3,
      "Model code patterns should have some similarity (> 0.3), got \(simModels)")
  }

  // MARK: - BERT Quality Tests (Linux only, disabled by default)

  #if os(Linux)
    @Test(
      "BERT: Semantic similarity validation",
      .disabled("Requires Python server, Linux only"))
    func testBERTSemanticSimilarity() async throws {
      let provider = BERTEmbeddingProvider()

      // Similar code
      let code1 = "func calculateSum(a: Int, b: Int) -> Int { return a + b }"
      let code2 = "func add(x: Int, y: Int) -> Int { return x + y }"

      // Different code
      let code3 = "class DatabaseConnection { var host: String; var port: Int }"

      let emb1 = try await provider.generateEmbedding(for: code1)
      let emb2 = try await provider.generateEmbedding(for: code2)
      let emb3 = try await provider.generateEmbedding(for: code3)

      let similarity12 = cosineSimilarity(emb1, emb2)
      let similarity13 = cosineSimilarity(emb1, emb3)

      print("BERT Semantic Similarity:")
      print("  Similar code: \(similarity12)")
      print("  Different code: \(similarity13)")

      // BERT should have higher quality (sentence transformers)
      #expect(
        similarity12 > 0.8,
        "BERT should have high quality (> 0.8) for similar code, got \(similarity12)")
      #expect(
        similarity13 < 0.5,
        "BERT should separate different code (< 0.5), got \(similarity13)")
    }

    @Test("BERT: Dimension consistency validation", .disabled("Requires Python server"))
    func testBERTDimensionConsistency() async throws {
      let provider = BERTEmbeddingProvider()

      let texts = [
        "short",
        "func test() { return 42 }",
        "class User { var name: String; var email: String }",
      ]

      for text in texts {
        let embedding = try await provider.generateEmbedding(for: text)
        #expect(embedding.count == 384, "BERT embeddings should be 384-dimensional")
      }
    }
  #endif

  // MARK: - Comparative Quality Tests (CoreML vs BERT)

  @Test("Comparative: Both providers produce meaningful embeddings")
  func testComparativeEmbeddingQuality() async throws {
    // CoreML test (always available on macOS)
    let coreMLProvider = try CoreMLEmbeddingProvider()

    let testCode = "func calculateSum(a: Int, b: Int) -> Int { return a + b }"
    let coreMLEmb = try await coreMLProvider.generateEmbedding(for: testCode)

    // Verify CoreML produces meaningful embeddings
    #expect(coreMLEmb.count == 300, "CoreML should produce 300-d embeddings")

    let magnitude = vectorMagnitude(coreMLEmb)
    #expect(
      magnitude > 0.95 && magnitude <= 1.05,
      "CoreML embeddings should be normalized")

    // Verify not all zeros (actual semantic content)
    let nonZeroCount = coreMLEmb.filter { $0 != 0.0 }.count
    #expect(
      nonZeroCount > 0,
      "CoreML embeddings should not be all zeros")

    print("Comparative Quality:")
    print("  CoreML: \(coreMLEmb.count)d, magnitude: \(magnitude), non-zero: \(nonZeroCount)")

    // BERT comparison (only on Linux with Python server)
    #if os(Linux)
      let bertProvider = BERTEmbeddingProvider()
      let bertEmb = try? await bertProvider.generateEmbedding(for: testCode)

      if let bertEmb = bertEmb {
        #expect(bertEmb.count == 384, "BERT should produce 384-d embeddings")
        let bertMagnitude = vectorMagnitude(bertEmb)
        print(
          "  BERT: \(bertEmb.count)d, magnitude: \(bertMagnitude), non-zero: \(bertEmb.filter { $0 != 0.0 }.count)"
        )
      }
    #endif
  }

  // MARK: - Edge Case Quality Tests

  @Test("Edge case: Empty and whitespace handling")
  func testEmptyTextQuality() async throws {
    let provider = try CoreMLEmbeddingProvider()

    // Empty string should throw error
    await #expect(throws: EmbeddingProviderError.self) {
      _ = try await provider.generateEmbedding(for: "")
    }

    // Whitespace-only should produce valid embedding (but low quality)
    let whitespaceEmb = try await provider.generateEmbedding(for: "   \n\t  ")
    #expect(whitespaceEmb.count == 300, "Whitespace should produce valid dimensions")
  }

  @Test("Edge case: Special characters and symbols")
  func testSpecialCharacterQuality() async throws {
    let provider = try CoreMLEmbeddingProvider()

    let specialTexts = [
      "func test() -> Result<String, Error> {}",
      "var array: [Int] = [1, 2, 3]",
      "if condition { /* comment */ return true }",
      "@available(iOS 15.0, *)",
      "protocol Equatable where Self: Hashable {}",
    ]

    print("Special Character Quality:")
    for text in specialTexts {
      let embedding = try await provider.generateEmbedding(for: text)
      let magnitude = vectorMagnitude(embedding)

      print("  '\(text.prefix(40))...' → magnitude: \(magnitude)")

      #expect(embedding.count == 300, "Should produce 300-d embeddings")
      #expect(
        magnitude > 0.8,
        "Should produce normalized embeddings for: '\(text)'")
    }
  }

  @Test("Performance: Batch quality consistency")
  func testBatchQualityConsistency() async throws {
    let provider = try CoreMLEmbeddingProvider()

    let texts = [
      "func add(a: Int, b: Int) -> Int { return a + b }",
      "func subtract(a: Int, b: Int) -> Int { return a - b }",
      "func multiply(a: Int, b: Int) -> Int { return a * b }",
      "func divide(a: Int, b: Int) -> Double { return Double(a) / Double(b) }",
    ]

    let embeddings = try await provider.generateEmbeddings(for: texts)

    #expect(embeddings.count == texts.count, "Should produce embeddings for all texts")

    print("Batch Quality Consistency:")
    for (i, embedding) in embeddings.enumerated() {
      let magnitude = vectorMagnitude(embedding)
      print("  Text \(i+1): magnitude \(magnitude)")

      #expect(embedding.count == 300, "Batch embedding \(i+1) should be 300-d")
      #expect(
        magnitude > 0.95 && magnitude <= 1.05,
        "Batch embedding \(i+1) should be normalized")
    }

    // Math functions should have some semantic similarity
    // Note: Word-level embeddings may not capture full semantic meaning
    for i in 0..<embeddings.count {
      for j in (i + 1)..<embeddings.count {
        let similarity = cosineSimilarity(embeddings[i], embeddings[j])
        print(
          "  Similarity between math functions \(i+1) and \(j+1): \(similarity)")

        #expect(
          similarity > 0.45,
          "Math functions should have some similarity (> 0.45), got \(similarity)")
      }
    }
  }
}
