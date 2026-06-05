#!/bin/sh
# ============================================================
#  06-doh.sh — DNS-over-HTTPS
#  Cloudflare Family + Google vía https-dns-proxy
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 7/10 · DNS-over-HTTPS (DoH)"

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

if [ ! -f /etc/config/https-dns-proxy ]; then
    warn "https-dns-proxy no instalado, usando DNS plano con filtrado."
    return 0 2>/dev/null || exit 0
fi

# --- Limpiar configuración previa ---
while uci delete https-dns-proxy.@https-dns-proxy[0] 2>/dev/null; do :; done

# --- Instancia 1: Cloudflare Family DoH ---
uci add https-dns-proxy https-dns-proxy
uci set https-dns-proxy.@https-dns-proxy[0].bootstrap_dns="${DOH_BOOTSTRAP_CF}"
uci set https-dns-proxy.@https-dns-proxy[0].resolver_url="${DOH_CF_URL}"
uci set https-dns-proxy.@https-dns-proxy[0].listen_addr="127.0.0.1"
uci set https-dns-proxy.@https-dns-proxy[0].listen_port="${DOH_CF_PORT}"
uci set https-dns-proxy.@https-dns-proxy[0].user="nobody"
uci set https-dns-proxy.@https-dns-proxy[0].group="nogroup"
uci set https-dns-proxy.@https-dns-proxy[0].logfile="/tmp/https-dns-proxy.log"

# --- Instancia 2: Google DoH (fallback) ---
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

# --- Redirigir dnsmasq a usar DoH local ---
uci delete dhcp.@dnsmasq[0].server 2>/dev/null
uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5053"
uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5054"
uci add_list dhcp.@dnsmasq[0].server="::1#5053"
uci add_list dhcp.@dnsmasq[0].server="::1#5054"
uci commit dhcp
/etc/init.d/dnsmasq restart

ok "DNS-over-HTTPS activo (Cloudflare Family DoH + Google DoH)."
