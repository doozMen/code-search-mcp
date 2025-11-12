import Foundation
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// BERT embedding provider using Python server backend.
///
/// This is a FALLBACK provider for systems without CoreML/Foundation Models support.
/// Uses sentence-transformers via a local HTTP server for 384-dimensional embeddings.
///
/// Server lifecycle:
/// - Starts automatically on first use
/// - Runs on localhost:8765 by default
/// - Shuts down when provider is deallocated
actor BERTEmbeddingProvider: EmbeddingProvider {
  // MARK: - Properties

  private let logger = Logger(label: "bert-provider")
  private let serverHost: String
  private let serverPort: Int
  private var serverProcess: Process?
  private var isInitialized = false

  // MARK: - Constants

  private static let defaultPort = 8765
  private static let serverScriptName = "bert_embedding_server.py"
  private static let startupTimeout: TimeInterval = 30.0
  private static let requestTimeout: TimeInterval = 60.0

  // MARK: - Initialization

  init(host: String = "127.0.0.1", port: Int = defaultPort) {
    self.serverHost = host
    self.serverPort = port
    logger.debug("BERTEmbeddingProvider initialized", metadata: [
      "host": "\(host)",
      "port": "\(port)",
    ])
  }

  deinit {
    // Clean shutdown on dealloc
    if let process = serverProcess {
      process.terminate()
    }
  }

  // MARK: - EmbeddingProvider Protocol

  /// Number of dimensions (384 for BERT all-MiniLM-L6-v2)
  let dimensions: Int = 384

  func generateEmbedding(for text: String) async throws -> [Float] {
    // Batch of 1 is efficient enough, server handles it
    let embeddings = try await generateEmbeddings(for: [text])
    guard let embedding = embeddings.first else {
      throw BERTProviderError.embeddingGenerationFailed(
        "Server did not return embedding for text")
    }
    return embedding
  }

  func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
    // Ensure server is running
    if !isInitialized {
      try await initialize()
    }

    // Verify server is still healthy
    guard try await checkServerHealth() else {
      throw BERTProviderError.serverNotHealthy("Server health check failed")
    }

    // Make request
    let url = URL(string: "http://\(serverHost):\(serverPort)/embed")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = Self.requestTimeout

    let requestBody = ["texts": texts]
    request.httpBody = try JSONEncoder().encode(requestBody)

    logger.debug("Sending embedding request", metadata: [
      "text_count": "\(texts.count)"
    ])

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw BERTProviderError.invalidResponse("Response is not HTTP")
    }

    guard httpResponse.statusCode == 200 else {
      let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw BERTProviderError.serverError(
        httpResponse.statusCode, errorMessage)
    }

    // Parse response
    let responseData = try JSONDecoder().decode(
      EmbeddingResponse.self, from: data)

    guard responseData.embeddings.count == texts.count else {
      throw BERTProviderError.embeddingGenerationFailed(
        "Server returned \(responseData.embeddings.count) embeddings for \(texts.count) texts"
      )
    }

    logger.debug("Successfully generated embeddings", metadata: [
      "count": "\(responseData.embeddings.count)",
      "dimension": "\(responseData.dimension)",
    ])

    return responseData.embeddings
  }

  // MARK: - Initialization

  /// Initialize the provider (start Python server if needed).
  func initialize() async throws {
    guard !isInitialized else {
      logger.debug("Provider already initialized")
      return
    }

    logger.info("Initializing BERT embedding provider")

    // Find Python script
    guard let scriptPath = findServerScript() else {
      throw BERTProviderError.serverScriptNotFound(
        "Could not find \(Self.serverScriptName)")
    }

    // Check Python dependencies
    try await verifyPythonDependencies()

    // Start server process
    try await startServer(scriptPath: scriptPath)

    // Wait for server to be ready
    try await waitForServerReady()

    isInitialized = true
    logger.info("BERT embedding provider initialized successfully")
  }

  // MARK: - Server Management

  private func findServerScript() -> String? {
    // Check common locations
    let possiblePaths = [
      // Development location
      FileManager.default.currentDirectoryPath + "/Scripts/\(Self.serverScriptName)",
      // Installed location (relative to binary)
      Bundle.main.bundlePath + "/../Scripts/\(Self.serverScriptName)",
      // Homebrew-style installation
      "/usr/local/share/code-search-mcp/\(Self.serverScriptName)",
      // User local installation
      NSHomeDirectory() + "/.local/share/code-search-mcp/\(Self.serverScriptName)",
    ]

    for path in possiblePaths {
      if FileManager.default.fileExists(atPath: path) {
        logger.debug("Found server script at: \(path)")
        return path
      }
    }

    logger.warning("Server script not found in any expected location")
    return nil
  }

  private func verifyPythonDependencies() async throws {
    // Try importing sentence_transformers
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "-c", "import sentence_transformers"]

    let pipe = Pipe()
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"

      throw BERTProviderError.dependenciesMissing(
        """
        Python package 'sentence-transformers' not found.
        Install with: pip3 install sentence-transformers
        Error: \(errorMessage)
        """
      )
    }

    logger.debug("Python dependencies verified")
  }

  private func startServer(scriptPath: String) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", scriptPath, "\(serverPort)"]

    // Redirect output for debugging
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    // Log output in background
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        self.logger.debug("Server stdout: \(output)")
      }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        self.logger.debug("Server stderr: \(output)")
      }
    }

    try process.run()
    serverProcess = process

    logger.info("Started BERT server process", metadata: [
      "pid": "\(process.processIdentifier)",
      "port": "\(serverPort)",
    ])
  }

  private func waitForServerReady() async throws {
    let startTime = Date()
    let timeout = Self.startupTimeout

    while Date().timeIntervalSince(startTime) < timeout {
      if try await checkServerHealth() {
        logger.debug("Server is ready")
        return
      }

      // Wait a bit before retrying
      try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
    }

    throw BERTProviderError.serverStartupTimeout(
      "Server did not become healthy within \(timeout) seconds")
  }

  private func checkServerHealth() async throws -> Bool {
    let url = URL(string: "http://\(serverHost):\(serverPort)/health")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 2.0

    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      if let httpResponse = response as? HTTPURLResponse {
        return httpResponse.statusCode == 200
      }
      return false
    } catch {
      // Server not ready yet
      return false
    }
  }
}

// MARK: - Response Models

private struct EmbeddingResponse: Codable, Sendable {
  let embeddings: [[Float]]
  let dimension: Int
  let count: Int
}

// MARK: - Error Types

enum BERTProviderError: Error, LocalizedError {
  case serverScriptNotFound(String)
  case dependenciesMissing(String)
  case serverStartupTimeout(String)
  case serverNotHealthy(String)
  case serverError(Int, String)
  case invalidResponse(String)
  case embeddingGenerationFailed(String)

  var errorDescription: String? {
    switch self {
    case .serverScriptNotFound(let message):
      return "Server script not found: \(message)"
    case .dependenciesMissing(let message):
      return "Python dependencies missing: \(message)"
    case .serverStartupTimeout(let message):
      return "Server startup timeout: \(message)"
    case .serverNotHealthy(let message):
      return "Server not healthy: \(message)"
    case .serverError(let code, let message):
      return "Server error (\(code)): \(message)"
    case .invalidResponse(let message):
      return "Invalid server response: \(message)"
    case .embeddingGenerationFailed(let message):
      return "Embedding generation failed: \(message)"
    }
  }
}
