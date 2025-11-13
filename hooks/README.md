# Claude Code Hooks

This directory contains hooks that enhance the developer experience when using the code-search-mcp plugin.

## Hook Architecture

Claude Code plugins support **command-based hooks** triggered by specific events. This plugin uses the `PostToolUse` event to provide helpful suggestions after tool execution.

## Current Hooks

### PostToolUse: Semantic Search Suggestion

**Trigger**: After `Grep` tool execution
**Script**: `scripts/suggest_semantic_search.sh`

**Purpose**: Guide users toward semantic search when using grep for conceptual queries.

#### How It Works

The hook analyzes the grep pattern for conceptual indicators:

1. **Question Words**: "how", "what", "why", "where", etc.
2. **Conceptual Terms**: "implementation", "pattern", "architecture", etc.
3. **Multiple Words**: 3+ words suggests semantic intent

If indicators are present, it suggests using `semantic_search` instead.

#### Examples

**Triggers Suggestion** ✅
```bash
# Conceptual query with question word
Grep pattern="how does background indexing work"
→ Suggests: semantic_search("how does background indexing work")

# Architecture exploration
Grep pattern="actor isolation patterns"
→ Suggests: semantic_search("actor isolation patterns")

# Implementation discovery
Grep pattern="job queue implementation"
→ Suggests: semantic_search("job queue implementation")
```

**Doesn't Trigger** ✅ (legitimate grep use)
```bash
Grep pattern="func indexProject"      # Exact function name
Grep pattern="IndexingError"          # Exact type name
Grep pattern="TODO"                   # Marker search
Grep pattern="import Foundation" -i   # Exact import
```

## Hook Configuration Format

**File**: `hooks/hooks.json`

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Grep",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/suggest_semantic_search.sh"
          }
        ]
      }
    ]
  }
}
```

### Available Hook Events

Based on Claude Code plugin standards:

- **PostToolUse**: After tool execution (Read, Write, Edit, Grep, etc.)
- **UserPromptSubmit**: Before user prompt processing

### Matcher Patterns

- Single tool: `"matcher": "Grep"`
- Multiple tools: `"matcher": "Write|Edit"`
- All tools: Omit matcher field

## Environment Variables

Scripts receive context via environment variables:

- `CLAUDE_PLUGIN_ROOT` - Plugin installation directory
- `CLAUDE_TOOL_NAME` - Name of the tool that was used
- `CLAUDE_TOOL_PARAMS_*` - Tool parameters (e.g., `CLAUDE_TOOL_PARAMS_PATTERN`)

## Benefits

- **Educational**: Helps users discover semantic search capabilities
- **Non-blocking**: Never prevents tool execution, just provides guidance
- **Smart**: Uses multiple heuristics to avoid false positives
- **Context-aware**: Understands the difference between conceptual and exact searches

## Testing

Test the hook locally:

```bash
# Install plugin
/plugin marketplace add /Users/stijnwillems/Developer/code-search-mcp
/plugin install code-search-mcp

# Test with conceptual query
Grep pattern="how does async indexing work"

# Should see suggestion after grep results
```

## Troubleshooting

**Hook not triggering?**
1. Verify script is executable: `chmod +x scripts/suggest_semantic_search.sh`
2. Check hooks.json syntax: `cat hooks/hooks.json | jq`
3. Review Claude Code logs for hook execution errors

**Script errors?**
- Ensure bash shebang is present: `#!/bin/bash`
- Test script manually: `CLAUDE_TOOL_PARAMS_PATTERN="test" ./scripts/suggest_semantic_search.sh`
- Check script permissions: `ls -l scripts/suggest_semantic_search.sh`

## Future Enhancements

Potential hook improvements:

1. **Auto-indexing prompt**: After `Write`/`Edit` in large projects
2. **Project filter suggestion**: When searching without project context
3. **Related code discovery**: After viewing file with `Read`
4. **Stale index warning**: When indexed files are older than 24 hours

## References

- [Plugin Structure Documentation](../skills/claude-code-plugin/PLUGIN-STRUCTURE.md)
- [9 Production Plugins](https://github.com/doozMen/promptping-marketplace)
- Claude Code Plugin Standards: Command-based hooks with `hooks.json`
