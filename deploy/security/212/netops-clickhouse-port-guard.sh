#!/bin/sh
set -eu

# 212 is a standalone ClickHouse data node.  This guard leaves the host
# default policy unchanged and protects only documented listeners.  It is
# intentionally idempotent so it can be replayed after a reboot.
ensure() { iptables -C INPUT "$@" 2>/dev/null || iptables -I INPUT 1 "$@"; }

# Operations access is currently sourced from the 172.31 management network.
# Keep loopback for local maintenance and deny all other IPv4 SSH sources.
ensure -p tcp --dport 5334 -m comment --comment netops-clickhouse-ssh-deny -j DROP
ensure -s 172.31.0.0/16 -p tcp --dport 5334 -m comment --comment netops-clickhouse-ssh-management -j ACCEPT
ensure -i lo -p tcp --dport 5334 -m comment --comment netops-clickhouse-ssh-local -j ACCEPT

# ClickHouse HTTP is the only remote data-plane protocol in the verified
# topology: 233 reads, 236 writes collector data, and 213 writes Radius data.
ensure -p tcp --dport 8123 -m comment --comment netops-clickhouse-http-deny -j DROP
ensure -s 172.25.194.213/32 -p tcp --dport 8123 -m comment --comment netops-clickhouse-http-radius -j ACCEPT
ensure -s 172.31.1.236/32 -p tcp --dport 8123 -m comment --comment netops-clickhouse-http-collector -j ACCEPT
ensure -s 172.31.1.233/32 -p tcp --dport 8123 -m comment --comment netops-clickhouse-http-platform -j ACCEPT
ensure -i lo -p tcp --dport 8123 -m comment --comment netops-clickhouse-http-local -j ACCEPT

# No active cluster, replication, MySQL-protocol or PostgreSQL-protocol client
# dependency was found.  Keep the ClickHouse internal/admin ports local-only.
for port in 9000 9004 9005 9009; do
  ensure -p tcp --dport "$port" -m comment --comment "netops-clickhouse-port-${port}-deny" -j DROP
  ensure -i lo -p tcp --dport "$port" -m comment --comment "netops-clickhouse-port-${port}-local" -j ACCEPT
done
