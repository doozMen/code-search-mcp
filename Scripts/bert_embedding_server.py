#!/usr/bin/env python3
"""
BERT Embedding Server for code-search-mcp

Provides a simple HTTP server for generating BERT embeddings.
Uses sentence-transformers with all-MiniLM-L6-v2 model (384 dimensions).

This is a FALLBACK provider for systems without CoreML/Foundation Models.
"""

import sys
import json
import logging
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import List, Dict
import threading

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("bert-server")

# Global model instance (lazy loaded)
_model = None
_model_lock = threading.Lock()


def get_model():
    """Get or initialize the BERT model (thread-safe)."""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                try:
                    from sentence_transformers import SentenceTransformer
                    logger.info("Loading BERT model: all-MiniLM-L6-v2")
                    _model = SentenceTransformer('all-MiniLM-L6-v2')
                    logger.info("Model loaded successfully")
                except ImportError:
                    logger.error("sentence-transformers not installed")
                    raise RuntimeError(
                        "sentence-transformers package not installed. "
                        "Run: pip3 install sentence-transformers"
                    )
                except Exception as e:
                    logger.error(f"Failed to load model: {e}")
                    raise
    return _model


class EmbeddingHandler(BaseHTTPRequestHandler):
    """HTTP request handler for embedding generation."""

    def log_message(self, format, *args):
        """Override to use Python logging instead of stderr."""
        logger.info(format % args)

    def do_GET(self):
        """Health check endpoint."""
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {
                'status': 'healthy',
                'model': 'all-MiniLM-L6-v2',
                'dimension': 384
            }
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        """Handle embedding generation requests."""
        if self.path != '/embed':
            self.send_error(404, "Not Found - use /embed")
            return

        try:
            # Parse request body
            content_length = int(self.headers['Content-Length'])
            body = self.rfile.read(content_length)
            data = json.loads(body)

            if 'texts' not in data:
                self.send_error(400, "Missing 'texts' field in request")
                return

            texts = data['texts']
            if not isinstance(texts, list):
                self.send_error(400, "'texts' must be an array")
                return

            if not texts:
                self.send_error(400, "'texts' array cannot be empty")
                return

            # Generate embeddings
            logger.info(f"Generating embeddings for {len(texts)} texts")
            model = get_model()
            embeddings = model.encode(texts, show_progress_bar=False)

            # Convert to list of lists (NumPy -> JSON)
            embeddings_list = [emb.tolist() for emb in embeddings]

            # Send response
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {
                'embeddings': embeddings_list,
                'dimension': 384,
                'count': len(embeddings_list)
            }
            self.wfile.write(json.dumps(response).encode())
            logger.info(f"Successfully generated {len(embeddings_list)} embeddings")

        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON: {e}")
            self.send_error(400, f"Invalid JSON: {e}")
        except Exception as e:
            logger.error(f"Error generating embeddings: {e}")
            self.send_error(500, f"Internal server error: {e}")


def run_server(host: str = '127.0.0.1', port: int = 8765):
    """Run the embedding server."""
    server_address = (host, port)
    httpd = HTTPServer(server_address, EmbeddingHandler)
    
    logger.info(f"BERT Embedding Server starting on {host}:{port}")
    logger.info("Endpoints:")
    logger.info("  GET  /health - Health check")
    logger.info("  POST /embed  - Generate embeddings")
    logger.info("")
    logger.info("Press Ctrl+C to stop")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
        httpd.server_close()


if __name__ == '__main__':
    # Parse command line arguments
    port = 8765
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            logger.error(f"Invalid port: {sys.argv[1]}")
            sys.exit(1)
    
    run_server(port=port)
