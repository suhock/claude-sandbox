#!/bin/bash
set -euo pipefail

# --- SSH directory ---
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# --- bashrc ---
cat /tmp/shared/bashrc.append >> ~/.bashrc

# --- Claude Code ---
curl -fsSL https://claude.ai/install.sh | bash
export PATH="/home/claude/.local/bin:${PATH}"
claude install

# --- tmux (after claude install, which may write its own .tmux.conf) ---
cp /tmp/shared/tmux.conf ~/.tmux.conf
