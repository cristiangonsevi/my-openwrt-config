#!/bin/sh
# ============================================================
#  08-kernel.sh — Optimizaciones del kernel y sistema
#  Sysctl, CPU governor, RPS, ethtool, firewall, MSS Clamping
#  Solo nftables (sin iptables). Idempotente.
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 9/10 · Optimizaciones del Kernel y Sistema"

# --- Detectar WAN si no está exportada ---
if [ -z "$WAN_IF" ]; then
    WAN_IF=$(uci get network.wan.ifname 2>/dev/null || \
             uci get network.wan.device 2>/dev/null || \
             ip route show default | awk '/default/{print $5}' | head -1)
    [ -z "$WAN_IF" ] && WAN_IF="${WAN_IF_FALLBACK}"
fi

# --- Sysctl: parámetros del kernel para mejor rendimiento ---
# Paths modernos (net.netfilter.nf_conntrack_* en vez de deprecated net.ipv4.netfilter.ip_conntrack_*)
cat > /etc/sysctl.d/99-openwrt-optimizations.conf << 'EOF'

# ---- Optimizaciones de red OpenWrt ----
# Buffer de red aumentado para coaxial
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# Reducir bufferbloat
net.ipv4.tcp_notsent_lowat=16384

# BBR congestion control (si el kernel lo soporta)
net.ipv4.tcp_congestion_control=bbr

# No resetear cwnd tras idle (evita arranque lento tras pausa)
net.ipv4.tcp_slow_start_after_idle=0

# Path MTU discovery proactivo (útil en DOCSIS con MTU variable)
net.ipv4.tcp_mtu_probing=1

# Más paquetes por ciclo NAPI (mejora throughput en CPU limitada)
net.core.netdev_budget=600
net.core.netdev_budget_usecs=8000

# Tabla de conexiones — ampliar para más dispositivos
# Paths modernos para kernels 5.x+
net.netfilter.nf_conntrack_max=65536
net.netfilter.nf_conntrack_tcp_timeout_established=3600
net.netfilter.nf_conntrack_udp_timeout=30
net.netfilter.nf_conntrack_udp_timeout_stream=180

# Habilitar Fast Open TCP
net.ipv4.tcp_fastopen=3

# Reducir tiempo de cierre de conexiones TCP
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5

# IP Forwarding (requerido para NAT)
net.ipv4.ip_forward=1

EOF

sysctl -p /etc/sysctl.d/99-openwrt-optimizations.conf 2>/dev/null

# --- IRQ Balance (si está instalado) ---
if /etc/init.d/irqbalance start 2>/dev/null; then
    /etc/init.d/irqbalance enable
    ok "IRQ Balance activado."
fi

# --- Cargar módulos del kernel sin reiniciar ---
modprobe tcp_bbr 2>/dev/null && info "Módulo BBR cargado."
modprobe sch_cake 2>/dev/null

# --- CPU Governor: forzar rendimiento máximo ---
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$cpu" ] && echo performance > "$cpu" 2>/dev/null
done
ok "CPU governor: performance."

# --- RPS: distribuir interrupciones de red entre núcleos ---
if [ -n "$WAN_IF" ] && [ -d /sys/class/net/"$WAN_IF"/queues ]; then
    echo 3 > /sys/class/net/"$WAN_IF"/queues/rx-0/rps_cpus 2>/dev/null
    ok "RPS activado en $WAN_IF."
fi

# --- ethtool: habilitar hardware offloading ---
if command -v ethtool >/dev/null 2>&1; then
    ethtool -K "$WAN_IF" gro on gso on 2>/dev/null
    ok "ethtool offloading habilitado en $WAN_IF."
fi

# --- Deshabilitar servicios innecesarios ---
for svc in odhcp6c rdisc6; do
    /etc/init.d/$svc stop 2>/dev/null
done

# --- Optimizar firewall para coaxial ---
uci set firewall.@defaults[0].syn_flood="1"
uci set firewall.@defaults[0].drop_invalid="1"
uci set firewall.@defaults[0].tcp_syncookies="1"
uci commit firewall
/etc/init.d/firewall reload

# --- MSS Clamping (evita fragmentación en DOCSIS) ---
# Solo nftables (fw4) — idempotente, no acumula reglas
if ! nft list chain inet fw4 forward 2>/dev/null | grep -q 'maxseg'; then
    nft add rule inet fw4 forward oifname "$WAN_IF" tcp flags syn / syn,rst counter \
        tcp option maxseg size set rt mtu 2>/dev/null && \
        ok "MSS Clamping activado en $WAN_IF (nftables)." || \
        warn "No se pudo activar MSS Clamping. ¿fw4 está activo?"
else
    ok "MSS Clamping ya estaba activo (nftables)."
fi

ok "Optimizaciones del kernel aplicadas."
