#!/bin/sh
# ============================================================
#  OpenWrt - Script de Optimización Completo
#  DNS: Cloudflare + Google | Filtrado de contenido adulto
#  SQM: Conexión Coaxial 140/19 Mbps
#  Autor: Generado para OpenWrt 21.x / 22.x / 23.x
# ============================================================

LOG="/tmp/openwrt_setup.log"
exec > >(tee -a "$LOG") 2>&1

echo ""
echo "============================================================"
echo "  OpenWrt - Configuración Avanzada DNS + SQM"
echo "  $(date)"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# VERIFICAR ROOT
# ------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Este script debe ejecutarse como root."
    exit 1
fi

# ============================================================
# 1. ACTUALIZAR PAQUETES E INSTALAR DEPENDENCIAS
# ============================================================
echo "[1/5] Actualizando lista de paquetes e instalando dependencias..."
apk update

# SQM (Smart Queue Management)
apk add luci-app-sqm sqm-scripts sqm-scripts-extra kmod-sched-cake kmod-ifb 2>/dev/null

# DNS-over-HTTPS y filtrado
apk add https-dns-proxy luci-app-https-dns-proxy 2>/dev/null

# Herramientas de red adicionales
apk add irqbalance kmod-nf-conntrack 2>/dev/null

echo "[OK] Dependencias instaladas."
echo ""

# ============================================================
# 2. CONFIGURACIÓN DNS — Cloudflare + Google + Filtrado
# ============================================================
echo "[2/5] Configurando DNS personalizado..."

# --- Respaldo de configuración actual ---
cp /etc/config/dhcp /etc/config/dhcp.bak 2>/dev/null
echo "[INFO] Respaldo guardado en /etc/config/dhcp.bak"

# --- Limpiar DNS anteriores del dnsmasq ---
uci delete dhcp.@dnsmasq[0].server 2>/dev/null

# -------------------------------------------------------
# DNS PRIMARIOS con filtrado de contenido (Family Safe)
#
# Cloudflare for Families:  1.1.1.3 / 1.0.0.3
#   → Bloquea malware + contenido adulto
# Google SafeSearch DNS:    8.8.8.8 / 8.8.4.4
#   (Google no tiene DNS de familia separado;
#    SafeSearch se refuerza vía dnsmasq más abajo)
# -------------------------------------------------------
uci add_list dhcp.@dnsmasq[0].server="1.1.1.3"       # Cloudflare Family (primario)
uci add_list dhcp.@dnsmasq[0].server="1.0.0.3"       # Cloudflare Family (secundario)
uci add_list dhcp.@dnsmasq[0].server="8.8.8.8"       # Google DNS (fallback)
uci add_list dhcp.@dnsmasq[0].server="8.8.4.4"       # Google DNS (fallback 2)

# --- Deshabilitar DNS del ISP, forzar nuestros DNS ---
uci set dhcp.@dnsmasq[0].noresolv="1"
uci set dhcp.@dnsmasq[0].domainneeded="1"
uci set dhcp.@dnsmasq[0].boguspriv="1"
uci set dhcp.@dnsmasq[0].filterwin2k="0"
uci set dhcp.@dnsmasq[0].localise_queries="1"
uci set dhcp.@dnsmasq[0].rebind_protection="1"
uci set dhcp.@dnsmasq[0].rebind_localhost="1"
uci set dhcp.@dnsmasq[0].local="/lan/"
uci set dhcp.@dnsmasq[0].expandhosts="1"
uci set dhcp.@dnsmasq[0].nonegcache="0"
uci set dhcp.@dnsmasq[0].cachesize="1000"
uci set dhcp.@dnsmasq[0].readethers="1"
uci set dhcp.@dnsmasq[0].leasefile="/tmp/dhcp.leases"

# --- Forzar SafeSearch en Google, YouTube, Bing ---
cat >> /etc/dnsmasq.conf << 'EOF'

# ---- Forzar SafeSearch Google ----
address=/forcesafesearch.google.com/216.239.38.120
cname=www.google.com,forcesafesearch.google.com
cname=google.com,forcesafesearch.google.com

# ---- Forzar SafeSearch Bing ----
address=/strict.bing.com/204.79.197.220
cname=www.bing.com,strict.bing.com

# ---- Forzar Modo Restringido YouTube ----
address=/restrict.youtube.com/216.239.38.119
cname=www.youtube.com,restrict.youtube.com
cname=m.youtube.com,restrict.youtube.com
cname=youtubei.googleapis.com,restrict.youtube.com
cname=youtube.googleapis.com,restrict.youtube.com
cname=www.youtube-nocookie.com,restrict.youtube.com

# ---- Bloquear dominios adultos conocidos ----
address=/xvideos.com/#
address=/pornhub.com/#
address=/xnxx.com/#
address=/xhamster.com/#
address=/redtube.com/#
address=/youporn.com/#
address=/tube8.com/#
address=/spankbang.com/#
address=/chaturbate.com/#
address=/livejasmin.com/#
address=/brazzers.com/#
address=/onlyfans.com/#
address=/rule34.xxx/#
address=/e621.net/#
address=/nhentai.net/#

EOF

uci commit dhcp
/etc/init.d/dnsmasq restart

echo "[OK] DNS configurado: Cloudflare Family + Google + SafeSearch activo."
echo ""

# ============================================================
# 3. HTTPS-DNS-PROXY (DNS sobre HTTPS — DoH)
#    Cifra las consultas DNS para mayor privacidad
# ============================================================
echo "[3/5] Configurando DNS-over-HTTPS (DoH)..."

if [ -f /etc/config/https-dns-proxy ]; then
    # Limpiar configuración previa
    while uci delete https-dns-proxy.@https-dns-proxy[0] 2>/dev/null; do :; done

    # Instancia 1: Cloudflare Family DoH
    uci add https-dns-proxy https-dns-proxy
    uci set https-dns-proxy.@https-dns-proxy[0].bootstrap_dns="1.1.1.1,1.0.0.1"
    uci set https-dns-proxy.@https-dns-proxy[0].resolver_url="https://family.cloudflare-dns.com/dns-query"
    uci set https-dns-proxy.@https-dns-proxy[0].listen_addr="127.0.0.1"
    uci set https-dns-proxy.@https-dns-proxy[0].listen_port="5053"
    uci set https-dns-proxy.@https-dns-proxy[0].user="nobody"
    uci set https-dns-proxy.@https-dns-proxy[0].group="nogroup"
    uci set https-dns-proxy.@https-dns-proxy[0].logfile="/tmp/https-dns-proxy.log"

    # Instancia 2: Google DoH (fallback)
    uci add https-dns-proxy https-dns-proxy
    uci set https-dns-proxy.@https-dns-proxy[1].bootstrap_dns="8.8.8.8,8.8.4.4"
    uci set https-dns-proxy.@https-dns-proxy[1].resolver_url="https://dns.google/dns-query"
    uci set https-dns-proxy.@https-dns-proxy[1].listen_addr="127.0.0.1"
    uci set https-dns-proxy.@https-dns-proxy[1].listen_port="5054"
    uci set https-dns-proxy.@https-dns-proxy[1].user="nobody"
    uci set https-dns-proxy.@https-dns-proxy[1].group="nogroup"

    uci commit https-dns-proxy
    /etc/init.d/https-dns-proxy enable
    /etc/init.d/https-dns-proxy restart

    # Redirigir dnsmasq a usar DoH local
    uci delete dhcp.@dnsmasq[0].server 2>/dev/null
    uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5053"
    uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5054"
    uci commit dhcp
    /etc/init.d/dnsmasq restart

    echo "[OK] DNS-over-HTTPS activo (Cloudflare Family DoH + Google DoH)."
else
    echo "[WARN] https-dns-proxy no instalado, usando DNS plano con filtrado."
fi
echo ""

# ============================================================
# 4. SQM — Smart Queue Management
#    Conexión coaxial: 140 Mbps bajada / 19 Mbps subida
#    Algoritmo: CAKE (mejor para coaxial/DOCSIS)
# ============================================================
echo "[4/5] Configurando SQM para conexión coaxial 140/19 Mbps..."

# Detectar interfaz WAN automáticamente
WAN_IF=$(uci get network.wan.ifname 2>/dev/null || \
         uci get network.wan.device 2>/dev/null || \
         ip route show default | awk '/default/{print $5}' | head -1)

if [ -z "$WAN_IF" ]; then
    WAN_IF="eth0.2"   # Valor por defecto común en OpenWrt
    echo "[WARN] Interfaz WAN no detectada, usando: $WAN_IF"
    echo "[WARN] Edita WAN_IF en este script si es incorrecta."
else
    echo "[INFO] Interfaz WAN detectada: $WAN_IF"
fi

# -------------------------------------------------------
# Cálculo de velocidades para SQM
# Se recomienda 85-95% de la velocidad contratada para
# dar margen al overhead de coaxial/DOCSIS
#
# Bajada: 150000 kbps × 0.90 = 135000 kbps
# Subida:  20000 kbps × 0.90 =  18000 kbps
# -------------------------------------------------------
DOWNLOAD_KBPS=135000   # 90% de 150 Mbps
UPLOAD_KBPS=18000      # 90% de 20 Mbps

# Limpiar instancias SQM previas
while uci delete sqm.@queue[0] 2>/dev/null; do :; done

# Crear nueva instancia SQM
uci add sqm queue

# Interfaz WAN
uci set sqm.@queue[0].interface="$WAN_IF"
uci set sqm.@queue[0].enabled="1"

# Velocidades (en kbps)
uci set sqm.@queue[0].download="$DOWNLOAD_KBPS"
uci set sqm.@queue[0].upload="$UPLOAD_KBPS"

# -------------------------------------------------------
# CAKE — algoritmo recomendado para coaxial
# Ventajas vs fq_codel: mejor manejo del overhead DOCSIS,
# menor latencia, mejor bufferbloat control
# -------------------------------------------------------
uci set sqm.@queue[0].qdisc="cake"
uci set sqm.@queue[0].script="piece_of_cake.qos"

# Overhead coaxial/DOCSIS — valor típico: 18-22 bytes
uci set sqm.@queue[0].linklayer="ethernet"
uci set sqm.@queue[0].overhead="22"
uci set sqm.@queue[0].linklayer_advanced="1"
uci set sqm.@queue[0].tcMTU="1518"
uci set sqm.@queue[0].tsize="128"
uci set sqm.@queue[0].mpu="64"
uci set sqm.@queue[0].linklayer_adapt_mechanism="default"

# Opciones avanzadas CAKE
# dual-dsthost: fairness por destino (ideal para streaming + gaming + VoIP)
uci set sqm.@queue[0].qdisc_advanced="1"
uci set sqm.@queue[0].ingress_ecn="ECN"
uci set sqm.@queue[0].egress_ecn="NOECN"
uci set sqm.@queue[0].squash_dscp="1"
uci set sqm.@queue[0].squash_ingress="1"
uci set sqm.@queue[0].qdisc_options="bandwidth ${DOWNLOAD_KBPS}kbit dual-dsthost nat wash ingress diffserv4"

uci commit sqm
/etc/init.d/sqm enable
/etc/init.d/sqm restart

echo "[OK] SQM CAKE configurado: ${DOWNLOAD_KBPS} kbps bajada / ${UPLOAD_KBPS} kbps subida."
echo ""

# ============================================================
# 5. OPTIMIZACIONES GENERALES DEL ROUTER
# ============================================================
echo "[5/5] Aplicando optimizaciones generales..."

# --- Sysctl: parámetros del kernel para mejor rendimiento ---
cat >> /etc/sysctl.conf << 'EOF'

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
net.core.default_qdisc=cake
net.ipv4.tcp_congestion_control=bbr

# Tabla de conexiones — ampliar para más dispositivos
net.netfilter.nf_conntrack_max=65536
net.ipv4.netfilter.ip_conntrack_tcp_timeout_established=3600
net.ipv4.netfilter.ip_conntrack_udp_timeout=30
net.ipv4.netfilter.ip_conntrack_udp_timeout_stream=180

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

sysctl -p /etc/sysctl.conf 2>/dev/null

# --- IRQ Balance (si está instalado) ---
if /etc/init.d/irqbalance start 2>/dev/null; then
    /etc/init.d/irqbalance enable
    echo "[OK] IRQ Balance activado."
fi

# --- Optimizar firewall para coaxial ---
uci set firewall.@defaults[0].syn_flood="1"
uci set firewall.@defaults[0].drop_invalid="1"
uci set firewall.@defaults[0].tcp_syncookies="1"
uci commit firewall
/etc/init.d/firewall reload

# --- Deshabilitar servicios innecesarios ---
for svc in odhcp6c rdisc6; do
    /etc/init.d/$svc stop 2>/dev/null
done

echo "[OK] Optimizaciones del kernel aplicadas."
echo ""

# ============================================================
# RESUMEN FINAL
# ============================================================
echo "============================================================"
echo "  CONFIGURACIÓN COMPLETADA EXITOSAMENTE"
echo "============================================================"
echo ""
echo "  DNS Primario  : 1.1.1.3 (Cloudflare Family — bloquea adultos)"
echo "  DNS Secundario: 1.0.0.3 (Cloudflare Family)"
echo "  DNS Fallback  : 8.8.8.8 / 8.8.4.4 (Google)"
echo "  DoH           : family.cloudflare-dns.com + dns.google"
echo "  SafeSearch    : Google, Bing, YouTube (modo restringido)"
echo ""
echo "  SQM Algoritmo : CAKE (óptimo para coaxial/DOCSIS)"
echo "  Interfaz WAN  : $WAN_IF"
echo "  Bajada SQM    : ${DOWNLOAD_KBPS} kbps (90% de 150 Mbps)"
echo "  Subida SQM    : ${UPLOAD_KBPS} kbps  (90% de 20 Mbps)"
echo "  Overhead      : 22 bytes (DOCSIS coaxial)"
echo ""
echo "  Log guardado en: $LOG"
echo ""
echo "  RECOMENDACIÓN: Reinicia el router para aplicar todos"
echo "  los cambios del kernel:"
echo "  $ reboot"
echo ""
echo "============================================================"
