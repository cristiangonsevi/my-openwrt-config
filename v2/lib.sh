#!/bin/sh
# ============================================================
#  lib.sh — Funciones helper compartidas
#  Source este archivo desde cada módulo y desde run.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

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

# Cargar config si no está ya cargada
load_config() {
    if [ -z "$CONFIG_LOADED" ]; then
        BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
        . "$BASE_DIR/config"
        CONFIG_LOADED=1
    fi
}
