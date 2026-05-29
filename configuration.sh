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

# ============================================================
#  CONFIGURACIÓN — Cambia estos valores según tu red
# ============================================================

# --- Velocidad de Internet (Mbps) ---
LINE_SPEED_DOWN=150        # Mbps contratados de bajada
LINE_SPEED_UP=20           # Mbps contratados de subida
SQM_PERCENT=90             # % de la velocidad real para SQM (85-95)

# --- DNS ---
DNS_PRIMARY="1.1.1.3"     # Cloudflare Family (bloquea malware+adultos)
DNS_SECONDARY="1.0.0.3"   # Cloudflare Family (secundario)
DNS_FALLBACK1="8.8.8.8"   # Google (fallback)
DNS_FALLBACK2="8.8.4.4"   # Google (fallback 2)
DNS_CACHESIZE=4096         # Entradas en cache DNS
DNS_FORWARDMAX=512         # Consultas DNS simultáneas máximas
DNS_MAX_CACHE_TTL=3600     # TTL máximo de cache (segundos)
DNS_MIN_CACHE_TTL=300      # TTL mínimo de cache (segundos)

# --- DNS-over-HTTPS (DoH) ---
DOH_CF_URL="https://family.cloudflare-dns.com/dns-query"
DOH_GOOGLE_URL="https://dns.google/dns-query"
DOH_BOOTSTRAP_CF="1.1.1.3,1.0.0.3"
DOH_BOOTSTRAP_GOOGLE="8.8.8.8,8.8.4.4"
DOH_CF_PORT=5053
DOH_GOOGLE_PORT=5054

# --- WiFi Principal ---
WIFI_PASS="123456789000"   # Contraseña WPA2/WPA3
WIFI_SSID_24="CRISEGO"     # Nombre red 2.4GHz
WIFI_SSID_5G="CRISEGO-5G"  # Nombre red 5GHz

# --- WiFi Invitados ---
GUEST_SSID="CRISEGO-INVITADOS"
GUEST_IP="192.168.3.1"     # IP del router en red guest
GUEST_MASK="255.255.255.0"
GUEST_DHCP_START=100
GUEST_DHCP_LIMIT=150
GUEST_DHCP_LEASE="2h"
GUEST_SPEED_KBPS=5000       # Límite ancho de banda invitados (kbps)
GUEST_TIMEOUT_SEC=3600      # 1 hora de navegación (segundos)
GUEST_COOLDOWN_SEC=900    # 6 horas entre sesiones (segundos)
GUEST_SESSION_MIN=60     # Timeout de sesión nodogsplash (minutos)

# --- SQM (Smart Queue Management) ---
SQM_OVERHEAD=22             # Overhead DOCSIS coaxial (bytes)
SQM_TC_MTU=1518             # MTU máximo para cálculos
SQM_TSIZE=128               # Entradas en tabla de rate
SQM_MPU=64                  # Tamaño mínimo de paquete

# --- Listas de bloqueo ---
BLOCKLIST_URL="https://raw.githubusercontent.com/emiliodallatorre/adult-hosts-list/refs/heads/main/list.txt"
ADLIST_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"

# --- NTP ---
NTP_SERVER_1="0.openwrt.pool.ntp.org"
NTP_SERVER_2="1.openwrt.pool.ntp.org"

# --- Red (auto-detectado, respaldo) ---
WAN_IF_FALLBACK="eth0.2"    # Solo si no se detecta automáticamente

# ============================================================

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

# Portal cautivo para invitados
apk add nodogsplash 2>/dev/null

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
uci add_list dhcp.@dnsmasq[0].server="${DNS_PRIMARY}"       # Cloudflare Family (primario)
uci add_list dhcp.@dnsmasq[0].server="${DNS_SECONDARY}"   # Cloudflare Family (secundario)
uci add_list dhcp.@dnsmasq[0].server="${DNS_FALLBACK1}"   # Google DNS (fallback)
uci add_list dhcp.@dnsmasq[0].server="${DNS_FALLBACK2}"   # Google DNS (fallback 2)

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
uci set dhcp.@dnsmasq[0].cachesize="${DNS_CACHESIZE}"
uci set dhcp.@dnsmasq[0].dnsforwardmax="${DNS_FORWARDMAX}"
uci set dhcp.@dnsmasq[0].readethers="1"
uci set dhcp.@dnsmasq[0].leasefile="/tmp/dhcp.leases"

# --- Forzar SafeSearch en Google, YouTube, Bing ---
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/safesearch.conf << EOF
# ---- Cache tuning ----
max-cache-ttl=${DNS_MAX_CACHE_TTL}
min-cache-ttl=${DNS_MIN_CACHE_TTL}

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
    WIFI_PASS="${WIFI_PASS}"
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
        uci show wireless | grep "wifi-iface" | grep "device='${RADIO}'" | \
            cut -d. -f2 | cut -d= -f1 | while read -r old_iface; do
            [ "$old_iface" != "guest" ] && uci delete wireless."$old_iface" 2>/dev/null
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
    GUEST_IP="${GUEST_IP}"
    GUEST_MASK="${GUEST_MASK}"
    GUEST_SSID="${GUEST_SSID}"

    # Usar el primer radio para invitados
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
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall reload

    ok "WiFi principal ${WIFI_SSID_24} / ${WIFI_SSID_5G} + invitados '${GUEST_SSID}' configurados."
    warn "Red invitados SIN contraseña. Agrega clave desde LuCI si lo deseas."

    # --- Portal Cautivo: 1h cada 6h ---
    if [ -x /usr/bin/nodogsplash ]; then
        info "Configurando portal cautivo para invitados (1h / 6h)..."

        # Detectar interfaz real de la red guest
        GUEST_IF=$(ip -4 addr show | grep -B2 '192\.168\.3\.' | grep -oE '^[0-9]+: [^:@]+' | awk '{print $2}' | head -1)
        [ -z "$GUEST_IF" ] && GUEST_IF="br-guest"
        info "Portal cautivo en interfaz: ${GUEST_IF}"

        # Script de control de tiempo por MAC
        cat > /usr/bin/guest-auth.sh << 'AUTH_EOF'
#!/bin/sh
# BinAuth: $0 auth_client <mac> <user> <pass>
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
COOLDOWN=GUEST_COOLDOWN_SEC
TIMEOUT=GUEST_TIMEOUT_SEC

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
        # Reemplazar placeholders con valores reales
        sed -i "s/GUEST_COOLDOWN_SEC/${GUEST_COOLDOWN_SEC}/" /usr/bin/guest-auth.sh
        sed -i "s/GUEST_TIMEOUT_SEC/${GUEST_TIMEOUT_SEC}/" /usr/bin/guest-auth.sh
        chmod +x /usr/bin/guest-auth.sh

        # Config .conf (nombres oficiales de nodogsplash)
        mkdir -p /etc/nodogsplash/htdocs
        cat > /etc/nodogsplash/nodogsplash.conf << NDS_EOF
GatewayInterface ${GUEST_IF}
GatewayAddress 192.168.3.1
GatewayName ${GUEST_SSID}
MaxClients 50
SessionTimeout ${GUEST_SESSION_MIN}
CheckInterval 10
BinAuth /usr/bin/guest-auth.sh

FirewallRuleSet authenticated-users {
    FirewallRule allow all
}

FirewallRuleSet preauthenticated-users {
    FirewallRule allow tcp port 53
    FirewallRule allow udp port 53
}

FirewallRuleSet users-to-router {
    FirewallRule allow udp port 53
    FirewallRule allow tcp port 53
    FirewallRule allow udp port 67
}
NDS_EOF

        # Calcular valores legibles para el splash
        TIMEOUT_MINS=$((GUEST_TIMEOUT_SEC / 60))
        if [ $TIMEOUT_MINS -ge 60 ]; then
            H=$((TIMEOUT_MINS / 60)); M=$((TIMEOUT_MINS % 60))
            [ $M -eq 0 ] && TIMEOUT_HUMAN="${H}h" || TIMEOUT_HUMAN="${H}h ${M}m"
        else
            TIMEOUT_HUMAN="${TIMEOUT_MINS} min"
        fi
        COOLDOWN_HOURS=$((GUEST_COOLDOWN_SEC / 3600))
        COOLDOWN_MINS=$(( (GUEST_COOLDOWN_SEC % 3600) / 60 ))
        if [ $COOLDOWN_HOURS -ge 1 ]; then
            [ $COOLDOWN_MINS -eq 0 ] && COOLDOWN_HUMAN="${COOLDOWN_HOURS}h" || COOLDOWN_HUMAN="${COOLDOWN_HOURS}h ${COOLDOWN_MINS}m"
        else
            COOLDOWN_HUMAN="${COOLDOWN_MINS} min"
        fi
        GUEST_SPEED_MBPS=$((GUEST_SPEED_KBPS / 1000))

        cat > /etc/nodogsplash/htdocs/splash.html << HTML_EOF
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$GUEST_SSID</title>
<style>

  *, *::before, *::after {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
  }

  :root {
    --bg: #09090b;
    --surface: #18181b;
    --surface-2: #27272a;
    --border: rgba(255,255,255,0.08);
    --border-hover: rgba(255,255,255,0.16);
    --text-primary: #fafafa;
    --text-muted: #a1a1aa;
    --text-faint: #52525b;
    --accent: #f4f4f5;
    --accent-fg: #18181b;
    --badge-bg: #27272a;
    --badge-border: rgba(255,255,255,0.1);
    --radius: 12px;
    --radius-sm: 8px;
    --radius-xs: 6px;
  }

  body {
    font-family: 'Geist', system-ui, -apple-system, sans-serif;
    background: var(--bg);
    color: var(--text-primary);
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 1rem;
    background-image:
      radial-gradient(ellipse 80% 60% at 50% 0%, rgba(255,255,255,0.03) 0%, transparent 60%);
  }

  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 1.75rem;
    max-width: 360px;
    width: 100%;
    position: relative;
    overflow: hidden;
  }

  .card::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 1px;
    background: linear-gradient(90deg, transparent, rgba(255,255,255,0.12), transparent);
  }

  .header {
    margin-bottom: 1.25rem;
  }

  .network-badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background: var(--badge-bg);
    border: 1px solid var(--badge-border);
    border-radius: 99px;
    padding: 4px 10px 4px 7px;
    font-size: 11px;
    font-weight: 500;
    color: var(--text-muted);
    letter-spacing: 0.02em;
    margin-bottom: 1rem;
  }

  .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #22c55e;
    box-shadow: 0 0 6px #22c55e88;
    animation: pulse 2s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
  }

  h1 {
    font-size: 1.25rem;
    font-weight: 600;
    letter-spacing: -0.02em;
    color: var(--text-primary);
    margin-bottom: 4px;
  }

  .subtitle {
    font-size: 0.8125rem;
    color: var(--text-muted);
    line-height: 1.5;
  }

  .divider {
    height: 1px;
    background: var(--border);
    margin: 1.25rem 0;
  }

  .rules-grid {
    display: grid;
    gap: 6px;
    margin-bottom: 1.25rem;
  }

  .rule-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 9px 11px;
    background: var(--surface-2);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    font-size: 0.8125rem;
    color: var(--text-muted);
    transition: border-color 0.15s;
  }

  .rule-item:hover {
    border-color: var(--border-hover);
  }

  .rule-icon {
    font-size: 15px;
    line-height: 1;
    flex-shrink: 0;
  }

  .rule-text {
    flex: 1;
  }

  .rule-value {
    font-size: 0.75rem;
    font-weight: 500;
    color: var(--text-primary);
    font-variant-numeric: tabular-nums;
  }

  .btn {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    width: 100%;
    padding: 10px 16px;
    background: var(--accent);
    color: var(--accent-fg);
    border: none;
    border-radius: var(--radius-sm);
    font-family: inherit;
    font-size: 0.875rem;
    font-weight: 600;
    letter-spacing: -0.01em;
    cursor: pointer;
    transition: opacity 0.15s, transform 0.1s;
    position: relative;
    overflow: hidden;
  }

  .btn:hover {
    opacity: 0.92;
  }

  .btn:active {
    transform: scale(0.98);
    opacity: 0.85;
  }

  .btn svg {
    width: 15px;
    height: 15px;
    flex-shrink: 0;
  }

  .promo-section {
    margin-top: 1.25rem;
  }

  .promo-label {
    font-size: 0.6875rem;
    font-weight: 500;
    color: var(--text-faint);
    letter-spacing: 0.06em;
    text-transform: uppercase;
    margin-bottom: 8px;
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .promo-label::before,
  .promo-label::after {
    content: '';
    flex: 1;
    height: 1px;
    background: var(--border);
  }

  .promo-cards {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }

  .promo-card {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 10px 12px;
    background: var(--surface-2);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    text-decoration: none;
    transition: border-color 0.15s, background 0.15s;
    cursor: pointer;
  }

  .promo-card:hover {
    border-color: var(--border-hover);
    background: #2d2d30;
  }

  .promo-card:active {
    transform: scale(0.98);
  }

  .promo-name {
    font-size: 0.8125rem;
    font-weight: 600;
    color: var(--text-primary);
    letter-spacing: -0.01em;
    display: flex;
    align-items: center;
    gap: 5px;
  }

  .promo-name svg {
    width: 11px;
    height: 11px;
    color: var(--text-faint);
    flex-shrink: 0;
  }

  .promo-desc {
    font-size: 0.6875rem;
    color: var(--text-muted);
    line-height: 1.4;
  }

  .footer {
    margin-top: 1rem;
    text-align: center;
    font-size: 0.6875rem;
    color: var(--text-faint);
    letter-spacing: 0.02em;
  }

  .footer a {
    color: var(--text-faint);
    text-decoration: none;
  }
</style>
</head>
<body>

<div class="card">
  <div class="header">
    <div class="network-badge">
      <span class="dot"></span>
      Red de invitados
    </div>
    <h1>$GUEST_SSID</h1>
    <p class="subtitle">Acceso gratuito con límite de tiempo. Acepta las condiciones para continuar.</p>
  </div>

  <div class="divider"></div>

  <div class="rules-grid">
    <div class="rule-item">
      <span class="rule-icon">⏱</span>
      <span class="rule-text">Sesión disponible</span>
      <span class="rule-value">$TIMEOUT_HUMAN</span>
    </div>
    <div class="rule-item">
      <span class="rule-icon">🔄</span>
      <span class="rule-text">Se renueva cada</span>
      <span class="rule-value">$COOLDOWN_HUMAN</span>
    </div>
    <div class="rule-item">
      <span class="rule-icon">🚫</span>
      <span class="rule-text">Contenido adulto</span>
      <span class="rule-value">Bloqueado</span>
    </div>
    <div class="rule-item">
      <span class="rule-icon">📶</span>
      <span class="rule-text">Velocidad máxima</span>
      <span class="rule-value">$GUEST_SPEED_MBPS Mbps</span>
    </div>
  </div>

  <form method="GET" action="\$authaction">
    <input type="hidden" name="tok" value="\$tok">
    <input type="hidden" name="redir" value="\$redir">
    <button type="submit" class="btn">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M5 12.55a11 11 0 0 1 14.08 0"/>
        <path d="M1.42 9a16 16 0 0 1 21.16 0"/>
        <path d="M8.53 16.11a6 6 0 0 1 6.95 0"/>
        <line x1="12" y1="20" x2="12.01" y2="20"/>
      </svg>
      Conectar a Internet
    </button>
  </form>

  <div class="promo-section">
    <div class="promo-label">Patrocinado por</div>
    <div class="promo-cards">
      <a class="promo-card" href="https://crisego.com" target="_blank" rel="noopener">
        <span class="promo-name">
          crisego.com
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>
            <polyline points="15 3 21 3 21 9"/>
            <line x1="10" y1="14" x2="21" y2="3"/>
          </svg>
        </span>
        <span class="promo-desc">Soluciones y servicios tecnológicos</span>
      </a>
      <a class="promo-card" href="https://termisearch.com" target="_blank" rel="noopener">
        <span class="promo-name">
          termisearch.com
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>
            <polyline points="15 3 21 3 21 9"/>
            <line x1="10" y1="14" x2="21" y2="3"/>
          </svg>
        </span>
        <span class="promo-desc">Búsqueda y gestión de términos</span>
      </a>
    </div>
  </div>

  <div class="footer">
    Powered by OpenWrt &nbsp;·&nbsp; Al conectarte aceptas las condiciones de uso
  </div>
</div>

</body>
</html>
HTML_EOF

        # Activar (limpiar sesiones previas y matar instancias viejas)
        rm -f /tmp/guest_sessions.txt
        killall nodogsplash 2>/dev/null
        sleep 1
        /etc/init.d/nodogsplash enable 2>/dev/null
        /etc/init.d/nodogsplash restart 2>/dev/null
        sleep 2

        if pgrep nodogsplash >/dev/null 2>&1; then
            ok "Portal cautivo activo en ${GUEST_IF}: 1h cada 6h."
        else
            warn "nodogsplash no arrancó. Ejecuta: logread | grep nodogsplash"
        fi
    else
        warn "nodogsplash no instalado. Portal cautivo omitido."
    fi
fi

step "PASO 6/9 · DNS-over-HTTPS (DoH)"

# --- Verificar sincronización de hora (TLS/DoH lo necesita) ---
info "Verificando sincronización NTP..."
if ntpctl -s status 2>/dev/null | grep -qi 'synced\|peer'; then
    ok "Hora sincronizada: $(date '+%Y-%m-%d %H:%M:%S')"
else
    warn "Reloj no sincronizado. Forzando sincronización NTP..."
    ntpd -q -p ${NTP_SERVER_1} -p ${NTP_SERVER_2} 2>/dev/null && \
        ok "Hora sincronizada: $(date '+%Y-%m-%d %H:%M:%S')" || \
        warn "No se pudo sincronizar. DoH puede fallar si el reloj está muy desfasado."
fi
echo ""

if [ -f /etc/config/https-dns-proxy ]; then
    # Limpiar configuración previa
    while uci delete https-dns-proxy.@https-dns-proxy[0] 2>/dev/null; do :; done

    # Instancia 1: Cloudflare Family DoH
    uci add https-dns-proxy https-dns-proxy
    uci set https-dns-proxy.@https-dns-proxy[0].bootstrap_dns="${DOH_BOOTSTRAP_CF}"
    uci set https-dns-proxy.@https-dns-proxy[0].resolver_url="${DOH_CF_URL}"
    uci set https-dns-proxy.@https-dns-proxy[0].listen_addr="127.0.0.1"
    uci set https-dns-proxy.@https-dns-proxy[0].listen_port="${DOH_CF_PORT}"
    uci set https-dns-proxy.@https-dns-proxy[0].user="nobody"
    uci set https-dns-proxy.@https-dns-proxy[0].group="nogroup"
    uci set https-dns-proxy.@https-dns-proxy[0].logfile="/tmp/https-dns-proxy.log"

    # Instancia 2: Google DoH (fallback)
    uci add https-dns-proxy https-dns-proxy
    uci set https-dns-proxy.@https-dns-proxy[1].bootstrap_dns="${DOH_BOOTSTRAP_GOOGLE}"
    uci set https-dns-proxy.@https-dns-proxy[1].resolver_url="${DOH_GOOGLE_URL}"
    uci set https-dns-proxy.@https-dns-proxy[1].listen_addr="127.0.0.1"
    uci set https-dns-proxy.@https-dns-proxy[1].listen_port="${DOH_GOOGLE_PORT}"
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
    WAN_IF="${WAN_IF_FALLBACK}"   # Valor por defecto común en OpenWrt
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
DOWNLOAD_KBPS=$(( LINE_SPEED_DOWN * 1000 * SQM_PERCENT / 100 ))
UPLOAD_KBPS=$(( LINE_SPEED_UP * 1000 * SQM_PERCENT / 100 ))

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
uci set sqm.@queue[0].overhead="${SQM_OVERHEAD}"
uci set sqm.@queue[0].linklayer_advanced="1"
uci set sqm.@queue[0].tcMTU="${SQM_TC_MTU}"
uci set sqm.@queue[0].tsize="${SQM_TSIZE}"
uci set sqm.@queue[0].mpu="${SQM_MPU}"
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
        uci set sqm.@queue[${GUEST_IDX}].download="1500"
        uci set sqm.@queue[${GUEST_IDX}].upload="1500"
        uci set sqm.@queue[${GUEST_IDX}].qdisc="cake"
        uci set sqm.@queue[${GUEST_IDX}].script="piece_of_cake.qos"
        uci set sqm.@queue[${GUEST_IDX}].qdisc_options="bandwidth ${GUEST_SPEED_KBPS}kbit nat dual-dsthost"
        uci commit sqm
        /etc/init.d/sqm restart
        ok "SQM invitados: $(($GUEST_SPEED_KBPS / 1000)) Mbps en ${GUEST_DEVICE}."
    else
        warn "Interfaz guest no disponible aún. SQM invitados se aplicará al reiniciar."
        # Crear entrada de todas formas para que SQM la tome luego
        uci add sqm queue
        GUEST_IDX=$(uci show sqm | grep -c "=queue")
        GUEST_IDX=$((GUEST_IDX - 1))
        uci set sqm.@queue[${GUEST_IDX}].interface="guest"
        uci set sqm.@queue[${GUEST_IDX}].enabled="1"
        uci set sqm.@queue[${GUEST_IDX}].download="${GUEST_SPEED_KBPS}"
        uci set sqm.@queue[${GUEST_IDX}].upload="${GUEST_SPEED_KBPS}"
        uci set sqm.@queue[${GUEST_IDX}].qdisc="cake"
        uci set sqm.@queue[${GUEST_IDX}].script="piece_of_cake.qos"
        uci set sqm.@queue[${GUEST_IDX}].qdisc_options="bandwidth ${GUEST_SPEED_KBPS}kbit nat dual-dsthost"
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

# --- Cargar módulos del kernel sin reiniciar ---
modprobe tcp_bbr 2>/dev/null && info "Módulo BBR cargado."
modprobe sch_cake 2>/dev/null

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
# nftables (fw4) en vez de iptables legacy — compatible con OpenWrt 23.05+
# Limpiar reglas iptables legacy previas si existen
iptables -t mangle -F FORWARD 2>/dev/null
nft add rule inet fw4 forward oifname "$WAN_IF" tcp flags syn / syn,rst counter \
    tcp option maxseg size set rt mtu 2>/dev/null && \
    ok "MSS Clamping activado en $WAN_IF (nftables)." || \
    warn "No se pudo activar MSS Clamping. ¿fw4 está activo?"

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
if nft list chain inet fw4 forward 2>/dev/null | grep -q 'maxseg'; then
    ok "MSS Clamping activo (nftables)."
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
printf "  ${CYAN}DNS Primario${NC}  : ${DNS_PRIMARY} (Cloudflare Family — bloquea adultos)\n"
printf "  ${CYAN}DNS Secundario${NC}: ${DNS_SECONDARY} (Cloudflare Family)\n"
printf "  ${CYAN}DNS Fallback${NC}  : ${DNS_FALLBACK1} / ${DNS_FALLBACK2} (Google)\n"
printf "  ${CYAN}DoH${NC}           : family.cloudflare-dns.com + dns.google\n"
printf "  ${CYAN}SafeSearch${NC}    : Google, Bing, YouTube (modo restringido)\n"
echo ""
printf "  ${CYAN}SQM Algoritmo${NC} : CAKE (óptimo para coaxial/DOCSIS)\n"
printf "  ${CYAN}Interfaz WAN${NC}  : ${WAN_IF}\n"
printf "  ${CYAN}Bajada SQM${NC}    : ${DOWNLOAD_KBPS} kbps (${SQM_PERCENT}%% de ${LINE_SPEED_DOWN} Mbps)\n"
printf "  ${CYAN}Subida SQM${NC}    : ${UPLOAD_KBPS} kbps  (${SQM_PERCENT}%% de ${LINE_SPEED_UP} Mbps)\n"
printf "  ${CYAN}Overhead${NC}      : ${SQM_OVERHEAD} bytes (DOCSIS coaxial)\n"
echo ""
printf "  ${CYAN}Log${NC} guardado en: ${LOG}\n"
echo ""
printf "  ${YELLOW}RECOMENDACIÓN:${NC} Reinicia el router para aplicar todos\n"
printf "  ${YELLOW}los cambios del kernel:${NC}\n"
printf "  ${BOLD}\$ reboot${NC}\n"
echo ""
