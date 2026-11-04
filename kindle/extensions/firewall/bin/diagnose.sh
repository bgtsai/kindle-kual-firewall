#!/bin/sh
# firewall diagnose.sh v1.12
# 收集寫開機自動執行、IPv6 阻擋、飛行模式、Wi-Fi 事件所需的資訊，結果寫到使用者區：
#   extensions/firewall/diagnose.txt             一次性的系統資訊
#   extensions/firewall/diagnose_wifi_events.txt 按下後 WIFI_EVENT_RECORD_S 秒內的 Wi-Fi 事件
#     （按完 Diagnose 後在這段時間內把 Wi-Fi 關掉再打開，才錄得到連線／斷線事件）

BASE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$BASE/diagnose.txt"
EVENTS="$BASE/diagnose_wifi_events.txt"

# 錄製 Wi-Fi 事件的時間 (s)
WIFI_EVENT_RECORD_S=120
# 錄製期間輪詢 cmState／wirelessEnable 的間隔 (s)；lipc-wait-event 參數不支援時靠這個補
WIFI_POLL_INTERVAL_S=3

section() { echo; echo "===== $1 ====="; }

{
    echo "firewall diagnose v1.12  $(date)"

    section "firmware / kernel"
    cat /etc/prettyversion.txt 2>&1
    uname -a 2>&1

    section "tools"
    for t in iptables ip6tables nslookup mntroot initctl eips lipc-get-prop lipc-set-prop lipc-wait-event; do
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

    section "wireless state (lipc)"
    printf 'com.lab126.cmd wirelessEnable: '; lipc-get-prop com.lab126.cmd wirelessEnable 2>&1
    printf 'com.lab126.wifid enable: ';      lipc-get-prop com.lab126.wifid enable 2>&1
    printf 'com.lab126.wifid cmState: ';     lipc-get-prop com.lab126.wifid cmState 2>&1

    section "shutdown / wifi upstart jobs (full text)"
    # 用來決定關機時要掛哪個事件、wifid 怎麼啟動（WIFI_NO_NET_PROBE 是怎麼讀的）
    for f in /etc/upstart/shutdown.conf /etc/upstart/wifid.conf /etc/upstart/wifim.conf /etc/upstart/wifis.conf /etc/upstart/cmd.conf /etc/upstart/network.conf; do
        echo "--- $f"
        cat "$f" 2>&1
    done

    section "upstart jobs mentioning shutdown / runlevel"
    grep -l -E 'shutdown|runlevel|stopping lab126' /etc/upstart/*.conf 2>&1

    section "firewall autostart"
    ls -l /etc/upstart/firewall.conf 2>&1 && cat /etc/upstart/firewall.conf

    section "firewall background process"
    for f in /var/run/firewall_resolver.pid /var/run/firewall_waiter.pid; do
        if [ -f "$f" ]; then
            p="$(cat "$f")"
            if kill -0 "$p" 2>/dev/null; then echo "$f: pid $p running"; else echo "$f: pid $p NOT running"; fi
        else
            echo "$f: (no pid file)"
        fi
    done
    ps 2>&1 | grep -E 'enable\.sh|lipc-wait-event|timeout' | grep -v grep
    printf 'wlan0 IPv4: '; ifconfig wlan0 2>&1 | awk '/inet addr:/ {print $2}'
    echo "FW_ALLOW rules: $(iptables -S FW_ALLOW 2>/dev/null | grep -c ACCEPT)"

    section "firewall Airplane-on-Boot"
    for f in /etc/upstart/firewall_airplane_shutdown.conf /etc/upstart/firewall_airplane_boot.conf; do
        ls -l "$f" 2>&1 && cat "$f"
    done

    section "firewall.log (last 30 lines)"
    tail -n 30 "$(cd "$(dirname "$0")/.." && pwd)/firewall.log" 2>&1

    section "mounts"
    mount 2>&1

    echo; echo "===== end ====="
} > "$OUT" 2>&1

# ---- 背景錄製 Wi-Fi 事件：不拖住 KUAL，時間到自動結束 ----
(
    {
        echo "firewall wifi events v1.12  start $(date)"
        echo "Turn Wi-Fi OFF and ON again within ${WIFI_EVENT_RECORD_S}s."
        echo
    } > "$EVENTS"
    # 參數取自 KOReader frontend/device/kindle/device.lua 的註解：lipc-wait-event -m -s 0 -t com.lab126.wifid '*'
    lipc-wait-event -m -s 0 -t com.lab126.wifid '*' >> "$EVENTS" 2>&1 &
    w1=$!
    lipc-wait-event -m -s 0 -t com.lab126.cmd '*' >> "$EVENTS" 2>&1 &
    w2=$!
    end=$(( $(date +%s) + WIFI_EVENT_RECORD_S ))
    last=""
    while [ "$(date +%s)" -lt "$end" ]; do
        now="poll cmState=$(lipc-get-prop com.lab126.wifid cmState 2>&1) wirelessEnable=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>&1)"
        # 只在狀態改變時記一行，避免檔案被重複內容塞滿
        [ "$now" != "$last" ] && echo "$(date '+%H:%M:%S') $now" >> "$EVENTS"
        last="$now"
        sleep "$WIFI_POLL_INTERVAL_S"
    done
    kill "$w1" "$w2" 2>/dev/null
    echo >> "$EVENTS"; echo "end $(date)" >> "$EVENTS"
    which eips >/dev/null 2>&1 && eips 2 3 "wifi events recorded          " >/dev/null 2>&1
) </dev/null >/dev/null 2>&1 &

# 在螢幕上提示完成（eips 不存在就略過，不影響結果檔）
which eips >/dev/null 2>&1 && eips 2 2 "diagnose.txt written - toggle Wi-Fi now (2 min)" >/dev/null 2>&1
