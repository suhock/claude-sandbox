#!/bin/bash
# Interactive tmux session picker for SSH logins

# Claude code and this picker both use UTF-8 characters
export LANG=C.utf8

MAX_SESSIONS=10

# Start tmux server (reads ~/.tmux.conf written at build time)
tmux start-server 2>/dev/null

# Colors
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_PRIMARY='\033[38;5;229m'   # Pale sandy yellow
C_SECONDARY='\033[38;5;246m' # Neutral gray

# Tmux status bar colors (cycled per session)
SESSION_COLORS=(
    colour216  # pale orange (Claude Code)
    colour109  # teal
    colour139  # mauve
    colour174  # pink
    colour108  # sage
    colour144  # khaki
    colour132  # rose
    colour103  # lavender
    colour167  # coral
    colour72   # sea green
)

show_menu() {
    local workspace="${SANDBOX_WORKSPACE:-workspace}"
 
    clear

    # Print the banner
    echo ""
    echo -e "${C_PRIMARY}  ▖  ▟▙  ▗  ${C_RESET}  ${C_BOLD}Claude Sandbox${C_RESET}"
    echo -e "${C_PRIMARY} ▟▜▖▟▛▜▙▗▛▙ ${C_RESET}  ${C_SECONDARY}${SANDBOX_ENV:-unknown}${C_RESET}"
    echo -e "${C_PRIMARY} █▀██▀▀██▀█ ${C_RESET}  ${C_SECONDARY}${workspace}${C_RESET}"
    printf "${C_SECONDARY}…${C_PRIMARY}████  ████${C_SECONDARY}";
    printf '…%.0s' $(seq 1 $(( $(tput cols) - 11 )));
    printf "${C_RESET}\n"
    echo ""

    # Obtain the list of active sessions
    sessions=()

    while IFS= read -r line; do
        sessions+=("$line")
    done < <(
        tmux list-sessions -F '#{session_name} #{session_activity}' 2>/dev/null | while read -r name ts; do
            now=$(date +%s)
            diff=$(( now - ts ))

            if [ $diff -lt 60 ]; then
                ago="less than a minute ago"
            elif [ $diff -lt 3600 ]; then
                ago="$(( diff / 60 ))m ago"
            elif [ $diff -lt 86400 ]; then
                ago="$(( diff / 3600 ))h ago"
            else
                ago="$(( diff / 86400 ))d ago"
            fi

            echo "$name ($ago)"
        done
    )

    # Show the list of active sessions
    if [ ${#sessions[@]} -eq 0 ]; then
        echo -e "  ${C_SECONDARY}No running sessions${C_RESET}"
    else
        echo -e "  ${C_SECONDARY}Active sessions${C_RESET}"
        for i in "${!sessions[@]}"; do
            if [ $i -lt $MAX_SESSIONS ]; then
                local key=$(( (i + 1) % 10 ))
                echo -e "  ${C_PRIMARY}${key}${C_RESET}  ${sessions[$i]}"
            fi
        done
    fi

    echo ""

    # Show options for new sessions
    if [ ${#sessions[@]} -lt $MAX_SESSIONS ]; then
        echo -e "  ${C_PRIMARY}N${C_RESET}  New Claude Code session"
        echo -e "  ${C_PRIMARY}S${C_RESET}  New shell session"
    fi

    echo ""

    # Show quit option
    echo -e "  ${C_PRIMARY}Q${C_RESET}  Quit"
    echo ""

    # Show prompt
    printf "  ${C_SECONDARY}>${C_RESET} "
}

get_session_name() {
    local idx=$1
    tmux list-sessions -F '#{session_name}' 2>/dev/null | sed -n "$((idx+1))p"
}

REDRAW=1
trap 'REDRAW=1' WINCH

while true; do
    if [ $REDRAW -eq 1 ]; then
        show_menu
        REDRAW=0
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
        n=1
        while tmux has-session -t "claude-$n" 2>/dev/null; do
            n=$((n + 1))
        done
        # Assign a distinct status bar color based on session number
        color_idx=$(( (n - 1) % ${#SESSION_COLORS[@]} ))
        scolor="${SESSION_COLORS[$color_idx]}"
        status_left=" ${SANDBOX_WORKSPACE:-workspace} · ${SANDBOX_ENV:-unknown} "
        status_right=" #I:#W* · #S "

        if [ "$choice" = "N" ]; then
            tmux new-session -s "claude-$n" "claude --dangerously-skip-permissions" \; \
                set-option mouse on \; \
                set-option status-style "bg=$scolor,fg=black" \; \
                set-option status-left-length 80 \; \
                set-option status-left "$status_left" \; \
                set-option status-right "$status_right"
        else
            tmux new-session -s "claude-$n" \; \
                set-option mouse on \; \
                set-option status-style "bg=$scolor,fg=black" \; \
                set-option status-left-length 80 \; \
                set-option status-left "$status_left" \; \
                set-option status-right "$status_right"
        fi
        continue
    fi

    # Attach to session by key (1-9,0 maps to index 0-9)
    if [[ "$choice" =~ ^[0-9]$ ]]; then
        local idx=$(( (choice + 9) % 10 ))
        session=$(get_session_name "$idx")
        if [ -n "$session" ]; then
            tmux attach -t "$session"
        fi
        continue
    fi
done
