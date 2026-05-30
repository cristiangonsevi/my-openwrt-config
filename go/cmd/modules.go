package main

import (
	"strings"
)

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
		"cleanup", "packages", "dns", "adblock",
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