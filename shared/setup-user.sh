#!/bin/bash
set -euo pipefail

# --- SSH directory ---
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# --- bashrc ---
# Handled by entrypoint.sh at runtime — ~/.bashrc is in the persistent home
# volume, so a build-time append never reaches an existing sandbox.

# --- Claude Code ---
curl -fsSL https://claude.ai/install.sh | bash
export PATH="/home/claude/.local/bin:${PATH}"
claude install
