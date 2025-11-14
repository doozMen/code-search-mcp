import Foundation
import Logging

/// Parser for Swift Package Manager packages using `swift package dump-package`.
///
/// Runs the Swift Package Manager command to get JSON representation of Package.swift
/// and extracts products to create separate subprojects for indexing.
actor SwiftPackageParser: Sendable {
  private let logger: Logger
  private let fileManager = FileManager.default

  init() {
    self.logger = Logger(label: "swift-package-parser")
  }

  /// Parse a Swift package and extract products as subprojects.
  ///
  /// Runs `swift package --package-path <path> dump-package` and parses the JSON output
  /// to discover products. Each product becomes a separate subproject for indexing.
  ///
  /// - Parameter packagePath: Path to directory containing Package.swift
  /// - Returns: Array of subprojects (one per product)
  /// - Throws: If command execution or JSON parsing fails
  func parsePackage(at packagePath: String) async throws -> [Subproject] {
    logger.debug(
      "Parsing Swift package",
      metadata: ["path": "\(packagePath)"])

    // Verify Package.swift exists
    let packageManifest = (packagePath as NSString).appendingPathComponent("Package.swift")
    guard fileManager.fileExists(atPath: packageManifest) else {
      throw SwiftPackageError.manifestNotFound(packagePath)
    }

    // Run swift package dump-package
    let jsonOutput = try await runSwiftPackageDump(at: packagePath)

    // Parse JSON
    let decoder = JSONDecoder()
    let manifest: PackageManifest
    do {
      manifest = try decoder.decode(PackageManifest.self, from: jsonOutput)
    } catch {
      logger.error(
        "Failed to parse package manifest JSON",
        metadata: [
          "path": "\(packagePath)",
          "error": "\(error)",
        ])
      throw SwiftPackageError.manifestParseError(error)
    }

    // Extract products as subprojects
    var subprojects: [Subproject] = []

    for product in manifest.products {
      // For each product, we'll index the targets it includes
      // The path will be the package root (since targets are defined relative to it)
      let subproject = Subproject(
        name: product.name,
        path: packagePath,
        type: .swiftPackageManager,
        isRoot: false
      )
      subprojects.append(subproject)

      logger.debug(
        "Detected Swift product",
        metadata: [
          "product": "\(product.name)",
          "type": "\(product.type.description)",
          "targets": "\(product.targets.joined(separator: ", "))",
        ])
    }

    logger.info(
      "Parsed Swift package",
      metadata: [
        "package": "\(manifest.name)",
        "products": "\(subprojects.count)",
      ])

    return subprojects
  }

  /// Run `swift package dump-package` command and return JSON output.
  ///
  /// - Parameter packagePath: Path to package directory
  /// - Returns: JSON data from dump-package command
  /// - Throws: If command execution fails
  private func runSwiftPackageDump(at packagePath: String) async throws -> Data {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    process.arguments = ["package", "--package-path", packagePath, "dump-package"]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    logger.debug(
      "Running swift package dump-package",
      metadata: ["path": "\(packagePath)"])

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      throw SwiftPackageError.commandExecutionFailed(error)
    }

    // Check exit status
    guard process.terminationStatus == 0 else {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"

      logger.error(
        "swift package dump-package failed",
        metadata: [
          "path": "\(packagePath)",
          "exit_code": "\(process.terminationStatus)",
          "error": "\(errorOutput)",
        ])

      throw SwiftPackageError.commandFailed(
        exitCode: Int(process.terminationStatus),
        output: errorOutput
      )
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

    logger.debug(
      "swift package dump-package succeeded",
      metadata: [
        "path": "\(packagePath)",
        "output_size": "\(outputData.count)",
      ])

    return outputData
  }
}

// MARK: - Package Manifest Models

/// Simplified model of Swift Package Manifest (from dump-package JSON).
private struct PackageManifest: Decodable {
  let name: String
  let products: [Product]
  let targets: [Target]?

  struct Product: Decodable {
    let name: String
    let targets: [String]
    let type: ProductType

    enum ProductType: Decodable {
      case executable
      case library(LibraryType)
      case plugin

      enum LibraryType: String, Decodable {
        case automatic
        case `static`
        case dynamic
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: LibraryType?].self) {
          if let libraryType = dict["library"] ?? nil {
            self = .library(libraryType)
          } else {
            self = .library(.automatic)
          }
        } else if (try? container.decode([String: String?].self)) != nil {
          // executable or plugin
          let typeDict = try container.decode([String: String?].self)
          if typeDict["executable"] != nil {
            self = .executable
          } else {
            self = .plugin
          }
        } else {
          throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unknown product type"
          )
        }
      }

      var description: String {
        switch self {
        case .executable: return "executable"
        case .library(let type): return "library(\(type.rawValue))"
        case .plugin: return "plugin"
        }
      }
    }
  }

  struct Target: Decodable {
    let name: String
    let path: String?
    let type: String?
  }
}

// MARK: - Error Types

enum SwiftPackageError: Error, LocalizedError {
  case manifestNotFound(String)
  case manifestParseError(Error)
  case commandExecutionFailed(Error)
  case commandFailed(exitCode: Int, output: String)

  var errorDescription: String? {
    switch self {
    case .manifestNotFound(let path):
      return "Package.swift not found at: \(path)"
    case .manifestParseError(let error):
      return "Failed to parse Package.swift manifest: \(error.localizedDescription)"
    case .commandExecutionFailed(let error):
      return "Failed to execute swift package command: \(error.localizedDescription)"
    case .commandFailed(let exitCode, let output):
      return "swift package dump-package failed with exit code \(exitCode): \(output)"
    }
  }
}
