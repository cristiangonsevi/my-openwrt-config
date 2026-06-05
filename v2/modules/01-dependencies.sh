#!/bin/sh
# ============================================================
#  01-dependencies.sh — Instalar dependencias
#  openNDS reemplaza nodogsplash. Sin iptables (nftables nativo).
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$BASE_DIR/config"
. "$BASE_DIR/lib.sh"

step "PASO 2/10 · Paquetes y Dependencias"

apk update

# SQM (Smart Queue Management)
apk add luci-app-sqm sqm-scripts sqm-scripts-extra kmod-sched-cake kmod-ifb 2>/dev/null

# DNS-over-HTTPS y filtrado
apk add https-dns-proxy luci-app-https-dns-proxy 2>/dev/null

# Herramientas de red adicionales
apk add irqbalance kmod-nf-conntrack kmod-tcp-bbr 2>/dev/null

# Prerequisitos para el script (curl/wget para blocklists, bind para nslookup)
apk add curl bind-client ethtool 2>/dev/null

# Portal cautivo (openNDS — sucesor de nodogsplash, nftables nativo)
apk add opennds 2>/dev/null

ok "Dependencias instaladas."
