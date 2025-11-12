import ArgumentParser
import Foundation
import Logging

/// Command to configure automatic re-indexing using git hooks and direnv.
///
/// This command generates and installs:
/// - `.envrc` - direnv configuration for automatic re-indexing on directory entry
/// - `.githooks/post-commit` - Re-index after committing changes
/// - `.githooks/post-merge` - Re-index after pulling/merging
/// - `.githooks/post-checkout` - Re-index after branch switching
/// - `.githooks/README.md` - Team setup instructions
struct SetupHooksCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "setup-hooks",
    abstract: "Configure automatic re-indexing with git hooks and direnv",
    discussion: """
      This command sets up automatic re-indexing for code-search-mcp using:

      1. direnv (.envrc) - Re-indexes when entering the directory
      2. Git hooks (.githooks/) - Re-indexes after git operations

      The hooks run in the background and won't block your workflow.

      Examples:
        # Setup in current directory
        code-search-mcp setup-hooks
        
        # Setup for specific project
        code-search-mcp setup-hooks --project-path ~/my-project
        
        # Skip direnv setup
        code-search-mcp setup-hooks --no-direnv
        
        # Install hooks immediately with git config
        code-search-mcp setup-hooks --install-hooks
      """
  )

  // MARK: - Options

  @Option(
    name: .long,
    help: "Project directory to configure (default: current directory)"
  )
  var projectPath: String = "."

  @Flag(
    name: .long,
    help: "Skip .envrc creation"
  )
  var noDirenv: Bool = false

  @Flag(
    name: .long,
    help: "Skip git hooks creation"
  )
  var noGitHooks: Bool = false

  @Flag(
    name: .long,
    help: "Install hooks immediately with 'git config core.hooksPath'"
  )
  var installHooks: Bool = false

  // MARK: - Command Execution

  func run() async throws {
    print("🔧 Setting up automatic re-indexing for code-search-mcp\n")

    // Resolve project path
    let resolvedPath = resolvePath(projectPath)
    let projectName = resolvedPath.lastPathComponent
    let fileManager = FileManager.default

    // Verify project directory exists
    guard fileManager.fileExists(atPath: resolvedPath.path) else {
      print("❌ Error: Project directory does not exist: \(resolvedPath.path)")
      throw ExitCode.failure
    }

    // Verify it's a git repository (if creating git hooks)
    if !noGitHooks {
      let gitDir = resolvedPath.appendingPathComponent(".git")
      guard fileManager.fileExists(atPath: gitDir.path) else {
        print(
          "❌ Error: Not a git repository. Initialize git first or use --no-git-hooks")
        throw ExitCode.failure
      }
    }

    var filesCreated: [String] = []

    // Create .envrc
    if !noDirenv {
      if try createEnvrc(projectPath: resolvedPath, projectName: projectName) {
        filesCreated.append(".envrc")
      }
    }

    // Create git hooks
    if !noGitHooks {
      let hooksCreated = try createGitHooks(
        projectPath: resolvedPath,
        projectName: projectName)
      filesCreated.append(contentsOf: hooksCreated)
    }

    // Install hooks if requested
    if installHooks && !noGitHooks {
      try installGitHooks(projectPath: resolvedPath)
    }

    // Summary
    print("\n✅ Setup complete!\n")

    if filesCreated.isEmpty {
      print("ℹ️  No files were created (all flags set to skip)")
    } else {
      print("📝 Files created:")
      for file in filesCreated {
        print("   • \(file)")
      }
    }

    if !noDirenv {
      print("\n📚 To enable direnv:")
      print("   1. Install direnv: brew install direnv")
      print("   2. Add to shell config: eval \"$(direnv hook zsh)\"")
      print("   3. Allow directory: direnv allow \(resolvedPath.path)")
    }

    if !noGitHooks && !installHooks {
      print("\n🪝 To activate git hooks:")
      print("   Option 1 (Recommended):")
      print("     cd \(resolvedPath.path)")
      print("     git config core.hooksPath .githooks")
      print("")
      print("   Option 2 (Manual copy):")
      print("     cp .githooks/* .git/hooks/")
      print("     chmod +x .git/hooks/post-*")
    }

    if installHooks && !noGitHooks {
      print("\n✅ Git hooks installed successfully!")
      print("   Hooks will run automatically on commit, merge, and checkout")
    }

    print("\n🔍 Verify installation:")
    print("   which code-search-mcp")
    print("   # Should show: ~/.swiftpm/bin/code-search-mcp")
  }

  // MARK: - Private Methods

  /// Resolve path to absolute URL, expanding ~ and relative paths
  private func resolvePath(_ path: String) -> URL {
    let nsPath = NSString(string: path)
    let expandedPath = nsPath.expandingTildeInPath

    if expandedPath.hasPrefix("/") {
      return URL(fileURLWithPath: expandedPath)
    } else {
      return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(expandedPath)
        .standardized
    }
  }

  /// Create .envrc file for direnv integration
  private func createEnvrc(projectPath: URL, projectName: String) throws -> Bool {
    let envrcPath = projectPath.appendingPathComponent(".envrc")
    let fileManager = FileManager.default

    // Check if file exists
    if fileManager.fileExists(atPath: envrcPath.path) {
      print("⚠️  .envrc already exists at \(envrcPath.path)")
      print("   Overwrite? (y/n): ", terminator: "")

      guard let response = readLine()?.lowercased(),
        response == "y" || response == "yes"
      else {
        print("   Skipped .envrc")
        return false
      }
    }

    let content = """
      # direnv configuration for \(projectName) code search indexing
      # Automatically re-indexes code when entering this directory

      # Set the project name for code-search-mcp
      export CODE_SEARCH_PROJECT_NAME="\(projectName)"
      export CODE_SEARCH_PROJECT_PATH="$PWD"

      # Trigger re-indexing in the background (won't block terminal)
      if command -v code-search-mcp &> /dev/null; then
        echo "📚 code-search-mcp: Re-indexing \(projectName)..."
        (code-search-mcp --log-level info --project-paths "$PWD" > /tmp/code-search-mcp-$$.log 2>&1 &)
        echo "   (Indexing in background, check /tmp/code-search-mcp-$$.log for progress)"
      else
        echo "⚠️  code-search-mcp not found in PATH"
      fi

      """

    try content.write(to: envrcPath, atomically: true, encoding: .utf8)
    print("✅ Created .envrc")

    return true
  }

  /// Create git hooks directory and hook files
  private func createGitHooks(projectPath: URL, projectName: String) throws -> [String] {
    let hooksDir = projectPath.appendingPathComponent(".githooks")
    let fileManager = FileManager.default

    // Create .githooks directory
    if !fileManager.fileExists(atPath: hooksDir.path) {
      try fileManager.createDirectory(
        at: hooksDir,
        withIntermediateDirectories: true,
        attributes: nil
      )
      print("✅ Created .githooks directory")
    }

    var created: [String] = []

    // Create post-commit hook
    if try createHook(
      name: "post-commit",
      projectName: projectName,
      hooksDir: hooksDir,
      content: postCommitHook()
    ) {
      created.append(".githooks/post-commit")
    }

    // Create post-merge hook
    if try createHook(
      name: "post-merge",
      projectName: projectName,
      hooksDir: hooksDir,
      content: postMergeHook()
    ) {
      created.append(".githooks/post-merge")
    }

    // Create post-checkout hook
    if try createHook(
      name: "post-checkout",
      projectName: projectName,
      hooksDir: hooksDir,
      content: postCheckoutHook()
    ) {
      created.append(".githooks/post-checkout")
    }

    // Create README
    if try createReadme(
      projectName: projectName,
      hooksDir: hooksDir
    ) {
      created.append(".githooks/README.md")
    }

    return created
  }

  /// Create a single hook file
  private func createHook(
    name: String,
    projectName: String,
    hooksDir: URL,
    content: String
  ) throws -> Bool {
    let hookPath = hooksDir.appendingPathComponent(name)
    let fileManager = FileManager.default

    // Check if file exists
    if fileManager.fileExists(atPath: hookPath.path) {
      print("⚠️  \(name) already exists")
      print("   Overwrite? (y/n): ", terminator: "")

      guard let response = readLine()?.lowercased(),
        response == "y" || response == "yes"
      else {
        print("   Skipped \(name)")
        return false
      }
    }

    try content.write(to: hookPath, atomically: true, encoding: .utf8)

    // Make executable
    try fileManager.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: hookPath.path
    )

    print("✅ Created \(name)")
    return true
  }

  /// Create README.md in hooks directory
  private func createReadme(projectName: String, hooksDir: URL) throws -> Bool {
    let readmePath = hooksDir.appendingPathComponent("README.md")

    // Don't prompt for README overwrite, just overwrite silently
    let content = """
      # Git Hooks for code-search-mcp Integration

      This directory contains git hooks that automatically re-index the codebase
      for code-search-mcp when code changes.

      ## Available Hooks

      - **post-commit**: Re-indexes after committing changes
      - **post-merge**: Re-indexes after pulling/merging
      - **post-checkout**: Re-indexes after switching branches

      ## Installation

      ### For Submodules (\(projectName) in parent repo)

      ```bash
      # Copy hooks to the submodule's git directory
      cp .githooks/* ../.git/modules/\(projectName)/hooks/
      chmod +x ../.git/modules/\(projectName)/hooks/post-*
      ```

      ### For Regular Git Repos

      ```bash
      # Copy hooks to .git/hooks
      cp .githooks/* .git/hooks/
      chmod +x .git/hooks/post-*
      ```

      ### Using Git's core.hooksPath (Recommended)

      ```bash
      # Configure git to use .githooks directory
      git config core.hooksPath .githooks
      chmod +x .githooks/post-*
      ```

      ## Requirements

      - `code-search-mcp` binary must be in PATH
      - Install: `swift build -c release && cp .build/release/code-search-mcp ~/.swiftpm/bin/`

      ## How It Works

      Each hook runs `code-search-mcp` in the background after the git operation,
      ensuring the search index stays up-to-date with your codebase changes.

      Log files are written to `/tmp/code-search-mcp-*.log` for debugging.

      """

    try content.write(to: readmePath, atomically: true, encoding: .utf8)
    print("✅ Created README.md")
    return true
  }

  /// Install git hooks by configuring core.hooksPath
  private func installGitHooks(projectPath: URL) throws {
    let process = Process()
    process.currentDirectoryURL = projectPath
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["config", "core.hooksPath", ".githooks"]

    let pipe = Pipe()
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
      print("❌ Failed to configure git hooks: \(errorMessage)")
      throw ExitCode.failure
    }

    print("✅ Git hooks configured (core.hooksPath = .githooks)")
  }

  // MARK: - Hook Templates

  private func postCommitHook() -> String {
    """
    #!/bin/bash
    # Post-commit hook: Re-index code after committing changes

    # Get the project directory (works for both regular repos and submodules)
    PROJECT_DIR="$(git rev-parse --show-toplevel)"

    if command -v code-search-mcp &> /dev/null; then
      echo "📚 [post-commit] Re-indexing after commit..."
      (code-search-mcp --log-level info --project-paths "$PROJECT_DIR" > /tmp/code-search-mcp-post-commit.log 2>&1 &)
    else
      echo "⚠️  code-search-mcp not found, skipping re-index"
    fi

    """
  }

  private func postMergeHook() -> String {
    """
    #!/bin/bash
    # Post-merge hook: Re-index code after pulling/merging changes

    # Get the project directory (works for both regular repos and submodules)
    PROJECT_DIR="$(git rev-parse --show-toplevel)"

    if command -v code-search-mcp &> /dev/null; then
      echo "📚 [post-merge] Re-indexing after pull/merge..."
      (code-search-mcp --log-level info --project-paths "$PROJECT_DIR" > /tmp/code-search-mcp-post-merge.log 2>&1 &)
    else
      echo "⚠️  code-search-mcp not found, skipping re-index"
    fi

    """
  }

  private func postCheckoutHook() -> String {
    """
    #!/bin/bash
    # Post-checkout hook: Re-index code after switching branches

    # Get the project directory (works for both regular repos and submodules)
    PROJECT_DIR="$(git rev-parse --show-toplevel)"

    # $3 is 1 if it's a branch checkout, 0 if it's a file checkout
    if [ "$3" = "1" ]; then
      if command -v code-search-mcp &> /dev/null; then
        echo "📚 [post-checkout] Re-indexing after branch switch..."
        (code-search-mcp --log-level info --project-paths "$PROJECT_DIR" > /tmp/code-search-mcp-post-checkout.log 2>&1 &)
      else
        echo "⚠️  code-search-mcp not found, skipping re-index"
      fi
    fi

    """
  }
}
