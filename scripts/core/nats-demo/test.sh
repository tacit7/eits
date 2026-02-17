#!/bin/bash

# NATS JetStream Test Script
# This script runs the NATS demo and provides interactive testing options

set -e

# Change to the nats-demo directory
cd "$(dirname "$0")/.."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 NATS JetStream Test Suite${NC}"
echo "=============================="

# Check if NATS server is running
check_nats_server() {
    if pgrep -x "nats-server" > /dev/null; then
        echo -e "${GREEN}✓${NC} NATS server is running"
        return 0
    else
        echo -e "${RED}✗${NC} NATS server is not running"
        echo "   Please run: ./scripts/setup.sh"
        exit 1
    fi
}

# Check Go dependencies
check_go_deps() {
    if [ ! -f "go.mod" ]; then
        echo "Initializing Go module..."
        go mod init nats-demo
    fi

    if ! grep -q "github.com/nats-io/nats.go" go.mod 2>/dev/null; then
        echo "Installing NATS Go client..."
        go get github.com/nats-io/nats.go
    fi

    echo -e "${GREEN}✓${NC} Go dependencies ready"
}

# Build the demo programs
build_demos() {
    echo ""
    echo "🔨 Building demo programs..."

    # Build main demo
    if go build -o bin/main main.go; then
        echo -e "${GREEN}✓${NC} Built main demo"
    else
        echo -e "${RED}✗${NC} Failed to build main demo"
        exit 1
    fi

    # Build publisher
    if go build -o bin/publisher publisher.go; then
        echo -e "${GREEN}✓${NC} Built publisher"
    else
        echo -e "${RED}✗${NC} Failed to build publisher"
    fi

    # Build consumer
    if go build -o bin/consumer consumer.go; then
        echo -e "${GREEN}✓${NC} Built consumer"
    else
        echo -e "${RED}✗${NC} Failed to build consumer"
    fi

    # Build multi-consumer
    if go build -o bin/multi_consumer multi_consumer.go 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Built multi-consumer"
    fi
}

# Run full demo
run_full_demo() {
    echo ""
    echo -e "${BLUE}📺 Running Full Demo${NC}"
    echo "===================="
    go run main.go
}

# Run publisher demo
run_publisher() {
    echo ""
    echo -e "${BLUE}📤 Running Publisher Demo${NC}"
    echo "========================"
    go run publisher.go
}

# Run consumer demo
run_consumer() {
    echo ""
    echo -e "${BLUE}📥 Running Consumer Demo${NC}"
    echo "======================="
    go run consumer.go
}

# Run multi-consumer demo
run_multi_consumer() {
    echo ""
    echo -e "${BLUE}👥 Running Multi-Consumer Demo${NC}"
    echo "============================="
    if [ -f "multi_consumer.go" ]; then
        go run multi_consumer.go
    else
        echo -e "${YELLOW}⚠${NC} multi_consumer.go not found"
    fi
}

# Stream management commands
stream_management() {
    echo ""
    echo -e "${BLUE}🔧 Stream Management${NC}"
    echo "==================="
    echo ""
    echo "1) List streams"
    echo "2) Create EVENTS stream"
    echo "3) View EVENTS stream info"
    echo "4) View messages in EVENTS stream"
    echo "5) Delete EVENTS stream"
    echo "6) Back to main menu"
    echo ""
    read -p "Select option: " stream_choice

    case $stream_choice in
        1)
            echo -e "\n${BLUE}Listing streams:${NC}"
            nats stream ls
            ;;
        2)
            echo -e "\n${BLUE}Creating EVENTS stream:${NC}"
            nats stream add EVENTS \
                --subjects="events.*" \
                --storage=file \
                --retention=limits \
                --max-msgs=10000 \
                --max-age=24h \
                --max-bytes=1MB \
                --replicas=1 \
                --no-ack
            ;;
        3)
            echo -e "\n${BLUE}EVENTS stream info:${NC}"
            nats stream info EVENTS
            ;;
        4)
            echo -e "\n${BLUE}Messages in EVENTS stream:${NC}"
            nats stream view EVENTS
            ;;
        5)
            echo -e "\n${YELLOW}⚠ Deleting EVENTS stream${NC}"
            read -p "Are you sure? (y/n) " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                nats stream delete EVENTS -f
            fi
            ;;
        6)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

# Consumer management commands
consumer_management() {
    echo ""
    echo -e "${BLUE}👤 Consumer Management${NC}"
    echo "====================="
    echo ""
    echo "1) List consumers for EVENTS stream"
    echo "2) Create new consumer"
    echo "3) Get next message from consumer"
    echo "4) Delete consumer"
    echo "5) Back to main menu"
    echo ""
    read -p "Select option: " consumer_choice

    case $consumer_choice in
        1)
            echo -e "\n${BLUE}Listing consumers:${NC}"
            nats consumer ls EVENTS
            ;;
        2)
            echo -e "\n${BLUE}Creating consumer:${NC}"
            read -p "Consumer name: " consumer_name
            nats consumer add EVENTS "$consumer_name" \
                --filter="events.*" \
                --deliver=all \
                --ack=explicit \
                --replay=instant \
                --no-pull
            ;;
        3)
            echo -e "\n${BLUE}Getting next message:${NC}"
            read -p "Consumer name: " consumer_name
            nats consumer next EVENTS "$consumer_name"
            ;;
        4)
            echo -e "\n${YELLOW}⚠ Deleting consumer${NC}"
            read -p "Consumer name: " consumer_name
            nats consumer delete EVENTS "$consumer_name" -f
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

# Monitoring commands
monitoring() {
    echo ""
    echo -e "${BLUE}📊 Monitoring${NC}"
    echo "============="
    echo ""
    echo "1) Server info"
    echo "2) JetStream report"
    echo "3) Stream report"
    echo "4) Connection report"
    echo "5) Real-time stream monitoring"
    echo "6) Back to main menu"
    echo ""
    read -p "Select option: " mon_choice

    case $mon_choice in
        1)
            echo -e "\n${BLUE}Server info:${NC}"
            nats server info
            ;;
        2)
            echo -e "\n${BLUE}JetStream report:${NC}"
            nats server report jetstream
            ;;
        3)
            echo -e "\n${BLUE}Stream report:${NC}"
            nats stream report
            ;;
        4)
            echo -e "\n${BLUE}Connection report:${NC}"
            nats server report connections
            ;;
        5)
            echo -e "\n${BLUE}Real-time monitoring (Ctrl+C to stop):${NC}"
            nats stream view EVENTS --follow
            ;;
        6)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

# Main menu
show_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}🎯 NATS Demo Test Menu${NC}"
        echo "====================="
        echo ""
        echo "Demo Programs:"
        echo "  1) Run full demo (main.go)"
        echo "  2) Run publisher demo"
        echo "  3) Run consumer demo"
        echo "  4) Run multi-consumer demo"
        echo ""
        echo "Management:"
        echo "  5) Stream management"
        echo "  6) Consumer management"
        echo "  7) Monitoring"
        echo ""
        echo "Quick Tests:"
        echo "  8) Publish test message"
        echo "  9) Create and view stream"
        echo ""
        echo "  0) Exit"
        echo ""
        read -p "Select option: " choice

        case $choice in
            1)
                run_full_demo
                ;;
            2)
                run_publisher
                ;;
            3)
                run_consumer
                ;;
            4)
                run_multi_consumer
                ;;
            5)
                stream_management
                ;;
            6)
                consumer_management
                ;;
            7)
                monitoring
                ;;
            8)
                echo -e "\n${BLUE}Publishing test message:${NC}"
                echo '{"test":"message","time":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' | nats pub events.test
                ;;
            9)
                echo -e "\n${BLUE}Creating and viewing stream:${NC}"
                nats stream add TEST --subjects="test.*" --storage=memory --retention=limits --replicas=1 --no-ack 2>/dev/null || true
                echo '{"msg":"Hello NATS!"}' | nats pub test.hello
                nats stream view TEST
                ;;
            0)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

# Main execution
main() {
    echo ""
    check_nats_server
    check_go_deps
    build_demos

    # Run mode selection
    if [ "$1" == "--auto" ]; then
        echo ""
        echo "🤖 Running in automatic mode..."
        run_full_demo
        echo ""
        echo "✅ Test complete!"
    else
        show_menu
    fi
}

# Run main function
main "$@"