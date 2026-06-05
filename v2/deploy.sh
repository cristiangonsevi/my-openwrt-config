#!/bin/sh
# ============================================================
#  deploy.sh v2 — Copia y ejecuta la config modular en el router
#  Uso: sh deploy.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE_DIR="/tmp/openwrt-v2"

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
echo "  $(printf "${BOLD}Deploy OpenWrt Config v2 (Modular)${NC}")"
echo ""

# --- Verificar estructura ---
if [ ! -f "$SCRIPT_DIR/run.sh" ] || [ ! -d "$SCRIPT_DIR/modules" ]; then
    err "Estructura v2 no encontrada. Ejecuta desde el directorio v2/."
    exit 1
fi

# --- Buscar router ---
printf "${CYAN}Detectando router OpenWrt en la red...${NC}\n"
ROUTER_IP=""
for ip in 192.168.1.1 192.168.200.1 192.168.0.1 10.0.0.1; do
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

# --- Verificar conectividad ---
printf "Conectando a ${CYAN}${ROUTER_IP}${NC}... "
if ! ping -c1 -W2 "$ROUTER_IP" >/dev/null 2>&1; then
    err "Router no responde."
    exit 1
fi
ok "Router alcanzable."

# --- Autenticación ---
SSH_BASE="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${ROUTER_IP}"
USE_PASS=""

if ${SSH_BASE} -o PasswordAuthentication=no "echo ok" >/dev/null 2>&1; then
    ok "Autenticado con clave SSH."
else
    if ! command -v sshpass >/dev/null 2>&1; then
        err "Se necesita sshpass para usar contraseña."
        warn "Instálalo: sudo apt install sshpass"
        warn "O copia la clave SSH al router: ssh-copy-id root@${ROUTER_IP}"
        exit 1
    fi

    printf "Contraseña de root@${ROUTER_IP}: "
    stty -echo
    read -r SSH_PASS
    stty echo
    echo ""

    [ -z "$SSH_PASS" ] && err "Contraseña vacía. Abortando." && exit 1

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

# --- Empaquetar y enviar v2/ ---
printf "Empaquetando directorio v2/...\n"
TARFILE="/tmp/openwrt-v2-$(date +%s).tar"
tar cf "$TARFILE" -C "$SCRIPT_DIR" .

printf "Copiando a ${CYAN}${ROUTER_IP}:${REMOTE_DIR}${NC}...\n"
do_ssh "mkdir -p ${REMOTE_DIR}" 2>/dev/null

# Usar pipe SSH en vez de scp (Dropbear no tiene sftp-server)
cat "$TARFILE" | do_ssh "cat > ${REMOTE_DIR}/pkg.tar"
COPY_OK=$?
rm -f "$TARFILE"

if [ "$COPY_OK" -eq 0 ]; then
    ok "Paquete copiado."
else
    err "Fallo al copiar el paquete."
    exit 1
fi

# --- Extraer y ejecutar ---
echo ""
printf "${BOLD}Ejecutando run.sh en el router...${NC}\n"
echo ""
do_ssh "cd ${REMOTE_DIR} && tar xf pkg.tar && sh run.sh"
EXIT_CODE=$?

echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
    ok "Completado exitosamente."
else
    warn "Terminó con código ${EXIT_CODE}. Revisa el log:"
    warn "  ssh root@${ROUTER_IP} 'cat /tmp/openwrt_setup.log'"
fi

# --- ¿Reiniciar router? ---
echo ""
printf "${YELLOW}¿Reiniciar el router ahora para aplicar módulos del kernel?${NC} [s/N]: "
read -r REBOOT_ANS
case "$REBOOT_ANS" in
    [sS]|[sS][iI]|[yY]|[yY][eE][sS])
        echo ""
        printf "${BOLD}Reiniciando ${ROUTER_IP}...${NC}\n"
        do_ssh "reboot" 2>/dev/null
        ok "Router reiniciándose. Volverá en ~30 segundos."
        ;;
    *)
        warn "No se reinició. Algunos cambios del kernel esperan al próximo reinicio."
        ;;
esac
