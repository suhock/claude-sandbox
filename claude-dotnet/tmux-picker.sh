#!/bin/bash
# Interactive tmux session picker for SSH logins
# 1-9, A-Z = attach to existing session, 0 = new Claude Code session

MAX_SESSIONS=10

show_menu() {
    clear
    echo "========================================"
    echo "  Claude Sandbox - tmux sessions"
    echo "========================================"
    echo ""

    sessions=()
    while IFS= read -r line; do
        sessions+=("$line")
    done < <(tmux list-sessions -F '#{session_name}: #{session_windows} window(s) (created #{session_created_string})' 2>/dev/null)

    if [ ${#sessions[@]} -eq 0 ]; then
        echo "  No running sessions."
    else
        for i in "${!sessions[@]}"; do
            if [ $i -lt $MAX_SESSIONS ]; then
                echo "  [$i] ${sessions[$i]}"
            fi
        done
    fi

    echo ""
    if [ ${#sessions[@]} -lt $MAX_SESSIONS ]; then
        echo "  [N] New Claude Code session"
    fi
    echo "  [Q] Quit"
    echo ""
    printf "  Select: "
}

get_session_name() {
    local idx=$1
    tmux list-sessions -F '#{session_name}' 2>/dev/null | sed -n "$((idx+1))p"
}

while true; do
    show_menu
    read -rsn1 choice

    # Normalize to uppercase
    choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')

    if [ "$choice" = "Q" ]; then
        echo ""
        break
    fi

    if [ "$choice" = "N" ]; then
        count=$(tmux list-sessions 2>/dev/null | wc -l)
        if [ "$count" -ge $MAX_SESSIONS ]; then
            continue
        fi
        n=1
        while tmux has-session -t "claude-$n" 2>/dev/null; do
            n=$((n + 1))
        done
        tmux new-session -s "claude-$n" "claude --dangerously-skip-permissions"
        continue
    fi

    # Attach to session by index (0-9)
    if [[ "$choice" =~ ^[0-9]$ ]]; then
        session=$(get_session_name "$choice")
        if [ -n "$session" ]; then
            tmux attach -t "$session"
        fi
        continue
    fi
done
