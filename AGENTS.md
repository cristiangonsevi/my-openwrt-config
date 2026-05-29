# AGENTS.md — OpenWrt Config Repository

## What This Is

A single-file OpenWrt shell script (`configuration.sh`) that configures DNS filtering + SafeSearch + DNS-over-HTTPS + SQM (CAKE) + kernel optimizations on an OpenWrt router. Designed for a **coaxial/DOCSIS 150/20 Mbps connection**.

## File Structure

```
openwrt-config/
├── AGENTS.md
└── configuration.sh   # The full setup script
```

That's it — single file, no tests, no CI, no Makefile.

## Package Manager — OpenWrt switched from `opkg` → `apk`

The script now uses `apk` (newer OpenWrt builds). Compatibility reference:

| Old `opkg` | New `apk` (script uses) |
|------------|-------------------------|
| `opkg update` | `apk update` |
| `opkg install <pkg>` | `apk add <pkg>` |
| `opkg remove <pkg>` | `apk del <pkg>` |

## Key Commands

| Action | Command |
|--------|---------|
| Run on router | `sh configuration.sh` (as root) |
| View log on router | `cat /tmp/openwrt_setup.log` |
| Verify DNS | `nslookup google.com` or `logread \| grep dnsmasq` |
| Verify SQM | `tc -s qdisc show dev $(uci get network.wan.ifname)` |
| Check SQM status | `sqm status` (if installed) |
| Check DoH proxy | `netstat -tlnp \| grep 5053` |

## Script Architecture (5 phases)

1. **Dependency install** — `apk update` then `apk add` for `luci-app-sqm`, `https-dns-proxy`, `irqbalance`, `kmod-tcp-bbr`, kernel modules
2. **DNS config** — Sets dnsmasq to use Cloudflare Family (1.1.1.3/1.0.0.3) + Google (8.8.8.8/8.8.4.4), disables ISP DNS (`noresolv=1`), writes SafeSearch CNAME overrides + adult domain blocks + cache tuning (`max-cache-ttl`, `min-cache-ttl`) to `/etc/dnsmasq.d/safesearch.conf`
3. **DNS-over-HTTPS** — Configures two `https-dns-proxy` instances (Cloudflare Family on :5053, Google on :5054), then re-points dnsmasq to local DoH proxies
4. **SQM (CAKE)** — Auto-detects WAN interface, configures `cake` qdisc at 135000/18000 kbps (90% of line rate), DOCSIS overhead 22 bytes with advanced link layer params, `dual-dsthost` + `ack-filter` shaper, `diffserv4` with `squash_dscp=0` (preserves DSCP for classification)
5. **Kernel tuning** — Writes `/etc/sysctl.d/99-openwrt-optimizations.conf` (buffer sizes, BBR/cake, conntrack, TCP fastopen, `tcp_slow_start_after_idle`, `tcp_mtu_probing`, `netdev_budget`), plus CPU governor → `performance`, RPS on WAN, ethtool GRO/GSO offload, `irqbalance`, firewall hardening, disables `odhcp6c`/`rdisc6`

## Critical Gotchas

- **Must run as root** — script exits immediately if `$(id -u) -ne 0`
- **OpenWrt-only** — uses `uci`, `apk`, OpenWrt init scripts — will not work on stock Linux
- **Idempotent but destructive** — clears previous DNS servers, SQM queues, https-dns-proxy instances before reapplying. DHCP config backup saved to `/etc/config/dhcp.bak`.
- **DNS SafeSearch + blocks are now idempotent** — writes to `/etc/dnsmasq.d/safesearch.conf` with `>` (overwrite), not appending to `/etc/dnsmasq.conf`. Safe to rerun.
- **Sysctl is now idempotent** — writes to `/etc/sysctl.d/99-openwrt-optimizations.conf` with `>` (overwrite), not appending to `/etc/sysctl.conf`.
- **WAN detection fallback** — tries `network.wan.ifname`, then `network.wan.device`, then `ip route`, then hardcodes `eth0.2`. Agent should check this variable after first run.
- **SafeSearch is DNS-based CNAME hijack** — not actual parental controls. Uses dnsmasq `address=` and `cname=` directives to redirect search/youtube domains to restricted versions. Easy to bypass, blocks only a hardcoded adult domain list.
- **Hardcoded speeds** — 135000/18000 kbps. These are 90% of a 150/20 link. Needs adjusting per connection.
- **No rollback logic** — the backup (`/etc/config/dhcp.bak`) is the only safety net. No rollback function exists.

## Patterns & Conventions

- **Shell**: POSIX `#!/bin/sh` — no bashisms
- **Logging**: `exec > >(tee -a "$LOG") 2>&1` captures all output to `/tmp/openwrt_setup.log`
- **UCI patterns**: always `uci set` then `uci commit <section>` then `/etc/init.d/<service> restart`
- **Self-cleaning**: uses `while uci delete ... 2>/dev/null; do :; done` to clear previous config sections
- **Step numbering**: explicit `[N/5]` labels in echo statements
- **Comments**: Spanish-language comments throughout (author appears native Spanish speaker)
- **Error tolerance**: most `apk add` and service commands silently discard errors with `2>/dev/null`

## No Testing / CI

There are no test files, CI configs, or linting scripts in this repo. The script is designed to be manually scp'd to an OpenWrt router and run directly.

## Scope

This is a purpose-specific config generator, not a library or framework. It produces a one-shot router setup. Future work is likely to involve: parameterizing connection speed, adding rollback, supporting other ISPs (fiber/DSL), or splitting into modular step files.
