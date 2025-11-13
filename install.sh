#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "==================================="
echo "code-search-mcp Installation"
echo "==================================="
echo ""

# Check for Swift
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift is not installed or not in PATH${NC}"
    echo "Please install Swift 6.0 or later"
    exit 1
fi

# Check Swift version
SWIFT_VERSION=$(swift --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
echo -e "${YELLOW}Found Swift version: $SWIFT_VERSION${NC}"

# Build in release mode
echo ""
echo "Building code-search-mcp in release mode..."
if swift build -c release; then
    echo -e "${GREEN}Build successful${NC}"
else
    echo -e "${RED}Build failed${NC}"
    exit 1
fi

# Install executable
echo ""
echo "Installing to ~/.swiftpm/bin..."

# Remove old executable if it exists
if [ -f ~/.swiftpm/bin/code-search-mcp ]; then
    rm ~/.swiftpm/bin/code-search-mcp
    echo "Removed existing installation"
fi

# Install using swift package command
if swift package experimental-install; then
    echo -e "${GREEN}Installation successful${NC}"
else
    echo -e "${RED}Installation failed${NC}"
    exit 1
fi

# Configure PATH
echo ""
echo "Configuring PATH..."

# Detect shell
CURRENT_SHELL=$(basename "$SHELL")
CONFIG_FILE=""
PATH_LINE='export PATH="$HOME/.swiftpm/bin:$PATH"'

case "$CURRENT_SHELL" in
  zsh)
    CONFIG_FILE="$HOME/.zshrc"
    ;;
  bash)
    if [ -f "$HOME/.bash_profile" ]; then
      CONFIG_FILE="$HOME/.bash_profile"
    else
      CONFIG_FILE="$HOME/.bashrc"
    fi
    ;;
  fish)
    CONFIG_FILE="$HOME/.config/fish/config.fish"
    PATH_LINE='set -gx PATH $HOME/.swiftpm/bin $PATH'
    mkdir -p "$HOME/.config/fish"
    ;;
  *)
    echo -e "${YELLOW}Unknown shell: $CURRENT_SHELL${NC}"
    echo "Manually add to your shell config:"
    echo '  export PATH="$HOME/.swiftpm/bin:$PATH"'
    CONFIG_FILE=""
    ;;
esac

# Add PATH if not already configured
if [ -n "$CONFIG_FILE" ]; then
  if grep -q '.swiftpm/bin' "$CONFIG_FILE" 2>/dev/null; then
    echo -e "${GREEN}PATH already configured in $CONFIG_FILE${NC}"
  else
    echo "" >> "$CONFIG_FILE"
    echo "# Added by code-search-mcp installer" >> "$CONFIG_FILE"
    echo "$PATH_LINE" >> "$CONFIG_FILE"
    echo -e "${GREEN}Added ~/.swiftpm/bin to PATH in $CONFIG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}⚡ To use immediately, run: source $CONFIG_FILE${NC}"
    echo "   Or open a new terminal window"
  fi
fi

# Verify installation
echo ""
echo "Verifying installation..."
if command -v code-search-mcp &> /dev/null; then
    echo -e "${GREEN}Verification successful${NC}"
    VERSION=$(code-search-mcp --version 2>&1 || echo "unknown")
    echo "Installed version: $VERSION"
else
    echo -e "${YELLOW}Note: code-search-mcp will be available after sourcing shell config${NC}"
    if [ -n "$CONFIG_FILE" ]; then
        echo "Run: source $CONFIG_FILE"
    fi
    # Check if binary exists in the expected location
    if [ -f ~/.swiftpm/bin/code-search-mcp ]; then
        echo -e "${GREEN}Binary installed at ~/.swiftpm/bin/code-search-mcp${NC}"
    else
        echo -e "${RED}Error: Binary not found at ~/.swiftpm/bin/code-search-mcp${NC}"
        exit 1
    fi
fi

# Print configuration instructions
echo ""
echo "==================================="
echo -e "${GREEN}Installation Complete!${NC}"
echo "==================================="
echo ""
echo "To use code-search-mcp with Claude Desktop:"
echo ""
echo "1. Open your Claude Desktop configuration:"
echo "   ~/Library/Application Support/Claude/claude_desktop_config.json"
echo ""
echo "2. Add the following server configuration:"
echo ""
cat << 'CONFIG'
  "code-search-mcp": {
    "command": "code-search-mcp",
    "args": ["--log-level", "info"],
    "env": {
      "PATH": "$HOME/.swiftpm/bin:/usr/local/bin:/usr/bin:/bin"
    }
  }
CONFIG

echo ""
echo "3. Restart Claude Desktop"
echo ""
echo "For help, run: code-search-mcp --help"
echo ""
