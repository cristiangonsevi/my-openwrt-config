#!/bin/sh
# ============================================================
#  09-verify.sh — Verificación final + resumen
#  Comprueba DNS, SQM, MSS Clamping, hora
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 10/10 · Verificación Final"

# --- Detectar WAN si no está exportada ---
if [ -z "$WAN_IF" ]; then
    WAN_IF=$(uci get network.wan.ifname 2>/dev/null || \
             uci get network.wan.device 2>/dev/null || \
             ip route show default | awk '/default/{print $5}' | head -1)
    [ -z "$WAN_IF" ] && WAN_IF="${WAN_IF_FALLBACK}"
fi

SPEEDTEST_FILE="/tmp/speedtest_result"
if [ -f "$SPEEDTEST_FILE.down" ] && [ -f "$SPEEDTEST_FILE.up" ]; then
    DETECTED_DOWN=$(cat "$SPEEDTEST_FILE.down")
    DETECTED_UP=$(cat "$SPEEDTEST_FILE.up")
    DOWNLOAD_KBPS=$(( DETECTED_DOWN * 1000 * SQM_PERCENT / 100 ))
    UPLOAD_KBPS=$(( DETECTED_UP * 1000 * SQM_PERCENT / 100 ))
else
    DOWNLOAD_KBPS=$(( LINE_SPEED_DOWN * 1000 * SQM_PERCENT / 100 ))
    UPLOAD_KBPS=$(( LINE_SPEED_UP * 1000 * SQM_PERCENT / 100 ))
fi

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

# --- Verificar openNDS ---
if pgrep opennds >/dev/null 2>&1; then
    ok "Portal cautivo (openNDS) activo."
else
    info "Portal cautivo no activo."
fi

# --- Resumen ---
echo ""
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
printf "  ${CYAN}Portal${NC}        : openNDS (nftables nativo)\n"
printf "  ${CYAN}Sesión${NC}        : ${GUEST_SESSION_MIN} min, cooldown ${GUEST_COOLDOWN_SEC}s\n"
echo ""
