#!/usr/bin/env python3
"""
BERT Embedding Generation Script

Generates 384-dimensional sentence-transformers embeddings for code chunks.
Communicates via JSON stdin/stdout for Swift interop.
"""

import sys
import json
from sentence_transformers import SentenceTransformer

# Load model once at startup (cached after first run)
MODEL_NAME = 'sentence-transformers/all-MiniLM-L6-v2'  # 384 dimensions
model = None

def load_model():
    global model
    if model is None:
        model = SentenceTransformer(MODEL_NAME)
    return model

def generate_embedding(text: str) -> list[float]:
    """Generate 384-dimensional embedding for text."""
    model = load_model()
    embedding = model.encode(text, convert_to_numpy=True)
    return embedding.tolist()

def generate_batch_embeddings(texts: list[str]) -> list[list[float]]:
    """Generate embeddings for multiple texts efficiently."""
    model = load_model()
    embeddings = model.encode(texts, convert_to_numpy=True, batch_size=32)
    return embeddings.tolist()

def main():
    """Process JSON requests from stdin and output results to stdout."""
    try:
        request = json.loads(sys.stdin.read())

        if 'text' in request:
            # Single embedding request
            embedding = generate_embedding(request['text'])
            response = {'embedding': embedding, 'dimension': len(embedding)}
        elif 'texts' in request:
            # Batch embedding request
            embeddings = generate_batch_embeddings(request['texts'])
            response = {'embeddings': embeddings, 'count': len(embeddings)}
        else:
            response = {'error': 'Invalid request: must provide "text" or "texts"'}

        print(json.dumps(response))
        sys.stdout.flush()

    except Exception as e:
        error_response = {'error': str(e)}
        print(json.dumps(error_response))
        sys.stderr.write(f"Error: {e}\n")
        sys.exit(1)

if __name__ == '__main__':
    main()
