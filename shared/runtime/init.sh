#!/bin/bash
# Root-level init: set up networking, then drop to claude user for the main entrypoint

# Route all traffic through the proxy container (transparent proxy)
ip route replace default via "$PROXY_IP"

# Drop NET_ADMIN capability so the claude user cannot modify routes,
# then switch to the claude user and run the main entrypoint
exec capsh --drop=cap_net_admin --user=claude -- -c /entrypoint.sh
