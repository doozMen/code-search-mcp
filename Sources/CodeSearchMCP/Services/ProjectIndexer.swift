import Foundation
import Logging

/// Service responsible for crawling project directories and extracting code chunks.
///
/// Responsibilities:
/// - Scan project directories for source files
/// - Parse files to extract logical code chunks (functions, classes, blocks)
/// - Build initial metadata about project structure
/// - Trigger embedding generation for discovered chunks
actor ProjectIndexer: Sendable {
    // MARK: - Properties

    private let indexPath: String
    private let logger: Logger
    private let fileManager = FileManager.default

    /// File extensions to index by language
    private let supportedExtensions: [String: String] = [
        "swift": "Swift",
        "py": "Python",
        "js": "JavaScript",
        "ts": "TypeScript",
        "jsx": "JavaScript",
        "tsx": "TypeScript",
        "java": "Java",
        "go": "Go",
        "rs": "Rust",
        "cpp": "C++",
        "c": "C",
        "h": "C",
        "hpp": "C++",
        "cs": "C#",
        "rb": "Ruby",
        "php": "PHP",
        "kt": "Kotlin",
    ]

    // MARK: - Initialization

    init(indexPath: String) {
        self.indexPath = indexPath
        self.logger = Logger(label: "project-indexer")

        // Ensure index directory exists
        try? fileManager.createDirectory(
            atPath: indexPath,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    // MARK: - Public Interface

    /// Index an entire project directory.
    ///
    /// Recursively scans the directory for supported source files,
    /// extracts code chunks, and generates embeddings.
    ///
    /// - Parameter path: Path to the project root directory
    /// - Throws: If directory access or indexing fails
    func indexProject(path: String) async throws {
        let projectName = (path as NSString).lastPathComponent

        logger.info("Starting project indexing", metadata: [
            "project": "\(projectName)",
            "path": "\(path)"
        ])

        // Validate path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw IndexingError.invalidProjectPath(path)
        }

        // Recursively find all source files
        let sourceFiles = try findSourceFiles(in: path)
        logger.info("Found source files", metadata: [
            "count": "\(sourceFiles.count)"
        ])

        // Extract code chunks from each file
        var totalChunks = 0
        for filePath in sourceFiles {
            do {
                let chunks = try extractCodeChunks(from: filePath, projectName: projectName)
                totalChunks += chunks.count
                logger.debug("Extracted chunks", metadata: [
                    "file": "\((filePath as NSString).lastPathComponent)",
                    "chunk_count": "\(chunks.count)"
                ])
            } catch {
                logger.warning("Failed to extract chunks from file", metadata: [
                    "file": "\(filePath)",
                    "error": "\(error)"
                ])
            }
        }

        logger.info("Project indexing complete", metadata: [
            "project": "\(projectName)",
            "total_chunks": "\(totalChunks)"
        ])
    }

    // MARK: - Private Methods

    /// Recursively find all supported source files in a directory.
    ///
    /// - Parameter directory: Directory to search
    /// - Returns: Array of file paths to source files
    /// - Throws: If directory enumeration fails
    private func findSourceFiles(in directory: String) throws -> [String] {
        var sourceFiles: [String] = []

        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            throw IndexingError.directoryEnumerationFailed(directory)
        }

        for case let file as String in enumerator {
            let fullPath = (directory as NSString).appendingPathComponent(file)
            let pathExtension = (file as NSString).pathExtension.lowercased()

            // Skip hidden files and known exclusions
            if file.hasPrefix(".") || isExcludedPath(file) {
                if file.hasPrefix(".") {
                    enumerator.skipDescendants()
                }
                continue
            }

            // Check if this is a supported file
            if supportedExtensions.keys.contains(pathExtension) {
                sourceFiles.append(fullPath)
            }
        }

        return sourceFiles
    }

    /// Check if a path should be excluded from indexing.
    ///
    /// - Parameter path: File or directory path
    /// - Returns: True if path should be excluded
    private func isExcludedPath(_ path: String) -> Bool {
        let excludedPatterns = [
            "node_modules",
            ".git",
            ".build",
            "build",
            "dist",
            "target",
            ".venv",
            "venv",
            "__pycache__",
            ".pytest_cache",
            "coverage",
            ".DS_Store",
        ]

        return excludedPatterns.contains { pattern in
            path.contains("/\(pattern)/") || path.hasPrefix(pattern)
        }
    }

    /// Extract code chunks from a single file.
    ///
    /// Parses the file to identify logical chunks (functions, classes, blocks)
    /// and creates CodeChunk objects with metadata.
    ///
    /// - Parameters:
    ///   - filePath: Path to the source file
    ///   - projectName: Name of the project this file belongs to
    /// - Returns: Array of extracted code chunks
    /// - Throws: If file reading or parsing fails
    private func extractCodeChunks(from filePath: String, projectName: String) throws -> [CodeChunk] {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let pathExtension = (filePath as NSString).pathExtension.lowercased()
        let language = supportedExtensions[pathExtension] ?? "Unknown"

        // TODO: Implement language-specific parsing
        // For now, return a basic chunk for the entire file
        let relativeFilePath = filePath.replacingOccurrences(
            of: projectName + "/",
            with: ""
        )

        let chunk = CodeChunk(
            id: UUID().uuidString,
            projectName: projectName,
            filePath: relativeFilePath,
            language: language,
            startLine: 1,
            endLine: content.split(separator: "\n").count,
            content: content,
            chunkType: "file",
            embedding: nil
        )

        return [chunk]
    }
}

// MARK: - Error Types

enum IndexingError: Error, LocalizedError {
    case invalidProjectPath(String)
    case directoryEnumerationFailed(String)
    case fileReadingFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .invalidProjectPath(let path):
            return "Invalid project path: \(path)"
        case .directoryEnumerationFailed(let directory):
            return "Failed to enumerate directory: \(directory)"
        case .fileReadingFailed(let file, let error):
            return "Failed to read file \(file): \(error)"
        }
    }
}
