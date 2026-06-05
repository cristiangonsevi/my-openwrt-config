#!/bin/sh
# ============================================================
#  01b-speedtest.sh — Detección automática de velocidad
#  Usa curl para medir download. Upload se estima si no se puede medir.
#  Escribe resultados a /tmp/speedtest_result para que SQM los use.
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 3/10 · Detección de Velocidad"

SPEEDTEST_FILE="/tmp/speedtest_result"
TEST_URL="https://speed.cloudflare.com/__down?bytes=10000000"
TEST_TIMEOUT=30
TEST_SIZE_MB=10

# --- Verificar que curl esté disponible ---
if ! command -v curl >/dev/null 2>&1; then
    warn "curl no disponible. Usando velocidades del config."
    echo "${LINE_SPEED_DOWN}" > "$SPEEDTEST_FILE.down"
    echo "${LINE_SPEED_UP}" > "$SPEEDTEST_FILE.up"
    return 0 2>/dev/null || exit 0
fi

info "Midiendo velocidad de descarga (puede tomar ~15s)..."

# --- Test de descarga con curl ---
DL_SPEED=$(curl -o /dev/null -w "%{speed_download}" \
    --connect-timeout 10 \
    --max-time "$TEST_TIMEOUT" \
    -s "$TEST_URL" 2>/dev/null)

# curl devuelve bytes/segundo, convertir a Mbps
if [ -n "$DL_SPEED" ] && [ "$DL_SPEED" != "0" ]; then
    # bytes/s → Mbps: (bytes/s * 8) / 1000000
    DL_MBPS=$(echo "$DL_SPEED" | awk '{printf "%.0f", ($1 * 8) / 1000000}')
else
    DL_MBPS=0
fi

# --- Validar resultado ---
if [ "$DL_MBPS" -gt 5 ] 2>/dev/null; then
    ok "Velocidad de descarga detectada: ${DL_MBPS} Mbps"

    # Estimar upload como % del download (no hay test fiable con curl)
    # Conexiones coaxiales típicamente tienen upload ~10-15% del download
    UL_MBPS=$((DL_MBPS * 13 / 100))
    [ "$UL_MBPS" -lt 1 ] && UL_MBPS=1

    info "Upload estimado: ${UL_MBPS} Mbps (13% del download)"

    # Guardar resultados
    echo "$DL_MBPS" > "$SPEEDTEST_FILE.down"
    echo "$UL_MBPS" > "$SPEEDTEST_FILE.up"
else
    warn "Speedtest falló o dio resultado bajo (${DL_MBPS} Mbps)."
    warn "Usando velocidades del config: ${LINE_SPEED_DOWN}/${LINE_SPEED_UP} Mbps."
    echo "${LINE_SPEED_DOWN}" > "$SPEEDTEST_FILE.down"
    echo "${LINE_SPEED_UP}" > "$SPEEDTEST_FILE.up"
fi
