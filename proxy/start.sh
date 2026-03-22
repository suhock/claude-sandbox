#!/bin/bash
set -e

rm -f /run/squid.pid

dnsmasq -k -C /etc/dnsmasq.conf &

exec squid -N -f /etc/squid/squid.conf