#!/bin/bash
# Docker Enforce Pre-Command Hook
# Intercepts package manager commands and enforces Docker-first policy
#
# Usage: Called automatically by Claude Code hooks system
# Manual: ./pre-command.sh "npm install express"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_ENFORCEMENT="block"
CONFIG_FILE=".claude/docker-config.json"

# Patterns to intercept
INTERCEPT_PATTERNS=(
    "^npm (install|ci|run|test|exec|start|build)"
    "^npx "
    "^yarn (add|install|run|start|build)"
    "^pnpm (add|install|run|start|build)"
    "^node "
    "^tsx "
    "^bun (run|install|add)"
)

# Load configuration from project
load_config() {
    local config_path="${PWD}/${CONFIG_FILE}"

    if [[ -f "$config_path" ]]; then
        # Parse JSON config (basic parsing without jq dependency)
        CONTAINER_NAME=$(grep -o '"containerName"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_path" 2>/dev/null | cut -d'"' -f4 || echo "")
        ENFORCEMENT=$(grep -o '"enforcement"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_path" 2>/dev/null | cut -d'"' -f4 || echo "$DEFAULT_ENFORCEMENT")

        # Check allowed commands
        if grep -q "\"allowedHostCommands\"" "$config_path" 2>/dev/null; then
            ALLOWED_COMMANDS=$(grep -o '"allowedHostCommands"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$config_path" 2>/dev/null || echo "[]")
        else
            ALLOWED_COMMANDS="[]"
        fi
    else
        CONTAINER_NAME=""
        ENFORCEMENT="$DEFAULT_ENFORCEMENT"
        ALLOWED_COMMANDS="[]"
    fi
}

# Check if command matches intercept patterns
should_intercept() {
    local cmd="$1"

    for pattern in "${INTERCEPT_PATTERNS[@]}"; do
        if echo "$cmd" | grep -qE "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Check if command is in allowed list
is_allowed() {
    local cmd="$1"

    # Check if command is in allowed list
    if echo "$ALLOWED_COMMANDS" | grep -q "\"$cmd\""; then
        return 0
    fi

    # Check partial matches (e.g., "npm run lint" matches "npm run lint:fix")
    while IFS= read -r allowed; do
        allowed=$(echo "$allowed" | tr -d '",[] ')
        if [[ -n "$allowed" ]] && [[ "$cmd" == "$allowed"* ]]; then
            return 0
        fi
    done < <(echo "$ALLOWED_COMMANDS" | tr ',' '\n')

    return 1
}

# Check if Docker container is running
check_container() {
    local container="$1"

    if [[ -z "$container" ]]; then
        echo -e "${YELLOW}WARNING: No containerName configured in ${CONFIG_FILE}${NC}" >&2
        return 1
    fi

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
        return 0
    else
        return 1
    fi
}

# Display block message
show_block_message() {
    local cmd="$1"
    local container="$2"

    echo -e "${RED}ERROR: Docker-first policy violation detected!${NC}" >&2
    echo "" >&2
    echo -e "Command: ${BLUE}$cmd${NC}" >&2
    echo -e "Reason:  Package manager commands must run inside Docker" >&2
    echo "" >&2

    if [[ -n "$container" ]]; then
        echo -e "Suggested command:" >&2
        echo -e "  ${GREEN}docker exec $container $cmd${NC}" >&2
    else
        echo -e "Configure containerName in ${CONFIG_FILE} first" >&2
    fi

    echo "" >&2
    echo -e "To allow this command on host, add to ${CONFIG_FILE}:" >&2
    echo -e "  \"allowedHostCommands\": [\"$cmd\"]" >&2
}

# Display warning message
show_warning() {
    local cmd="$1"
    local container="$2"

    echo -e "${YELLOW}WARNING: Running package manager on host instead of Docker${NC}" >&2
    if [[ -n "$container" ]]; then
        echo -e "Recommended: ${GREEN}docker exec $container $cmd${NC}" >&2
    fi
    echo -e "Proceeding anyway..." >&2
}

# Transform command to docker exec
transform_command() {
    local cmd="$1"
    local container="$2"

    if [[ -z "$container" ]]; then
        echo -e "${RED}ERROR: Cannot transform - no containerName configured${NC}" >&2
        exit 1
    fi

    if ! check_container "$container"; then
        echo -e "${RED}ERROR: Container '$container' is not running${NC}" >&2
        echo -e "Start it with: ${GREEN}docker compose up -d${NC}" >&2
        exit 1
    fi

    echo -e "${BLUE}Transforming to:${NC} docker exec $container $cmd" >&2
    exec docker exec "$container" $cmd
}

# Main enforcement logic
enforce() {
    local cmd="$1"

    # Load project configuration
    load_config

    # Check if enforcement is disabled
    if [[ "$ENFORCEMENT" == "disabled" ]]; then
        return 0
    fi

    # Check if command should be intercepted
    if ! should_intercept "$cmd"; then
        return 0
    fi

    # Check if command is explicitly allowed
    if is_allowed "$cmd"; then
        return 0
    fi

    # Apply enforcement policy
    case "$ENFORCEMENT" in
        block)
            show_block_message "$cmd" "$CONTAINER_NAME"
            exit 1
            ;;
        warn)
            show_warning "$cmd" "$CONTAINER_NAME"
            return 0
            ;;
        transform)
            transform_command "$cmd" "$CONTAINER_NAME"
            ;;
        *)
            echo -e "${YELLOW}Unknown enforcement mode: $ENFORCEMENT${NC}" >&2
            return 0
            ;;
    esac
}

# CLI interface
main() {
    local action="${1:-}"
    local cmd="${2:-}"

    case "$action" in
        check)
            if [[ -z "$cmd" ]]; then
                echo "Usage: $0 check <command>" >&2
                exit 1
            fi
            load_config
            if should_intercept "$cmd" && ! is_allowed "$cmd"; then
                echo "WOULD_BLOCK: $cmd"
                exit 1
            else
                echo "ALLOWED: $cmd"
                exit 0
            fi
            ;;
        validate)
            load_config
            if [[ -z "$CONTAINER_NAME" ]]; then
                echo "ERROR: No container configured"
                exit 1
            fi
            if check_container "$CONTAINER_NAME"; then
                echo "OK: Container '$CONTAINER_NAME' is running"
                exit 0
            else
                echo "ERROR: Container '$CONTAINER_NAME' is not running"
                exit 1
            fi
            ;;
        transform)
            if [[ -z "$cmd" ]]; then
                echo "Usage: $0 transform <command>" >&2
                exit 1
            fi
            load_config
            if [[ -n "$CONTAINER_NAME" ]]; then
                echo "docker exec $CONTAINER_NAME $cmd"
            else
                echo "ERROR: No container configured" >&2
                exit 1
            fi
            ;;
        enforce|"")
            if [[ -z "$cmd" ]] && [[ -n "$action" ]] && [[ "$action" != "enforce" ]]; then
                cmd="$action"
            fi
            if [[ -z "$cmd" ]]; then
                echo "Usage: $0 [enforce] <command>" >&2
                exit 1
            fi
            enforce "$cmd"
            ;;
        --help|-h)
            echo "Docker Enforce - Docker-first policy enforcement"
            echo ""
            echo "Usage: $0 <action> [command]"
            echo ""
            echo "Actions:"
            echo "  check <cmd>      Check if command would be blocked"
            echo "  validate         Validate container is running"
            echo "  transform <cmd>  Get docker exec version of command"
            echo "  enforce <cmd>    Apply enforcement policy (default)"
            echo ""
            echo "Configuration: .claude/docker-config.json"
            ;;
        *)
            # Assume it's a command to enforce
            enforce "$action $cmd"
            ;;
    esac
}

main "$@"
