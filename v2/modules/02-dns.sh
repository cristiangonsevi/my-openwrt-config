#!/bin/sh
# ============================================================
#  02-dns.sh — DNS + SafeSearch + bloqueo adultos
#  Cloudflare Family + Google, filtrado por dnsmasq
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 3/10 · DNS — Cloudflare + Google + Filtrado"

# --- Respaldo de configuración actual (solo si no existe) ---
if [ ! -f /etc/config/dhcp.bak ]; then
    cp /etc/config/dhcp /etc/config/dhcp.bak 2>/dev/null
    info "Respaldo guardado en /etc/config/dhcp.bak"
else
    info "Respaldo ya existe en /etc/config/dhcp.bak (no se sobreescribe)."
fi

# --- Limpiar DNS anteriores del dnsmasq ---
uci delete dhcp.@dnsmasq[0].server 2>/dev/null

# --- DNS primarios con filtrado (Cloudflare Family) ---
uci add_list dhcp.@dnsmasq[0].server="${DNS_PRIMARY}"
uci add_list dhcp.@dnsmasq[0].server="${DNS_SECONDARY}"
uci add_list dhcp.@dnsmasq[0].server="${DNS_FALLBACK1}"
uci add_list dhcp.@dnsmasq[0].server="${DNS_FALLBACK2}"

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
