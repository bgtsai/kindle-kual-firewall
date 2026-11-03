#!/bin/sh
# firewall disable.sh v1.8
. "$(dirname "$0")/common.sh"

stop_resolver

# 清除阻斷規則並恢復預設放行
iptables -F OUTPUT
iptables -P OUTPUT ACCEPT
log "Firewall disabled (all traffic allowed)" "防火牆已關閉（全部放行）"
notify "Firewall OFF"
