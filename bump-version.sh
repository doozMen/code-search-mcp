#!/bin/bash

# Code Search MCP Version Bump Script
# Usage: ./bump-version.sh <new-version>
# Example: ./bump-version.sh 0.2.1
# Example: ./bump-version.sh 0.3.0

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <new-version>"
    echo ""
    echo "Examples:"
    echo "  $0 0.2.1             # Bump to patch release"
    echo "  $0 0.3.0             # Bump to minor release"
    echo "  $0 1.0.0             # Bump to major release"
    echo ""
    echo "Version will be updated in:"
    echo "  - .claude-plugin/plugin.json (plugin version)"
    echo "  - Sources/CodeSearchMCP/CodeSearchMCP.swift (CLI version)"
    echo "  - Sources/CodeSearchMCP/MCPServer.swift (server version)"
    exit 1
fi

NEW_VERSION=$1

# Validate version format (basic check)
if ! [[ $NEW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: Invalid version format: $NEW_VERSION"
    echo "Expected format: X.Y.Z or X.Y.Z-prerelease (e.g., 0.2.0, 0.2.1-beta.1)"
    exit 1
fi

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Update plugin.json
PLUGIN_JSON="$CURRENT_DIR/.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ]; then
    sed -i '' "s/\"version\": \"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" "$PLUGIN_JSON"
    echo "✓ Updated plugin.json to version $NEW_VERSION"
else
    echo "⚠ Warning: plugin.json not found at $PLUGIN_JSON"
fi

# Update CodeSearchMCP.swift
CLI_SWIFT="$CURRENT_DIR/Sources/CodeSearchMCP/CodeSearchMCP.swift"
if [ -f "$CLI_SWIFT" ]; then
    sed -i '' "s/version: \"[^\"]*\"/version: \"$NEW_VERSION\"/" "$CLI_SWIFT"
    echo "✓ Updated CodeSearchMCP.swift to version $NEW_VERSION"
else
    echo "⚠ Warning: CodeSearchMCP.swift not found at $CLI_SWIFT"
fi

# Update MCPServer.swift
SERVER_SWIFT="$CURRENT_DIR/Sources/CodeSearchMCP/MCPServer.swift"
if [ -f "$SERVER_SWIFT" ]; then
    sed -i '' "s/version: \"[^\"]*\"/version: \"$NEW_VERSION\"/" "$SERVER_SWIFT"
    echo "✓ Updated MCPServer.swift to version $NEW_VERSION"
else
    echo "⚠ Warning: MCPServer.swift not found at $SERVER_SWIFT"
fi

echo ""
echo "Version bump complete! ✨"
echo "New version: $NEW_VERSION"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Commit changes: git add . && git commit -m 'chore: Bump version to $NEW_VERSION'"
echo "  3. Create git tag: git tag v$NEW_VERSION"
echo "  4. Build: swift build -c release"
echo "  5. Install: ./install.sh"
