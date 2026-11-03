#!/bin/sh
# firewall enable.sh v1.8
. "$(dirname "$0")/common.sh"

stop_resolver

# ---- 基本規則：立即生效，不依賴網路 ----
# 為什麼先套基本規則、放行網域之後再補：Wi-Fi 沒開時 DNS 查不到（實測 2026-11-04），
# 舊版在那種情況下一條放行規則都沒加，連上網後也不會補。
iptables -F OUTPUT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
  || iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT \
  || log "ERROR: neither conntrack nor state module is available" "錯誤：conntrack 與 state 模組都無法使用"
iptables -A OUTPUT -j DROP
log "Basic rules applied (WAN blocked)" "基本規則已套用（WAN 已阻斷）"

# ---- 背景重試：解析成功的網域就補上放行規則，全部成功後結束 ----
# 用 -I OUTPUT 1 插在最前面，才會排在 DROP 之前
(
    pending="$(echo $ALLOW_DOMAINS)"
    round=0
    while [ -n "$pending" ]; do
        round=$((round + 1))
        still=""
        for d in $pending; do
            ips="$(resolve_ipv4 "$d")"
            if [ -n "$ips" ]; then
                for ip in $ips; do
                    for port in $ALLOW_PORTS; do
                        iptables -I OUTPUT 1 -p tcp -d "$ip" --dport "$port" -j ACCEPT
                    done
                done
                log "Allowed $d: $(echo $ips)" "已放行上一行的網域"
            else
                still="$still $d"
            fi
        done
        pending="$(echo $still)"
        if [ -n "$pending" ]; then
            [ $((round % RESOLVE_PENDING_LOG_ROUNDS)) -eq 1 ] && log "Not resolved yet, retrying: $pending" "上一行的網域尚未解析，持續重試"
            sleep "$RESOLVE_RETRY_INTERVAL"
        fi
    done
    log "All domains allowed" "全部網域放行完成"
    rm -f "$PIDFILE"
) </dev/null >/dev/null 2>&1 &
echo $! > "$PIDFILE"

notify "Firewall ON (allow-list pending)"
