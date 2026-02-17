#!/bin/bash

# Test script to verify Nerd Font toggle functionality

echo "=== Nerd Font Toggle Test ==="
echo ""

echo "Building Eye in the Sky TUI..."
go build -o bin/eye-ui ./cmd/eye-ui
if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi
echo "Build successful!"
echo ""

echo "Test 1: Default mode (Nerd Fonts enabled)"
echo "Expected: Unicode glyphs (●/◉/○/✓/✗) and box-drawing chars (─/│)"
echo "Command: ./bin/eye-ui"
echo "Press Ctrl+C to exit after viewing"
echo ""
read -p "Press Enter to start test 1..."
./bin/eye-ui
echo ""

echo "Test 2: Plain ASCII mode"
echo "Expected: ASCII chars (*/@ /o/+/x) and plain borders (-/|)"
echo "Command: NERD_FONTS=0 ./bin/eye-ui"
echo "Press Ctrl+C to exit after viewing"
echo ""
read -p "Press Enter to start test 2..."
NERD_FONTS=0 ./bin/eye-ui
echo ""

echo "=== Tests Complete ==="
echo ""
echo "Manual verification checklist:"
echo "  [ ] Status icons changed between modes"
echo "  [ ] Table borders changed between modes"
echo "  [ ] Subagent pipes (│ vs |) changed between modes"
echo ""
