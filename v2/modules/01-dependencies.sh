#!/bin/sh
# ============================================================
#  01-dependencies.sh — Instalar dependencias
#  openNDS reemplaza nodogsplash. Sin iptables (nftables nativo).
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 2/10 · Paquetes y Dependencias"

apk update

# SQM (Smart Queue Management)
# Nota: sqm-scripts-extra puede no existir en todas las versiones
apk add luci-app-sqm sqm-scripts kmod-sched-cake kmod-ifb || \
    warn "SQM: algunos paquetes no se instalaron. Verifica con: apk list | grep sqm"

# DNS-over-HTTPS y filtrado
apk add https-dns-proxy luci-app-https-dns-proxy || \
    warn "DoH: algunos paquetes no se instalaron."

# Herramientas de red adicionales
apk add irqbalance kmod-nf-conntrack kmod-tcp-bbr 2>/dev/null

# Prerequisitos para el script (curl/wget para blocklists, bind para nslookup)
apk add curl bind-client ethtool 2>/dev/null

# Portal cautivo (openNDS — sucesor de nodogsplash, nftables nativo)
apk add opennds || warn "openNDS no se instaló."

ok "Dependencias instaladas."

# --- Verificar que SQM quedó instalado ---
if [ -x /etc/init.d/sqm ]; then
    ok "SQM verificado: /etc/init.d/sqm existe."
else
    warn "SQM no instalado correctamente. Intentando instalar sqm-scripts solo..."
    apk add sqm-scripts 2>&1
    if [ -x /etc/init.d/sqm ]; then
        ok "SQM instalado (solo sqm-scripts)."
    else
        err "SQM no disponible. Instala manualmente: apk add sqm-scripts"
    fi
fi
