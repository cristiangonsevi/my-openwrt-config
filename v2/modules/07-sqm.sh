#!/bin/sh
# ============================================================
#  07-sqm.sh — SQM CAKE para WAN + invitados
#  CAKE con DOCSIS overhead, dual-dsthost, ack-filter
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 8/10 · SQM — Smart Queue Management"

# --- Verificar que SQM esté instalado ---
if [ ! -x /etc/init.d/sqm ]; then
    warn "SQM no instalado. Intentando instalar..."
    apk add sqm-scripts kmod-sched-cake kmod-ifb 2>&1
    if [ ! -x /etc/init.d/sqm ]; then
        err "SQM no disponible. Saltando configuración SQM."
        return 0 2>/dev/null || exit 0
    fi
fi

# --- Detectar interfaz WAN automáticamente ---
WAN_IF=$(uci get network.wan.ifname 2>/dev/null || \
         uci get network.wan.device 2>/dev/null || \
         ip route show default | awk '/default/{print $5}' | head -1)

if [ -z "$WAN_IF" ]; then
    WAN_IF="${WAN_IF_FALLBACK}"
    warn "Interfaz WAN no detectada, usando: $WAN_IF"
    warn "Edita WAN_IF_FALLBACK en config si es incorrecta."
else
    info "Interfaz WAN detectada: $WAN_IF"
fi

export WAN_IF

# --- Cálculo de velocidades para SQM ---
DOWNLOAD_KBPS=$(( LINE_SPEED_DOWN * 1000 * SQM_PERCENT / 100 ))
UPLOAD_KBPS=$(( LINE_SPEED_UP * 1000 * SQM_PERCENT / 100 ))

# --- Limpiar instancias SQM previas ---
while uci delete sqm.@queue[0] 2>/dev/null; do :; done

# --- Crear nueva instancia SQM WAN ---
uci add sqm queue
uci set sqm.@queue[0].interface="$WAN_IF"
uci set sqm.@queue[0].enabled="1"
uci set sqm.@queue[0].download="$DOWNLOAD_KBPS"
uci set sqm.@queue[0].upload="$UPLOAD_KBPS"

# CAKE — algoritmo recomendado para coaxial
uci set sqm.@queue[0].qdisc="cake"
uci set sqm.@queue[0].script="piece_of_cake.qos"

# Overhead coaxial/DOCSIS
uci set sqm.@queue[0].linklayer="ethernet"
uci set sqm.@queue[0].overhead="${SQM_OVERHEAD}"
uci set sqm.@queue[0].linklayer_advanced="1"
uci set sqm.@queue[0].tcMTU="${SQM_TC_MTU}"
uci set sqm.@queue[0].tsize="${SQM_TSIZE}"
uci set sqm.@queue[0].mpu="${SQM_MPU}"
uci set sqm.@queue[0].linklayer_adapt_mechanism="default"

# Opciones avanzadas CAKE
uci set sqm.@queue[0].qdisc_advanced="1"
uci set sqm.@queue[0].ingress_ecn="ECN"
uci set sqm.@queue[0].egress_ecn="NOECN"
uci set sqm.@queue[0].squash_dscp="0"
uci set sqm.@queue[0].squash_ingress="1"
uci set sqm.@queue[0].qdisc_options="bandwidth ${DOWNLOAD_KBPS}kbit dual-dsthost nat wash ingress ack-filter diffserv4"

uci commit sqm
/etc/init.d/sqm enable
/etc/init.d/sqm restart

ok "SQM CAKE configurado: ${DOWNLOAD_KBPS} kbps bajada / ${UPLOAD_KBPS} kbps subida."

# --- SQM para red de invitados ---
if uci get network.guest >/dev/null 2>&1; then
    GUEST_DEVICE=$(uci get network.guest.device 2>/dev/null)
    if [ -z "$GUEST_DEVICE" ] || ! ip link show "$GUEST_DEVICE" >/dev/null 2>&1; then
        GUEST_DEVICE=$(ip -4 addr show | grep -B2 '192\.168\.3\.' | grep -oE '^[0-9]+: [^:@]+' | awk '{print $2}' | head -1)
    fi
    [ -z "$GUEST_DEVICE" ] && GUEST_DEVICE="guest"

    if ip link show "$GUEST_DEVICE" >/dev/null 2>&1; then
        uci add sqm queue
        GUEST_IDX=$(uci show sqm | grep -c "=queue")
        GUEST_IDX=$((GUEST_IDX - 1))
        uci set sqm.@queue[${GUEST_IDX}].interface="$GUEST_DEVICE"
        uci set sqm.@queue[${GUEST_IDX}].enabled="1"
        uci set sqm.@queue[${GUEST_IDX}].download="${GUEST_SPEED_KBPS}"
        uci set sqm.@queue[${GUEST_IDX}].upload="${GUEST_SPEED_KBPS}"
        uci set sqm.@queue[${GUEST_IDX}].qdisc="cake"
        uci set sqm.@queue[${GUEST_IDX}].script="piece_of_cake.qos"
        uci set sqm.@queue[${GUEST_IDX}].qdisc_options="bandwidth ${GUEST_SPEED_KBPS}kbit nat dual-dsthost"
        uci commit sqm
        /etc/init.d/sqm restart
        ok "SQM invitados: $(($GUEST_SPEED_KBPS / 1000)) Mbps en ${GUEST_DEVICE}."
    else
        warn "Interfaz guest no disponible aún. SQM invitados se aplicará al reiniciar."
        uci add sqm queue
        GUEST_IDX=$(uci show sqm | grep -c "=queue")
        GUEST_IDX=$((GUEST_IDX - 1))
        uci set sqm.@queue[${GUEST_IDX}].interface="guest"
        uci set sqm.@queue[${GUEST_IDX}].enabled="1"
        uci set sqm.@queue[${GUEST_IDX}].download="${GUEST_SPEED_KBPS}"
        uci set sqm.@queue[${GUEST_IDX}].upload="${GUEST_SPEED_KBPS}"
        uci set sqm.@queue[${GUEST_IDX}].qdisc="cake"
        uci set sqm.@queue[${GUEST_IDX}].script="piece_of_cake.qos"
        uci set sqm.@queue[${GUEST_IDX}].qdisc_options="bandwidth ${GUEST_SPEED_KBPS}kbit nat dual-dsthost"
        uci commit sqm
    fi
else
    info "Red de invitados no configurada. SQM invitados omitido."
fi
