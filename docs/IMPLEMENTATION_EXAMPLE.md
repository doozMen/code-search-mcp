# Multi-Project Management: Implementation Example

## Quick Start Guide

This document shows concrete implementation examples for the multi-project architecture described in MULTI_PROJECT_ARCHITECTURE.md.

## Example: WorkspaceManager Implementation

Create a new file `Sources/CodeSearchMCP/Services/WorkspaceManager.swift`:

```swift
import Foundation
import Logging
import Crypto

/// Manages multiple projects within a workspace, handling activation,
/// deactivation, and context switching.
actor WorkspaceManager: Sendable {
    // MARK: - Properties
    
    private let indexPath: String
    private let logger: Logger
    private let fileManager = FileManager.default
    
    /// Currently active projects (loaded in memory)
    private var activeProjects: Set<ProjectIdentifier> = []
    
    /// Metadata for all known projects
    private var projectRegistry: [ProjectIdentifier: ProjectMetadata] = [:]
    
    /// Maximum number of projects to keep active
    private let maxActiveProjects: Int
    
    /// Path to workspace state file
    private var workspaceStatePath: String {
        (indexPath as NSString)
            .appendingPathComponent("workspaces")
            .appendingPathComponent("default")
            .appendingPathComponent("workspace.json")
    }
    
    // MARK: - Initialization
    
    init(indexPath: String, maxActiveProjects: Int = 5) {
        self.indexPath = indexPath
        self.maxActiveProjects = maxActiveProjects
        self.logger = Logger(label: "workspace-manager")
        
        // Create workspace directories
        let workspaceDir = (indexPath as NSString)
            .appendingPathComponent("workspaces")
            .appendingPathComponent("default")
        
        try? fileManager.createDirectory(
            atPath: workspaceDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Load existing workspace state
        Task {
            await loadWorkspaceState()
        }
    }
    
    // MARK: - Project Management
    
    /// Activate a project, loading it into memory
    func activateProject(_ path: String) async throws -> ProjectIdentifier {
        let projectId = ProjectIdentifier(path: path)
        
        logger.info("Activating project", metadata: [
            "name": "\(projectId.name)",
            "path": "\(projectId.path)"
        ])
        
        // Check if already active
        if activeProjects.contains(projectId) {
            logger.debug("Project already active")
            return projectId
        }
        
        // Enforce max active projects limit
        if activeProjects.count >= maxActiveProjects {
            // Deactivate least recently used project
            if let lruProject = await findLeastRecentlyUsedProject() {
                try await deactivateProject(lruProject)
            }
        }
        
        // Load project metadata
        let metadata = try await loadOrCreateProjectMetadata(projectId)
        projectRegistry[projectId] = metadata
        
        // Mark as active
        activeProjects.insert(projectId)
        
        // Persist workspace state
        try await saveWorkspaceState()
        
        logger.info("Project activated", metadata: [
            "active_count": "\(activeProjects.count)"
        ])
        
        return projectId
    }
    
    /// Deactivate a project, removing it from memory
    func deactivateProject(_ id: ProjectIdentifier) async throws {
        guard activeProjects.contains(id) else {
            logger.warning("Attempted to deactivate inactive project")
            return
        }
        
        logger.info("Deactivating project", metadata: [
            "name": "\(id.name)"
        ])
        
        // Update last accessed time
        if var metadata = projectRegistry[id] {
            metadata.lastAccessed = Date()
            projectRegistry[id] = metadata
            try await saveProjectMetadata(id, metadata: metadata)
        }
        
        // Remove from active set
        activeProjects.remove(id)
        
        // Persist workspace state
        try await saveWorkspaceState()
        
        logger.info("Project deactivated", metadata: [
            "active_count": "\(activeProjects.count)"
        ])
    }
}
```

## Example: direnv Configuration

Create `.envrc` in your project directory:

```bash
#!/usr/bin/env bash
# code-search-mcp direnv configuration

# Set this project as the active project for code-search-mcp
export CODE_SEARCH_PROJECT_PATH="$(pwd)"

# Configure workspace name (optional)
export CODE_SEARCH_WORKSPACE="mycompany"

# Auto-index on activation
export CODE_SEARCH_AUTO_INDEX="true"

# Default search scope to current project
export CODE_SEARCH_SEARCH_SCOPE="project"

# Project-specific indexing settings
export CODE_SEARCH_CHUNK_SIZE="100"
export CODE_SEARCH_OVERLAP_SIZE="20"

# Exclude patterns (colon-separated)
export CODE_SEARCH_EXCLUDE=".build:node_modules:vendor"

echo "code-search-mcp: Activated project $(basename $(pwd))"
```

## Example: Project Configuration File

Create `.code-search-mcp.json` in project root:

```json
{
  "version": "1.0",
  "project": {
    "name": "MyAwesomeApp",
    "description": "iOS app with SwiftUI",
    "language_focus": ["swift", "objective-c"],
    "exclude_patterns": [
      ".build/",
      "DerivedData/",
      "*.generated.swift",
      "vendor/",
      "Pods/"
    ]
  },
  "indexing": {
    "chunk_size": 100,
    "overlap_size": 20,
    "max_file_size": 1048576,
    "symbol_extraction": true,
    "dependency_tracking": true
  },
  "search": {
    "default_scope": "project",
    "include_dependencies": false,
    "semantic_threshold": 0.7
  },
  "cache": {
    "max_project_size": 524288000,
    "compression_enabled": true,
    "retention_days": 30
  }
}
```

## Storage Example

After implementation, your cache directory structure would look like:

```
~/.cache/code-search-mcp/
├── workspaces/
│   └── default/
│       └── workspace.json
├── projects/
│   ├── a1b2c3d4.../  # MyApp project
│   │   ├── metadata.json
│   │   ├── symbols.json
│   │   ├── dependencies.json
│   │   └── embeddings/
│   │       └── ref_12345.json  # Reference to global cache
│   └── e5f6g7h8.../  # MyLib project
│       ├── metadata.json
│       ├── symbols.json
│       └── dependencies.json
├── global/
│   └── embeddings/
│       ├── abc123...def.embedding  # Shared embedding
│       └── xyz789...ghi.embedding  # Shared embedding
└── config/
    ├── settings.json
    └── projects.json
```

## Summary

This implementation provides:

1. **Automatic project switching** with direnv
2. **LRU cache management** to prevent unbounded growth
3. **Workspace persistence** across sessions
4. **Flexible search scoping** per query
5. **Environment-based configuration** for CI/CD compatibility

The system gracefully handles multiple projects while maintaining reasonable memory and disk usage.
