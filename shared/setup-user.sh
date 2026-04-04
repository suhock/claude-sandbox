#!/bin/bash
set -euo pipefail

# --- SSH directory ---
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# --- bashrc ---
echo 'export LANG=C.utf8' >> ~/.bashrc
echo '[ -f ~/.sandbox_env ] && . ~/.sandbox_env' >> ~/.bashrc
echo 'export PATH="/home/claude/.local/bin:${PATH}"' >> ~/.bashrc
echo 'export TERM=xterm-256color' >> ~/.bashrc
echo 'cd /workspace' >> ~/.bashrc
echo 'if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then exec /home/claude/tmux-picker.sh; fi' >> ~/.bashrc

# --- Claude Code ---
curl -fsSL https://claude.ai/install.sh | bash
export PATH="/home/claude/.local/bin:${PATH}"
claude install

# --- tmux (after claude install, which may write its own .tmux.conf) ---
cat > ~/.tmux.conf << 'TMUX_CONF'
set -s escape-time 200
set -g mouse on
set -g history-limit 100000
set -g terminal-overrides 'xterm*:smcup@:rmcup@'
set -g detach-on-destroy on
set -g window-status-format ''
set -g window-status-current-format ''
TMUX_CONF
