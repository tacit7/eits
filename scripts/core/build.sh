#!/bin/bash

set -e

echo "🔨 Building Eye in the Sky Core..."

mkdir -p bin

echo "📦 Building MCP server binary..."
go build -tags fts5 -o bin/eits-mcp-server ./cmd/server

# CLI and TUI disabled for now (schema changes in progress)
# echo "📦 Building CLI tool binary..."
# go build -tags fts5 -o bin/eits-cli ./cmd/eits-cli
# echo "📦 Building TUI dashboard binary..."
# go build -tags fts5 -o bin/eits-tui ./cmd/eye-ui

echo "✅ Build complete!"
echo ""
echo "Binaries available:"
echo "  🔧 MCP Server: ./bin/eits-mcp-server"
echo ""
echo "Usage:"
echo "  MCP Server: ./bin/eits-mcp-server"