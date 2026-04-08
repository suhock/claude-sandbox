#!/bin/sh
set -e

# --- Allowed domains ---
# Copy environment-specific domains if present
ENV_DOMAINS="/etc/gateway/environments/${SANDBOX_ENV}/allowed-domains.conf"
if [ -f "$ENV_DOMAINS" ]; then
  cp "$ENV_DOMAINS" /etc/gateway/allowed-domains.d/env.conf
fi

# Load all domain files (strip comments and blank lines)
ALLOWED_DOMAINS=$(cat /etc/gateway/allowed-domains.d/*.conf 2>/dev/null | grep -v '^#' | grep -v '^$')

# --- dnsmasq: generate ipset directives for each allowed domain ---
for domain in $ALLOWED_DOMAINS; do
  echo "ipset=/$domain/allowed_hosts" >> /etc/dnsmasq.conf
done

# --- DNS ---
dnsmasq -k -C /etc/dnsmasq.conf &
DNSMASQ_PID=$!

# --- iptables ---
# Create ipset for allowed destination IPs (populated dynamically by dnsmasq)
ipset create allowed_hosts hash:ip

# Find the outbound (default network) interface
OUTBOUND_IF=$(ip route | awk '/default/{print $5}')

# NAT outbound traffic
iptables -t nat -A POSTROUTING -o "$OUTBOUND_IF" -j MASQUERADE

# Allow established/related connections
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow traffic to IPs that dnsmasq has resolved for allowed domains
iptables -A FORWARD -m set --match-set allowed_hosts dst -j ACCEPT

# Reject everything else
iptables -A FORWARD -p tcp -j REJECT --reject-with tcp-reset
iptables -A FORWARD -j REJECT --reject-with icmp-port-unreachable

# --- SSH forwarding ---
# Wait for claude container's sshd to be reachable before accepting connections
echo "Waiting for claude container SSH..."
while ! nc -z claude 22 2>/dev/null; do
  sleep 0.5
done
echo "Claude container SSH is ready"

# Forward SSH with retry so connections during brief sshd restarts don't fail
socat TCP-LISTEN:22,fork TCP:claude:22 &
SOCAT_PID=$!

# Supervise both critical processes — exit if either dies so Docker restarts us
while kill -0 $DNSMASQ_PID 2>/dev/null && kill -0 $SOCAT_PID 2>/dev/null; do
  sleep 2
done
echo "Critical process exited, shutting down" >&2
kill $DNSMASQ_PID $SOCAT_PID 2>/dev/null
wait
exit 1
