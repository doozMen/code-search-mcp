import Foundation
import Logging

/// Service responsible for extracting and maintaining code metadata.
///
/// Builds and maintains dependency graphs, import relationships,
/// and other metadata about code structure.
///
/// Responsibilities:
/// - Extract import/dependency statements
/// - Build bidirectional dependency graphs
/// - Track file relationships and dependencies
/// - Support dependency traversal queries
actor CodeMetadataExtractor: Sendable {
    // MARK: - Properties

    private let indexPath: String
    private let logger: Logger
    private let fileManager = FileManager.default

    /// Dependency graph cache directory
    private let dependencyGraphDir: String

    // MARK: - Initialization

    init(indexPath: String) {
        self.indexPath = indexPath
        self.dependencyGraphDir = (indexPath as NSString).appendingPathComponent("dependencies")
        self.logger = Logger(label: "code-metadata-extractor")

        // Create dependency graph directory
        try? fileManager.createDirectory(
            atPath: dependencyGraphDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    // MARK: - Public Interface

    /// Find files related to a given file through imports/dependencies.
    ///
    /// - Parameters:
    ///   - filePath: Path to the file
    ///   - direction: Direction of search ("imports", "imports_from", or "both")
    /// - Returns: Array of related file paths
    /// - Throws: If dependency lookup fails
    func findRelatedFiles(
        filePath: String,
        direction: String = "both"
    ) async throws -> [String] {
        logger.debug("Finding related files", metadata: [
            "file": "\(filePath)",
            "direction": "\(direction)"
        ])

        throw CodeSearchError.notYetImplemented(
            feature: "Dependency graph traversal for related files",
            issueNumber: nil
        )
    }

    /// Extract dependencies from a code file.
    ///
    /// Parses import/require statements based on language.
    ///
    /// - Parameters:
    ///   - filePath: Path to file
    ///   - content: File content
    ///   - language: Programming language
    /// - Returns: Array of dependency information
    /// - Throws: If extraction fails
    func extractDependencies(
        from filePath: String,
        content: String,
        language: String
    ) async throws -> [Dependency] {
        logger.debug("Extracting dependencies", metadata: [
            "file": "\(filePath)",
            "language": "\(language)"
        ])

        switch language.lowercased() {
        case "swift":
            return extractSwiftDependencies(from: content, filePath: filePath)
        case "python":
            return extractPythonDependencies(from: content, filePath: filePath)
        case "javascript", "typescript":
            return extractJavaScriptDependencies(from: content, filePath: filePath)
        case "java":
            return extractJavaDependencies(from: content, filePath: filePath)
        default:
            return []
        }
    }

    // MARK: - Language-Specific Dependency Extraction

    /// Extract dependencies from Swift code.
    ///
    /// Looks for:
    /// - import statements
    private func extractSwiftDependencies(from content: String, filePath: String) -> [Dependency] {
        // TODO: Use regex to find "import X" statements
        // Pattern: ^import\s+(\w+)
        var dependencies: [Dependency] = []

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        for (lineNumber, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") {
                let moduleName = String(trimmed.dropFirst("import ".count))
                    .trimmingCharacters(in: .whitespaces)
                dependencies.append(Dependency(
                    kind: "module",
                    target: moduleName,
                    sourceFile: filePath,
                    lineNumber: lineNumber + 1
                ))
            }
        }

        return dependencies
    }

    /// Extract dependencies from Python code.
    ///
    /// Looks for:
    /// - import statements
    /// - from ... import statements
    private func extractPythonDependencies(from content: String, filePath: String) -> [Dependency] {
        // Not yet implemented - requires regex for import and from...import statements
        return []
    }

    /// Extract dependencies from JavaScript/TypeScript code.
    ///
    /// Looks for:
    /// - import statements
    /// - require() calls
    private func extractJavaScriptDependencies(from content: String, filePath: String) -> [Dependency] {
        // Not yet implemented - requires regex for import and require statements
        return []
    }

    /// Extract dependencies from Java code.
    ///
    /// Looks for:
    /// - import statements
    private func extractJavaDependencies(from content: String, filePath: String) -> [Dependency] {
        // Not yet implemented - requires regex for import statements
        return []
    }

    // MARK: - Dependency Graph Management

    /// Build and cache the dependency graph for a project.
    ///
    /// - Parameter projectName: Project to build graph for
    /// - Throws: If graph building fails
    func buildDependencyGraph(for projectName: String) async throws {
        logger.info("Building dependency graph", metadata: [
            "project": "\(projectName)"
        ])

        throw CodeSearchError.notYetImplemented(
            feature: "Dependency graph building and caching",
            issueNumber: nil
        )
    }

    /// Get the dependency graph for a project.
    ///
    /// - Parameter projectName: Project name
    /// - Returns: Dependency graph
    /// - Throws: If graph loading fails
    func getDependencyGraph(for projectName: String) async throws -> DependencyGraph {
        let graphPath = (dependencyGraphDir as NSString)
            .appendingPathComponent("\(projectName).graph.json")

        throw CodeSearchError.notYetImplemented(
            feature: "Dependency graph loading and caching",
            issueNumber: nil
        )
    }

    // MARK: - Reverse Dependency Lookup

    /// Find all files that import/reference a given file.
    ///
    /// - Parameter filePath: File path
    /// - Returns: Array of files that import this file
    /// - Throws: If lookup fails
    private func getImporters(of filePath: String) async throws -> [String] {
        throw CodeSearchError.notYetImplemented(
            feature: "Reverse dependency lookup (importers)",
            issueNumber: nil
        )
    }

    /// Find all files this file imports/references.
    ///
    /// - Parameter filePath: File path
    /// - Returns: Array of files imported by this file
    /// - Throws: If lookup fails
    private func getImports(from filePath: String) async throws -> [String] {
        throw CodeSearchError.notYetImplemented(
            feature: "Forward dependency lookup (imports)",
            issueNumber: nil
        )
    }
}

// MARK: - Data Models

/// Represents a dependency relationship between code elements.
struct Dependency: Sendable, Codable {
    /// Type of dependency: "module", "class", "function", "file"
    let kind: String

    /// Name or path of the dependency target
    let target: String

    /// File containing the import/dependency statement
    let sourceFile: String

    /// Line number where dependency is declared
    let lineNumber: Int
}

/// Represents the complete dependency graph for a project.
struct DependencyGraph: Sendable {
    /// Project name
    let projectName: String

    /// Map from file to files it imports
    let importsMap: [String: [String]]

    /// Map from file to files that import it
    let importedByMap: [String: [String]]

    /// Get files imported by a file
    func getImports(from file: String) -> [String] {
        importsMap[file] ?? []
    }

    /// Get files that import a given file
    func getImporters(of file: String) -> [String] {
        importedByMap[file] ?? []
    }

    /// Get all files that transitively import a given file
    func getTransitiveImporters(of file: String) -> [String] {
        var result: Set<String> = []
        var queue = [file]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let importers = getImporters(of: current)

            for importer in importers where !result.contains(importer) {
                result.insert(importer)
                queue.append(importer)
            }
        }

        return Array(result).sorted()
    }
}

// MARK: - Error Types

enum MetadataError: Error, LocalizedError {
    case dependencyExtractionFailed(String)
    case graphBuildingFailed(Error)
    case invalidFilePath(String)

    var errorDescription: String? {
        switch self {
        case .dependencyExtractionFailed(let reason):
            return "Dependency extraction failed: \(reason)"
        case .graphBuildingFailed(let error):
            return "Failed to build dependency graph: \(error)"
        case .invalidFilePath(let path):
            return "Invalid file path: \(path)"
        }
    }
}
