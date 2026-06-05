#!/bin/sh
# ============================================================
#  00-cleanup.sh — Eliminar paquetes conflictivos
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 1/10 · Limpiar Paquetes Conflictivos"

info "Eliminando paquetes que entran en conflicto con esta config..."
for pkg in adblock-fast luci-app-adblock-fast luci-i18n-adblock-fast-es family-dns safe-search nodogsplash; do
    if apk info -e "$pkg" >/dev/null 2>&1; then
        apk del "$pkg" 2>/dev/null && info "Eliminado: $pkg"
    fi
done
ok "Paquetes conflictivos eliminados."
