# AGENTS.md — OpenWrt Config Repository

## What This Is

OpenWrt shell scripts that configure DNS filtering + SafeSearch + DNS-over-HTTPS + SQM (CAKE) + kernel optimizations + captive portal on an OpenWrt router. Designed for a **coaxial/DOCSIS 150/20 Mbps connection**.

Two versions coexist:
- **v1** (`configuration.sh`) — monolithic single-file script (original)
- **v2** (`v2/`) — modular version, one script per section, openNDS portal, nftables only

## File Structure

```
openwrt-config/
├── AGENTS.md
├── configuration.sh          # v1 — monolithic (original, se conserva)
├── deploy.sh                 # v1 — deployment helper
└── v2/
    ├── run.sh                # v2 — orquestador principal
    ├── deploy.sh             # v2 — deployment helper
    ├── config                # v2 — variables compartidas
    ├── lib.sh                # v2 — funciones helper (ok, warn, err, info, step)
    └── modules/
        ├── 00-cleanup.sh     # Eliminar paquetes conflictivos
        ├── 01-dependencies.sh # Instalar dependencias (apk)
        ├── 02-dns.sh         # DNS + SafeSearch + bloqueo adultos
        ├── 03-adblock.sh     # Bloqueo de anuncios/rastreadores
        ├── 04-wifi.sh        # WiFi principal + invitados + firewall
        ├── 05-portal.sh      # Portal cautivo (openNDS + BinAuth)
        ├── 06-doh.sh         # DNS-over-HTTPS
        ├── 07-sqm.sh         # SQM CAKE (WAN + invitados)
        ├── 08-kernel.sh      # Sysctl + CPU governor + RPS + ethtool
        └── 09-verify.sh      # Verificación final + resumen
```

## Package Manager — OpenWrt switched from `opkg` → `apk`

The scripts use `apk` (newer OpenWrt builds). Compatibility reference:

| Old `opkg` | New `apk` (scripts use) |
|------------|-------------------------|
| `opkg update` | `apk update` |
| `opkg install <pkg>` | `apk add <pkg>` |
| `opkg remove <pkg>` | `apk del <pkg>` |

## Key Commands

| Action | Command |
|--------|---------|
| Run v2 on router | `sh v2/run.sh` (as root) |
| Run single module | `sh v2/run.sh --module 07-sqm.sh` |
| Run v1 on router | `sh configuration.sh` (as root) |
| Deploy v2 to router | `sh v2/deploy.sh` |
| Deploy v1 to router | `sh deploy.sh` |
| View log on router | `cat /tmp/openwrt_setup.log` |
| Verify DNS | `nslookup google.com` or `logread \| grep dnsmasq` |
| Verify SQM | `tc -s qdisc show dev $(uci get network.wan.ifname)` |
| Check SQM status | `sqm status` (if installed) |
| Check DoH proxy | `netstat -tlnp \| grep 5053` |
| Check openNDS | `pgrep opennds` or `ndsctl status` |

## v2 Architecture (10 modules)

1. **00-cleanup** — Removes conflicting packages (`adblock-fast`, `family-dns`, `safe-search`, `nodogsplash`)
2. **01-dependencies** — `apk update` + installs `luci-app-sqm`, `https-dns-proxy`, `irqbalance`, `kmod-tcp-bbr`, `opennds`, `curl`, `ethtool`
3. **02-dns** — Sets dnsmasq to use Cloudflare Family + Google, SafeSearch CNAME overrides, adult domain blocklist, cache tuning
4. **03-adblock** — Downloads StevenBlack hosts list, converts to dnsmasq `address=/.../#` format
5. **04-wifi** — Detects radios, creates WPA2/WPA3 main SSIDs, creates open guest network (192.168.3.0/24), firewall zone isolation
6. **05-portal** — Configures openNDS captive portal via UCI, BinAuth script for MAC-based time control (1h session, 15min cooldown)
7. **06-doh** — Configures two `https-dns-proxy` instances (Cloudflare Family on :5053, Google on :5054), re-points dnsmasq to local DoH
8. **07-sqm** — Auto-detects WAN, configures CAKE qdisc at 90% line rate, DOCSIS overhead 22 bytes, guest SQM at 5 Mbps
9. **08-kernel** — Sysctl tuning (buffers, BBR, conntrack, TCP fastopen), CPU governor → `performance`, RPS on WAN, ethtool GRO/GSO, MSS Clamping via nftables, firewall hardening
10. **09-verify** — Checks DNS, SQM, MSS Clamping, time sync, openNDS; prints summary

## v2 vs v1 Differences

| Aspect | v1 | v2 |
|--------|----|----|
| Structure | Single 1254-line file | 14 files, 10 modules |
| Captive portal | nodogsplash | openNDS (nftables native) |
| iptables | Uses `iptables-nft` | Pure nftables (fw4) |
| Sysctl paths | `net.ipv4.netfilter.ip_conntrack_*` | `net.netfilter.nf_conntrack_*` |
| MSS Clamping | `iptables -t mangle -F` + nft add | nft add with idempotency check |
| DHCP backup | Overwrites every run | Only if backup doesn't exist |
| Guest SQM | Hardcoded 1500 | Uses `${GUEST_SPEED_KBPS}` |
| Run single section | Not possible | `sh run.sh --module XX-name.sh` |

## Critical Gotchas

- **Must run as root** — scripts exit immediately if `$(id -u) -ne 0`
- **OpenWrt-only** — uses `uci`, `apk`, OpenWrt init scripts — will not work on stock Linux
- **v2 is idempotent** — safe to rerun. MSS Clamping checks before adding, DHCP backup preserved, openNDS config cleaned before reapplying
- **openNDS uses fw4 hook** — `option fwhook_enabled '1'` makes openNDS inject nftables rules automatically
- **openNDS splash page** — uses built-in ThemeSpec "click to continue" (`login_option_enabled '1'`), not custom HTML
- **BinAuth signature** — openNDS BinAuth args differ from nodogsplash: `$2=mac $3=originurl $4=useragent $5=ip $6=token $7=custom`
- **WAN detection fallback** — tries `network.wan.ifname`, then `network.wan.device`, then `ip route`, then hardcodes `eth0.2`
- **SafeSearch is DNS-based CNAME hijack** — not actual parental controls. Easy to bypass.
- **Hardcoded speeds** — 135000/18000 kbps (90% of 150/20 link). Edit `v2/config` to adjust.
- **No rollback logic** — the backup (`/etc/config/dhcp.bak`) is the only safety net.

## Patterns & Conventions

- **Shell**: POSIX `#!/bin/sh` — no bashisms (works on OpenWrt's ash/busybox)
- **Config sharing**: each module sources `v2/config` and `v2/lib.sh` via relative path
- **Logging**: `exec > >(tee -a "$LOG") 2>&1` in run.sh captures all output to `/tmp/openwrt_setup.log`
- **UCI patterns**: always `uci set` then `uci commit <section>` then `/etc/init.d/<service> restart`
- **Self-cleaning**: uses `while uci delete ... 2>/dev/null; do :; done` to clear previous config sections
- **Step numbering**: explicit `[N/10]` labels in step() calls
- **Comments**: Spanish-language comments throughout
- **Error tolerance**: most `apk add` and service commands silently discard errors with `2>/dev/null`

## No Testing / CI

There are no test files, CI configs, or linting scripts in this repo. The scripts are designed to be manually scp'd (via `deploy.sh`) to an OpenWrt router and run directly.

## Scope

This is a purpose-specific config generator, not a library or framework. It produces a one-shot router setup. v2 adds modularity for easier maintenance and partial re-runs.
