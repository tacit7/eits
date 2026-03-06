#!/bin/bash

# NATS JetStream Cleanup Script
# This script cleans up NATS resources and stops the server

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧹 NATS JetStream Cleanup Script${NC}"
echo "================================="
echo ""

# Function to delete all streams
delete_all_streams() {
    echo "📦 Deleting all streams..."

    # Get list of streams
    streams=$(nats stream ls -n 2>/dev/null || echo "")

    if [ -z "$streams" ]; then
        echo -e "${YELLOW}  No streams found${NC}"
    else
        for stream in $streams; do
            echo -e "  Deleting stream: ${YELLOW}$stream${NC}"
            nats stream delete "$stream" -f 2>/dev/null || echo "  Failed to delete $stream"
        done
        echo -e "${GREEN}✓${NC} All streams deleted"
    fi
}

# Function to delete all consumers
delete_all_consumers() {
    echo ""
    echo "👤 Deleting all consumers..."

    # Get list of streams first
    streams=$(nats stream ls -n 2>/dev/null || echo "")

    if [ -z "$streams" ]; then
        echo -e "${YELLOW}  No streams/consumers found${NC}"
    else
        for stream in $streams; do
            consumers=$(nats consumer ls "$stream" -n 2>/dev/null || echo "")
            if [ ! -z "$consumers" ]; then
                echo -e "  Stream ${YELLOW}$stream${NC} consumers:"
                for consumer in $consumers; do
                    echo -e "    Deleting consumer: $consumer"
                    nats consumer delete "$stream" "$consumer" -f 2>/dev/null || true
                done
            fi
        done
        echo -e "${GREEN}✓${NC} All consumers deleted"
    fi
}

# Function to stop NATS server
stop_nats_server() {
    echo ""
    echo "🛑 Stopping NATS server..."

    if pgrep -x "nats-server" > /dev/null; then
        # Get PID
        PID=$(pgrep nats-server)
        echo -e "  Found NATS server (PID: $PID)"

        # Kill the process
        kill $PID 2>/dev/null || killall nats-server 2>/dev/null || true

        # Wait for process to stop
        sleep 2

        if pgrep -x "nats-server" > /dev/null; then
            echo -e "${YELLOW}  Force stopping NATS server...${NC}"
            kill -9 $PID 2>/dev/null || killall -9 nats-server 2>/dev/null || true
        fi

        echo -e "${GREEN}✓${NC} NATS server stopped"
    else
        echo -e "${YELLOW}  NATS server is not running${NC}"
    fi
}

# Function to clean JetStream data
clean_jetstream_data() {
    echo ""
    echo "🗑️  Cleaning JetStream data..."

    JETSTREAM_DIR="$HOME/.nats/jetstream"

    if [ -d "$JETSTREAM_DIR" ]; then
        read -p "Delete JetStream data directory? This will remove all persisted data. (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$JETSTREAM_DIR"
            echo -e "${GREEN}✓${NC} JetStream data directory deleted"
        else
            echo -e "${YELLOW}  Skipping JetStream data deletion${NC}"
        fi
    else
        echo -e "${YELLOW}  No JetStream data directory found${NC}"
    fi
}

# Function to clean demo artifacts
clean_demo_artifacts() {
    echo ""
    echo "📁 Cleaning demo artifacts..."

    # Change to nats-demo directory
    cd "$(dirname "$0")/.."

    # Remove binaries
    if [ -d "bin" ]; then
        rm -rf bin
        echo -e "${GREEN}✓${NC} Removed compiled binaries"
    fi

    # Remove go.mod and go.sum if they exist
    read -p "Remove Go module files (go.mod, go.sum)? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f go.mod go.sum
        echo -e "${GREEN}✓${NC} Removed Go module files"
    fi

    # Remove log files
    if [ -f "/tmp/nats-server.log" ]; then
        rm -f /tmp/nats-server.log
        echo -e "${GREEN}✓${NC} Removed server log file"
    fi
}

# Function to show cleanup summary
show_summary() {
    echo ""
    echo "📋 Cleanup Summary"
    echo "=================="

    # Check if server is running
    if pgrep -x "nats-server" > /dev/null; then
        echo -e "${RED}✗${NC} NATS server is still running"
    else
        echo -e "${GREEN}✓${NC} NATS server is stopped"
    fi

    # Check for streams
    if command -v nats &> /dev/null && pgrep -x "nats-server" > /dev/null; then
        stream_count=$(nats stream ls -n 2>/dev/null | wc -l | tr -d ' ')
        if [ "$stream_count" -gt 0 ]; then
            echo -e "${YELLOW}⚠${NC} $stream_count stream(s) still exist"
        fi
    fi

    # Check for JetStream data
    if [ -d "$HOME/.nats/jetstream" ]; then
        size=$(du -sh "$HOME/.nats/jetstream" 2>/dev/null | cut -f1)
        echo -e "${YELLOW}⚠${NC} JetStream data exists ($size)"
    else
        echo -e "${GREEN}✓${NC} No JetStream data"
    fi

    echo ""
}

# Main cleanup function
main() {
    echo "This script will clean up NATS JetStream resources."
    echo ""

    # Check what to clean
    echo "Select cleanup mode:"
    echo "  1) Quick cleanup (delete streams/consumers only)"
    echo "  2) Full cleanup (stop server, delete all data)"
    echo "  3) Stop server only"
    echo "  4) Delete data only (server must be stopped)"
    echo "  5) Custom cleanup"
    echo "  0) Cancel"
    echo ""
    read -p "Select option: " mode

    case $mode in
        1)
            # Quick cleanup
            echo ""
            echo -e "${BLUE}Quick Cleanup Mode${NC}"
            echo "=================="
            if pgrep -x "nats-server" > /dev/null; then
                delete_all_consumers
                delete_all_streams
            else
                echo -e "${RED}✗${NC} NATS server is not running"
                echo "  Start server first: ./scripts/setup.sh"
            fi
            ;;
        2)
            # Full cleanup
            echo ""
            echo -e "${BLUE}Full Cleanup Mode${NC}"
            echo "================="
            echo -e "${YELLOW}⚠ This will stop the server and delete all data${NC}"
            read -p "Continue? (y/n) " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if pgrep -x "nats-server" > /dev/null; then
                    delete_all_consumers
                    delete_all_streams
                fi
                stop_nats_server
                clean_jetstream_data
                clean_demo_artifacts
            else
                echo "Cleanup cancelled"
                exit 0
            fi
            ;;
        3)
            # Stop server only
            stop_nats_server
            ;;
        4)
            # Delete data only
            if pgrep -x "nats-server" > /dev/null; then
                echo -e "${RED}✗${NC} NATS server is running"
                echo "  Please stop server first"
                exit 1
            fi
            clean_jetstream_data
            clean_demo_artifacts
            ;;
        5)
            # Custom cleanup
            echo ""
            echo -e "${BLUE}Custom Cleanup${NC}"
            echo "=============="
            echo ""

            if pgrep -x "nats-server" > /dev/null; then
                read -p "Delete all consumers? (y/n) " -n 1 -r
                echo ""
                [[ $REPLY =~ ^[Yy]$ ]] && delete_all_consumers

                read -p "Delete all streams? (y/n) " -n 1 -r
                echo ""
                [[ $REPLY =~ ^[Yy]$ ]] && delete_all_streams

                read -p "Stop NATS server? (y/n) " -n 1 -r
                echo ""
                [[ $REPLY =~ ^[Yy]$ ]] && stop_nats_server
            else
                echo -e "${YELLOW}NATS server is not running${NC}"
            fi

            read -p "Delete JetStream data? (y/n) " -n 1 -r
            echo ""
            [[ $REPLY =~ ^[Yy]$ ]] && clean_jetstream_data

            read -p "Clean demo artifacts? (y/n) " -n 1 -r
            echo ""
            [[ $REPLY =~ ^[Yy]$ ]] && clean_demo_artifacts
            ;;
        0)
            echo "Cleanup cancelled"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            exit 1
            ;;
    esac

    # Show summary
    show_summary

    echo "✅ Cleanup complete!"
    echo ""
    echo "To start fresh:"
    echo "  ./scripts/setup.sh    # Start NATS server"
    echo "  ./scripts/test.sh     # Run demos"
}

# Run main function
main "$@"