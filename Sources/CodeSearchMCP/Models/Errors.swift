import Foundation

/// Central error types for CodeSearchMCP functionality.
///
/// Provides clear, actionable error messages with optional GitHub issue tracking.
enum CodeSearchError: Error, LocalizedError {
  case notYetImplemented(feature: String, issueNumber: Int?)

  var errorDescription: String? {
    switch self {
    case .notYetImplemented(let feature, let issue):
      if let issue = issue {
        return
          "\(feature) is not yet implemented. Track progress: https://github.com/doozMen/code-search-mcp/issues/\(issue)"
      }
      return "\(feature) is not yet implemented."
    }
  }
}
