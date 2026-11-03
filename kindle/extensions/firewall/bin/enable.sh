#!/bin/sh
# firewall enable.sh v1.5
. "$(dirname "$0")/common.sh"

stop_resolver

# ---- 基本規則：立即生效，不依賴網路 ----
# 為什麼先套基本規則、GitHub 之後再補：Wi-Fi 沒開時 DNS 查不到 GitHub（實測 2026-11-04），
# 舊版在那種情況下一條 GitHub 規則都沒加，連上網後也不會補。
iptables -F OUTPUT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
  || iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT \
  || log "ERROR: conntrack/state 模組都無法使用"
iptables -A OUTPUT -j DROP
log "基本規則已套用（WAN 已阻斷）"

# ---- 背景重試：解析成功的網域就補上放行規則，全部成功後結束 ----
# 用 -I OUTPUT 1 插在最前面，才會排在 DROP 之前
(
    pending="$ALLOW_DOMAINS"
    while [ -n "$pending" ]; do
        still=""
        for d in $pending; do
            ips="$(resolve_ipv4 "$d")"
            if [ -n "$ips" ]; then
                for ip in $ips; do
                    iptables -I OUTPUT 1 -p tcp -d "$ip" --dport 443 -j ACCEPT
                done
                log "已放行 $d: $(echo $ips)"
            else
                still="$still $d"
            fi
        done
        pending="$(echo $still)"
        [ -n "$pending" ] && sleep "$RESOLVE_RETRY_INTERVAL"
    done
    log "GitHub 放行完成"
    rm -f "$PIDFILE"
) </dev/null >/dev/null 2>&1 &
echo $! > "$PIDFILE"

notify "Firewall ON (GitHub pending)"
