import Foundation
import Testing

@testable import CodeSearchMCP

/// Comprehensive test suite for CodeMetadataExtractor.
///
/// Tests cover:
/// - Dependency extraction (Swift, Python, JavaScript, Java)
/// - Dependency graph building
/// - Graph persistence and loading
/// - Transitive dependency traversal
@Suite("CodeMetadataExtractor Tests")
struct CodeMetadataExtractorTests {
  // MARK: - Test Helpers

  private static func createTempDir() throws -> String {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).path
    try FileManager.default.createDirectory(
      atPath: tempDir,
      withIntermediateDirectories: true
    )
    return tempDir
  }

  private static func cleanupTempDir(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }

  // MARK: - Initialization Tests

  @Test("CodeMetadataExtractor creates dependency directory")
  func testInitialization() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let extractor = CodeMetadataExtractor(indexPath: tempDir)

    let dependencyDir = (tempDir as NSString).appendingPathComponent("dependencies")
    #expect(FileManager.default.fileExists(atPath: dependencyDir))
  }

  // MARK: - Dependency Extraction Tests

  @Test("Extract Swift import statements")
  func testSwiftDependencies() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let extractor = CodeMetadataExtractor(indexPath: tempDir)

    let swiftCode = """
      import Foundation
      import SwiftUI
      import Combine

      class MyClass {
        // implementation
      }
      """

    let dependencies = try await extractor.extractDependencies(
      from: "MyClass.swift",
      content: swiftCode,
      language: "swift"
    )

    #expect(dependencies.count == 3)
    #expect(dependencies.contains { $0.target == "Foundation" })
    #expect(dependencies.contains { $0.target == "SwiftUI" })
    #expect(dependencies.contains { $0.target == "Combine" })
  }

  @Test("Extract Python import statements")
  func testPythonDependencies() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let extractor = CodeMetadataExtractor(indexPath: tempDir)

    let pythonCode = """
      import os
      import sys
      from datetime import datetime
      from typing import List, Dict

      def my_function():
        pass
      """

    let dependencies = try await extractor.extractDependencies(
      from: "module.py",
      content: pythonCode,
      language: "python"
    )

    // Currently returns empty (not yet implemented)
    #expect(dependencies.isEmpty)
  }

  @Test("Extract JavaScript import statements")
  func testJavaScriptDependencies() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let extractor = CodeMetadataExtractor(indexPath: tempDir)

    let jsCode = """
      import React from 'react';
      import { useState } from 'react';
      const lodash = require('lodash');

      function Component() {
        return <div>Hello</div>;
      }
      """

    let dependencies = try await extractor.extractDependencies(
      from: "Component.js",
      content: jsCode,
      language: "javascript"
    )

    // Currently returns empty (not yet implemented)
    #expect(dependencies.isEmpty)
  }

  @Test("Extract Java import statements")
  func testJavaDependencies() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let extractor = CodeMetadataExtractor(indexPath: tempDir)

    let javaCode = """
      import java.util.List;
      import java.util.ArrayList;
      import com.example.MyClass;

      public class Test {
        // implementation
      }
      """

    let dependencies = try await extractor.extractDependencies(
      from: "Test.java",
      content: javaCode,
      language: "java"
    )

    // Currently returns empty (not yet implemented)
    #expect(dependencies.isEmpty)
  }

  // MARK: - Dependency Graph Tests

  @Test("Build dependency graph from dependencies")
  func testBuildDependencyGraph() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let extractor = CodeMetadataExtractor(indexPath: tempDir)

    let dependencies = [
      Dependency(kind: "module", target: "Foundation", sourceFile: "A.swift", lineNumber: 1),
      Dependency(kind: "module", target: "SwiftUI", sourceFile: "A.swift", lineNumber: 2),
      Dependency(kind: "module", target: "Foundation", sourceFile: "B.swift", lineNumber: 1),
      Dependency(kind: "module", target: "A", sourceFile: "B.swift", lineNumber: 3),
    ]

    try await extractor.buildDependencyGraph(for: "test-project", dependencies: dependencies)

    // Verify graph file was created
    let graphPath = (tempDir as NSString).appendingPathComponent("dependencies")
    let graphFile = (graphPath as NSString).appendingPathComponent("test-project.graph.json")
    #expect(FileManager.default.fileExists(atPath: graphFile))
  }

  @Test("Load dependency graph from disk")
  func testLoadDependencyGraph() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let extractor = CodeMetadataExtractor(indexPath: tempDir)

    // Build and store a graph
    let dependencies = [
      Dependency(kind: "module", target: "Foundation", sourceFile: "A.swift", lineNumber: 1)
    ]

    try await extractor.buildDependencyGraph(for: "test-project", dependencies: dependencies)

    // Load it back
    let graph = try await extractor.getDependencyGraph(for: "test-project")

    #expect(graph.projectName == "test-project")
    #expect(!graph.importsMap.isEmpty || !graph.importedByMap.isEmpty)
  }

  @Test("Load nonexistent graph returns empty")
  func testLoadNonexistentGraph() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let extractor = CodeMetadataExtractor(indexPath: tempDir)

    let graph = try await extractor.getDependencyGraph(for: "nonexistent")

    #expect(graph.projectName == "nonexistent")
    #expect(graph.importsMap.isEmpty)
    #expect(graph.importedByMap.isEmpty)
  }

  @Test("Clear dependency graph removes file")
  func testClearDependencyGraph() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let extractor = CodeMetadataExtractor(indexPath: tempDir)

    // Create a graph
    let dependencies = [
      Dependency(kind: "module", target: "Foundation", sourceFile: "A.swift", lineNumber: 1)
    ]
    try await extractor.buildDependencyGraph(for: "test-project", dependencies: dependencies)

    let graphPath = (tempDir as NSString).appendingPathComponent("dependencies")
    let graphFile = (graphPath as NSString).appendingPathComponent("test-project.graph.json")
    #expect(FileManager.default.fileExists(atPath: graphFile))

    // Clear it
    try await extractor.clearDependencyGraph(for: "test-project")

    // Verify it's gone
    #expect(!FileManager.default.fileExists(atPath: graphFile))
  }

  // MARK: - DependencyGraph Model Tests

  @Test("DependencyGraph getImports returns correct files")
  func testGetImports() throws {
    let graph = DependencyGraph(
      projectName: "test",
      importsMap: [
        "A.swift": ["Foundation", "SwiftUI"],
        "B.swift": ["Foundation"],
      ],
      importedByMap: [:],
      lastUpdated: Date()
    )

    let imports = graph.getImports(from: "A.swift")
    #expect(imports.count == 2)
    #expect(imports.contains("Foundation"))
    #expect(imports.contains("SwiftUI"))
  }

  @Test("DependencyGraph getImporters returns correct files")
  func testGetImporters() throws {
    let graph = DependencyGraph(
      projectName: "test",
      importsMap: [:],
      importedByMap: [
        "Foundation": ["A.swift", "B.swift"],
        "SwiftUI": ["A.swift"],
      ],
      lastUpdated: Date()
    )

    let importers = graph.getImporters(of: "Foundation")
    #expect(importers.count == 2)
    #expect(importers.contains("A.swift"))
    #expect(importers.contains("B.swift"))
  }

  @Test("DependencyGraph getTransitiveImporters works")
  func testTransitiveImporters() throws {
    let graph = DependencyGraph(
      projectName: "test",
      importsMap: [:],
      importedByMap: [
        "A": ["B"],
        "B": ["C", "D"],
        "C": ["E"],
      ],
      lastUpdated: Date()
    )

    let transitiveImporters = graph.getTransitiveImporters(of: "A")
    #expect(transitiveImporters.contains("B"))
    #expect(transitiveImporters.contains("C"))
    #expect(transitiveImporters.contains("D"))
    #expect(transitiveImporters.contains("E"))
  }

  @Test("DependencyGraph is Codable")
  func testDependencyGraphCodable() throws {
    let graph = DependencyGraph(
      projectName: "test",
      importsMap: ["A": ["B"]],
      importedByMap: ["B": ["A"]],
      lastUpdated: Date()
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(graph)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(DependencyGraph.self, from: data)

    #expect(decoded.projectName == graph.projectName)
    #expect(decoded.importsMap.count == graph.importsMap.count)
  }

  // MARK: - Dependency Model Tests

  @Test("Dependency is Sendable and Codable")
  func testDependencyModel() throws {
    let dep = Dependency(
      kind: "module",
      target: "Foundation",
      sourceFile: "Test.swift",
      lineNumber: 1
    )

    #expect(dep.kind == "module")
    #expect(dep.target == "Foundation")

    let encoder = JSONEncoder()
    let data = try encoder.encode(dep)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Dependency.self, from: data)

    #expect(decoded.kind == dep.kind)
    #expect(decoded.target == dep.target)
  }

  // MARK: - Find Related Files Tests (Stubs)

  @Test("Find related files throws not implemented")
  func testFindRelatedFilesNotImplemented() async throws {
    let tempDir = try Self.createTempDir()
    defer { Self.cleanupTempDir(tempDir) }

    let extractor = CodeMetadataExtractor(indexPath: tempDir)

    await #expect(throws: Error.self) {
      try await extractor.findRelatedFiles(filePath: "test.swift")
    }
  }
}
