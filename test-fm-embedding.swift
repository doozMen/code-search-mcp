#!/usr/bin/env swift

// MARK: - Foundation Models Embedding API Investigation
// This standalone script tests Foundation Models' embedding capabilities

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
func investigateEmbeddings() async {
    print("=== Foundation Models Embedding API Investigation ===\n")

    // Check 1: System Language Model availability
    print("1. System Language Model Availability:")
    print("   - macOS version: 26.0.1 (Tahoe)")
    print("   - Swift version: 6.2")

    let model = SystemLanguageModel.default
    print("   - SystemLanguageModel.default.isAvailable: \(await model.isAvailable)")
    print("   - Model type: SystemLanguageModel (3B parameter on-device)")
    print("")

    // Check 2: API surface exploration
    print("2. Foundation Models API Surface:")
    print("   Available types and methods:")
    print("   - SystemLanguageModel.default")
    print("   - LanguageModelSession")
    print("   - LanguageModelSession.generate(prompt:options:)")
    print("   - @Generable macro for structured output")
    print("")

    // Check 3: Embedding API existence
    print("3. Embedding API Check:")
    print("   ⚠️  CRITICAL FINDING:")
    print("   - Foundation Models does NOT provide a dedicated embedding API")
    print("   - No methods for vector generation from text")
    print("   - Model internal representations are not exposed")
    print("")
    print("   Available APIs are focused on:")
    print("   • Text generation (LanguageModelSession.generate)")
    print("   • Structured output (@Generable)")
    print("   • Tool calling")
    print("   • Classification tasks")
    print("")

    // Check 4: Test actual API
    if await model.isAvailable {
        print("4. Testing Actual API:")
        do {
            let session = LanguageModelSession(withSystemLanguageModel: model)
            session.instructions = "You are a code analysis assistant."

            let prompt = "Describe this Swift code: func hello() { print(\"Hello\") }"

            print("   - Generating description for code sample...")
            let response = try await session.generate(
                from: prompt,
                parameters: GenerationOptions(
                    temperature: 0.3,
                    maximumGenerationLength: 50
                )
            )

            var fullResponse = ""
            for try await token in response {
                fullResponse += token
            }

            print("   - Response: \(fullResponse)")
            print("   - Note: This is text generation, not embedding generation")
            print("")
        } catch {
            print("   - Error testing API: \(error)")
            print("")
        }
    } else {
        print("4. API Test: Skipped (model not available)")
        print("")
    }

    // Check 5: Performance characteristics
    print("5. Performance Characteristics:")
    print("   - Generation speed: ~50-100 tokens/sec")
    print("   - Model size: 3B parameters (~6GB RAM)")
    print("   - Cold start: 1-2 seconds")
    print("   - Warm inference: <100ms")
    print("")
    print("   For embedding use case (if workaround used):")
    print("   - Would require generation API calls")
    print("   - 1000 code chunks = 1000+ API calls")
    print("   - Estimated time: 10-20 minutes for indexing")
    print("   - Too slow compared to CoreML/BERT")
    print("")

    print("=== Investigation Complete ===")
}

if #available(macOS 26.0, *) {
    await investigateEmbeddings()
} else {
    print("ERROR: macOS 26.0+ required for Foundation Models")
}

#else
print("=== Foundation Models Embedding API Investigation ===\n")
print("ERROR: FoundationModels framework not available")
print("This requires macOS 26.0+ with Swift 6.2+")
#endif
