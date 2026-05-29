#!/bin/sh
# ============================================================
#  Deploy — Copia y ejecuta configuration.sh en el router
#  Uso: sh deploy.sh
# ============================================================

SCRIPT="configuration.sh"
REMOTE_PATH="/tmp/configuration.sh"

# --- Color ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; }

echo ""
echo "  $(printf "${BOLD}Deploy OpenWrt Config${NC}")"
echo ""

# --- Buscar router ---
printf "${CYAN}Detectando router OpenWrt en la red...${NC}\n"
ROUTER_IP=""
for ip in 192.168.1.1 192.168.0.1 10.0.0.1; do
    if ping -c1 -W1 "$ip" >/dev/null 2>&1; then
        ROUTER_IP="$ip"
        break
    fi
done

if [ -z "$ROUTER_IP" ]; then
    printf "${YELLOW}No se detectó automáticamente.${NC}\n"
    printf "IP del router OpenWrt: "
    read -r ROUTER_IP
fi

[ -z "$ROUTER_IP" ] && err "Sin IP. Abortando." && exit 1

# --- Verificar que el script local existe ---
if [ ! -f "$SCRIPT" ]; then
    err "No se encuentra ${SCRIPT} en el directorio actual."
    exit 1
fi

# --- Verificar conectividad ---
printf "Conectando a ${CYAN}${ROUTER_IP}${NC}... "
if ! ping -c1 -W2 "$ROUTER_IP" >/dev/null 2>&1; then
    err "Router no responde."
    exit 1
fi
ok "Router alcanzable."

# --- Autenticación: clave SSH o contraseña ---
SSH_BASE="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${ROUTER_IP}"
USE_PASS=""

# Intentar con clave SSH primero
if ${SSH_BASE} -o PasswordAuthentication=no "echo ok" >/dev/null 2>&1; then
    ok "Autenticado con clave SSH."
else
    # Necesita contraseña
    if ! command -v sshpass >/dev/null 2>&1; then
        err "Se necesita sshpass para usar contraseña."
        warn "Instálalo: sudo apt install sshpass"
        warn "O copia la clave SSH al router:"
        warn "  ssh-copy-id root@${ROUTER_IP}"
        exit 1
    fi

    printf "Contraseña de root@${ROUTER_IP}: "
    stty -echo
    read -r SSH_PASS
    stty echo
    echo ""

    [ -z "$SSH_PASS" ] && err "Contraseña vacía. Abortando." && exit 1

    # Verificar que la contraseña funciona
    if ! sshpass -p "$SSH_PASS" ${SSH_BASE} "echo ok" >/dev/null 2>&1; then
        err "Contraseña incorrecta o acceso SSH denegado."
        exit 1
    fi

    USE_PASS="1"
    ok "Autenticado con contraseña."
fi

# --- Función SSH unificada ---
do_ssh() {
    if [ -n "$USE_PASS" ]; then
        sshpass -p "$SSH_PASS" ${SSH_BASE} "$@"
    else
        ${SSH_BASE} "$@"
    fi
}

# --- Copiar script via SSH pipe (Dropbear no tiene SFTP) ---
printf "Copiando ${CYAN}${SCRIPT}${NC} → ${CYAN}${ROUTER_IP}:${REMOTE_PATH}${NC}...\n"
if [ -n "$USE_PASS" ]; then
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no root@"${ROUTER_IP}" "cat > ${REMOTE_PATH}" < "$SCRIPT"
    COPY_OK=$?
else
    ${SSH_BASE} "cat > ${REMOTE_PATH}" < "$SCRIPT"
    COPY_OK=$?
fi

if [ "$COPY_OK" -eq 0 ]; then
    ok "Script copiado."
else
    err "Fallo al copiar el script."
    exit 1
fi

# --- Ejecutar ---
echo ""
printf "${BOLD}Ejecutando configuration.sh en el router...${NC}\n"
echo ""
do_ssh "sh ${REMOTE_PATH}"
EXIT_CODE=$?

echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
    ok "Completado exitosamente."
else
    warn "Terminó con código ${EXIT_CODE}. Revisa el log:"
    warn "  ssh root@${ROUTER_IP} 'cat /tmp/openwrt_setup.log'"
fi
