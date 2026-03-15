#!/bin/bash
#
# Mem0 Server Backup/Restore CLI Tool
#
# Usage:
#   ./backup.sh create                      - Create a new backup
#   ./backup.sh list                        - List all backups
#   ./backup.sh verify <backup_id>          - Verify backup integrity
#   ./backup.sh restore <backup_id>         - Restore from backup
#   ./backup.sh restore <backup_id> --dry-run  - Preview restore
#   ./backup.sh delete <backup_id>          - Delete a backup
#   ./backup.sh download <backup_id>        - Download backup as tarball
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
NC='\033[0m' # No Color

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
cmd_create() {
    check_server

    log_info "Creating backup..."

    local backup_type="${1:-full}"
    local include="${2:-postgres,neo4j,api_keys,history}"

    local payload="{\"backup_type\": \"$backup_type\", \"include\": [\"postgres\", \"neo4j\", \"api_keys\", \"history\"]}"

    response=$(api_call "POST" "/admin/backup" "$payload")

    if echo "$response" | grep -q "id"; then
        backup_id=$(echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        log_info "Backup created successfully: $backup_id"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    else
        log_error "Failed to create backup"
        echo "$response"
        exit 1
    fi
}

cmd_list() {
    check_server

    log_info "Listing backups..."

    response=$(api_call "GET" "/admin/backup/list" "")

    if echo "$response" | grep -q "backups"; then
        echo "$response" | python3 -m json.tool
    else
        log_error "Failed to list backups"
        echo "$response"
        exit 1
    fi
}

cmd_verify() {
    local backup_id=$1

    if [ -z "$backup_id" ]; then
        log_error "Backup ID is required"
        echo "Usage: $0 verify <backup_id>"
        exit 1
    fi

    check_server
    log_info "Verifying backup: $backup_id"

    response=$(api_call "GET" "/admin/backup/$backup_id/verify" "")

    if echo "$response" | grep -q "valid"; then
        echo "$response" | python3 -m json.tool

        if echo "$response" | grep -q '"valid":true'; then
            log_info "Backup is valid!"
        else
            log_error "Backup is invalid!"
            exit 1
        fi
    else
        log_error "Failed to verify backup"
        echo "$response"
        exit 1
    fi
}

cmd_restore() {
    local backup_id=$1
    local dry_run=""
    local strategy="overwrite"

    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run="true"
                ;;
            --strategy)
                strategy="$2"
                shift
                ;;
        esac
        shift
    done

    if [ -z "$backup_id" ]; then
        log_error "Backup ID is required"
        echo "Usage: $0 restore <backup_id> [--dry-run] [--strategy overwrite|merge]"
        exit 1
    fi

    check_server

    if [ "$dry_run" = "true" ]; then
        log_warn "Running in DRY-RUN mode - no data will be changed"
    else
        log_warn "This will restore data from backup: $backup_id"
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Restore cancelled"
            exit 0
        fi
    fi

    log_info "Restoring from backup: $backup_id"

    local payload="{\"strategy\": \"$strategy\", \"dry_run\": $dry_run}"
    response=$(api_call "POST" "/admin/backup/$backup_id/restore" "$payload")

    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"

    if [ "$dry_run" != "true" ]; then
        log_info "Restore completed"
    fi
}

cmd_delete() {
    local backup_id=$1

    if [ -z "$backup_id" ]; then
        log_error "Backup ID is required"
        echo "Usage: $0 delete <backup_id>"
        exit 1
    fi

    check_server

    log_warn "This will permanently delete backup: $backup_id"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Delete cancelled"
        exit 0
    fi

    log_info "Deleting backup: $backup_id"

    response=$(api_call "DELETE" "/admin/backup/$backup_id" "")

    if echo "$response" | grep -q "deleted"; then
        log_info "Backup deleted successfully"
    else
        log_error "Failed to delete backup"
        echo "$response"
        exit 1
    fi
}

cmd_download() {
    local backup_id=$1

    if [ -z "$backup_id" ]; then
        log_error "Backup ID is required"
        echo "Usage: $0 download <backup_id>"
        exit 1
    fi

    check_server
    log_info "Downloading backup: $backup_id"

    output_file="backup_${backup_id}.tar.gz"

    curl -s -H "$API_KEY_HEADER" \
        "$SERVER_URL/admin/backup/$backup_id/download" \
        -o "$output_file"

    if [ -f "$output_file" ]; then
        log_info "Backup downloaded to: $output_file"
        ls -lh "$output_file"
    else
        log_error "Failed to download backup"
        exit 1
    fi
}

# Main
case "${1:-}" in
    create)
        cmd_create "${2:-}" "${3:-}"
        ;;
    list)
        cmd_list
        ;;
    verify)
        cmd_verify "$2"
        ;;
    restore)
        cmd_restore "$2" "$3" "$4" "$5"
        ;;
    delete)
        cmd_delete "$2"
        ;;
    download)
        cmd_download "$2"
        ;;
    help|--help|-h)
        echo "Mem0 Server Backup CLI"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  create [type]             Create a new backup (default: full)"
        echo "  list                      List all backups"
        echo "  verify <backup_id>        Verify backup integrity"
        echo "  restore <backup_id>       Restore from backup"
        echo "  restore <backup_id> --dry-run    Preview restore (no changes)"
        echo "  delete <backup_id>        Delete a backup"
        echo "  download <backup_id>      Download backup as tarball"
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