#!/bin/bash
# Sync host plugins into the writable state directory.
# Most marketplace plugins are hosted on github.com, which is blocked by the
# gateway's network rules. Copying pre-installed plugins from the host avoids
# the need to whitelist github.com. The metadata JSON files also need Windows-
# to-Linux path translation since the host is Windows.
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

# Seed environment-provided Claude Code skills / LSP plugins. Environments stage
# content under /opt/claude-skills at build time; copy it into the skills dir at
# runtime because ~/.claude is a bind mount that shadows anything baked into the
# image. This is how the php environment registers phpactor with the LSP tool.
if [ -d /opt/claude-skills ]; then
    mkdir -p ~/.claude/skills
    cp -rf /opt/claude-skills/. ~/.claude/skills/
fi

# Attempt a Claude Code update on every start. The install lives in the
# persistent home volume (~/.local), so the new version sticks across restarts
# without an image rebuild — the same thing `claude-sandbox -UpdateClaude` does,
# just automatic, so long-lived sandboxes don't drift behind the current release.
#
# Backgrounded on purpose: a synchronous download would delay sshd, and the CLI
# only waits a few seconds for it before printing connection details. Failures
# (offline host, gateway rules, download hiccup) are logged and ignored — an
# unreachable network must never keep the sandbox from coming up. DISABLE_AUTOUPDATER
# is set for interactive sessions, so unset it for this explicit update, and cap
# the attempt with a timeout so a stalled download can't hang around forever.
if command -v claude >/dev/null 2>&1; then
    (
        echo "Claude Code $(claude --version 2>/dev/null) — checking for updates..."
        if timeout 300 env -u DISABLE_AUTOUPDATER claude update; then
            echo "Claude Code now at $(claude --version 2>/dev/null)"
        else
            echo "Claude Code update attempt failed (exit $?); keeping the installed version" >&2
        fi
    ) &
fi

# Make container env vars available to SSH sessions
echo "export SANDBOX_ENV=\"$SANDBOX_ENV\"" > /home/claude/.sandbox_env
echo "export SANDBOX_WORKSPACE=\"$SANDBOX_WORKSPACE\"" >> /home/claude/.sandbox_env

# Start sshd in foreground — sshd manages its own children (reaps zombies)
# and the container lifecycle is tied to sshd
echo "============================================"
echo " SSH in to manage tmux sessions"
echo "============================================"

exec sudo /usr/sbin/sshd -D -e
