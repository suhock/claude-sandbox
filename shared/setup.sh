#!/bin/bash
set -euo pipefail

# Shared setup script for all environments.
# Usage:
#   RUN bash /tmp/setup.sh --root   (as root: packages, sshd, user creation)
#   USER claude
#   RUN bash /tmp/setup.sh --user   (as claude: tmux, bashrc, Claude Code)

case "${1:-}" in
--root)
    # --- Packages ---
    apt-get update && apt-get install -y \
        git curl bash \
        openssh-server tmux sudo

    # Install Node.js only if not already present (e.g., node:* base images)
    if ! command -v node &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
        && apt-get install -y nodejs
    fi

    apt-get clean && rm -rf /var/lib/apt/lists/*

    # --- sshd ---
    mkdir -p /run/sshd
    sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    echo "AuthorizedKeysFile .ssh/authorized_keys" >> /etc/ssh/sshd_config
    echo "claude ALL=(root) NOPASSWD: /usr/sbin/sshd" >> /etc/sudoers.d/claude-sshd
    chmod 440 /etc/sudoers.d/claude-sshd

    # --- User creation (handles UID 1000 conflicts) ---
    existing_user=$(getent passwd 1000 | cut -d: -f1 || true)
    if [ -n "$existing_user" ] && [ "$existing_user" != "claude" ]; then
        usermod -l claude -d /home/claude -m "$existing_user"
        groupmod -n claude "$(id -gn 1000)"
    elif [ -z "$existing_user" ]; then
        useradd -m -u 1000 -s /bin/bash claude
    fi
    passwd -d claude
    ;;

--user)
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
    ;;

*)
    echo "Usage: setup.sh --root | --user" >&2
    exit 1
    ;;
esac
