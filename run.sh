#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SANDBOX_DIR="$HOME/.claude-sandbox"
mkdir -p "$SANDBOX_DIR"
AUTHORIZED_KEYS_FILE="$SANDBOX_DIR/authorized_keys"

VALID_ENVIRONMENTS=()
for dir in "$SCRIPT_DIR/environments"/*/; do
    [ -d "$dir" ] && VALID_ENVIRONMENTS+=("$(basename "$dir")")
done

# --- Defaults ---

WORKDIR="$(pwd)"
SSH_PORT=0
ENVIRONMENT=""
ACTION=""
SANDBOX_DEV=false

# --- Argument parsing ---

while [ $# -gt 0 ]; do
    case "$1" in
        --start)       ACTION="start"; shift ;;
        --rebuild)     ACTION="rebuild"; shift ;;
        --restart)     ACTION="restart"; shift ;;
        --connect)     ACTION="connect"; shift ;;
        --copy-ssh-keys) ACTION="copy-ssh-keys"; shift ;;
        --sandbox-dev) SANDBOX_DEV=true; shift ;;
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --workdir)     WORKDIR="$2"; shift 2 ;;
        --ssh-port)    SSH_PORT="$2"; shift 2 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Default action
[ -z "$ACTION" ] && ACTION="start"

# --- Color helpers ---

yellow() { echo -e "\033[33m$*\033[0m"; }
red()    { echo -e "\033[31m$*\033[0m"; }

# --- Functions ---

get_instance_name() {
    local env_name="$1"
    local normalized
    normalized="$(echo "$WORKDIR" | sed 's:/*$::' | tr '[:upper:]' '[:lower:]')"
    local workdir_name
    workdir_name="$(basename "$normalized")"
    local hash
    hash="$(echo -n "${normalized}:${env_name}" | sha256sum | cut -c1-8)"
    echo "claude-${workdir_name}-${env_name}-${hash}"
}

get_ssh_port() {
    local instance_name="$1"
    if [ "$SSH_PORT" -ne 0 ]; then
        echo "$SSH_PORT"
        return
    fi
    local port_hash="${instance_name##*-}"
    local hex4="${port_hash:0:4}"
    echo $(( 22001 + 16#$hex4 % 999 ))
}

resolve_environment() {
    local matched=()
    for env_ in "${VALID_ENVIRONMENTS[@]}"; do
        local candidate="$SANDBOX_DIR/$(get_instance_name "$env_")"
        if [ -d "$candidate" ]; then
            matched+=("$env_")
        fi
    done

    if [ ${#matched[@]} -eq 1 ]; then
        ENVIRONMENT="${matched[0]}"
        echo "Using environment: $ENVIRONMENT (inferred from previous use)"
    elif [ ${#matched[@]} -gt 1 ]; then
        echo ""
        echo "Multiple environments found for this directory: ${matched[*]}"
        echo "Please specify one with --environment <name>"
        echo ""
        exit 1
    fi
}

show_usage() {
    echo ""
    echo "Usage:"
    echo "  claude-sandbox [--start] --environment <name> [--workdir <path>]"
    echo "                 [--ssh-port <port>]"
    echo "  claude-sandbox --restart --environment <name> [--workdir <path>]"
    echo "                 [--ssh-port <port>]"
    echo "  claude-sandbox --rebuild --environment <name> [--workdir <path>]"
    echo "                 [--ssh-port <port>]"
    echo "  claude-sandbox --connect --environment <name>"
    echo "  claude-sandbox --copy-ssh-keys"
    echo ""
    echo "Environments: ${VALID_ENVIRONMENTS[*]}"
    echo ""
    echo "Commands (default: --start):"
    echo "  --start            Start the sandbox (build if necessary)"
    echo "  --restart          Stop and restart the container"
    echo "  --rebuild          Force rebuild the container image"
    echo "  --connect          SSH into the container"
    echo "  --copy-ssh-keys    Populate ~/.claude-sandbox/authorized_keys from ~/.ssh"
    echo ""
    echo "Options:"
    echo "  --environment  Runtime environment (inferred if only one exists for directory)"
    echo "  --workdir      Workspace directory (default: current directory)"
    echo "  --ssh-port     SSH port (default: auto-assigned)"
    echo "  --sandbox-dev  Bind-mount runtime scripts for live iteration"
    echo ""
}

copy_ssh_keys() {
    # Remove authorized_keys if it's a directory (Docker creates one when mounting a missing file)
    if [ -d "$AUTHORIZED_KEYS_FILE" ]; then
        rm -rf "$AUTHORIZED_KEYS_FILE"
    fi

    local user_ssh_dir="$HOME/.ssh"
    local keys=()

    # Fetch all public keys
    if compgen -G "$user_ssh_dir/*.pub" > /dev/null 2>&1; then
        while IFS= read -r line; do
            keys+=("$line")
        done < <(cat "$user_ssh_dir"/*.pub)
    fi

    # Fetch authorized_keys
    if [ -f "$user_ssh_dir/authorized_keys" ]; then
        while IFS= read -r line; do
            keys+=("$line")
        done < "$user_ssh_dir/authorized_keys"
    fi

    if [ ${#keys[@]} -eq 0 ]; then
        echo "No public keys found in $user_ssh_dir" >&2
        return 1
    fi

    # Preserve the picker's key if it exists in the current file
    if [ -f "$AUTHORIZED_KEYS_FILE" ]; then
        while IFS= read -r line; do
            if [[ "$line" == *claude-sandbox-picker ]]; then
                keys+=("$line")
            fi
        done < "$AUTHORIZED_KEYS_FILE"
    fi

    # Write unique keys
    printf '%s\n' "${keys[@]}" | sort -u > "$AUTHORIZED_KEYS_FILE"

    local count
    count="$(wc -l < "$AUTHORIZED_KEYS_FILE")"
    echo ""
    echo "Wrote $count key(s) to $AUTHORIZED_KEYS_FILE"
    echo ""

    if ! compgen -G "$user_ssh_dir/*.pub" > /dev/null 2>&1; then
        yellow "WARNING: No SSH key pair found on this machine."
        yellow "  You will not be able to connect from this machine without one."
        yellow "  Generate a key pair with: ssh-keygen -t ed25519"
        echo ""
    fi

    return 0
}

do_connect() {
    local instance_name
    instance_name="$(get_instance_name "$ENVIRONMENT")"
    local port
    port="$(get_ssh_port "$instance_name")"
    ssh -o StrictHostKeyChecking=no -p "$port" claude@localhost
}

stop_picker() {
    local picker_compose="$SCRIPT_DIR/picker/compose.yml"
    export SANDBOX_AUTHORIZED_KEYS="$AUTHORIZED_KEYS_FILE"
    docker compose -f "$picker_compose" -p claude-picker down 2>/dev/null || true
}

ensure_picker() {
    local picker_compose_args=("-f" "$SCRIPT_DIR/picker/compose.yml")
    if [ "$SANDBOX_DEV" = true ]; then
        picker_compose_args+=("-f" "$SCRIPT_DIR/picker/dev.compose.yml")
    fi

    # Ensure authorized keys file exists
    if [ ! -f "$AUTHORIZED_KEYS_FILE" ]; then
        touch "$AUTHORIZED_KEYS_FILE"
    fi

    export SANDBOX_AUTHORIZED_KEYS="$AUTHORIZED_KEYS_FILE"
    export HOST_HOSTNAME="$(hostname)"

    local port="${PICKER_SSH_PORT:-22000}"

    local running
    running="$(docker compose "${picker_compose_args[@]}" -p claude-picker ps --status running --format '{{.Name}}' 2>/dev/null || true)"
    if ! echo "$running" | grep -q "picker"; then
        docker compose "${picker_compose_args[@]}" -p claude-picker up -d --build
        ssh-keygen -R "[localhost]:$port" 2>/dev/null || true
    fi
}

test_sandbox_running() {
    local compose_args=("$@")
    local running
    running="$(docker compose "${compose_args[@]}" ps --status running --format '{{.Name}}' 2>/dev/null || true)"
    echo "$running" | grep -q "$ENVIRONMENT"
}

init_compose_env() {
    local instance_name="$1"
    local port="$2"

    export COMPOSE_PROJECT_NAME="$instance_name"
    export SANDBOX_ROOT="$SCRIPT_DIR"
    export SANDBOX_ENV="$ENVIRONMENT"
    export SANDBOX_WORKSPACE="$(basename "$WORKDIR")"
    export DEV_DIR="$WORKDIR"
    export HOME="$HOME"
    export CLAUDE_SSH_PORT="$port"

    # Derive unique /28 subnet from port
    local base=$(( port * 16 ))
    export SUBNET="10.$(( (base / 65536) % 256 )).$(( (base / 256) % 256 )).$(( base % 256 ))/28"
    local gateway_base=$(( base + 2 ))
    export GATEWAY_IP="10.$(( (gateway_base / 65536) % 256 )).$(( (gateway_base / 256) % 256 )).$(( gateway_base % 256 ))"
    export HOST_PLUGINS_DIR="$HOME/.claude/plugins"

    # Per-instance state directory
    export CLAUDE_STATE_DIR="$SANDBOX_DIR/$instance_name"
    mkdir -p "$CLAUDE_STATE_DIR"

    # SSH authorized keys file
    export SANDBOX_AUTHORIZED_KEYS="$AUTHORIZED_KEYS_FILE"

    if [ -d "$SANDBOX_AUTHORIZED_KEYS" ]; then
        rm -rf "$SANDBOX_AUTHORIZED_KEYS"
    fi

    if [ ! -f "$SANDBOX_AUTHORIZED_KEYS" ]; then
        touch "$SANDBOX_AUTHORIZED_KEYS"
    fi
}

get_compose_args() {
    local args=("-f" "$SCRIPT_DIR/docker-compose.yml" "-f" "$SCRIPT_DIR/environments/$ENVIRONMENT/compose.yml")
    if [ "$SANDBOX_DEV" = true ]; then
        args+=("-f" "$SCRIPT_DIR/dev.compose.yml")
    fi
    echo "${args[@]}"
}

init_state_dir() {
    # Ensure .claude.json exists in state dir
    local claude_json="$CLAUDE_STATE_DIR/.claude.json"
    if [ ! -f "$claude_json" ]; then
        echo '{}' > "$claude_json"
    fi

    # Fix ownership so container's claude user (UID 1000) can read/write
    docker run --rm -v "$CLAUDE_STATE_DIR:/state" alpine chown -R 1000:1000 /state

    # Remove stale SSH host key for this port
    ssh-keygen -R "[localhost]:$CLAUDE_SSH_PORT" 2>/dev/null || true
}

sandbox_build() {
    local compose_args
    read -ra compose_args <<< "$(get_compose_args)"
    docker compose "${compose_args[@]}" build
    init_state_dir
}

sandbox_up() {
    local compose_args
    read -ra compose_args <<< "$(get_compose_args)"
    ensure_picker
    docker compose "${compose_args[@]}" up -d
    wait_for_sshd "$1"
    show_connection_info "$2" "$1"
}

wait_for_sshd() {
    local port="$1"
    local retries=0

    while [ $retries -lt 15 ]; do
        local result
        result="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=1 -p "$port" claude@localhost echo ok 2>&1 || true)"
        if [ "$result" = "ok" ]; then
            break
        fi
        sleep 0.5
        retries=$(( retries + 1 ))
    done
}

show_connection_info() {
    local instance_name="$1"
    local port="$2"
    local picker_port="${PICKER_SSH_PORT:-22000}"

    echo ""
    echo "[$instance_name] workspace: $WORKDIR ($ENVIRONMENT)"
    echo ""
    echo "  Connect directly to the sandbox:"
    echo "      ssh -p $port claude@localhost"
    echo ""
    echo "  Connect through the sandbox picker:"
    echo "      ssh -p $picker_port claude@localhost"
    echo ""

    show_ssh_warnings
}

show_ssh_warnings() {
    local has_keys=false
    if [ -f "$SANDBOX_AUTHORIZED_KEYS" ] && [ -s "$SANDBOX_AUTHORIZED_KEYS" ]; then
        has_keys=true
    fi

    if [ "$has_keys" = false ]; then
        yellow "WARNING: No SSH keys configured. You will not be able to connect."
        echo ""
        yellow "  Add public keys to: $AUTHORIZED_KEYS_FILE"
        yellow "  Or re-run with --copy-ssh-keys to import from ~/.ssh"
        echo ""
    fi

    if ! compgen -G "$HOME/.ssh/*.pub" > /dev/null 2>&1; then
        yellow "WARNING: No SSH key pair found on this machine."
        yellow "  You will not be able to connect from this machine without one."
        yellow "  Generate a key pair with: ssh-keygen -t ed25519"
        echo ""
    fi
}

# --- Validation ---

# Check exclusive flags
if [ "$SANDBOX_DEV" = true ] && [[ "$ACTION" =~ ^(connect|copy-ssh-keys)$ ]]; then
    echo "--sandbox-dev can only be used with --start, --rebuild, or --restart" >&2
    exit 1
fi

# Handle copy-ssh-keys (no environment needed)
if [ "$ACTION" = "copy-ssh-keys" ]; then
    copy_ssh_keys
    exit $?
fi

# Resolve environment if not specified
if [ -z "$ENVIRONMENT" ]; then
    resolve_environment
fi

if [ -z "$ENVIRONMENT" ]; then
    show_usage
    exit 0
fi

# Validate environment
valid=false
for env_ in "${VALID_ENVIRONMENTS[@]}"; do
    if [ "$env_" = "$ENVIRONMENT" ]; then
        valid=true
        break
    fi
done

if [ "$valid" = false ]; then
    echo "" >&2
    echo "Unknown environment: $ENVIRONMENT. Valid options: ${VALID_ENVIRONMENTS[*]}" >&2
    echo "" >&2
    exit 1
fi

# --- Actions ---

instance_name="$(get_instance_name "$ENVIRONMENT")"
port="$(get_ssh_port "$instance_name")"

case "$ACTION" in
    connect)
        do_connect
        ;;
    restart)
        init_compose_env "$instance_name" "$port"
        read -ra compose_args <<< "$(get_compose_args)"
        if test_sandbox_running "${compose_args[@]}"; then
            docker compose "${compose_args[@]}" down
        fi
        sandbox_up "$port" "$instance_name"
        ;;
    rebuild)
        init_compose_env "$instance_name" "$port"
        read -ra compose_args <<< "$(get_compose_args)"
        if test_sandbox_running "${compose_args[@]}"; then
            docker compose "${compose_args[@]}" down
        fi
        stop_picker
        sandbox_build
        sandbox_up "$port" "$instance_name"
        ;;
    start|*)
        init_compose_env "$instance_name" "$port"
        read -ra compose_args <<< "$(get_compose_args)"
        if test_sandbox_running "${compose_args[@]}"; then
            show_connection_info "$instance_name" "$port"
        else
            sandbox_build
            sandbox_up "$port" "$instance_name"
        fi
        ;;
esac
