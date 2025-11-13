/**
 * Hook: Suggest semantic search for conceptual grep queries
 *
 * This hook detects when grep is being used for conceptual/semantic queries
 * and provides a helpful suggestion to use semantic_search instead for better results.
 */

export async function beforeToolCall({ toolName, params, context }) {
  // Only intercept grep tool calls
  if (toolName !== "Grep") {
    return;
  }

  const pattern = params.pattern;

  // Skip if no pattern
  if (!pattern) {
    return;
  }

  // Heuristics for detecting conceptual queries
  const conceptualIndicators = {
    // Natural language question words
    questionWords: /\b(how|what|why|where|when|which|who)\b/i,

    // Common conceptual terms
    conceptualTerms: /\b(implementation|pattern|architecture|design|approach|strategy|workflow|process)\b/i,

    // Multiple words (likely semantic rather than exact match)
    multipleWords: pattern.split(/\s+/).length >= 3,

    // Contains spaces (less likely to be an identifier)
    hasSpaces: /\s/.test(pattern),

    // No code-specific syntax (brackets, dots, camelCase exact matches)
    notCodeSyntax: !/[.\[\](){}<>]/.test(pattern) && !/^[a-z]+[A-Z]/.test(pattern)
  };

  // Count how many indicators are present
  const indicators = [
    conceptualIndicators.questionWords.test(pattern),
    conceptualIndicators.conceptualTerms.test(pattern),
    conceptualIndicators.multipleWords,
    conceptualIndicators.hasSpaces,
    conceptualIndicators.notCodeSyntax
  ];

  const indicatorCount = indicators.filter(Boolean).length;

  // Suggest semantic search if 2 or more indicators present
  if (indicatorCount >= 2) {
    const message = `
🔍 Semantic Search Suggestion

Pattern: "${pattern}"
Indicators: ${indicatorCount}/5 (conceptual query detected)

Consider using semantic_search instead for better conceptual matches:
  semantic_search("${pattern}")

Why semantic search?
• Finds code by MEANING, not just text matching
• Discovers related implementations even with different naming
• Returns relevance-scored results

When to still use grep:
• Exact identifier searches (function names, class names)
• Finding specific syntax patterns
• File-wide replacements with line numbers
`;

    return {
      systemMessage: message,
      // Don't block the grep call - just provide guidance
      allowExecution: true
    };
  }

  // Allow grep to proceed without suggestion
  return;
}
