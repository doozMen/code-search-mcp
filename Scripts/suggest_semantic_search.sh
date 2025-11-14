#!/bin/bash
# Post-grep suggestion for semantic search

# This hook runs AFTER grep execution to suggest semantic_search
# when conceptual patterns were used

# Extract grep pattern from tool use context
PATTERN="${CLAUDE_TOOL_PARAMS_PATTERN:-}"

if [ -z "$PATTERN" ]; then
  exit 0
fi

# Heuristics for detecting conceptual queries
if echo "$PATTERN" | grep -qE '\b(how|what|why|where|when|which|who)\b' || \
   echo "$PATTERN" | grep -qE '\b(implementation|pattern|architecture|design|approach|strategy|workflow|process)\b' || \
   [ $(echo "$PATTERN" | wc -w) -ge 3 ]; then
  
  cat <<MESSAGE

🔍 Semantic Search Suggestion

Pattern: "$PATTERN"

Consider using semantic_search for better conceptual matches:
  semantic_search("$PATTERN")

Why semantic search?
• Finds code by MEANING, not just text matching
• Discovers related implementations even with different naming
• Returns relevance-scored results

MESSAGE
fi
