#!/bin/bash
# Install Python dependencies for BERT embedding generation

set -e

echo "Installing Python dependencies for code-search-mcp..."

# Check if pip is available
if ! command -v pip3 &> /dev/null; then
    echo "Error: pip3 not found. Please install Python 3 first."
    exit 1
fi

# Install sentence-transformers (includes torch and transformers)
pip3 install --upgrade sentence-transformers

echo "Python dependencies installed successfully!"
echo ""
echo "Installed packages:"
pip3 show sentence-transformers | grep -E "Name|Version"
