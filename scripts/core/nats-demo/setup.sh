#!/bin/bash

# NATS JetStream Setup Script
# This script installs NATS server and CLI tools if needed, then starts the server

set -e

echo "🚀 NATS JetStream Setup Script"
echo "=============================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if NATS server is installed
check_nats_server() {
    if command -v nats-server &> /dev/null; then
        echo -e "${GREEN}✓${NC} NATS server is installed: $(nats-server -v)"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} NATS server is not installed"
        return 1
    fi
}

# Check if NATS CLI is installed
check_nats_cli() {
    if command -v nats &> /dev/null; then
        echo -e "${GREEN}✓${NC} NATS CLI is installed: $(nats --version)"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} NATS CLI is not installed"
        return 1
    fi
}

# Install NATS using Homebrew (macOS)
install_nats_macos() {
    echo "📦 Installing NATS using Homebrew..."

    if ! command -v brew &> /dev/null; then
        echo -e "${RED}✗${NC} Homebrew is not installed. Please install from https://brew.sh"
        exit 1
    fi

    brew install nats-server nats
    echo -e "${GREEN}✓${NC} NATS installation complete"
}

# Install NATS on Linux
install_nats_linux() {
    echo "📦 Installing NATS for Linux..."

    # Download latest NATS server
    NATS_VERSION=$(curl -s https://api.github.com/repos/nats-io/nats-server/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    echo "Downloading NATS server v${NATS_VERSION}..."

    curl -L https://github.com/nats-io/nats-server/releases/download/v${NATS_VERSION}/nats-server-v${NATS_VERSION}-linux-amd64.tar.gz -o /tmp/nats-server.tar.gz
    tar -xzf /tmp/nats-server.tar.gz -C /tmp

    # Install to /usr/local/bin (requires sudo)
    sudo mv /tmp/nats-server-v${NATS_VERSION}-linux-amd64/nats-server /usr/local/bin/
    rm -rf /tmp/nats-server*

    # Download NATS CLI
    NATSCLI_VERSION=$(curl -s https://api.github.com/repos/nats-io/natscli/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    echo "Downloading NATS CLI v${NATSCLI_VERSION}..."

    curl -L https://github.com/nats-io/natscli/releases/download/v${NATSCLI_VERSION}/nats-${NATSCLI_VERSION}-linux-amd64.zip -o /tmp/nats-cli.zip
    unzip -q /tmp/nats-cli.zip -d /tmp
    sudo mv /tmp/nats-${NATSCLI_VERSION}-linux-amd64/nats /usr/local/bin/
    rm -rf /tmp/nats-*

    echo -e "${GREEN}✓${NC} NATS installation complete"
}

# Start NATS server with JetStream
start_nats_server() {
    echo ""
    echo "🚀 Starting NATS server with JetStream enabled..."

    # Check if NATS is already running
    if pgrep -x "nats-server" > /dev/null; then
        echo -e "${YELLOW}⚠${NC} NATS server is already running"
        echo "   To restart: killall nats-server && $0"
        return 0
    fi

    # Create data directory for JetStream
    JETSTREAM_DIR="$HOME/.nats/jetstream"
    mkdir -p "$JETSTREAM_DIR"
    echo -e "${GREEN}✓${NC} JetStream storage directory: $JETSTREAM_DIR"

    # Start NATS server in background
    echo "Starting NATS server..."
    nats-server -js -sd "$JETSTREAM_DIR" > /tmp/nats-server.log 2>&1 &

    # Wait for server to start
    sleep 2

    # Check if server started successfully
    if pgrep -x "nats-server" > /dev/null; then
        echo -e "${GREEN}✓${NC} NATS server is running (PID: $(pgrep nats-server))"
        echo -e "${GREEN}✓${NC} Log file: /tmp/nats-server.log"
    else
        echo -e "${RED}✗${NC} Failed to start NATS server"
        echo "Check log file: /tmp/nats-server.log"
        tail -n 20 /tmp/nats-server.log
        exit 1
    fi
}

# Verify JetStream is enabled
verify_jetstream() {
    echo ""
    echo "🔍 Verifying JetStream status..."

    # Give server time to fully initialize
    sleep 1

    # Check JetStream status
    if nats server report jetstream 2>/dev/null | grep -q "JetStream"; then
        echo -e "${GREEN}✓${NC} JetStream is enabled and ready"
        nats server report jetstream 2>/dev/null | grep -E "Memory:|Storage:|Streams:|Consumers:" || true
    else
        echo -e "${YELLOW}⚠${NC} Could not verify JetStream status"
    fi
}

# Main execution
main() {
    echo ""
    echo "📋 Checking prerequisites..."

    # Detect OS
    OS="$(uname -s)"
    case "${OS}" in
        Linux*)     OS_TYPE="linux";;
        Darwin*)    OS_TYPE="macos";;
        *)          echo "Unsupported OS: ${OS}"; exit 1;;
    esac

    echo "   Detected OS: $OS_TYPE"

    # Check and install NATS server
    if ! check_nats_server; then
        echo ""
        read -p "Install NATS server? (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [[ "$OS_TYPE" == "macos" ]]; then
                install_nats_macos
            else
                install_nats_linux
            fi
        else
            echo "NATS server is required. Exiting."
            exit 1
        fi
    fi

    # Check and install NATS CLI
    if ! check_nats_cli; then
        echo ""
        read -p "Install NATS CLI? (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [[ "$OS_TYPE" == "macos" ]]; then
                brew install nats
            else
                # CLI was installed with server on Linux
                echo "NATS CLI should be installed. Try: nats --version"
            fi
        fi
    fi

    # Start NATS server
    start_nats_server

    # Verify JetStream
    verify_jetstream

    echo ""
    echo "✅ Setup complete!"
    echo ""
    echo "📝 Quick Commands:"
    echo "   Check server:    nats server info"
    echo "   List streams:    nats stream ls"
    echo "   Stop server:     killall nats-server"
    echo "   View logs:       tail -f /tmp/nats-server.log"
    echo ""
    echo "🎯 Next step: Run ./test.sh to execute the demo"
}

# Run main function
main "$@"