#!/bin/sh
# firewall common.sh v1.5 — 各腳本共用的路徑與函式

BASE="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$BASE/firewall.log"
PIDFILE="/var/run/firewall_resolver.pid"
UPSTART_CONF="/etc/upstart/firewall.conf"

# 允許連線的網域（KOReader 從 GitHub 更新；Release 下載會轉到 objects.githubusercontent.com）
ALLOW_DOMAINS="api.github.com github.com objects.githubusercontent.com"

# 背景重試解析的間隔 (s)
RESOLVE_RETRY_INTERVAL=30

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# 螢幕提示（eips 不存在就略過）
notify() { which eips >/dev/null 2>&1 && eips 2 2 "$1                    " >/dev/null 2>&1; }

# 解析網域的 IPv4。
# 為什麼不用 awk '/^Address: /'：Kindle 的 busybox nslookup 輸出是「Address 1: 1.2.3.4 名稱」，
# 舊寫法抓不到；第一個 Address 是 DNS 伺服器本身（127.0.0.1），所以只取「Name:」之後的 IPv4。
resolve_ipv4() {
    nslookup "$1" 2>/dev/null | awk '
        /^Name:/ { f = 1; next }
        f && /Address/ {
            for (i = 1; i <= NF; i++)
                if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i
        }'
}

# 停掉先前留下的背景解析程序（重按 Enable 或 Disable 時用）
stop_resolver() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
    fi
}
