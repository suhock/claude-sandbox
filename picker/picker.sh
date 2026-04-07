#!/bin/bash
# Interactive sandbox picker — discovers running/stopped sandboxes, starts and connects

export LANG=C.utf8
[ -f ~/.sandbox_env ] && . ~/.sandbox_env

# Color palette
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_PRIMARY='\033[38;5;223m'   # pale yellow
C_SECONDARY='\033[38;5;174m' # claude code pink
C_TERTIARY='\033[38;5;246m'  # neutral gray
C_STOPPED='\033[38;5;240m'   # dark gray

# echo with clear-to-end-of-line
echo_line() { echo -e "$@\033[K"; }

discover_sandboxes() {
    sandbox_names=()
    sandbox_ports=()
    sandbox_envs=()
    sandbox_workspaces=()
    sandbox_running=()

    # Running sandboxes (have port mappings)
    while IFS=$'\t' read -r name ports env workspace; do
        local port=$(echo "$ports" | sed -n 's/.*:\([0-9]*\)->22\/tcp.*/\1/p' | head -1)
        [ -z "$port" ] && continue

        sandbox_names+=("$name")
        sandbox_ports+=("$port")
        sandbox_envs+=("$env")
        sandbox_workspaces+=("$workspace")
        sandbox_running+=(1)
    done < <(sudo docker ps --filter "label=sandbox.env" \
        --format '{{.Names}}\t{{.Ports}}\t{{.Label "sandbox.env"}}\t{{.Label "sandbox.workspace"}}' 2>/dev/null)

    # Stopped sandboxes
    while IFS=$'\t' read -r name env workspace project; do
        # Skip if we already have this project in the running list
        local already_listed=0
        for running_name in "${sandbox_names[@]}"; do
            if [[ "$running_name" == *"$project"* ]]; then
                already_listed=1
                break
            fi
        done
        [ $already_listed -eq 1 ] && continue

        sandbox_names+=("$name")
        sandbox_ports+=("")
        sandbox_envs+=("$env")
        sandbox_workspaces+=("$workspace")
        sandbox_running+=(0)
    done < <(sudo docker ps -a --filter "label=sandbox.env" --filter "status=exited" \
        --format '{{.Names}}\t{{.Label "sandbox.env"}}\t{{.Label "sandbox.workspace"}}\t{{.Label "com.docker.compose.project"}}' 2>/dev/null)

    # Sort by workspace+env for stable ordering regardless of state
    local indices=($(for i in "${!sandbox_names[@]}"; do
        echo "$i ${sandbox_workspaces[$i]} ${sandbox_envs[$i]}"
    done | sort -k2,3 | awk '{print $1}'))

    local tmp_names=() tmp_ports=() tmp_envs=() tmp_workspaces=() tmp_running=()
    for i in "${indices[@]}"; do
        tmp_names+=("${sandbox_names[$i]}")
        tmp_ports+=("${sandbox_ports[$i]}")
        tmp_envs+=("${sandbox_envs[$i]}")
        tmp_workspaces+=("${sandbox_workspaces[$i]}")
        tmp_running+=("${sandbox_running[$i]}")
    done
    sandbox_names=("${tmp_names[@]}")
    sandbox_ports=("${tmp_ports[@]}")
    sandbox_envs=("${tmp_envs[@]}")
    sandbox_workspaces=("${tmp_workspaces[@]}")
    sandbox_running=("${tmp_running[@]}")
}

start_sandbox() {
    local name=$1
    local project=$(sudo docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$name" 2>/dev/null)
    [ -z "$project" ] && return 1

    # Find all containers in this project and start them (proxy first)
    local containers=$(sudo docker ps -a --filter "label=com.docker.compose.project=$project" --format '{{.Names}}\t{{.Label "com.docker.compose.service"}}' 2>/dev/null)

    # Start proxy first
    echo "$containers" | while IFS=$'\t' read -r cname service; do
        [ "$service" = "proxy" ] && sudo docker start "$cname" >/dev/null 2>&1
    done

    # Then start the rest
    echo "$containers" | while IFS=$'\t' read -r cname service; do
        [ "$service" != "proxy" ] && sudo docker start "$cname" >/dev/null 2>&1
    done

    # Get the SSH port
    local port=$(sudo docker port "${project}-proxy-1" 22 2>/dev/null | sed -n 's/.*:\([0-9]*\)/\1/p' | head -1)
    [ -z "$port" ] && return 1

    # Wait for SSH to become available
    local retries=0
    while [ $retries -lt 30 ]; do
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=1 \
            -o BatchMode=yes -q -p "$port" claude@host.docker.internal echo ok 2>/dev/null | grep -q ok; then
            echo "$port"
            return 0
        fi
        sleep 1
        retries=$((retries + 1))
    done

    return 1
}

show_menu() {
    # Print the terminal title
    printf '\033]0;🟨 %s\007' "${HOST_HOSTNAME:-$(hostname)}"
    
    printf '\033[?25l\033[H'

    echo_line ""
    echo_line "${C_PRIMARY} ▖▖▖ ▟▙ ▗▗▗ ${C_RESET}"
    echo_line "${C_PRIMARY} ██▙▟▛▜▙▟██ ${C_RESET} ${C_BOLD}Claude Sandbox${C_RESET}"
    local host="${HOST_HOSTNAME:-$(hostname)}"
    printf "${C_TERTIARY}…${C_PRIMARY}████  ████${C_TERTIARY}… %s " "$host"
    local fill=$(( $(tput cols) - 14 - ${#host} ))
    [ $fill -gt 0 ] && printf '…%.0s' $(seq 1 $fill)
    printf "${C_RESET}\n"
    echo_line ""

    if [ ${#sandbox_names[@]} -eq 0 ]; then
        echo_line "  ${C_TERTIARY}No sandboxes found${C_RESET}"
    else
        echo_line "  ${C_TERTIARY}Sandbox Instances${C_RESET}"
        echo_line ""

        for i in "${!sandbox_names[@]}"; do
            local key=$(( (i + 1) % 10 ))
            local env="${sandbox_envs[$i]:-unknown}"
            local workspace="${sandbox_workspaces[$i]:-workspace}"
            if [ "${sandbox_running[$i]}" -eq 1 ]; then
                echo_line "  ${C_PRIMARY}${key}${C_RESET}  ${C_SECONDARY}${workspace} (${env})${C_RESET} ${C_TERTIARY}:${sandbox_ports[$i]}${C_RESET}"
            else
                echo_line "  ${C_PRIMARY}${key}${C_RESET}  ${C_STOPPED}${workspace} (${env})${C_RESET}"
            fi
        done
    fi

    echo_line ""
    echo_line "  ${C_PRIMARY}Q${C_RESET}  Quit"
    echo_line ""

    printf "  ${C_TERTIARY}>${C_RESET} \033[J\033[?25h"
}

connect_to_sandbox() {
    local port=$1
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 -p "$port" claude@host.docker.internal
}

clear

# Main loop
REDRAW=1
LAST_DRAW=0
REFRESH_INTERVAL=2
MENU_STATE=""

trap 'REDRAW=1' WINCH
stty -echo
trap 'stty echo' EXIT

while true; do
    now=$(date +%s)
    if [ $REDRAW -eq 1 ] || [ $(( now - LAST_DRAW )) -ge $REFRESH_INTERVAL ]; then
        prev_state="$MENU_STATE"
        discover_sandboxes
        MENU_STATE=$(printf '%s\n' "${sandbox_names[@]}" "${sandbox_running[@]}")
        if [ $REDRAW -eq 1 ] || [ "$MENU_STATE" != "$prev_state" ]; then
            show_menu
        fi
        REDRAW=0
        LAST_DRAW=$now
    fi

    read -rsn1 -t 0.25 choice || continue
    [ -z "$choice" ] && continue
    # Flush remaining bytes of escape sequences (e.g. arrow keys)
    if [[ "$choice" == $'\033' ]]; then
        read -rsn2 -t 0.01 _ || true
        continue
    fi
    if [ "$choice" = "Q" ] || [ "$choice" = "q" ]; then
        stty echo
        printf "%s\n" "$choice"
        break
    fi

    # Ignore anything that isn't a valid menu key
    if [[ ! "$choice" =~ ^[0-9]$ ]]; then
        continue
    fi

    idx=$(( (choice + 9) % 10 ))
    if [ $idx -lt ${#sandbox_names[@]} ]; then
        stty echo
        if [ "${sandbox_running[$idx]}" -eq 1 ]; then
            printf "\n\n  ${C_TERTIARY}Connecting...${C_RESET}"
            connect_to_sandbox "${sandbox_ports[$idx]}"
        else
            # Start stopped sandbox
            printf "\n\n  ${C_TERTIARY}Starting...${C_RESET}"
            port=$(start_sandbox "${sandbox_names[$idx]}")
            if [ -n "$port" ]; then
                connect_to_sandbox "$port"
            fi
        fi
        stty -echo
    fi
    REDRAW=1
done
