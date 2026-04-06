#!/bin/bash
# Interactive tmux session picker for SSH logins

# Claude code and this picker both use UTF-8 characters
export LANG=C.utf8

MAX_SESSIONS=10

# Start tmux server with our sandbox config (separate from Claude Code's .tmux.conf)
tmux -f ~/.tmux-sandbox.conf start-server 2>/dev/null

# Color palette
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_PRIMARY='\033[38;5;229m'   # Pale sandy yellow
C_SECONDARY='\033[38;5;246m' # Neutral gray

# echo with clear-to-end-of-line (flicker-free overwrite)
echo_line() { echo -e "$@\033[K"; }

# Session colors as 256-color indices (cycled per session)
# Used for both tmux status bars (colour<N>) and ANSI menu text (\033[38;5;<N>m)
SESSION_COLORS=(
    216  # pale orange (Claude Code)
    109  # teal
    139  # mauve
    174  # pink
    108  # sage
    144  # khaki
    132  # rose
    103  # lavender
    167  # coral
    72   # sea green
)

show_menu() {
    local workspace="${SANDBOX_WORKSPACE:-workspace}"

    # Move cursor home, hide it during redraw
    printf '\033[?25l\033[H'

    # Print the banner
    echo_line "${C_PRIMARY}  ▖  ▟▙  ▗  ${C_RESET}  "
    echo_line "${C_PRIMARY} ▟▜▖▟▛▜▙▗▛▙ ${C_RESET}  ${C_BOLD}Claude Sandbox${C_RESET}"
    echo_line "${C_PRIMARY} █▀██▀▀██▀█ ${C_RESET}  ${C_SECONDARY}${SANDBOX_ENV:-unknown} · ${workspace}${C_RESET}"
    printf "${C_SECONDARY}…${C_PRIMARY}████  ████${C_SECONDARY}";
    printf '…%.0s' $(seq 1 $(( $(tput cols) - 11 )));
    printf "${C_RESET}\n"
    echo ""

    # Obtain the list of active sessions
    session_names=()
    session_ages=()

    while read -r name ts; do
        local now=$(date +%s)
        local diff=$(( now - ts ))

        if [ $diff -lt 60 ]; then
            ago="less than a minute ago"
        elif [ $diff -lt 3600 ]; then
            ago="$(( diff / 60 ))m ago"
        elif [ $diff -lt 86400 ]; then
            ago="$(( diff / 3600 ))h ago"
        else
            ago="$(( diff / 86400 ))d ago"
        fi

        session_names+=("$name")
        session_ages+=("$ago")
    done < <(tmux list-sessions -F '#{session_name} #{session_activity}' 2>/dev/null)

    # Show the list of active sessions
    if [ ${#session_names[@]} -eq 0 ]; then
        echo_line "  ${C_SECONDARY}No running sessions${C_RESET}"
    else
        echo_line "  ${C_SECONDARY}Active sessions${C_RESET}"
        for i in "${!session_names[@]}"; do
            if [ $i -lt $MAX_SESSIONS ]; then
                local key=$(( (i + 1) % 10 ))
                local cindex=${SESSION_COLORS[$(( i % ${#SESSION_COLORS[@]} ))]}
                local c_session="\033[38;5;${cindex}m"
                echo_line "  ${C_PRIMARY}${key}${C_RESET}  ${c_session}${session_names[$i]}${C_RESET} ${C_SECONDARY}${session_ages[$i]}${C_RESET}"
            fi
        done
    fi

    echo_line ""

    # Show options for new sessions
    if [ ${#session_names[@]} -lt $MAX_SESSIONS ]; then
        echo_line "  ${C_PRIMARY}N${C_RESET}  New Claude Code session"
        echo_line "  ${C_PRIMARY}S${C_RESET}  New shell session"
    fi

    echo_line ""

    # Show quit option
    echo_line "  ${C_PRIMARY}Q${C_RESET}  Quit"
    echo_line ""

    # Show prompt, clear remaining lines, show cursor
    printf "  ${C_SECONDARY}>${C_RESET} \033[J\033[?25h"
}

get_session_name() {
    local idx=$1
    tmux list-sessions -F '#{session_name}' 2>/dev/null | sed -n "$((idx+1))p"
}

create_session() {
    local name=$1
    local cmd=$2

    # Find next available session number
    local n=1
    while tmux has-session -t "${name}-$n" 2>/dev/null; do
        n=$((n + 1))
    done

    # Assign a distinct status bar color based on session number
    local color_idx=$(( (n - 1) % ${#SESSION_COLORS[@]} ))
    local scolor="colour${SESSION_COLORS[$color_idx]}"
    local status_left=" ${SANDBOX_WORKSPACE:-workspace} · ${SANDBOX_ENV:-unknown} "
    local status_right=" #I:#W* · #S "

    tmux new-session -s "${name}-$n" $cmd \; \
        set-option mouse on \; \
        set-option status-style "bg=$scolor,fg=black" \; \
        set-option status-left-length 80 \; \
        set-option status-left "$status_left" \; \
        set-option status-right "$status_right"
}

clear
REDRAW=1
LAST_DRAW=0
REFRESH_INTERVAL=1
trap 'REDRAW=1' WINCH

while true; do
    now=$(date +%s)
    if [ $REDRAW -eq 1 ] || [ $(( now - LAST_DRAW )) -ge $REFRESH_INTERVAL ]; then
        show_menu
        REDRAW=0
        LAST_DRAW=$now
    fi
    read -rsn1 -t 0.25 choice || { continue; }
    [ -z "$choice" ] && continue

    # Normalize to uppercase
    choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')

    if [ "$choice" = "Q" ]; then
        echo ""
        break
    fi

    if [ "$choice" = "N" ] || [ "$choice" = "S" ]; then
        count=$(tmux list-sessions 2>/dev/null | wc -l)
        if [ "$count" -ge $MAX_SESSIONS ]; then
            continue
        fi
        if [ "$choice" = "N" ]; then
            create_session "claude" "claude --dangerously-skip-permissions"
        else
            create_session "shell" ""
        fi
        REDRAW=1
        continue
    fi

    # Attach to session by key (1-9,0 maps to index 0-9)
    if [[ "$choice" =~ ^[0-9]$ ]]; then
        idx=$(( (choice + 9) % 10 ))
        session=$(get_session_name "$idx")
        if [ -n "$session" ]; then
            tmux attach -t "$session"
        fi
        REDRAW=1
        continue
    fi
done
