#!/bin/sh
# firewall diagnose.sh v1.5
# 收集寫開機自動執行與 IPv6 阻擋所需的資訊，結果寫到使用者區，
# USB 連電腦時位於 extensions/firewall/diagnose.txt

OUT="$(cd "$(dirname "$0")/.." && pwd)/diagnose.txt"

section() { echo; echo "===== $1 ====="; }

{
    echo "firewall diagnose v1.5  $(date)"

    section "firmware / kernel"
    cat /etc/prettyversion.txt 2>&1
    uname -a 2>&1

    section "tools"
    for t in iptables ip6tables nslookup mntroot initctl eips; do
        printf '%s: ' "$t"; which "$t" 2>/dev/null || echo "(not found)"
    done

    section "nslookup github.com (raw output, to verify parsing)"
    nslookup github.com 2>&1

    section "resolv.conf (which DNS server)"
    cat /etc/resolv.conf 2>&1

    section "IPv6 addresses"
    ip -6 addr show 2>&1 || cat /proc/net/if_inet6 2>&1

    section "iptables -L -n -v"
    iptables -L -n -v 2>&1

    section "ip6tables -L -n -v"
    ip6tables -L -n -v 2>&1

    section "conntrack / state modules"
    iptables -m conntrack -h >/dev/null 2>&1 && echo "conntrack: OK" || echo "conntrack: FAIL"
    iptables -m state -h >/dev/null 2>&1 && echo "state: OK" || echo "state: FAIL"

    section "/etc/upstart file list"
    ls -l /etc/upstart/ 2>&1

    section "upstart start/stop triggers"
    for f in /etc/upstart/*.conf; do
        echo "--- $f"
        grep -E '^[[:space:]]*(start on|stop on|emits)' "$f" 2>/dev/null
    done

    section "firewall autostart"
    ls -l /etc/upstart/firewall.conf 2>&1 && cat /etc/upstart/firewall.conf

    section "firewall.log (last 30 lines)"
    tail -n 30 "$(cd "$(dirname "$0")/.." && pwd)/firewall.log" 2>&1

    section "mounts"
    mount 2>&1

    echo; echo "===== end ====="
} > "$OUT" 2>&1

# 在螢幕上提示完成（eips 不存在就略過，不影響結果檔）
which eips >/dev/null 2>&1 && eips 2 2 "diagnose.txt written" >/dev/null 2>&1
