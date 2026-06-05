#!/bin/sh
# ============================================================
#  05-portal.sh — Portal cautivo con openNDS
#  openNDS reemplaza a nodogsplash. Nftables nativo vía fw4.
#  BinAuth controla tiempo de sesión por MAC (cooldown).
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 6/10 · Portal Cautivo (openNDS)"

if ! command -v opennds >/dev/null 2>&1 && [ ! -x /usr/bin/opennds ]; then
    warn "openNDS no instalado. Portal cautivo omitido."
    return 0 2>/dev/null || exit 0
fi

info "Configurando portal cautivo con openNDS..."

# --- Detectar interfaz real de la red guest ---
GUEST_IF=$(ip -4 addr show | grep -B2 '192\.168\.3\.' | grep -oE '^[0-9]+: [^:@]+' | awk '{print $2}' | head -1)
[ -z "$GUEST_IF" ] && GUEST_IF="br-guest"
info "Portal cautivo en interfaz: ${GUEST_IF}"

# --- Deploy custom dark theme ---
MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$MODULE_DIR/files/theme_dark.sh" ]; then
    cp "$MODULE_DIR/files/theme_dark.sh" /usr/lib/opennds/theme_dark.sh 2>/dev/null
    chmod +x /usr/lib/opennds/theme_dark.sh 2>/dev/null
    info "Dark theme deployado a /usr/lib/opennds/theme_dark.sh"
else
    warn "theme_dark.sh no encontrado, usando tema por defecto."
fi

# --- Script BinAuth para control de tiempo por MAC ---
# openNDS BinAuth args para auth_client:
#   $1=method $2=mac $3=originurl $4=useragent $5=ip $6=token $7=custom
# Output: echo "$sessiontimeout $upload_rate $download_rate $upload_quota $download_quota"
# Exit: 0=allow, 1=deny
cat > /usr/bin/guest-auth.sh << 'AUTH_EOF'
#!/bin/sh
METHOD="$1"
MAC="$2"
SESSION_FILE="/tmp/guest_sessions.txt"
NOW=$(date +%s)
touch "$SESSION_FILE"

COOLDOWN=GUEST_COOLDOWN_SEC
TIMEOUT=GUEST_TIMEOUT_SEC_MIN

UPLOAD_RATE=0
DOWNLOAD_RATE=0
UPLOAD_QUOTA=0
DOWNLOAD_QUOTA=0

if [ "$METHOD" != "auth_client" ]; then
    exit 0
fi

LAST=$(grep "^${MAC} " "$SESSION_FILE" 2>/dev/null | awk '{print $2}')

if [ -z "$LAST" ] || [ $((NOW - LAST)) -ge $COOLDOWN ]; then
    grep -v "^${MAC} " "$SESSION_FILE" > /tmp/guest_tmp 2>/dev/null
    echo "${MAC} ${NOW}" >> /tmp/guest_tmp
    mv /tmp/guest_tmp "$SESSION_FILE"
    echo "$TIMEOUT $UPLOAD_RATE $DOWNLOAD_RATE $UPLOAD_QUOTA $DOWNLOAD_QUOTA"
    exit 0
else
    echo "0 0 0 0 0"
    exit 1
fi
AUTH_EOF

sed -i "s/GUEST_COOLDOWN_SEC/${GUEST_COOLDOWN_SEC}/" /usr/bin/guest-auth.sh
sed -i "s/GUEST_TIMEOUT_SEC_MIN/${GUEST_SESSION_MIN}/" /usr/bin/guest-auth.sh
chmod +x /usr/bin/guest-auth.sh

# --- Limpiar config previa de openNDS ---
while uci delete opennds.@opennds[0] 2>/dev/null; do :; done

# --- Configurar openNDS vía UCI ---
uci set opennds.cfg0=opennds
uci set opennds.cfg0.enabled='1'
uci set opennds.cfg0.gatewayinterface="${GUEST_IF}"
uci set opennds.cfg0.gatewayname="${GUEST_SSID}"
uci set opennds.cfg0.gatewayport='2050'
uci set opennds.cfg0.maxclients='50'
uci set opennds.cfg0.sessiontimeout="${GUEST_SESSION_MIN}"
uci set opennds.cfg0.preauthidletimeout='30'
uci set opennds.cfg0.authidletimeout='120'
uci set opennds.cfg0.checkinterval='10'
uci set opennds.cfg0.login_option_enabled='3'
uci set opennds.cfg0.themespec_path='/usr/lib/opennds/theme_dark.sh'
uci set opennds.cfg0.fwhook_enabled='1'
uci set opennds.cfg0.dhcp_default_url_enable='1'
uci set opennds.cfg0.enable_serial_number_suffix='0'
uci set opennds.cfg0.gatewayfqdn='disable'
uci set opennds.cfg0.debuglevel='1'
uci set opennds.cfg0.max_page_size='20480'
uci set opennds.cfg0.binauth='/usr/bin/guest-auth.sh'

# Acceso DNS/DHCP para invitados no autenticados
uci -q delete opennds.cfg0.users_to_router
uci add_list opennds.cfg0.users_to_router='allow udp port 53'
uci add_list opennds.cfg0.users_to_router='allow tcp port 53'
uci add_list opennds.cfg0.users_to_router='allow udp port 67'

uci commit opennds
/etc/init.d/opennds enable 2>/dev/null
/etc/init.d/opennds restart 2>/dev/null
sleep 2

if pgrep opennds >/dev/null 2>&1; then
    ok "Portal cautivo (openNDS) activo en ${GUEST_IF}: ${GUEST_SESSION_MIN}min, cooldown ${GUEST_COOLDOWN_SEC}s."
else
    warn "openNDS no arrancó. Ejecuta: logread | grep opennds"
fi
