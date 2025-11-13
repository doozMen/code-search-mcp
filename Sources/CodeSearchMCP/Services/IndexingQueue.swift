import Foundation
import Logging

/// Manages background indexing tasks to prevent blocking the MCP server.
///
/// This actor coordinates concurrent indexing operations, allowing the server to:
/// - Accept indexing requests from git hooks without blocking
/// - Track progress of background indexing jobs
/// - Limit concurrent operations to prevent resource exhaustion
/// - Prioritize user-initiated re-indexing over hook-triggered background tasks
actor IndexingQueue: Sendable {
  // MARK: - Types

  /// Unique identifier for a queued indexing job.
  typealias JobID = UUID

  /// Priority level for indexing jobs.
  enum JobPriority: Int {
    case low = 0      // Background hook-triggered indexing
    case normal = 1   // User-initiated reload via MCP tool
    case high = 2     // Emergency re-index after migration or errors

    /// Comparison for priority queue ordering (higher = sooner).
    func comparePriority(to other: JobPriority) -> Bool {
      return self.rawValue > other.rawValue
    }
  }

  /// State of an indexing job.
  enum JobStatus: String, Codable {
    case queued = "queued"
    case inProgress = "in_progress"
    case completed = "completed"
    case failed = "failed"
  }

  /// Information about a queued indexing job.
  struct JobInfo: Sendable {
    let id: JobID
    let projectName: String?
    let priority: JobPriority
    let status: JobStatus
    let createdAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let error: String?
    let fileCount: Int?
    let chunkCount: Int?
  }

  // MARK: - Properties

  private let logger: Logger
  private let maxConcurrentJobs: Int

  /// Queue of pending jobs, sorted by priority.
  private var pendingJobs: [QueuedJob] = []

  /// Currently executing jobs.
  private var activeJobs: [JobID: RunningJob] = [:]

  /// Completed job history (last 100 for debugging).
  private var completedJobs: [JobInfo] = []

  // MARK: - Private Types

  private struct QueuedJob {
    let id: JobID
    let projectName: String?
    let priority: JobPriority
    let createdAt: Date
    let operation: @Sendable () async throws -> (fileCount: Int, chunkCount: Int)
  }

  private struct RunningJob {
    let id: JobID
    let projectName: String?
    let priority: JobPriority
    let createdAt: Date
    let startedAt: Date
    let task: Task<(fileCount: Int, chunkCount: Int), Error>
  }

  // MARK: - Initialization

  init(maxConcurrentJobs: Int = 1) {
    self.logger = Logger(label: "indexing-queue")
    self.maxConcurrentJobs = max(1, maxConcurrentJobs)
    logger.info(
      "Indexing queue initialized",
      metadata: ["max_concurrent": "\(maxConcurrentJobs)"]
    )
  }

  // MARK: - Public Interface

  /// Queue an indexing operation to run in the background.
  ///
  /// Returns immediately with a job ID. The operation runs asynchronously
  /// without blocking the caller. Use `getJobStatus()` to poll progress.
  ///
  /// - Parameters:
  ///   - projectName: Optional project name (for single-project re-index)
  ///   - priority: Job priority level (affects order)
  ///   - operation: Async closure that performs indexing and returns file/chunk counts
  /// - Returns: Job ID for tracking progress
  func enqueue(
    projectName: String? = nil,
    priority: JobPriority = .normal,
    operation: @escaping @Sendable () async throws -> (fileCount: Int, chunkCount: Int)
  ) -> JobID {
    let jobID = UUID()
    let queuedJob = QueuedJob(
      id: jobID,
      projectName: projectName,
      priority: priority,
      createdAt: Date(),
      operation: operation
    )

    // Insert into queue sorted by priority (highest first)
    let insertIndex = pendingJobs.firstIndex { existingJob in
      !priority.comparePriority(to: existingJob.priority)
    } ?? pendingJobs.count

    pendingJobs.insert(queuedJob, at: insertIndex)

    logger.info(
      "Job enqueued",
      metadata: [
        "job_id": "\(jobID.uuidString)",
        "project": "\(projectName ?? "all")",
        "priority": "\(priority)",
        "queue_size": "\(pendingJobs.count)",
      ]
    )

    // Try to start pending jobs if slots are available
    Task.detached { await self.processQueue() }

    return jobID
  }

  /// Get the current status of a queued or running job.
  ///
  /// - Parameter jobID: The job ID returned from `enqueue()`
  /// - Returns: Job info, or nil if not found
  func getJobStatus(_ jobID: JobID) -> JobInfo? {
    // Check pending jobs
    if let pendingJob = pendingJobs.first(where: { $0.id == jobID }) {
      return JobInfo(
        id: pendingJob.id,
        projectName: pendingJob.projectName,
        priority: pendingJob.priority,
        status: .queued,
        createdAt: pendingJob.createdAt,
        startedAt: nil,
        completedAt: nil,
        error: nil,
        fileCount: nil,
        chunkCount: nil
      )
    }

    // Check active jobs
    if let activeJob = activeJobs[jobID] {
      return JobInfo(
        id: activeJob.id,
        projectName: activeJob.projectName,
        priority: activeJob.priority,
        status: .inProgress,
        createdAt: activeJob.createdAt,
        startedAt: activeJob.startedAt,
        completedAt: nil,
        error: nil,
        fileCount: nil,
        chunkCount: nil
      )
    }

    // Check completed jobs
    return completedJobs.first { $0.id == jobID }
  }

  /// Get all jobs (pending, active, and recent completed).
  func getAllJobs() -> [JobInfo] {
    var jobs: [JobInfo] = []

    // Add pending jobs
    for pendingJob in pendingJobs {
      jobs.append(
        JobInfo(
          id: pendingJob.id,
          projectName: pendingJob.projectName,
          priority: pendingJob.priority,
          status: .queued,
          createdAt: pendingJob.createdAt,
          startedAt: nil,
          completedAt: nil,
          error: nil,
          fileCount: nil,
          chunkCount: nil
        )
      )
    }

    // Add active jobs
    for activeJob in activeJobs.values {
      jobs.append(
        JobInfo(
          id: activeJob.id,
          projectName: activeJob.projectName,
          priority: activeJob.priority,
          status: .inProgress,
          createdAt: activeJob.createdAt,
          startedAt: activeJob.startedAt,
          completedAt: nil,
          error: nil,
          fileCount: nil,
          chunkCount: nil
        )
      )
    }

    // Add completed jobs (most recent first)
    jobs.append(contentsOf: completedJobs.sorted { $0.completedAt ?? Date() > $1.completedAt ?? Date() })

    return jobs
  }

  /// Get queue statistics.
  func getStats() -> (pending: Int, active: Int, completed: Int) {
    return (
      pending: pendingJobs.count,
      active: activeJobs.count,
      completed: completedJobs.count
    )
  }

  // MARK: - Private Methods

  /// Process the queue, starting jobs when slots are available.
  private func processQueue() async {
    while activeJobs.count < maxConcurrentJobs && !pendingJobs.isEmpty {
      let queuedJob = pendingJobs.removeFirst()

      let runningJob = RunningJob(
        id: queuedJob.id,
        projectName: queuedJob.projectName,
        priority: queuedJob.priority,
        createdAt: queuedJob.createdAt,
        startedAt: Date(),
        task: Task {
          try await queuedJob.operation()
        }
      )

      activeJobs[queuedJob.id] = runningJob

      logger.info(
        "Job started",
        metadata: [
          "job_id": "\(queuedJob.id.uuidString)",
          "project": "\(queuedJob.projectName ?? "all")",
          "active_count": "\(activeJobs.count)",
        ]
      )

      // Monitor this job for completion
      Task.detached { await self.monitorJob(queuedJob.id) }
    }
  }

  /// Monitor a running job until it completes, then update status and process queue.
  private func monitorJob(_ jobID: JobID) async {
    guard let runningJob = activeJobs[jobID] else { return }

    do {
      let result = try await runningJob.task.value
      let completedInfo = JobInfo(
        id: jobID,
        projectName: runningJob.projectName,
        priority: runningJob.priority,
        status: .completed,
        createdAt: runningJob.createdAt,
        startedAt: runningJob.startedAt,
        completedAt: Date(),
        error: nil,
        fileCount: result.fileCount,
        chunkCount: result.chunkCount
      )

      activeJobs.removeValue(forKey: jobID)
      completedJobs.append(completedInfo)

      // Keep only last 100 completed jobs
      if completedJobs.count > 100 {
        completedJobs.removeFirst()
      }

      logger.info(
        "Job completed",
        metadata: [
          "job_id": "\(jobID.uuidString)",
          "project": "\(runningJob.projectName ?? "all")",
          "files": "\(result.fileCount)",
          "chunks": "\(result.chunkCount)",
        ]
      )

      // Process more jobs from queue
      await processQueue()
    } catch {
      let completedInfo = JobInfo(
        id: jobID,
        projectName: runningJob.projectName,
        priority: runningJob.priority,
        status: .failed,
        createdAt: runningJob.createdAt,
        startedAt: runningJob.startedAt,
        completedAt: Date(),
        error: "\(error)",
        fileCount: nil,
        chunkCount: nil
      )

      activeJobs.removeValue(forKey: jobID)
      completedJobs.append(completedInfo)

      // Keep only last 100 completed jobs
      if completedJobs.count > 100 {
        completedJobs.removeFirst()
      }

      logger.error(
        "Job failed",
        metadata: [
          "job_id": "\(jobID.uuidString)",
          "project": "\(runningJob.projectName ?? "all")",
          "error": "\(error)",
        ]
      )

      // Process more jobs from queue even after failure
      await processQueue()
    }
  }
}
