package main

import (
	_ "embed"
	"encoding/base64"
	"strings"
)

//go:embed splash.html
var splashHTML []byte

func splashHTMLBase64() string {
	return base64.StdEncoding.EncodeToString(splashHTML)
}

var modulesScripts = map[string]string{
	"cleanup": `
for pkg in adblock-fast luci-app-adblock-fast luci-i18n-adblock-fast-es family-dns safe-search; do
  if apk info -e "$pkg" >/dev/null 2>&1; then
    apk del "$pkg" 2>/dev/null
  fi
done
echo "cleanup_done"`,

	"packages": `
apk update
apk add luci-app-sqm sqm-scripts sqm-scripts-extra kmod-sched-cake kmod-ifb 2>/dev/null
apk add https-dns-proxy luci-app-https-dns-proxy 2>/dev/null
apk add irqbalance kmod-nf-conntrack kmod-tcp-bbr curl bind-client ethtool 2>/dev/null
apk add nodogsplash iptables-nft kmod-ipt-nat kmod-ipt-core 2>/dev/null
echo "packages_done"`,

	"dns": `
cp /etc/config/dhcp /etc/config/dhcp.bak 2>/dev/null
uci delete dhcp.@dnsmasq[0].server 2>/dev/null
uci add_list dhcp.@dnsmasq[0].server="1.1.1.3"
uci add_list dhcp.@dnsmasq[0].server="1.0.0.3"
uci add_list dhcp.@dnsmasq[0].server="8.8.8.8"
uci add_list dhcp.@dnsmasq[0].server="8.8.4.4"
uci set dhcp.@dnsmasq[0].noresolv="1"
uci set dhcp.@dnsmasq[0].cachesize="4096"
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/safesearch.conf << 'EOF'
max-cache-ttl=3600
min-cache-ttl=300
address=/forcesafesearch.google.com/216.239.38.120
cname=www.google.com,forcesafesearch.google.com
cname=google.com,forcesafesearch.google.com
address=/strict.bing.com/204.79.197.220
cname=www.bing.com,strict.bing.com
address=/restrict.youtube.com/216.239.38.119
cname=www.youtube.com,restrict.youtube.com
cname=m.youtube.com,restrict.youtube.com
EOF
uci commit dhcp
/etc/init.d/dnsmasq restart
echo "dns_done"`,

	"adblock": `
BLOCKLIST_URL="https://raw.githubusercontent.com/emiliodallatorre/adult-hosts-list/refs/heads/main/list.txt"
ADLIST_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
mkdir -p /etc/dnsmasq.d
> /etc/dnsmasq.d/adblock.conf
curl -sL --connect-timeout 10 --max-time 90 "$ADLIST_URL" 2>/dev/null | \
  grep '^0\.0\.0\.0 ' | awk '{print "address=/"$2"/#"}' | \
  grep -v '^0\.0\.0\.0$' | grep -v '^#' | \
  grep -v 'localhost$' | grep -v 'local$' >> /etc/dnsmasq.d/adblock.conf
/etc/init.d/dnsmasq restart
echo "adblock_done"`,

	"wifi": `
RADIOS=$(uci show wireless | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1)
FIRST_RADIO=$(echo "$RADIOS" | head -n1)
for RADIO in $RADIOS; do
  CHANNEL=$(uci get wireless.${RADIO}.channel 2>/dev/null)
  case "$CHANNEL" in
    [1-9]|1[0-4]) SSID="CRISEGO" ;;
    3[6-9]|[4-9][0-9]|[1-9][0-9][0-9]) SSID="CRISEGO-5G" ;;
    *) SSID="CRISEGO" ;;
  esac
  uci show wireless | grep "=wifi-iface" | cut -d= -f1 | cut -d. -f2 | while read -r old; do
    dev=$(uci -q get wireless."$old".device)
    [ "$dev" = "$RADIO" ] && [ "$old" != "guest" ] && uci delete wireless."$old" 2>/dev/null
  done
  IFACE="main_${RADIO}"
  uci set wireless.${IFACE}=wifi-iface
  uci set wireless.${IFACE}.device="${RADIO}"
  uci set wireless.${IFACE}.mode="ap"
  uci set wireless.${IFACE}.ssid="${SSID}"
  uci set wireless.${IFACE}.encryption="sae-mixed"
  uci set wireless.${IFACE}.key="123456789000"
  uci set wireless.${IFACE}.network="lan"
done
# Guest network
uci delete network.guest 2>/dev/null
uci set network.guest=interface
uci set network.guest.proto="static"
uci set network.guest.ipaddr="192.168.3.1"
uci set network.guest.netmask="255.255.255.0"
uci delete dhcp.guest 2>/dev/null
uci set dhcp.guest=dhcp
uci set dhcp.guest.interface="guest"
uci set dhcp.guest.start="100"
uci set dhcp.guest.limit="150"
uci set dhcp.guest.leasetime="2h"
uci delete wireless.guest 2>/dev/null
uci set wireless.guest=wifi-iface
uci set wireless.guest.device="${FIRST_RADIO}"
uci set wireless.guest.mode="ap"
uci set wireless.guest.ssid="CRISEGO-INVITADOS"
uci set wireless.guest.network="guest"
uci set wireless.guest.encryption="none"
uci set wireless.guest.isolate="1"
# Firewall guest
uci delete firewall.guest 2>/dev/null
uci set firewall.guest=zone
uci set firewall.guest.name="guest"
uci set firewall.guest.network="guest"
uci set firewall.guest.input="REJECT"
uci set firewall.guest.forward="REJECT"
uci set firewall.guest.output="ACCEPT"
uci delete firewall.guest_wan 2>/dev/null
uci set firewall.guest_wan=forwarding
uci set firewall.guest_wan.src="guest"
uci set firewall.guest_wan.dest="wan"
uci commit network
uci commit dhcp
uci commit wireless
uci commit firewall
/etc/init.d/network reload
wifi reload 2>/dev/null || wifi
sleep 3
/etc/init.d/dnsmasq restart
echo "wifi_done"`,

	"portal": `
if [ -x /usr/bin/nodogsplash ]; then
  GUEST_IF=$(ip -4 addr show | grep -B2 '192\.168\.3\.' | grep -oE '^[0-9]+: [^:@]+' | awk '{print $2}' | head -1)
  [ -z "$GUEST_IF" ] && GUEST_IF="br-guest"
  cat > /usr/bin/guest-auth.sh << 'AUTH_EOF'
#!/bin/sh
METHOD="$1"
MAC="$2"
SESSION_FILE="/tmp/guest_sessions.txt"
NOW=$(date +%s)
touch "$SESSION_FILE"
if [ "$METHOD" != "auth_client" ]; then
  echo "0 0 0"
  exit 0
fi
LAST=$(grep "^${MAC} " "$SESSION_FILE" 2>/dev/null | awk '{print $2}')
COOLDOWN=21600
TIMEOUT=3600
if [ -z "$LAST" ] || [ $((NOW - LAST)) -ge $COOLDOWN ]; then
  grep -v "^${MAC} " "$SESSION_FILE" > /tmp/guest_tmp 2>/dev/null
  echo "${MAC} ${NOW}" >> /tmp/guest_tmp
  mv /tmp/guest_tmp "$SESSION_FILE"
  echo "$TIMEOUT 0 0"
  exit 0
else
  echo "0 0 0"
  exit 1
fi
AUTH_EOF
  chmod +x /usr/bin/guest-auth.sh
  cat > /etc/nodogsplash/htdocs/splash.html <<'ENDHTML'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CRISEGO-INVITADOS</title>
<style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
:root{--bg:#09090b;--surface:#18181b;--surface-2:#27272a;--border:rgba(255,255,255,0.08);--border-hover:rgba(255,255,255,0.16);--text-primary:#fafafa;--text-muted:#a1a1aa;--text-faint:#52525b;--accent:#f4f4f5;--accent-fg:#18181b;--badge-bg:#27272a;--badge-border:rgba(255,255,255,0.1);--radius:12px;--radius-sm:8px;--radius-xs:6px}
body{font-family:system-ui,-apple-system,sans-serif;background:var(--bg);color:var(--text-primary);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:1rem;background-image:radial-gradient(ellipse 80% 60% at 50% 0%,rgba(255,255,255,0.03) 0%,transparent 60%)}
.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:1.75rem;max-width:360px;width:100%;position:relative;overflow:hidden}
.card::before{content:'';position:absolute;top:0;left:0;right:0;height:1px;background:linear-gradient(90deg,transparent,rgba(255,255,255,0.12),transparent)}
.header{margin-bottom:1.25rem}
.network-badge{display:inline-flex;align-items:center;gap:5px;padding:4px 10px;background:var(--badge-bg);border:1px solid var(--badge-border);border-radius:50px;font-size:0.6875rem;font-weight:500;margin-bottom:0.75rem}
.dot{width:6px;height:6px;background:#22c55e;border-radius:50%;box-shadow:0 0 6px #22c55e88}
h1{font-size:1.5rem;font-weight:600;margin-bottom:0.5rem;letter-spacing:-0.02em}
.subtitle{font-size:0.8125rem;color:var(--text-muted);line-height:1.5}
.divider{height:1px;background:var(--border);margin:1.25rem 0}
.rules-grid{display:flex;flex-direction:column;gap:8px;margin-bottom:1.25rem}
.rule-item{display:flex;align-items:center;gap:10px;padding:10px 12px;background:var(--surface-2);border-radius:var(--radius-xs);font-size:0.8125rem}
.rule-icon{font-size:1rem;width:20px;text-align:center}
.rule-text{flex:1;color:var(--text-muted)}
.rule-value{font-weight:500;color:var(--text-primary)}
form{margin-top:0.5rem}
.btn{width:100%;padding:14px;background:var(--accent);color:var(--accent-fg);border:none;border-radius:var(--radius-sm);font-size:0.9375rem;font-weight:600;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:8px;transition:opacity .15s,transform .1s}
.btn:hover{opacity:0.9}
.btn:active{transform:scale(0.98)}
.btn svg{width:18px;height:18px}
.promo-section{margin-top:1.25rem}
.promo-label{font-size:0.6875rem;font-weight:500;color:var(--text-faint);margin-bottom:8px;text-transform:uppercase;letter-spacing:0.05em}
.promo-cards{display:flex;flex-direction:column;gap:6px}
.promo-card{display:flex;align-items:center;gap:10px;padding:10px 12px;background:var(--surface-2);border:1px solid var(--border);border-radius:var(--radius-sm);text-decoration:none;transition:border-color .15s,background .15s}
.promo-card:hover{border-color:var(--border-hover);background:var(--badge-bg)}
.promo-name{font-size:0.8125rem;font-weight:500;color:var(--text-primary);display:flex;align-items:center;gap:4px}
.promo-name svg{width:11px;height:11px;color:var(--text-faint);flex-shrink:0}
.promo-desc{font-size:0.6875rem;color:var(--text-muted);line-height:1.4}
.footer{margin-top:1rem;text-align:center;font-size:0.6875rem;color:var(--text-faint);letter-spacing:0.02em}
.footer a{color:var(--text-faint);text-decoration:none}
</style>
</head>
<body>
<div class="card">
<div class="header">
<div class="network-badge"><span class="dot"></span>Red de invitados</div>
<h1>CRISEGO-INVITADOS</h1>
<p class="subtitle">Acceso gratuito con limite de tiempo. Acepta las condiciones para continuar.</p>
</div>
<div class="divider"></div>
<div class="rules-grid">
<div class="rule-item"><span class="rule-icon">⏱</span><span class="rule-text">Sesion disponible</span><span class="rule-value">1h</span></div>
<div class="rule-item"><span class="rule-icon">🔄</span><span class="rule-text">Se renueva cada</span><span class="rule-value">6h</span></div>
<div class="rule-item"><span class="rule-icon">🚫</span><span class="rule-text">Contenido adulto</span><span class="rule-value">Bloqueado</span></div>
<div class="rule-item"><span class="rule-icon">📶</span><span class="rule-text">Velocidad maxima</span><span class="rule-value">5 Mbps</span></div>
</div>
<form method="GET" action="$authaction">
<input type="hidden" name="tok" value="$tok">
<input type="hidden" name="redir" value="$redir">
<button type="submit" class="btn">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.55a11 11 0 0 1 14.08 0"/><path d="M1.42 9a16 16 0 0 1 21.16 0"/><path d="M8.53 16.11a6 6 0 0 1 6.95 0"/><line x1="12" y1="20" x2="12.01" y2="20"/></svg>
Conectar a Internet
</button>
</form>
<div class="promo-section">
<div class="promo-label">Patrocinado por</div>
<div class="promo-cards">
<a class="promo-card" href="https://crisego.com" target="_blank" rel="noopener"><span class="promo-name">crisego.com <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg></span><span class="promo-desc">Soluciones y servicios tecnologicos</span></a>
<a class="promo-card" href="https://termisearch.com" target="_blank" rel="noopener"><span class="promo-name">termisearch.com <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg></span><span class="promo-desc">Busqueda y gestion de terminos</span></a>
</div>
</div>
<div class="footer">Powered by OpenWrt - Al conectarte aceptas las condiciones de uso</div>
</div>
</body>
</html>
ENDHTML
  rm -f /tmp/guest_sessions.txt
  killall nodogsplash 2>/dev/null
  sleep 1
  /etc/init.d/nodogsplash enable 2>/dev/null
  /etc/init.d/nodogsplash restart 2>/dev/null
  sleep 2
fi
echo "portal_done"`,

	"doh": `
DOH_CF_URL="https://family.cloudflare-dns.com/dns-query"
DOH_GOOGLE_URL="https://dns.google/dns-query"
if [ -f /etc/config/https-dns-proxy ]; then
  while uci delete https-dns-proxy.@https-dns-proxy[0] 2>/dev/null; do :; done
  uci add https-dns-proxy https-dns-proxy
  uci set https-dns-proxy.@https-dns-proxy[0].bootstrap_dns="1.1.1.3,1.0.0.3"
  uci set https-dns-proxy.@https-dns-proxy[0].resolver_url="${DOH_CF_URL}"
  uci set https-dns-proxy.@https-dns-proxy[0].listen_addr="127.0.0.1"
  uci set https-dns-proxy.@https-dns-proxy[0].listen_port="5053"
  uci add https-dns-proxy https-dns-proxy
  uci set https-dns-proxy.@https-dns-proxy[1].bootstrap_dns="8.8.8.8,8.8.4.4"
  uci set https-dns-proxy.@https-dns-proxy[1].resolver_url="${DOH_GOOGLE_URL}"
  uci set https-dns-proxy.@https-dns-proxy[1].listen_addr="127.0.0.1"
  uci set https-dns-proxy.@https-dns-proxy[1].listen_port="5054"
  uci commit https-dns-proxy
  /etc/init.d/https-dns-proxy enable
  /etc/init.d/https-dns-proxy restart
  uci delete dhcp.@dnsmasq[0].server 2>/dev/null
  uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5053"
  uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5054"
  uci commit dhcp
  /etc/init.d/dnsmasq restart
fi
echo "doh_done"`,

	"sqm": `
DOWN_KBPS=135000
UP_KBPS=18000
WAN_IF=$(uci get network.wan.ifname 2>/dev/null || uci get network.wan.device 2>/dev/null || ip route show default | awk '/default/{print $5}' | head -1)
[ -z "$WAN_IF" ] && WAN_IF="eth0.2"
while uci delete sqm.@queue[0] 2>/dev/null; do :; done
uci add sqm queue
uci set sqm.@queue[0].interface="$WAN_IF"
uci set sqm.@queue[0].enabled="1"
uci set sqm.@queue[0].download="$DOWN_KBPS"
uci set sqm.@queue[0].upload="$UP_KBPS"
uci set sqm.@queue[0].qdisc="cake"
uci set sqm.@queue[0].script="piece_of_cake.qos"
uci set sqm.@queue[0].linklayer="ethernet"
uci set sqm.@queue[0].overhead="22"
uci commit sqm
/etc/init.d/sqm enable
/etc/init.d/sqm restart
echo "sqm_done"`,

	"kernel": `
cat > /etc/sysctl.d/99-openwrt-optimizations.conf << 'EOF'
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.core.netdev_budget=600
net.netfilter.nf_conntrack_max=65536
net.ipv4.ip_forward=1
EOF
sysctl -p /etc/sysctl.d/99-openwrt-optimizations.conf 2>/dev/null
modprobe tcp_bbr 2>/dev/null
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  [ -f "$cpu" ] && echo performance > "$cpu" 2>/dev/null
done
/etc/init.d/irqbalance start 2>/dev/null
/etc/init.d/irqbalance enable 2>/dev/null
echo "kernel_done"`,

	"verify": `
echo "=== VERIFICATION ==="
echo -n "NTP: "
ntpctl -s status 2>/dev/null | grep -qi 'synced' && echo "OK" || echo "FALLO"
echo -n "DNS: "
nslookup google.com 127.0.0.1 >/dev/null 2>&1 && echo "OK" || echo "FALLO"
echo -n "SQM: "
tc -s qdisc show | grep -q cake && echo "OK" || echo "FALLO"
echo -n "BBR: "
sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep bbr && echo "OK" || echo "FALLO"
echo -n "MSS clamp: "
nft list chain inet fw4 forward 2>/dev/null | grep -q maxseg && echo "OK" || echo "FALLO"
echo "=== END VERIFICATION ==="`,
}

func validModules() []string {
	return []string{
		"cleanup", "packages", "dns", "adblock", "wifi", "portal",
		"wifi", "doh", "sqm", "kernel", "verify",
	}
}

func isValidModule(m string) bool {
	for _, v := range validModules() {
		if m == v {
			return true
		}
	}
	return false
}

func filterModules(mods []string) []string {
	var valid []string
	for _, m := range mods {
		m = strings.TrimSpace(strings.ToLower(m))
		if m != "" && moduleExists(m) {
			valid = append(valid, m)
		}
	}
	return valid
}
