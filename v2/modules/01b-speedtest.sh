#!/bin/sh
# ============================================================
#  01b-speedtest.sh — Detección automática de velocidad
#  Usa curl para medir download con múltiples intentos.
#  Escribe resultados a /tmp/speedtest_result para que SQM los use.
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 3/10 · Detección de Velocidad"

SPEEDTEST_FILE="/tmp/speedtest_result"
TEST_URL="https://speed.cloudflare.com/__down?bytes=25000000"
WARMUP_URL="https://speed.cloudflare.com/__down?bytes=2000000"
TEST_TIMEOUT=30
TEST_SIZE_MB=45
NUM_TESTS=3

# --- Verificar que curl esté disponible ---
if ! command -v curl >/dev/null 2>&1; then
    warn "curl no disponible. Usando velocidades del config."
    echo "${LINE_SPEED_DOWN}" > "$SPEEDTEST_FILE.down"
    echo "${LINE_SPEED_UP}" > "$SPEEDTEST_FILE.up"
    return 0 2>/dev/null || exit 0
fi

# --- Warm-up: descargar una vez para llenar buffers/cache ---
info "Calentando conexión..."
curl -o /dev/null -s --connect-timeout 5 --max-time 10 "$WARMUP_URL" 2>/dev/null

# --- Ejecutar múltiples tests de descarga ---
info "Midiendo velocidad de descarga (${NUM_TESTS} intentos de ${TEST_SIZE_MB} MB)..."
BEST_DL=0
ATTEMPT=0

while [ "$ATTEMPT" -lt "$NUM_TESTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))

    DL_SPEED=$(curl -o /dev/null -w "%{speed_download}" \
        --connect-timeout 10 \
        --max-time "$TEST_TIMEOUT" \
        -s "$TEST_URL" 2>/dev/null)

    # bytes/s → Mbps
    if [ -n "$DL_SPEED" ] && [ "$DL_SPEED" != "0" ]; then
        DL_MBPS=$(echo "$DL_SPEED" | awk '{printf "%.0f", ($1 * 8) / 1000000}')
    else
        DL_MBPS=0
    fi

    info "  Intento ${ATTEMPT}/${NUM_TESTS}: ${DL_MBPS} Mbps"

    # Quedarse con el mejor resultado
    if [ "$DL_MBPS" -gt "$BEST_DL" ] 2>/dev/null; then
        BEST_DL=$DL_MBPS
    fi

    # Pausa breve entre tests
    [ "$ATTEMPT" -lt "$NUM_TESTS" ] && sleep 2
done

# --- Validar resultado contra config ---
# Si el mejor resultado es menos del 60% del config, el test no es fiable
THRESHOLD=$(( LINE_SPEED_DOWN * 60 / 100 ))

if [ "$BEST_DL" -gt "$THRESHOLD" ] 2>/dev/null; then
    ok "Velocidad de descarga detectada: ${BEST_DL} Mbps (mejor de ${NUM_TESTS} intentos)"

    # Estimar upload usando la proporción del config (más preciso que 13% fijo)
    # Ejemplo: config 150/20 → ratio = 20/150 = 0.133
    UL_MBPS=$(( BEST_DL * LINE_SPEED_UP / LINE_SPEED_DOWN ))
    [ "$UL_MBPS" -lt 1 ] && UL_MBPS=1

    info "Upload estimado: ${UL_MBPS} Mbps (proporción config: ${LINE_SPEED_UP}/${LINE_SPEED_DOWN})"

    echo "$BEST_DL" > "$SPEEDTEST_FILE.down"
    echo "$UL_MBPS" > "$SPEEDTEST_FILE.up"
else
    warn "Speedtest detectó ${BEST_DL} Mbps, menos del 60% de lo contratado (${LINE_SPEED_DOWN} Mbps)."
    warn "Usando velocidades del config como fallback."
    echo "${LINE_SPEED_DOWN}" > "$SPEEDTEST_FILE.down"
    echo "${LINE_SPEED_UP}" > "$SPEEDTEST_FILE.up"
fi
