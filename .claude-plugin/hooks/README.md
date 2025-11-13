# Claude Code Hooks

This directory contains hooks that enhance the developer experience when using the code-search-mcp plugin.

## beforeToolCall Hook

**Purpose**: Guide users toward semantic search when using grep for conceptual queries.

### How It Works

The hook intercepts `Grep` tool calls and analyzes the pattern for conceptual indicators:

1. **Question Words**: "how", "what", "why", "where", etc.
2. **Conceptual Terms**: "implementation", "pattern", "architecture", etc.
3. **Multiple Words**: 3+ words suggests semantic intent
4. **Has Spaces**: Less likely to be an exact identifier
5. **Not Code Syntax**: No dots, brackets, or camelCase

If **2 or more indicators** are present, it suggests using `semantic_search` instead.

### Examples

**Triggers Suggestion ✅**
```
grep "how does background indexing work"
→ Suggests: semantic_search("how does background indexing work")

grep "actor isolation patterns"
→ Suggests: semantic_search("actor isolation patterns")

grep "job queue implementation"
→ Suggests: semantic_search("job queue implementation")
```

**Doesn't Trigger ✅** (legitimate grep use)
```
grep "func indexProject"  # Exact function name
grep "IndexingError"      # Exact type name
grep "TODO"               # Marker search
grep -i "import Foundation" # Exact import
```

### Benefits

- **Educational**: Helps users discover semantic search capabilities
- **Non-blocking**: Never prevents grep execution, just provides guidance
- **Smart**: Uses multiple heuristics to avoid false positives
- **Context-aware**: Understands the difference between conceptual and exact searches

### Configuration

The hook is automatically loaded when the plugin is installed. No configuration needed!

### Testing

See `test_hook.js` for unit tests of the detection logic.
