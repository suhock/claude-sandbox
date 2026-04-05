#!/bin/sh
set -e

# --- Allowed domains ---
# Copy environment-specific domains if present
ENV_DOMAINS="/etc/proxy/environments/${SANDBOX_ENV}/allowed-domains.conf"
if [ -f "$ENV_DOMAINS" ]; then
  cp "$ENV_DOMAINS" /etc/proxy/allowed-domains.d/env.conf
fi

# Load all domain files
ALLOWED_DOMAINS=$(cat /etc/proxy/allowed-domains.d/*.conf 2>/dev/null | grep -v '^#' | grep -v '^$')

# --- DNS (start early so nslookup works below) ---
dnsmasq -k -C /etc/dnsmasq.conf &
sleep 0.5

# --- IP forwarding and NAT ---
# Find the outbound (default network) interface
OUTBOUND_IF=$(ip route | awk '/default/{print $5}')

# NAT outbound traffic from the internal network
iptables -t nat -A POSTROUTING -o "$OUTBOUND_IF" -j MASQUERADE

# Allow established/related connections back in
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Resolve each allowed domain and allow forwarding to its IPs
for domain in $ALLOWED_DOMAINS; do
  for ip in $(nslookup "$domain" 127.0.0.1 2>/dev/null | awk '/^Address: [0-9]+\./{print $2}'); do
    iptables -A FORWARD -d "$ip" -j ACCEPT
  done
done

# Reject all other forwarded traffic (immediate failure instead of timeout)
iptables -A FORWARD -p tcp -j REJECT --reject-with tcp-reset
iptables -A FORWARD -j REJECT --reject-with icmp-port-unreachable

# --- SSH forwarding ---
exec socat TCP-LISTEN:22,fork TCP:claude:22
