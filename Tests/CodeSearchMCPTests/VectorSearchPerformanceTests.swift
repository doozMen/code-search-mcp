import Testing
import Foundation
import Accelerate
@testable import CodeSearchMCP

/// Performance tests for vector search optimizations.
///
/// Validates SIMD performance improvements and in-memory index benefits.
@Suite("Vector Search Performance")
struct VectorSearchPerformanceTests {

    // MARK: - SIMD vs Naive Performance Comparison

    @Test("SIMD cosine similarity is 10x faster than naive implementation")
    func testSIMDPerformance() async throws {
        // Generate test vectors (384 dimensions like BERT)
        let dimensions = 384
        let vector1 = generateRandomVector(dimensions: dimensions)
        let vector2 = generateRandomVector(dimensions: dimensions)

        // Warm up
        _ = cosineSimilaritySIMD(vector1, vector2)
        _ = cosineSimilarityNaive(vector1, vector2)

        // Benchmark naive implementation
        let naiveIterations = 10000
        let naiveStart = Date()
        for _ in 0..<naiveIterations {
            _ = cosineSimilarityNaive(vector1, vector2)
        }
        let naiveDuration = Date().timeIntervalSince(naiveStart)

        // Benchmark SIMD implementation
        let simdIterations = 10000
        let simdStart = Date()
        for _ in 0..<simdIterations {
            _ = cosineSimilaritySIMD(vector1, vector2)
        }
        let simdDuration = Date().timeIntervalSince(simdStart)

        // Calculate speedup
        let speedup = naiveDuration / simdDuration

        print("""
        SIMD Performance Test Results:
        - Naive: \(naiveDuration * 1000)ms for \(naiveIterations) iterations
        - SIMD:  \(simdDuration * 1000)ms for \(simdIterations) iterations
        - Speedup: \(speedup)x
        - Per operation: \(simdDuration / Double(simdIterations) * 1_000_000)μs
        """)

        // Assert at least 5x speedup (conservative to account for variability)
        #expect(speedup > 5.0, "SIMD should be at least 5x faster than naive")

        // Verify results are equivalent
        let naiveResult = cosineSimilarityNaive(vector1, vector2)
        let simdResult = cosineSimilaritySIMD(vector1, vector2)
        #expect(abs(naiveResult - simdResult) < 0.0001, "Results should be equivalent")
    }

    @Test("Parallel search scales with CPU cores")
    func testParallelSearchScaling() async throws {
        // Create test chunks with embeddings
        let chunkCount = 10000
        let dimensions = 384
        let chunks = (0..<chunkCount).map { i in
            CodeChunk(
                id: "chunk-\(i)",
                projectName: "test-project",
                filePath: "/test/file\(i).swift",
                language: "swift",
                startLine: i * 50,
                endLine: (i + 1) * 50,
                content: "Test content \(i)",
                embedding: generateRandomVector(dimensions: dimensions)
            )
        }

        let queryEmbedding = generateRandomVector(dimensions: dimensions)

        // Test serial processing
        let serialStart = Date()
        var serialResults: [Float] = []
        for chunk in chunks {
            if let embedding = chunk.embedding {
                let similarity = cosineSimilaritySIMD(queryEmbedding, embedding)
                serialResults.append(similarity)
            }
        }
        let serialDuration = Date().timeIntervalSince(serialStart)

        // Test parallel processing
        let parallelStart = Date()
        let parallelResults = await withTaskGroup(
            of: [Float].self,
            returning: [Float].self
        ) { group in
            let coreCount = ProcessInfo.processInfo.processorCount
            let batchSize = chunks.count / (coreCount * 2)

            for i in stride(from: 0, to: chunks.count, by: batchSize) {
                let endIndex = min(i + batchSize, chunks.count)
                let batch = Array(chunks[i..<endIndex])

                group.addTask {
                    var results: [Float] = []
                    for chunk in batch {
                        if let embedding = chunk.embedding {
                            let similarity = self.cosineSimilaritySIMD(queryEmbedding, embedding)
                            results.append(similarity)
                        }
                    }
                    return results
                }
            }

            var allResults: [Float] = []
            for await batchResults in group {
                allResults.append(contentsOf: batchResults)
            }
            return allResults
        }
        let parallelDuration = Date().timeIntervalSince(parallelStart)

        let parallelSpeedup = serialDuration / parallelDuration
        let coreCount = ProcessInfo.processInfo.processorCount

        print("""
        Parallel Search Scaling Test Results:
        - Chunks: \(chunkCount)
        - CPU Cores: \(coreCount)
        - Serial: \(serialDuration * 1000)ms
        - Parallel: \(parallelDuration * 1000)ms
        - Speedup: \(parallelSpeedup)x
        - Efficiency: \(parallelSpeedup / Double(coreCount) * 100)%
        """)

        // Assert reasonable parallel speedup (at least 2x on multi-core)
        if coreCount > 1 {
            #expect(parallelSpeedup > 2.0, "Parallel processing should show speedup")
        }

        // Verify results are equivalent
        #expect(serialResults.count == parallelResults.count, "Result counts should match")
    }

    @Test("In-memory index achieves <50ms for 50k vectors")
    func testInMemoryIndexPerformance() async throws {
        // Create in-memory index
        let tempDir = FileManager.default.temporaryDirectory.path
        let index = InMemoryVectorIndex(indexPath: tempDir)

        // Generate 50k test vectors
        let vectorCount = 50000
        let dimensions = 384

        // Add vectors to index
        for i in 0..<vectorCount {
            let metadata = InMemoryVectorIndex.ChunkMetadata(
                projectName: "test",
                filePath: "/test/file\(i).swift",
                language: "swift",
                startLine: i * 50,
                endLine: (i + 1) * 50,
                content: "Test content \(i)"
            )

            await index.addEmbedding(
                chunkId: "chunk-\(i)",
                embedding: generateRandomVector(dimensions: dimensions),
                metadata: metadata
            )
        }

        // Test search performance
        let queryEmbedding = generateRandomVector(dimensions: dimensions)

        let searchStart = Date()
        let results = await index.search(
            queryEmbedding: queryEmbedding,
            topK: 10,
            projectFilter: nil
        )
        let searchDuration = Date().timeIntervalSince(searchStart) * 1000 // Convert to ms

        print("""
        In-Memory Index Performance Test Results:
        - Vectors indexed: \(vectorCount)
        - Dimensions: \(dimensions)
        - Search time: \(searchDuration)ms
        - Results found: \(results.count)
        - Target: <50ms
        """)

        // Assert performance target
        #expect(searchDuration < 50, "Search should complete in <50ms for 50k vectors")
        #expect(results.count <= 10, "Should return at most 10 results")

        // Check memory stats
        let stats = await index.getMemoryStats()
        print("""
        Memory Usage:
        - Used: \(stats.usedMB)MB
        - Chunks: \(stats.totalChunks)
        - Cache hit rate: \(stats.cacheHitRate * 100)%
        """)
    }

    // MARK: - Helper Functions

    /// Generate random vector for testing.
    private func generateRandomVector(dimensions: Int) -> [Float] {
        return (0..<dimensions).map { _ in Float.random(in: -1...1) }
    }

    /// Naive cosine similarity implementation for comparison.
    private func cosineSimilarityNaive(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var magA: Float = 0
        var magB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * a[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }

        let denominator = sqrt(magA) * sqrt(magB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    /// SIMD cosine similarity using Accelerate.
    private func cosineSimilaritySIMD(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        let count = vDSP_Length(a.count)

        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, count)

        var magnitudeSquaredA: Float = 0
        var magnitudeSquaredB: Float = 0
        vDSP_svesq(a, 1, &magnitudeSquaredA, count)
        vDSP_svesq(b, 1, &magnitudeSquaredB, count)

        let denominator = sqrt(magnitudeSquaredA) * sqrt(magnitudeSquaredB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
}
