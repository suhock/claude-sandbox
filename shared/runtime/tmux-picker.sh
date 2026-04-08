#!/bin/bash
# Attach to existing tmux session or create one with a Claude Code window

export LANG=C.utf8

SESSION="sandbox"
TMUX_CONF=~/.tmux-sandbox.conf
workspace="${SANDBOX_WORKSPACE:-workspace}"

if ! tmux -f "$TMUX_CONF" has-session -t "$SESSION" 2>/dev/null; then
    tmux -f "$TMUX_CONF" new-session -d -s "$SESSION" \
        -n claude 'claude --dangerously-skip-permissions' \; \
        set-option status-left " ${workspace} · ${SANDBOX_ENV:-unknown} · "
fi

exec tmux -f "$TMUX_CONF" attach -t "$SESSION"
