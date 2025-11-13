import Foundation
import Accelerate

/// Utilities for vector mathematics operations.
///
/// Provides SIMD-optimized implementations using the Accelerate framework
/// for maximum performance on Apple Silicon and Intel processors.
public enum VectorMath {

  /// Compute cosine similarity between two vectors using SIMD operations.
  ///
  /// Uses Accelerate framework for ~10x speedup over naive implementation.
  /// Measures angle between vectors; result ranges from -1 to 1
  /// where 1 indicates perfect similarity.
  ///
  /// Formula: cos(θ) = (a · b) / (||a|| * ||b||)
  ///
  /// - Parameters:
  ///   - vector1: First embedding vector
  ///   - vector2: Second embedding vector
  /// - Returns: Cosine similarity score (-1.0 to 1.0)
  public static func cosineSimilarity(_ vector1: [Float], _ vector2: [Float]) -> Float {
    guard vector1.count == vector2.count, !vector1.isEmpty else {
      return 0.0
    }

    let count = vDSP_Length(vector1.count)
    var dotProduct: Float = 0
    var magnitudeSquared1: Float = 0
    var magnitudeSquared2: Float = 0

    // Compute dot product and magnitudes using SIMD
    vDSP_dotpr(vector1, 1, vector2, 1, &dotProduct, count)
    vDSP_svesq(vector1, 1, &magnitudeSquared1, count)
    vDSP_svesq(vector2, 1, &magnitudeSquared2, count)

    let denominator = sqrt(magnitudeSquared1) * sqrt(magnitudeSquared2)
    guard denominator > 0 else {
      return 0.0
    }

    return dotProduct / denominator
  }

  /// Compute cosine similarity with ContiguousArray for better performance.
  ///
  /// - Parameters:
  ///   - a: First embedding vector (contiguous)
  ///   - b: Second embedding vector (contiguous)
  /// - Returns: Cosine similarity score
  public static func cosineSimilaritySIMD(
    _ a: ContiguousArray<Float>,
    _ b: ContiguousArray<Float>
  ) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0.0 }

    let count = vDSP_Length(a.count)

    return a.withUnsafeBufferPointer { aPtr in
      b.withUnsafeBufferPointer { bPtr in
        guard let aBase = aPtr.baseAddress,
              let bBase = bPtr.baseAddress else { return Float(0) }

        // Compute dot product using SIMD
        var dotProduct: Float = 0
        vDSP_dotpr(aBase, 1, bBase, 1, &dotProduct, count)

        // Compute squared magnitudes using SIMD
        var magnitudeSquaredA: Float = 0
        var magnitudeSquaredB: Float = 0
        vDSP_svesq(aBase, 1, &magnitudeSquaredA, count)
        vDSP_svesq(bBase, 1, &magnitudeSquaredB, count)

        // Compute cosine similarity
        let denominator = sqrt(magnitudeSquaredA) * sqrt(magnitudeSquaredB)
        guard denominator > 0 else { return 0.0 }

        return dotProduct / denominator
      }
    }
  }

  /// Calculate vector magnitude (L2 norm).
  ///
  /// - Parameter vector: Input vector
  /// - Returns: Magnitude (always >= 0)
  public static func magnitude(_ vector: [Float]) -> Float {
    sqrt(vector.reduce(0) { $0 + ($1 * $1) })
  }

  /// Normalize a vector to unit length.
  ///
  /// - Parameter vector: Input vector
  /// - Returns: Normalized vector (magnitude = 1.0)
  public static func normalize(_ vector: [Float]) -> [Float] {
    let mag = magnitude(vector)
    guard mag > 0 else { return vector }
    return vector.map { $0 / mag }
  }
}
