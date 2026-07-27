# Production security guard templates

This directory is the source-controlled record of the host security guards
deployed on 2026-07-26.  It deliberately contains no credentials, tokens, or
runtime `.env` files.

## Applying a guard

Copy the host-specific shell script to `/usr/local/sbin/`, mode `0700`, then
copy the matching systemd unit to `/etc/systemd/system/` and run:

```bash
systemctl daemon-reload
systemctl enable --now <unit-name>
```

The scripts are idempotent: they add only the labelled NetOps rules if absent.
They do not change the host default policy or SSH listener.  Verify after
every apply with `iptables -S`, `systemctl status <unit>`, and an allowed plus
a denied source test.

## Docker note

On server 20, Docker published ports have two possible paths: direct Docker
forwarding and the host `docker-proxy`.  The 20 guard therefore protects both
`DOCKER-USER` and `INPUT`.  The MySQL host port `13306` is DNATed to the
container's `172.21.0.3:3306`, so the `DOCKER-USER` rule must match the
post-DNAT destination/port, not `13306`.

## Fail2ban

`fail2ban/*.local` contains the SSH-only jail templates.  Use the template
whose SSH port matches the host.  The policy is five failed attempts in ten
minutes, followed by a 24-hour ban.  It uses the systemd SSH journal and does
not replace firewall source allowlists.

## 212 ClickHouse data node

`212/netops-clickhouse-port-guard.sh` protects the verified data-node surface:
SSH `5334` is limited to `172.31.0.0/16`; ClickHouse HTTP `8123` is limited to
233, 236, 213 and loopback; native/internal `9000/9004/9005/9009` are
loopback-only.  It must be installed together with `212-netops-sshd.local`.
The script must be revised before adding a ClickHouse cluster, replication or
another HTTP client.
