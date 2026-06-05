#!/bin/sh
# ============================================================
#  03-adblock.sh — Bloqueo de anuncios y rastreadores
#  StevenBlack hosts list → dnsmasq
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 4/10 · Bloqueo de Anuncios y Rastreadores"

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

/etc/init.d/dnsmasq restart
