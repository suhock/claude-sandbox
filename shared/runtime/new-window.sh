#!/bin/bash
# Create a new tmux window (called from status bar buttons and the session picker)

type=$1

case "$type" in
    claude)
        tmux new-window -n claude 'claude --dangerously-skip-permissions'
        ;;
    bash)
        tmux new-window -n bash
        ;;
esac
