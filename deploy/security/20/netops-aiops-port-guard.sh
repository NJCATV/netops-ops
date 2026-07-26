#!/bin/sh
set -eu

# INPUT covers host services and Docker userland-proxy.  DOCKER-USER covers
# direct Docker forwarding paths.  No default policy or SSH rule is changed.
ensure_input() { iptables -C INPUT "$@" 2>/dev/null || iptables -I INPUT 1 "$@"; }
ensure_docker() { iptables -C DOCKER-USER "$@" 2>/dev/null || iptables -I DOCKER-USER 1 "$@"; }

# 233 is the only BFF/monitor client for the host services.
ensure_input -p tcp --dport 18190 -m comment --comment netops-aiops-monitor-deny -j DROP
ensure_input -s 172.31.1.233/32 -p tcp --dport 18190 -m comment --comment netops-aiops-monitor-233 -j ACCEPT
ensure_input -i lo -p tcp --dport 18190 -m comment --comment netops-aiops-monitor-local -j ACCEPT
ensure_input -p tcp --dport 18080 -m comment --comment netops-aiops-api-deny -j DROP
ensure_input -s 172.31.1.233/32 -p tcp --dport 18080 -m comment --comment netops-aiops-api-233 -j ACCEPT
ensure_input -i lo -p tcp --dport 18080 -m comment --comment netops-aiops-api-local -j ACCEPT

# Docker-published internal/control services: local and the AIOps bridge only.
for port in 6099 3001 3000 18088 8080; do
  ensure_input -p tcp --dport "$port" -m comment --comment "netops-aiops-port-${port}-deny" -j DROP
  ensure_input -s 172.21.0.0/16 -p tcp --dport "$port" -m comment --comment "netops-aiops-port-${port}-bridge" -j ACCEPT
  ensure_input -i lo -p tcp --dport "$port" -m comment --comment "netops-aiops-port-${port}-local" -j ACCEPT
done

ensure_input -p tcp --dport 9200 -m comment --comment netops-aiops-es-deny -j DROP
ensure_input -i lo -p tcp --dport 9200 -m comment --comment netops-aiops-es-local -j ACCEPT
ensure_input -p tcp --dport 5601 -m comment --comment netops-aiops-kibana-deny -j DROP
ensure_input -s 172.31.0.0/16 -p tcp --dport 5601 -m comment --comment netops-aiops-kibana-lan -j ACCEPT
ensure_input -i lo -p tcp --dport 5601 -m comment --comment netops-aiops-kibana-local -j ACCEPT
ensure_input -p tcp --dport 13306 -m comment --comment netops-aiops-mysql-deny -j DROP
ensure_input -s 172.31.0.0/16 -p tcp --dport 13306 -m comment --comment netops-aiops-mysql-lan -j ACCEPT
ensure_input -i lo -p tcp --dport 13306 -m comment --comment netops-aiops-mysql-local -j ACCEPT

# Direct Docker forwarding paths.  The MySQL published host port 13306 is
# post-DNAT 172.21.0.3:3306 when it reaches this chain.
for port in 6099 3001 3000 18088 8080; do
  ensure_docker -p tcp --dport "$port" -m comment --comment "netops-aiops-port-${port}-deny" -j DROP
  ensure_docker -s 172.21.0.0/16 -p tcp --dport "$port" -m comment --comment "netops-aiops-port-${port}-bridge" -j RETURN
done
ensure_docker -p tcp --dport 9200 -m comment --comment netops-aiops-es-deny -j DROP
ensure_docker -s 172.21.0.0/16 -p tcp --dport 9200 -m comment --comment netops-aiops-es-bridge -j RETURN
ensure_docker -p tcp --dport 5601 -m comment --comment netops-aiops-kibana-deny -j DROP
ensure_docker -s 172.31.0.0/16 -p tcp --dport 5601 -m comment --comment netops-aiops-kibana-lan -j RETURN
ensure_docker -d 172.21.0.3/32 -p tcp --dport 3306 -m comment --comment netops-aiops-mysql-deny -j DROP
ensure_docker -s 172.21.0.0/16 -d 172.21.0.3/32 -p tcp --dport 3306 -m comment --comment netops-aiops-mysql-bridge -j RETURN
ensure_docker -s 172.31.0.0/16 -d 172.21.0.3/32 -p tcp --dport 3306 -m comment --comment netops-aiops-mysql-lan -j RETURN
