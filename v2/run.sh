#!/bin/sh
# ============================================================
#  run.sh — Orquestador principal v2
#  Ejecuta todos los módulos en orden
#  Uso: sh run.sh [--module 02-dns.sh]
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SCRIPT_DIR

. "$SCRIPT_DIR/lib.sh"
. "$SCRIPT_DIR/config"
export CONFIG_LOADED=1

LOG="/tmp/openwrt_setup.log"

# Ejecutar todo dentro de un bloque que teea al log y consola
# Compatible con ash/busybox (OpenWrt) sin process substitution
_main() {

echo ""
printf "${BOLD}${MAGENTA}"
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║     OpenWrt v2 · Configuración Modular                ║"
echo "  ╚════════════════════════════════════════════════════════╝"
printf "${NC}"
printf "  ${WHITE}Inicio:${NC} %s\n" "$(date)"
echo ""

# --- Verificar root ---
if [ "$(id -u)" -ne 0 ]; then
    err "Este script debe ejecutarse como root."
    exit 1
fi

# --- Modo módulo único ---
if [ "$1" = "--module" ] && [ -n "$2" ]; then
    MOD="$SCRIPT_DIR/modules/$2"
    if [ -f "$MOD" ]; then
        info "Ejecutando módulo: $2"
        sh "$MOD"
        exit $?
    else
        err "Módulo no encontrado: $2"
        err "Módulos disponibles:"
        ls "$SCRIPT_DIR"/modules/[0-9]*.sh 2>/dev/null | while read -r f; do
            printf "  - %s\n" "$(basename "$f")"
        done
        exit 1
    fi
fi

# --- Ejecutar todos los módulos en orden ---
TOTAL=0
PASSED=0
FAILED=0

for MOD in "$SCRIPT_DIR"/modules/[0-9]*.sh; do
    [ -f "$MOD" ] || continue
    MOD_NAME=$(basename "$MOD")
    TOTAL=$((TOTAL + 1))

    if sh "$MOD"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        warn "Módulo ${MOD_NAME} terminó con errores."
    fi
done

# --- Resumen final ---
echo ""
printf "\n${BOLD}${GREEN}"
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║      CONFIGURACIÓN COMPLETADA                         ║"
echo "  ╚════════════════════════════════════════════════════════╝"
printf "${NC}\n"

printf "  ${CYAN}Módulos ejecutados${NC}: ${TOTAL}\n"
printf "  ${CYAN}Exitosos${NC}         : ${GREEN}${PASSED}${NC}\n"
if [ "$FAILED" -gt 0 ]; then
    printf "  ${CYAN}Con errores${NC}      : ${RED}${FAILED}${NC}\n"
fi
echo ""
printf "  ${CYAN}Log${NC} guardado en: ${LOG}\n"
echo ""
printf "  ${YELLOW}RECOMENDACIÓN:${NC} Reinicia el router para aplicar todos\n"
printf "  ${YELLOW}los cambios del kernel:${NC}\n"
printf "  ${BOLD}\$ reboot${NC}\n"
echo ""

} # fin de _main

# Ejecutar _main con output a consola Y log (compatible con ash)
_main "$@" 2>&1 | tee -a "$LOG"
exit ${PIPESTATUS[0]:-0}
