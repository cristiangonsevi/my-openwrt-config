#!/bin/sh
# ============================================================
#  04-wifi.sh — WiFi principal + invitados + firewall
#  Detecta radios, crea SSIDs, red guest aislada
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 5/10 · WiFi — Principal + Invitados"

# --- Detectar radios WiFi disponibles ---
RADIOS=$(uci show wireless | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1)
if [ -z "$RADIOS" ]; then
    warn "No se detectaron interfaces WiFi. Saltando configuración."
    return 0 2>/dev/null || exit 0
fi

RADIO_COUNT=0

for RADIO in $RADIOS; do
    RADIO_COUNT=$((RADIO_COUNT + 1))

    # Detectar banda (por band o por canal)
    BAND=$(uci get wireless.${RADIO}.band 2>/dev/null)
    CHANNEL=$(uci get wireless.${RADIO}.channel 2>/dev/null)
    [ -z "$BAND" ] && {
        case "$CHANNEL" in
            [1-9]|1[0-4]) BAND="2g" ;;
            3[6-9]|[4-9][0-9]|[1-9][0-9][0-9]) BAND="5g" ;;
        esac
    }

    # Asignar SSID según banda
    case "$BAND" in
        5g|5GHz|5) SSID="${WIFI_SSID_5G}" ;;
        *)          SSID="${WIFI_SSID_24}" ;;
    esac

    # Eliminar TODAS las wifi-iface previas de esta radio (excepto guest)
    uci show wireless | grep "=wifi-iface" | cut -d= -f1 | cut -d. -f2 | while read -r old_iface; do
        dev=$(uci -q get wireless."$old_iface".device 2>/dev/null)
        [ "$dev" = "$RADIO" ] && [ "$old_iface" != "guest" ] && uci delete wireless."$old_iface" 2>/dev/null
    done

    # Crear una única wifi-iface limpia por radio
    IFACE="main_${RADIO}"
    uci set wireless.${IFACE}=wifi-iface
    uci set wireless.${IFACE}.device="${RADIO}"
    uci set wireless.${IFACE}.mode="ap"
    uci set wireless.${IFACE}.ssid="${SSID}"
    uci set wireless.${IFACE}.encryption="sae-mixed"
    uci set wireless.${IFACE}.key="${WIFI_PASS}"
    uci set wireless.${IFACE}.network="lan"

    info "WiFi ${SSID} configurado en ${RADIO} (WPA2/WPA3)."
done

# --- Red invitados (abierta, aislada) ---
GUEST_NET="guest"
FIRST_RADIO=$(echo "$RADIOS" | head -n1)

# Red
uci delete network.${GUEST_NET} 2>/dev/null
uci set network.${GUEST_NET}=interface
uci set network.${GUEST_NET}.proto="static"
uci set network.${GUEST_NET}.ipaddr="${GUEST_IP}"
uci set network.${GUEST_NET}.netmask="${GUEST_MASK}"

# DHCP para invitados
uci delete dhcp.${GUEST_NET} 2>/dev/null
uci set dhcp.${GUEST_NET}=dhcp
uci set dhcp.${GUEST_NET}.interface="${GUEST_NET}"
uci set dhcp.${GUEST_NET}.start="${GUEST_DHCP_START}"
uci set dhcp.${GUEST_NET}.limit="${GUEST_DHCP_LIMIT}"
uci set dhcp.${GUEST_NET}.leasetime="${GUEST_DHCP_LEASE}"

# WiFi invitados
uci delete wireless.${GUEST_NET} 2>/dev/null
uci set wireless.${GUEST_NET}=wifi-iface
uci set wireless.${GUEST_NET}.device="${FIRST_RADIO}"
uci set wireless.${GUEST_NET}.mode="ap"
uci set wireless.${GUEST_NET}.ssid="${GUEST_SSID}"
uci set wireless.${GUEST_NET}.network="${GUEST_NET}"
uci set wireless.${GUEST_NET}.encryption="none"
uci set wireless.${GUEST_NET}.isolate="1"

# Firewall: zona invitados (Internet sí, LAN no)
uci delete firewall.${GUEST_NET} 2>/dev/null
uci set firewall.${GUEST_NET}=zone
uci set firewall.${GUEST_NET}.name="${GUEST_NET}"
uci set firewall.${GUEST_NET}.network="${GUEST_NET}"
uci set firewall.${GUEST_NET}.input="REJECT"
uci set firewall.${GUEST_NET}.forward="REJECT"
uci set firewall.${GUEST_NET}.output="ACCEPT"

# Reglas: DNS + DHCP al router
uci delete firewall.${GUEST_NET}_dns 2>/dev/null
uci set firewall.${GUEST_NET}_dns=rule
uci set firewall.${GUEST_NET}_dns.name="Guest-DNS"
uci set firewall.${GUEST_NET}_dns.src="${GUEST_NET}"
uci set firewall.${GUEST_NET}_dns.dest_port="53"
uci set firewall.${GUEST_NET}_dns.proto="udp"
uci set firewall.${GUEST_NET}_dns.target="ACCEPT"

uci delete firewall.${GUEST_NET}_dhcp 2>/dev/null
uci set firewall.${GUEST_NET}_dhcp=rule
uci set firewall.${GUEST_NET}_dhcp.name="Guest-DHCP"
uci set firewall.${GUEST_NET}_dhcp.src="${GUEST_NET}"
uci set firewall.${GUEST_NET}_dhcp.dest_port="67-68"
uci set firewall.${GUEST_NET}_dhcp.proto="udp"
uci set firewall.${GUEST_NET}_dhcp.target="ACCEPT"

# Forward: invitados → WAN (Internet) con NAT
uci delete firewall.${GUEST_NET}_wan 2>/dev/null
uci set firewall.${GUEST_NET}_wan=forwarding
uci set firewall.${GUEST_NET}_wan.src="${GUEST_NET}"
uci set firewall.${GUEST_NET}_wan.dest="wan"

# Bloquear invitados → LAN
uci delete firewall.${GUEST_NET}_block_lan 2>/dev/null
uci set firewall.${GUEST_NET}_block_lan=rule
uci set firewall.${GUEST_NET}_block_lan.name="Guest-Block-LAN"
uci set firewall.${GUEST_NET}_block_lan.src="${GUEST_NET}"
uci set firewall.${GUEST_NET}_block_lan.dest="lan"
uci set firewall.${GUEST_NET}_block_lan.target="REJECT"

# Permitir acceso al portal cautivo (puerto 2050)
uci delete firewall.${GUEST_NET}_portal 2>/dev/null
uci set firewall.${GUEST_NET}_portal=rule
uci set firewall.${GUEST_NET}_portal.name="Guest-Portal"
uci set firewall.${GUEST_NET}_portal.src="${GUEST_NET}"
uci set firewall.${GUEST_NET}_portal.proto="tcp"
uci set firewall.${GUEST_NET}_portal.dest_port="2050"
uci set firewall.${GUEST_NET}_portal.target="ACCEPT"

uci commit network
uci commit dhcp
uci commit wireless
uci commit firewall

/etc/init.d/network reload
ifup guest 2>/dev/null
wifi reload 2>/dev/null || wifi 2>/dev/null
sleep 3
/etc/init.d/dnsmasq restart
/etc/init.d/firewall reload

ok "WiFi principal ${WIFI_SSID_24} / ${WIFI_SSID_5G} + invitados '${GUEST_SSID}' configurados."
warn "Red invitados SIN contraseña. Agrega clave desde LuCI si lo deseas."
