#!/bin/bash
# Install Python dependencies for BERT embedding generation

set -e

echo "Installing Python dependencies for code-search-mcp..."
echo ""

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 not found. Please install Python 3 first."
    echo "  On macOS: brew install python@3"
    exit 1
fi

# Check if pip is available
if ! command -v pip3 &> /dev/null; then
    echo "Error: pip3 not found. Please install Python 3 first."
    exit 1
fi

# Check Python version (need 3.8+)
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
REQUIRED_VERSION="3.8"

if ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)"; then
    echo "Error: Python $PYTHON_VERSION found, but $REQUIRED_VERSION or higher is required"
    exit 1
fi

echo "Python version: $PYTHON_VERSION ✓"
echo ""

# Check if already installed
if python3 -c "import sentence_transformers" 2>/dev/null; then
    echo "sentence-transformers is already installed:"
    pip3 show sentence-transformers | grep -E "Name|Version"
    echo ""
    read -p "Reinstall/upgrade? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping installation."
        exit 0
    fi
fi

# Install sentence-transformers (includes torch and transformers)
echo "Installing sentence-transformers..."
pip3 install --upgrade sentence-transformers

echo ""
echo "✓ Python dependencies installed successfully!"
echo ""
echo "Installed packages:"
pip3 show sentence-transformers | grep -E "Name|Version"
echo ""
echo "You can now use BERT embedding provider in code-search-mcp."
echo ""
echo "To start the server manually:"
echo "  python3 Scripts/bert_embedding_server.py"
echo ""
echo "Or let code-search-mcp manage it automatically."
