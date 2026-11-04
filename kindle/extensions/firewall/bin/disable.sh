#!/bin/sh
# firewall disable.sh v1.10
. "$(dirname "$0")/common.sh"

stop_resolver

# 清除阻斷規則並恢復預設放行
iptables -F OUTPUT
iptables -F "$ALLOW_CHAIN" 2>/dev/null
iptables -X "$ALLOW_CHAIN" 2>/dev/null
iptables -P OUTPUT ACCEPT
log "Firewall disabled (all traffic allowed)" "防火牆已關閉（全部放行）"
notify "Firewall OFF"
