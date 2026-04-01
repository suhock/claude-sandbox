#!/bin/bash
# Sync host plugins into the writable state directory
if [ -d /host-plugins ]; then
    mkdir -p ~/.claude/plugins
    # Always refresh marketplace data and plugin cache from host
    cp -a /host-plugins/marketplaces/. ~/.claude/plugins/marketplaces/ 2>/dev/null
    cp -a /host-plugins/cache/. ~/.claude/plugins/cache/ 2>/dev/null
    # Copy metadata files only if they don't already exist
    for f in installed_plugins.json known_marketplaces.json blocklist.json install-counts-cache.json; do
        if [ -f "/host-plugins/$f" ] && [ ! -f ~/.claude/plugins/"$f" ]; then
            cp /host-plugins/"$f" ~/.claude/plugins/"$f"
        fi
    done

    # Fix Windows paths in plugin metadata to Linux paths
    for f in ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/known_marketplaces.json; do
        if [ -f "$f" ]; then
            sed -i 's|C:\\\\Users\\\\[^\\]*\\\\.claude\\\\plugins\\\\|/home/claude/.claude/plugins/|g' "$f"
            sed -i 's|\\\\|/|g' "$f"
        fi
    done
fi

# Mark workspace as safe for git (bind mount has different ownership)
git config --global --add safe.directory /workspace

# Import authorized keys from mounted host keys
if [ -d /host-ssh-keys ]; then
    cat /host-ssh-keys/*.pub >> ~/.ssh/authorized_keys 2>/dev/null
    chmod 600 ~/.ssh/authorized_keys 2>/dev/null
fi

# Start sshd (needs root, use sudo)
sudo /usr/sbin/sshd

# Start claude in a tmux session
tmux new-session -d -s claude "claude --dangerously-skip-permissions"

echo "============================================"
echo " Claude is running in tmux session 'claude'"
echo " SSH in and run: tmux attach -t claude"
echo "============================================"

# Keep container alive; if the tmux session dies, restart it
while true; do
    if ! tmux has-session -t claude 2>/dev/null; then
        echo "Claude session ended. Restarting..."
        tmux new-session -d -s claude "claude --dangerously-skip-permissions"
    fi
    sleep 5
done
