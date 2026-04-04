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

# Make container env vars available to SSH sessions
echo "export SANDBOX_ENV=\"$SANDBOX_ENV\"" > /home/claude/.sandbox_env
echo "export SANDBOX_WORKSPACE=\"$SANDBOX_WORKSPACE\"" >> /home/claude/.sandbox_env

# Mark workspace as safe for git (bind mount has different ownership)
git config --global --add safe.directory /workspace

# Start sshd (needs root, use sudo)
sudo /usr/sbin/sshd

# Keep container alive
echo "============================================"
echo " SSH in to manage tmux sessions"
echo "============================================"

exec sleep infinity
