#!/bin/bash
# Root-level init: set up networking, then drop to claude user for the main entrypoint

# Resolve gateway IP via Docker DNS, then route all traffic through it
GATEWAY_IP=$(getent hosts gateway | awk '{print $1}')
ip route replace default via "$GATEWAY_IP"
echo "nameserver $GATEWAY_IP" > /etc/resolv.conf

# Drop NET_ADMIN capability so the claude user cannot modify routes,
# then switch to the claude user and run the main entrypoint
exec capsh --drop=cap_net_admin --user=claude -- -c /entrypoint.sh
