#!/bin/bash
#
# Mem0 Server Migration CLI Tool
#
# Usage:
#   ./migrate.sh export                     - Export migration package
#   ./migrate.sh import <file>              - Import migration package
#   ./migrate.sh import <file> --strategy merge  - Merge with existing data
#

set -e

# Configuration
SERVER_URL="${MEM0_SERVER_URL:-http://localhost:8000}"
ADMIN_KEY="${ADMIN_SECRET_KEY:-admin_secret_key_CHANGE_ME}"
API_KEY_HEADER="Authorization: Bearer $ADMIN_KEY"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_server() {
    if ! curl -s -f "$SERVER_URL/health" > /dev/null 2>&1; then
        log_error "Server is not running at $SERVER_URL"
        exit 1
    fi
}

api_call() {
    local method=$1
    local endpoint=$2
    local data=$3

    if [ -n "$data" ]; then
        curl -s -X "$method" \
            -H "Content-Type: application/json" \
            -H "$API_KEY_HEADER" \
            -d "$data" \
            "$SERVER_URL$endpoint"
    else
        curl -s -X "$method" \
            -H "$API_KEY_HEADER" \
            "$SERVER_URL$endpoint"
    fi
}

# Commands
cmd_export() {
    check_server

    log_info "Exporting migration package..."

    local include="${1:-postgres,neo4j,api_keys,history}"
    local payload="{\"include\": [\"postgres\", \"neo4j\", \"api_keys\", \"history\"]}"

    response=$(api_call "POST" "/admin/migrate/export" "$payload")

    if echo "$response" | grep -q "migration_file"; then
        migration_file=$(echo "$response" | grep -o '"migration_file":"[^"]*"' | cut -d'"' -f4)
        checksum=$(echo "$response" | grep -o '"checksum":"[^"]*"' | cut -d'"' -f4)
        size=$(echo "$response" | grep -o '"size_bytes":[0-9]*' | cut -d':' -f2)

        log_info "Migration package exported successfully!"
        echo ""
        echo "Migration Package Details:"
        echo "  File: $migration_file"
        echo "  Checksum: $checksum"
        echo "  Size: $((size / 1024 / 1024)) MB"
        echo ""

        # Try to download the package
        backup_id=$(echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$backup_id" ]; then
            output_file="migration_$(date +%Y%m%d_%H%M%S).tar.gz"
            log_info "Downloading migration package..."

            curl -s -H "$API_KEY_HEADER" \
                "$SERVER_URL/admin/backup/$backup_id/download" \
                -o "$output_file"

            if [ -f "$output_file" ]; then
                log_info "Migration package saved to: $output_file"
                echo ""
                echo "To transfer to another server:"
                echo "  scp $output_file target_server:/path/to/"
                echo ""
                echo "Then on the target server:"
                echo "  ./migrate.sh import /path/to/$output_file"
            fi
        fi
    else
        log_error "Failed to export migration"
        echo "$response"
        exit 1
    fi
}

cmd_import() {
    local migration_file=$1
    local strategy="overwrite"

    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --strategy)
                strategy="$2"
                shift
                ;;
        esac
        shift
    done

    if [ -z "$migration_file" ]; then
        log_error "Migration file is required"
        echo "Usage: $0 import <file> [--strategy overwrite|merge]"
        exit 1
    fi

    if [ ! -f "$migration_file" ]; then
        log_error "File not found: $migration_file"
        exit 1
    fi

    check_server

    file_size=$(stat -f%z "$migration_file" 2>/dev/null || stat -c%s "$migration_file" 2>/dev/null)
    log_info "Importing migration from: $migration_file ($((file_size / 1024 / 1024)) MB)"
    log_info "Strategy: $strategy"

    log_warn "This will import data from the migration package"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Import cancelled"
        exit 0
    fi

    # Upload the migration file to server (via temporary copy to server's backup dir)
    # For now, assume the file is already accessible to the server
    log_step "Uploading migration file..."

    # In a real implementation, this would be a file upload
    # For now, we copy to a known location
    temp_dir="/tmp/mem0_migration_$$"
    mkdir -p "$temp_dir"
    cp "$migration_file" "$temp_dir/"

    # Call import API
    local payload="{\"strategy\": \"$strategy\", \"migration_file\": \"$temp_dir/$migration_file\"}"
    response=$(api_call "POST" "/admin/migrate/import" "$payload")

    rm -rf "$temp_dir"

    if echo "$response" | grep -q "restored"; then
        log_info "Migration imported successfully!"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    else
        log_error "Failed to import migration"
        echo "$response"
        exit 1
    fi
}

cmd_status() {
    check_server

    log_info "Migration Status:"
    echo ""

    log_step "Server: $SERVER_URL"

    # Check backups
    response=$(api_call "GET" "/admin/backup/list" "")
    backup_count=$(echo "$response" | grep -o '"count":[0-9]*' | cut -d':' -f2)
    log_info "Available backups: ${backup_count:-0}"

    # Check recent backups
    if echo "$response" | grep -q "backups"; then
        echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
backups = data.get('backups', [])
if backups:
    print('\nRecent backups:')
    for b in backups[:5]:
        print(f\"  - {b.get('id', 'N/A')}: {b.get('created_at', 'N/A')}\")
" 2>/dev/null
    fi

    echo ""
    log_info "Ready for migration operations"
}

# Main
case "${1:-}" in
    export)
        cmd_export "${2:-}"
        ;;
    import)
        cmd_import "$2" "$3" "$4" "$5"
        ;;
    status)
        cmd_status
        ;;
    help|--help|-h)
        echo "Mem0 Server Migration CLI"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  export                    Export migration package"
        echo "  import <file>             Import migration package"
        echo "  import <file> --strategy merge   Merge with existing data"
        echo "  status                    Show migration status"
        echo ""
        echo "Workflow:"
        echo "  1. On source server: ./migrate.sh export"
        echo "  2. Transfer the migration file to target server"
        echo "  3. On target server: ./migrate.sh import <file>"
        echo ""
        echo "Environment Variables:"
        echo "  MEM0_SERVER_URL           Server URL (default: http://localhost:8000)"
        echo "  ADMIN_SECRET_KEY          Admin API key (default: admin_secret_key_CHANGE_ME)"
        ;;
    *)
        log_error "Unknown command: ${1:-}"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac