#!/bin/bash
# Root-level init: set up networking, then drop to claude user for the main entrypoint

# Resolve gateway IP via Docker DNS, then route all traffic through it
GATEWAY_IP=$(getent hosts gateway | awk '{print $1}')
ip route replace default via "$GATEWAY_IP"
echo "nameserver $GATEWAY_IP" > /etc/resolv.conf

# Remap claude user's UID/GID to match the bind-mounted workspace owner.
# This is the standard approach for containers that mount host directories
# (same pattern as VS Code devcontainers). On Linux hosts, the workspace
# has the host user's real UID; on Docker Desktop for Windows, files appear
# as root (UID 0) so we fall back to chown instead of remapping to root.
WORKSPACE_UID=$(stat -c '%u' /workspace)
WORKSPACE_GID=$(stat -c '%g' /workspace)
CLAUDE_UID=$(id -u claude)
CLAUDE_GID=$(id -g claude)

if [ "$WORKSPACE_UID" != "$CLAUDE_UID" ]; then
    if [ "$WORKSPACE_UID" != "0" ]; then
        # Linux host: remap claude to match host UID/GID
        if [ "$WORKSPACE_GID" != "$CLAUDE_GID" ] && [ "$WORKSPACE_GID" != "0" ]; then
            groupmod -g "$WORKSPACE_GID" claude
        fi
        usermod -u "$WORKSPACE_UID" claude
        chown -R "$WORKSPACE_UID:$WORKSPACE_GID" /home/claude
    else
        # Docker Desktop (Windows/Mac): files are root-owned, chown is
        # cosmetic inside the container and doesn't affect host permissions
        chown -R claude:claude /workspace
    fi
fi

# Drop NET_ADMIN capability so the claude user cannot modify routes,
# then switch to the claude user and run the main entrypoint
exec capsh --drop=cap_net_admin --user=claude -- -c /entrypoint.sh
