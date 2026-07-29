#!/bin/bash
set -euo pipefail

# --- SSH directory ---
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# --- bashrc ---
# The sandbox shell init lives at /opt/sandbox/bashrc.sh (outside the home
# volume, so it stays fresh across rebuilds). Only a stable source line is
# baked into ~/.bashrc; it seeds into the home volume once and never changes.
echo '[ -f /opt/sandbox/bashrc.sh ] && . /opt/sandbox/bashrc.sh' >> ~/.bashrc

# --- Claude Code ---
curl -fsSL https://claude.ai/install.sh | bash
export PATH="/home/claude/.local/bin:${PATH}"
claude install
