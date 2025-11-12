import Foundation

/// Metadata about an indexed project.
///
/// Tracks information about projects that have been indexed including
/// their location, indexed time, statistics, and file structure.
struct ProjectMetadata: Sendable, Codable {
  /// Unique identifier for the project
  let id: String

  /// Name of the project
  let name: String

  /// Root directory path of the project
  let rootPath: String

  /// Timestamp when project was first indexed
  let indexedAt: Date

  /// Timestamp of last index update
  let lastUpdatedAt: Date

  /// Total number of source files in project
  let fileCount: Int

  /// Total number of code chunks extracted
  let chunkCount: Int

  /// Total lines of code (approximate)
  let lineCount: Int

  /// Programming languages found in project
  let languages: [String: Int]  // Language -> file count

  /// Project-level statistics
  let statistics: ProjectStatistics

  /// Index status
  let indexStatus: IndexStatus

  // MARK: - Computed Properties

  /// Is this project fully indexed?
  var isFullyIndexed: Bool {
    indexStatus == .complete
  }

  /// Time since last update
  var timeSinceLastUpdate: TimeInterval {
    Date().timeIntervalSince(lastUpdatedAt)
  }

  /// Primary programming languages (top 3)
  var primaryLanguages: [String] {
    languages
      .sorted { $0.value > $1.value }
      .prefix(3)
      .map { $0.key }
  }

  // MARK: - Initialization

  init(
    id: String = UUID().uuidString,
    name: String,
    rootPath: String,
    indexedAt: Date = Date(),
    lastUpdatedAt: Date = Date(),
    fileCount: Int = 0,
    chunkCount: Int = 0,
    lineCount: Int = 0,
    languages: [String: Int] = [:],
    statistics: ProjectStatistics = ProjectStatistics(),
    indexStatus: IndexStatus = .pending
  ) {
    self.id = id
    self.name = name
    self.rootPath = rootPath
    self.indexedAt = indexedAt
    self.lastUpdatedAt = lastUpdatedAt
    self.fileCount = fileCount
    self.chunkCount = chunkCount
    self.lineCount = lineCount
    self.languages = languages
    self.statistics = statistics
    self.indexStatus = indexStatus
  }

  // MARK: - Update Methods

  /// Update metadata after indexing.
  ///
  /// - Parameters:
  ///   - fileCount: Updated file count
  ///   - chunkCount: Updated chunk count
  ///   - lineCount: Updated line count
  ///   - languages: Updated language distribution
  /// - Returns: Updated metadata object
  func updated(
    fileCount: Int,
    chunkCount: Int,
    lineCount: Int,
    languages: [String: Int]
  ) -> ProjectMetadata {
    ProjectMetadata(
      id: id,
      name: name,
      rootPath: rootPath,
      indexedAt: indexedAt,
      lastUpdatedAt: Date(),
      fileCount: fileCount,
      chunkCount: chunkCount,
      lineCount: lineCount,
      languages: languages,
      statistics: statistics.updated(
        fileCount: fileCount,
        chunkCount: chunkCount,
        lineCount: lineCount
      ),
      indexStatus: .complete
    )
  }
}

// MARK: - Project Statistics

/// Aggregated statistics about a project.
struct ProjectStatistics: Sendable, Codable {
  /// Average code chunk size (lines)
  let averageChunkSize: Int

  /// Largest code chunk size (lines)
  let maxChunkSize: Int

  /// Smallest code chunk size (lines)
  let minChunkSize: Int

  /// Estimated cyclomatic complexity (rough measure)
  let complexityScore: Double

  // MARK: - Initialization

  init(
    averageChunkSize: Int = 0,
    maxChunkSize: Int = 0,
    minChunkSize: Int = 0,
    complexityScore: Double = 0.0
  ) {
    self.averageChunkSize = averageChunkSize
    self.maxChunkSize = maxChunkSize
    self.minChunkSize = minChunkSize
    self.complexityScore = complexityScore
  }

  /// Update statistics based on indexed counts.
  ///
  /// - Parameters:
  ///   - fileCount: Number of files
  ///   - chunkCount: Number of chunks
  ///   - lineCount: Total lines
  /// - Returns: Updated statistics
  func updated(fileCount: Int, chunkCount: Int, lineCount: Int) -> ProjectStatistics {
    let avgChunkSize = chunkCount > 0 ? lineCount / chunkCount : 0
    let complexity = Double(lineCount) / Double(max(1, fileCount)) / 10.0

    return ProjectStatistics(
      averageChunkSize: avgChunkSize,
      maxChunkSize: lineCount / max(1, chunkCount / 10),  // Rough estimate
      minChunkSize: max(1, avgChunkSize / 5),
      complexityScore: min(1.0, complexity)
    )
  }
}

// MARK: - Index Status Enum

/// Status of project indexing.
enum IndexStatus: String, Sendable, Codable {
  /// Not yet indexed
  case pending

  /// Indexing in progress
  case indexing

  /// Indexing complete
  case complete

  /// Indexing failed
  case failed

  /// Indexing paused/incomplete
  case partial
}

// MARK: - Project Registry

/// Registry of all indexed projects.
///
/// Maintains metadata about all projects that have been indexed
/// and provides efficient lookup and filtering.
struct ProjectRegistry: Sendable, Codable {
  /// Map from project name to metadata
  private var projects: [String: ProjectMetadata]

  // MARK: - Initialization

  init(projects: [String: ProjectMetadata] = [:]) {
    self.projects = projects
  }

  // MARK: - Public Interface

  /// Get metadata for a project by name.
  ///
  /// - Parameter name: Project name
  /// - Returns: Project metadata if found
  func project(named name: String) -> ProjectMetadata? {
    projects[name]
  }

  /// Get all indexed projects.
  ///
  /// - Returns: Array of all project metadata
  func allProjects() -> [ProjectMetadata] {
    Array(projects.values).sorted { $0.name < $1.name }
  }

  /// Get projects by programming language.
  ///
  /// - Parameter language: Language name
  /// - Returns: Projects containing code in that language
  func projects(withLanguage language: String) -> [ProjectMetadata] {
    projects.values.filter { project in
      project.languages.keys.contains(language)
    }
  }

  /// Get the most recently updated project.
  ///
  /// - Returns: Most recently updated project metadata
  func mostRecentlyUpdated() -> ProjectMetadata? {
    projects.values.max { $0.lastUpdatedAt < $1.lastUpdatedAt }
  }

  /// Register a new project.
  ///
  /// - Parameter metadata: Project metadata
  mutating func register(_ metadata: ProjectMetadata) {
    projects[metadata.name] = metadata
  }

  /// Remove a project from registry.
  ///
  /// - Parameter name: Project name
  mutating func unregister(_ name: String) {
    projects.removeValue(forKey: name)
  }

  /// Check if a project is registered.
  ///
  /// - Parameter name: Project name
  /// - Returns: True if registered
  func isRegistered(_ name: String) -> Bool {
    projects[name] != nil
  }

  /// Get count of indexed projects.
  var count: Int {
    projects.count
  }

  /// Get total indexed code chunks across all projects.
  var totalChunks: Int {
    projects.values.reduce(0) { $0 + $1.chunkCount }
  }

  /// Get all languages across all projects.
  var allLanguages: Set<String> {
    Set(projects.values.flatMap { $0.languages.keys })
  }
}

// MARK: - Codable Conformance

extension ProjectMetadata {
  enum CodingKeys: String, CodingKey {
    case id
    case name
    case rootPath = "root_path"
    case indexedAt = "indexed_at"
    case lastUpdatedAt = "last_updated_at"
    case fileCount = "file_count"
    case chunkCount = "chunk_count"
    case lineCount = "line_count"
    case languages
    case statistics
    case indexStatus = "index_status"
  }
}

extension ProjectStatistics {
  enum CodingKeys: String, CodingKey {
    case averageChunkSize = "average_chunk_size"
    case maxChunkSize = "max_chunk_size"
    case minChunkSize = "min_chunk_size"
    case complexityScore = "complexity_score"
  }
}
