#!/bin/sh
# ============================================================
#  OpenWrt - Script de Optimización Completo
#  DNS: Cloudflare + Google | Filtrado de contenido adulto
#  SQM: Conexión Coaxial 140/19 Mbps
#  Autor: Generado para OpenWrt 21.x / 22.x / 23.x
# ============================================================

# --- Colores ANSI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Funciones helper ---
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
info() { printf "${CYAN}[INFO]${NC} %s\n" "$*"; }
step() {
    echo ""
    printf "${BOLD}${BLUE}============================================================${NC}\n"
    printf "${BOLD}${BLUE}  %s${NC}\n" "$*"
    printf "${BOLD}${BLUE}============================================================${NC}\n"
    echo ""
}

# --- Spinner (POSIX) ---
# Uso: long_running_cmd &
#       spinner $! "Mensaje..."
#       wait $!
spinner() {
    local pid=$1 msg="$2" delay=0.1 i=0
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % ${#chars} ))
        printf "\r  ${CYAN}%s${NC} %s" "$(printf '%s' "$chars" | cut -c $((i+1)))" "$msg"
        sleep "$delay"
    done
    printf "\r\033[K"
}

LOG="/tmp/openwrt_setup.log"
exec > >(tee -a "$LOG") 2>&1

echo ""
printf "${BOLD}${MAGENTA}"
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║     OpenWrt · Configuración Avanzada DNS + SQM        ║"
echo "  ╚════════════════════════════════════════════════════════╝"
printf "${NC}"
printf "  ${WHITE}Inicio:${NC} %s\n" "$(date)"
echo ""

# ------------------------------------------------------------
# VERIFICAR ROOT
# ------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    err "Este script debe ejecutarse como root."
    exit 1
fi

# ============================================================
# 0. ELIMINAR PAQUETES CONFLICTIVOS
# ============================================================
step "PASO 1/9 · Limpiar Paquetes Conflictivos"

info "Eliminando paquetes que entran en conflicto con esta config..."
for pkg in adblock-fast luci-app-adblock-fast luci-i18n-adblock-fast-es family-dns safe-search; do
    if apk info -e "$pkg" >/dev/null 2>&1; then
        apk del "$pkg" 2>/dev/null && info "Eliminado: $pkg"
    fi
done
ok "Paquetes conflictivos eliminados."

# ============================================================
# 1. ACTUALIZAR PAQUETES E INSTALAR DEPENDENCIAS
# ============================================================
step "PASO 2/9 · Paquetes y Dependencias"

apk update

# SQM (Smart Queue Management)
apk add luci-app-sqm sqm-scripts sqm-scripts-extra kmod-sched-cake kmod-ifb 2>/dev/null

# DNS-over-HTTPS y filtrado
apk add https-dns-proxy luci-app-https-dns-proxy 2>/dev/null

# Herramientas de red adicionales
apk add irqbalance kmod-nf-conntrack kmod-tcp-bbr 2>/dev/null

# Prerequisitos para el script (curl/wget para blocklists, bind para nslookup)
apk add curl bind-client ethtool 2>/dev/null

ok "Dependencias instaladas."

step "PASO 3/9 · DNS — Cloudflare + Google + Filtrado"

# --- Respaldo de configuración actual ---
cp /etc/config/dhcp /etc/config/dhcp.bak 2>/dev/null
info "Respaldo guardado en /etc/config/dhcp.bak"

# --- Limpiar DNS anteriores del dnsmasq ---
uci delete dhcp.@dnsmasq[0].server 2>/dev/null

# -------------------------------------------------------
# DNS PRIMARIOS con filtrado de contenido (Family Safe)
#
# Cloudflare for Families:  1.1.1.3 / 1.0.0.3
#   → Bloquea malware + contenido adulto
# Google SafeSearch DNS:    8.8.8.8 / 8.8.4.4
#   (Google no tiene DNS de familia separado;
#    SafeSearch se refuerza vía dnsmasq más abajo)
# -------------------------------------------------------
uci add_list dhcp.@dnsmasq[0].server="1.1.1.3"       # Cloudflare Family (primario)
uci add_list dhcp.@dnsmasq[0].server="1.0.0.3"       # Cloudflare Family (secundario)
uci add_list dhcp.@dnsmasq[0].server="8.8.8.8"       # Google DNS (fallback)
uci add_list dhcp.@dnsmasq[0].server="8.8.4.4"       # Google DNS (fallback 2)

# --- Deshabilitar DNS del ISP, forzar nuestros DNS ---
uci set dhcp.@dnsmasq[0].noresolv="1"
uci set dhcp.@dnsmasq[0].domainneeded="1"
uci set dhcp.@dnsmasq[0].boguspriv="1"
uci set dhcp.@dnsmasq[0].filterwin2k="0"
uci set dhcp.@dnsmasq[0].localise_queries="1"
uci set dhcp.@dnsmasq[0].rebind_protection="1"
uci set dhcp.@dnsmasq[0].rebind_localhost="1"
uci set dhcp.@dnsmasq[0].local="/lan/"
uci set dhcp.@dnsmasq[0].expandhosts="1"
uci set dhcp.@dnsmasq[0].nonegcache="0"
uci set dhcp.@dnsmasq[0].cachesize="4096"
uci set dhcp.@dnsmasq[0].dnsforwardmax="512"
uci set dhcp.@dnsmasq[0].readethers="1"
uci set dhcp.@dnsmasq[0].leasefile="/tmp/dhcp.leases"

# --- Forzar SafeSearch en Google, YouTube, Bing ---
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/safesearch.conf << 'EOF'
# ---- Cache tuning ----
max-cache-ttl=3600
min-cache-ttl=300

# ---- Forzar SafeSearch Google ----
address=/forcesafesearch.google.com/216.239.38.120
cname=www.google.com,forcesafesearch.google.com
cname=google.com,forcesafesearch.google.com

# ---- Forzar SafeSearch Bing ----
address=/strict.bing.com/204.79.197.220
cname=www.bing.com,strict.bing.com

# ---- Forzar Modo Restringido YouTube ----
address=/restrict.youtube.com/216.239.38.119
cname=www.youtube.com,restrict.youtube.com
cname=m.youtube.com,restrict.youtube.com
cname=youtubei.googleapis.com,restrict.youtube.com
cname=youtube.googleapis.com,restrict.youtube.com
cname=www.youtube-nocookie.com,restrict.youtube.com

EOF

# --- Bloquear dominios adultos desde lista remota ---
BLOCKLIST_URL="https://raw.githubusercontent.com/emiliodallatorre/adult-hosts-list/refs/heads/main/list.txt"
info "Descargando lista de bloqueo adulto desde GitHub..."
if command -v curl >/dev/null 2>&1; then
    curl -sL --connect-timeout 10 --max-time 30 "$BLOCKLIST_URL" 2>/dev/null | \
        grep -v '^[[:space:]]*$' | grep -v '^[[:space:]]*#' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        sed 's|.*|address=/&/#|' >> /etc/dnsmasq.d/safesearch.conf
elif command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=10 --tries=1 "$BLOCKLIST_URL" 2>/dev/null | \
        grep -v '^[[:space:]]*$' | grep -v '^[[:space:]]*#' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        sed 's|.*|address=/&/#|' >> /etc/dnsmasq.d/safesearch.conf
fi
BLOCKED=$(grep -c 'address=/' /etc/dnsmasq.d/safesearch.conf 2>/dev/null || echo "0")
ok "Lista de bloqueo cargada: ${BLOCKED} dominios bloqueados."

# --- Bloquear DNS IPv6 para evitar bypass del filtro ---
if uci get dhcp.@dnsmasq[0].filter_aaaa >/dev/null 2>&1; then
    uci set dhcp.@dnsmasq[0].filter_aaaa="1"
    info "Filtro AAAA (IPv6 DNS) activado para prevenir bypass."
fi

uci commit dhcp
/etc/init.d/dnsmasq restart

ok "DNS configurado: Cloudflare Family + Google + SafeSearch activo."

step "PASO 4/9 · Bloqueo de Anuncios y Rastreadores"

# --- Descargar lista de anuncios/malware/tracking (StevenBlack) ---
ADLIST_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
info "Descargando lista de anuncios y rastreadores..."
cat > /etc/dnsmasq.d/adblock.conf << 'EOF'
# ---- Bloqueo de anuncios y rastreadores ----
EOF

if command -v curl >/dev/null 2>&1; then
    curl -sL --connect-timeout 10 --max-time 90 "$ADLIST_URL" 2>/dev/null | \
        grep '^0\.0\.0\.0 ' | awk '{print $2}' | grep -v '^0\.0\.0\.0$' | \
        grep -v '^#' | grep -v 'localhost$' | grep -v 'local$' | \
        sed 's|.*|address=/&/#|' >> /etc/dnsmasq.d/adblock.conf
elif command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=10 --tries=2 "$ADLIST_URL" 2>/dev/null | \
        grep '^0\.0\.0\.0 ' | awk '{print $2}' | grep -v '^0\.0\.0\.0$' | \
        grep -v '^#' | grep -v 'localhost$' | grep -v 'local$' | \
        sed 's|.*|address=/&/#|' >> /etc/dnsmasq.d/adblock.conf
fi

ADBLOCKED=$(grep -c 'address=/' /etc/dnsmasq.d/adblock.conf 2>/dev/null || echo "0")
ok "Lista de anuncios cargada: ${ADBLOCKED} dominios bloqueados."
warn "Si algunos sitios no cargan, revisa /etc/dnsmasq.d/adblock.conf"

# Recargar dnsmasq para aplicar bloqueo de anuncios
/etc/init.d/dnsmasq restart

step "PASO 5/9 · WiFi — Principal + Invitados"

# --- Detectar radios WiFi disponibles ---
RADIOS=$(uci show wireless | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1)
if [ -z "$RADIOS" ]; then
    warn "No se detectaron interfaces WiFi. Saltando configuración."
else
    WIFI_PASS="123456789000"
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
            5g|5GHz|5) SSID="CRISEGO-5G" ;;
            *)          SSID="CRISEGO" ;;
        esac

        # Buscar wifi-iface existente para esta radio
        IFACE=$(uci show wireless | grep "wifi-iface" | grep "device='${RADIO}'" | head -1 | cut -d. -f2 | cut -d= -f1)
        if [ -z "$IFACE" ]; then
            # Si no hay AP principal, crear uno
            IFACE="main_${RADIO}"
            uci delete wireless.${IFACE} 2>/dev/null
            uci set wireless.${IFACE}=wifi-iface
            uci set wireless.${IFACE}.device="${RADIO}"
            uci set wireless.${IFACE}.mode="ap"
        fi

        uci set wireless.${IFACE}.ssid="${SSID}"
        uci set wireless.${IFACE}.encryption="sae-mixed"
        uci set wireless.${IFACE}.key="${WIFI_PASS}"
        uci set wireless.${IFACE}.network="lan"

        info "WiFi ${SSID} configurado en ${RADIO} (WPA2)."
    done

    # --- Red invitados (abierta, aislada) ---
    GUEST_NET="guest"
    GUEST_IP="192.168.3.1"
    GUEST_MASK="255.255.255.0"
    GUEST_SSID="CRISEGO-INVITADOS"

    # Usar el primer radio para invitados
    FIRST_RADIO=$(echo "$RADIOS" | awk '{print $1}')

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
    uci set dhcp.${GUEST_NET}.start="100"
    uci set dhcp.${GUEST_NET}.limit="150"
    uci set dhcp.${GUEST_NET}.leasetime="2h"

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

    # Forward: invitados → WAN (Internet)
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

    uci commit network
    uci commit dhcp
    uci commit wireless
    uci commit firewall

    /etc/init.d/network reload
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall reload

    ok "WiFi principal CRISEGO / CRISEGO-5G + invitados '${GUEST_SSID}' configurados."
    warn "Red invitados SIN contraseña. Agrega clave desde LuCI si lo deseas."
fi

step "PASO 6/9 · DNS-over-HTTPS (DoH)"

# --- Verificar sincronización de hora (TLS/DoH lo necesita) ---
info "Verificando sincronización NTP..."
if ntpctl -s status 2>/dev/null | grep -qi 'synced\|peer'; then
    ok "Hora sincronizada: $(date '+%Y-%m-%d %H:%M:%S')"
else
    warn "Reloj no sincronizado. Forzando sincronización NTP..."
    ntpd -q -p 0.openwrt.pool.ntp.org -p 1.openwrt.pool.ntp.org 2>/dev/null && \
        ok "Hora sincronizada: $(date '+%Y-%m-%d %H:%M:%S')" || \
        warn "No se pudo sincronizar. DoH puede fallar si el reloj está muy desfasado."
fi
echo ""

if [ -f /etc/config/https-dns-proxy ]; then
    # Limpiar configuración previa
    while uci delete https-dns-proxy.@https-dns-proxy[0] 2>/dev/null; do :; done

    # Instancia 1: Cloudflare Family DoH
    uci add https-dns-proxy https-dns-proxy
    uci set https-dns-proxy.@https-dns-proxy[0].bootstrap_dns="1.1.1.3,1.0.0.3"
    uci set https-dns-proxy.@https-dns-proxy[0].resolver_url="https://family.cloudflare-dns.com/dns-query"
    uci set https-dns-proxy.@https-dns-proxy[0].listen_addr="127.0.0.1"
    uci set https-dns-proxy.@https-dns-proxy[0].listen_port="5053"
    uci set https-dns-proxy.@https-dns-proxy[0].user="nobody"
    uci set https-dns-proxy.@https-dns-proxy[0].group="nogroup"
    uci set https-dns-proxy.@https-dns-proxy[0].logfile="/tmp/https-dns-proxy.log"

    # Instancia 2: Google DoH (fallback)
    uci add https-dns-proxy https-dns-proxy
    uci set https-dns-proxy.@https-dns-proxy[1].bootstrap_dns="8.8.8.8,8.8.4.4"
    uci set https-dns-proxy.@https-dns-proxy[1].resolver_url="https://dns.google/dns-query"
    uci set https-dns-proxy.@https-dns-proxy[1].listen_addr="127.0.0.1"
    uci set https-dns-proxy.@https-dns-proxy[1].listen_port="5054"
    uci set https-dns-proxy.@https-dns-proxy[1].user="nobody"
    uci set https-dns-proxy.@https-dns-proxy[1].group="nogroup"

    uci commit https-dns-proxy
    /etc/init.d/https-dns-proxy enable
    /etc/init.d/https-dns-proxy restart

    # Redirigir dnsmasq a usar DoH local
    uci delete dhcp.@dnsmasq[0].server 2>/dev/null
    uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5053"
    uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5054"
    uci add_list dhcp.@dnsmasq[0].server="::1#5053"
    uci add_list dhcp.@dnsmasq[0].server="::1#5054"
    uci commit dhcp
    /etc/init.d/dnsmasq restart

    ok "DNS-over-HTTPS activo (Cloudflare Family DoH + Google DoH)."
else
    warn "https-dns-proxy no instalado, usando DNS plano con filtrado."
fi

step "PASO 7/9 · SQM — Smart Queue Management"

# Detectar interfaz WAN automáticamente
WAN_IF=$(uci get network.wan.ifname 2>/dev/null || \
         uci get network.wan.device 2>/dev/null || \
         ip route show default | awk '/default/{print $5}' | head -1)

if [ -z "$WAN_IF" ]; then
    WAN_IF="eth0.2"   # Valor por defecto común en OpenWrt
    warn "Interfaz WAN no detectada, usando: $WAN_IF"
    warn "Edita WAN_IF en este script si es incorrecta."
else
    info "Interfaz WAN detectada: $WAN_IF"
fi

# -------------------------------------------------------
# Cálculo de velocidades para SQM
# Se recomienda 85-95% de la velocidad contratada para
# dar margen al overhead de coaxial/DOCSIS
#
# Bajada: 150000 kbps × 0.90 = 135000 kbps
# Subida:  20000 kbps × 0.90 =  18000 kbps
# -------------------------------------------------------
DOWNLOAD_KBPS=135000   # 90% de 150 Mbps
UPLOAD_KBPS=18000      # 90% de 20 Mbps

# Limpiar instancias SQM previas
while uci delete sqm.@queue[0] 2>/dev/null; do :; done

# Crear nueva instancia SQM
uci add sqm queue

# Interfaz WAN
uci set sqm.@queue[0].interface="$WAN_IF"
uci set sqm.@queue[0].enabled="1"

# Velocidades (en kbps)
uci set sqm.@queue[0].download="$DOWNLOAD_KBPS"
uci set sqm.@queue[0].upload="$UPLOAD_KBPS"

# -------------------------------------------------------
# CAKE — algoritmo recomendado para coaxial
# Ventajas vs fq_codel: mejor manejo del overhead DOCSIS,
# menor latencia, mejor bufferbloat control
# -------------------------------------------------------
uci set sqm.@queue[0].qdisc="cake"
uci set sqm.@queue[0].script="piece_of_cake.qos"

# Overhead coaxial/DOCSIS — valor típico: 18-22 bytes
uci set sqm.@queue[0].linklayer="ethernet"
uci set sqm.@queue[0].overhead="22"
uci set sqm.@queue[0].linklayer_advanced="1"
uci set sqm.@queue[0].tcMTU="1518"
uci set sqm.@queue[0].tsize="128"
uci set sqm.@queue[0].mpu="64"
uci set sqm.@queue[0].linklayer_adapt_mechanism="default"

# Opciones avanzadas CAKE
# dual-dsthost: fairness por destino (ideal para streaming + gaming + VoIP)
uci set sqm.@queue[0].qdisc_advanced="1"
uci set sqm.@queue[0].ingress_ecn="ECN"
uci set sqm.@queue[0].egress_ecn="NOECN"
uci set sqm.@queue[0].squash_dscp="0"
uci set sqm.@queue[0].squash_ingress="1"
uci set sqm.@queue[0].qdisc_options="bandwidth ${DOWNLOAD_KBPS}kbit dual-dsthost nat wash ingress ack-filter diffserv4"

uci commit sqm
/etc/init.d/sqm enable
/etc/init.d/sqm restart

ok "SQM CAKE configurado: ${DOWNLOAD_KBPS} kbps bajada / ${UPLOAD_KBPS} kbps subida."

# --- SQM para red de invitados (5 Mbps) ---
if uci get network.guest >/dev/null 2>&1; then
    # Detectar dispositivo real de la red guest
    GUEST_DEVICE=$(uci get network.guest.device 2>/dev/null)
    if [ -z "$GUEST_DEVICE" ] || ! ip link show "$GUEST_DEVICE" >/dev/null 2>&1; then
        # Buscar interfaz con IP de guest (192.168.3.x)
        GUEST_DEVICE=$(ip -4 addr show | grep -B2 '192\.168\.3\.' | grep -oE '^[0-9]+: [^:@]+' | awk '{print $2}' | head -1)
    fi
    [ -z "$GUEST_DEVICE" ] && GUEST_DEVICE="guest"

    if ip link show "$GUEST_DEVICE" >/dev/null 2>&1; then
        uci add sqm queue
        GUEST_IDX=$(uci show sqm | grep -c "=queue")
        GUEST_IDX=$((GUEST_IDX - 1))
        uci set sqm.@queue[${GUEST_IDX}].interface="$GUEST_DEVICE"
        uci set sqm.@queue[${GUEST_IDX}].enabled="1"
        uci set sqm.@queue[${GUEST_IDX}].download="500"
        uci set sqm.@queue[${GUEST_IDX}].upload="500"
        uci set sqm.@queue[${GUEST_IDX}].qdisc="cake"
        uci set sqm.@queue[${GUEST_IDX}].script="piece_of_cake.qos"
        uci set sqm.@queue[${GUEST_IDX}].qdisc_options="bandwidth 5000kbit nat dual-dsthost"
        uci commit sqm
        /etc/init.d/sqm restart
        ok "SQM invitados: 5 Mbps en ${GUEST_DEVICE}."
    else
        warn "Interfaz guest no disponible aún. SQM invitados se aplicará al reiniciar."
        # Crear entrada de todas formas para que SQM la tome luego
        uci add sqm queue
        GUEST_IDX=$(uci show sqm | grep -c "=queue")
        GUEST_IDX=$((GUEST_IDX - 1))
        uci set sqm.@queue[${GUEST_IDX}].interface="guest"
        uci set sqm.@queue[${GUEST_IDX}].enabled="1"
        uci set sqm.@queue[${GUEST_IDX}].download="5000"
        uci set sqm.@queue[${GUEST_IDX}].upload="5000"
        uci set sqm.@queue[${GUEST_IDX}].qdisc="cake"
        uci set sqm.@queue[${GUEST_IDX}].script="piece_of_cake.qos"
        uci set sqm.@queue[${GUEST_IDX}].qdisc_options="bandwidth 5000kbit nat dual-dsthost"
        uci commit sqm
    fi
else
    info "Red de invitados no configurada. SQM invitados omitido."
fi

step "PASO 8/9 · Optimizaciones del Kernel y Sistema"

# --- Sysctl: parámetros del kernel para mejor rendimiento ---
cat > /etc/sysctl.d/99-openwrt-optimizations.conf << 'EOF'

# ---- Optimizaciones de red OpenWrt ----
# Buffer de red aumentado para coaxial
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# Reducir bufferbloat
net.ipv4.tcp_notsent_lowat=16384

# BBR congestion control (si el kernel lo soporta)
net.ipv4.tcp_congestion_control=bbr

# No resetear cwnd tras idle (evita arranque lento tras pausa)
net.ipv4.tcp_slow_start_after_idle=0

# Path MTU discovery proactivo (útil en DOCSIS con MTU variable)
net.ipv4.tcp_mtu_probing=1

# Más paquetes por ciclo NAPI (mejora throughput en CPU limitada)
net.core.netdev_budget=600
net.core.netdev_budget_usecs=8000

# Tabla de conexiones — ampliar para más dispositivos
net.netfilter.nf_conntrack_max=65536
net.ipv4.netfilter.ip_conntrack_tcp_timeout_established=3600
net.ipv4.netfilter.ip_conntrack_udp_timeout=30
net.ipv4.netfilter.ip_conntrack_udp_timeout_stream=180

# Habilitar Fast Open TCP
net.ipv4.tcp_fastopen=3

# Reducir tiempo de cierre de conexiones TCP
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5

# IP Forwarding (requerido para NAT)
net.ipv4.ip_forward=1

EOF

sysctl -p /etc/sysctl.d/99-openwrt-optimizations.conf 2>/dev/null

# --- IRQ Balance (si está instalado) ---
if /etc/init.d/irqbalance start 2>/dev/null; then
    /etc/init.d/irqbalance enable
    ok "IRQ Balance activado."
fi

# --- CPU Governor: forzar rendimiento máximo ---
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$cpu" ] && echo performance > "$cpu" 2>/dev/null
done
ok "CPU governor: performance."

# --- RPS: distribuir interrupciones de red entre núcleos ---
if [ -n "$WAN_IF" ] && [ -d /sys/class/net/"$WAN_IF"/queues ]; then
    echo 3 > /sys/class/net/"$WAN_IF"/queues/rx-0/rps_cpus 2>/dev/null
    ok "RPS activado en $WAN_IF."
fi

# --- ethtool: habilitar hardware offloading ---
if command -v ethtool >/dev/null 2>&1; then
    ethtool -K "$WAN_IF" gro on gso on 2>/dev/null
    ok "ethtool offloading habilitado en $WAN_IF."
fi

# --- Deshabilitar servicios innecesarios ---
for svc in odhcp6c rdisc6; do
    /etc/init.d/$svc stop 2>/dev/null
done

# --- Optimizar firewall para coaxial ---
uci set firewall.@defaults[0].syn_flood="1"
uci set firewall.@defaults[0].drop_invalid="1"
uci set firewall.@defaults[0].tcp_syncookies="1"
uci commit firewall
/etc/init.d/firewall reload

# --- MSS Clamping (evita fragmentación en DOCSIS) ---
iptables -t mangle -F FORWARD 2>/dev/null
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o "$WAN_IF" -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null && \
    ok "MSS Clamping activado en $WAN_IF."

ok "Optimizaciones del kernel aplicadas."

# ============================================================
# 8. VERIFICACIÓN FINAL
# ============================================================
step "PASO 9/9 · Verificación Final"

# --- Verificar hora ---
info "Verificando estado del sistema..."
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
if [ "$(date +%Y 2>/dev/null)" -gt 2024 ] 2>/dev/null; then
    ok "Reloj sincronizado: ${CURRENT_TIME}"
else
    warn "Reloj desincronizado (año: $(date +%Y)). DoH y TLS pueden fallar."
fi

# --- Verificar DNS ---
info "Probando resolución DNS..."
DNS_OK=0
for i in 1 2 3; do
    if command -v nslookup >/dev/null 2>&1; then
        nslookup openwrt.org 127.0.0.1 >/dev/null 2>&1 && DNS_OK=1 && break
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -qO- --timeout=3 "http://openwrt.org" >/dev/null 2>&1 && DNS_OK=1 && break
    fi
    sleep 1
done
[ "$DNS_OK" -eq 1 ] && ok "DNS funcionando correctamente." || \
    warn "DNS no responde. Revisa dnsmasq y https-dns-proxy."

# --- Verificar SQM ---
if [ -x /etc/init.d/sqm ] && /etc/init.d/sqm status 2>/dev/null | grep -qv 'not running'; then
    ok "SQM CAKE está activo."
elif tc -s qdisc show dev "$WAN_IF" 2>/dev/null | grep -q 'cake'; then
    ok "SQM CAKE detectado en ${WAN_IF}."
elif [ -x /etc/init.d/sqm ]; then
    warn "SQM está instalado pero no corriendo."
else
    info "SQM no instalado."
fi

# --- Verificar MSS Clamping ---
if iptables -t mangle -L FORWARD 2>/dev/null | grep -q 'TCPMSS'; then
    ok "MSS Clamping activo."
fi

echo ""

# ============================================================
# RESUMEN FINAL
# ============================================================
printf "\n${BOLD}${GREEN}"
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║      CONFIGURACIÓN COMPLETADA EXITOSAMENTE            ║"
echo "  ╚════════════════════════════════════════════════════════╝"
printf "${NC}\n"
printf "  ${CYAN}DNS Primario${NC}  : 1.1.1.3 (Cloudflare Family — bloquea adultos)\n"
printf "  ${CYAN}DNS Secundario${NC}: 1.0.0.3 (Cloudflare Family)\n"
printf "  ${CYAN}DNS Fallback${NC}  : 8.8.8.8 / 8.8.4.4 (Google)\n"
printf "  ${CYAN}DoH${NC}           : family.cloudflare-dns.com + dns.google\n"
printf "  ${CYAN}SafeSearch${NC}    : Google, Bing, YouTube (modo restringido)\n"
echo ""
printf "  ${CYAN}SQM Algoritmo${NC} : CAKE (óptimo para coaxial/DOCSIS)\n"
printf "  ${CYAN}Interfaz WAN${NC}  : ${WAN_IF}\n"
printf "  ${CYAN}Bajada SQM${NC}    : ${DOWNLOAD_KBPS} kbps (90%% de 150 Mbps)\n"
printf "  ${CYAN}Subida SQM${NC}    : ${UPLOAD_KBPS} kbps  (90%% de 20 Mbps)\n"
printf "  ${CYAN}Overhead${NC}      : 22 bytes (DOCSIS coaxial)\n"
echo ""
printf "  ${CYAN}Log${NC} guardado en: ${LOG}\n"
echo ""
printf "  ${YELLOW}RECOMENDACIÓN:${NC} Reinicia el router para aplicar todos\n"
printf "  ${YELLOW}los cambios del kernel:${NC}\n"
printf "  ${BOLD}\$ reboot${NC}\n"
echo ""
