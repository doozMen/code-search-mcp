#!/usr/bin/env swift

import Foundation
import Accelerate

// SIMD cosine similarity using Accelerate
func cosineSimilaritySIMD(_ a: [Float], _ b: [Float]) -> Float {
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

// Naive cosine similarity
func cosineSimilarityNaive(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    
    var dotProduct: Float = 0
    var magA: Float = 0
    var magB: Float = 0
    
    for i in 0..<a.count {
        dotProduct += a[i] * b[i]
        magA += a[i] * a[i]
        magB += b[i] * b[i]
    }
    
    let denominator = sqrt(magA) * sqrt(magB)
    guard denominator > 0 else { return 0 }
    
    return dotProduct / denominator
}

// Generate random vector
func generateRandomVector(dimensions: Int) -> [Float] {
    return (0..<dimensions).map { _ in Float.random(in: -1...1) }
}

// Run benchmark
func runBenchmark() {
    print("SIMD Vector Search Performance Benchmark")
    print("=========================================\n")
    
    let dimensions = 384  // BERT embedding size
    let iterations = 10000
    
    // Generate test vectors
    let vector1 = generateRandomVector(dimensions: dimensions)
    let vector2 = generateRandomVector(dimensions: dimensions)
    
    // Warm up
    _ = cosineSimilaritySIMD(vector1, vector2)
    _ = cosineSimilarityNaive(vector1, vector2)
    
    // Benchmark naive implementation
    print("Benchmarking naive implementation...")
    let naiveStart = Date()
    for _ in 0..<iterations {
        _ = cosineSimilarityNaive(vector1, vector2)
    }
    let naiveDuration = Date().timeIntervalSince(naiveStart)
    
    // Benchmark SIMD implementation
    print("Benchmarking SIMD implementation...")
    let simdStart = Date()
    for _ in 0..<iterations {
        _ = cosineSimilaritySIMD(vector1, vector2)
    }
    let simdDuration = Date().timeIntervalSince(simdStart)
    
    // Results
    let speedup = naiveDuration / simdDuration
    
    print("\n📊 Results:")
    print("===========")
    print("Vector dimensions: \(dimensions)")
    print("Iterations: \(iterations)")
    print("")
    print("Naive implementation:")
    print("  Total time: \(String(format: "%.3f", naiveDuration * 1000))ms")
    print("  Per operation: \(String(format: "%.3f", naiveDuration / Double(iterations) * 1_000_000))μs")
    print("")
    print("SIMD implementation:")
    print("  Total time: \(String(format: "%.3f", simdDuration * 1000))ms")
    print("  Per operation: \(String(format: "%.3f", simdDuration / Double(iterations) * 1_000_000))μs")
    print("")
    print("🚀 Speedup: \(String(format: "%.2f", speedup))x faster")
    
    // Verify correctness
    let naiveResult = cosineSimilarityNaive(vector1, vector2)
    let simdResult = cosineSimilaritySIMD(vector1, vector2)
    let difference = abs(naiveResult - simdResult)
    
    print("\n✅ Correctness check:")
    print("  Naive result: \(naiveResult)")
    print("  SIMD result: \(simdResult)")
    print("  Difference: \(difference)")
    print("  Match: \(difference < 0.0001 ? "YES ✓" : "NO ✗")")
    
    // Test with different vector sizes
    print("\n📈 Performance across different vector sizes:")
    print("==============================================")
    
    for size in [128, 256, 384, 512, 768, 1024] {
        let v1 = generateRandomVector(dimensions: size)
        let v2 = generateRandomVector(dimensions: size)
        
        let testIterations = 5000
        
        let naiveStart = Date()
        for _ in 0..<testIterations {
            _ = cosineSimilarityNaive(v1, v2)
        }
        let naiveTime = Date().timeIntervalSince(naiveStart)
        
        let simdStart = Date()
        for _ in 0..<testIterations {
            _ = cosineSimilaritySIMD(v1, v2)
        }
        let simdTime = Date().timeIntervalSince(simdStart)
        
        let speedup = naiveTime / simdTime
        print("  \(size) dimensions: \(String(format: "%.2f", speedup))x speedup")
    }
    
    print("\n✅ Benchmark complete!")
}

// Run the benchmark
runBenchmark()
