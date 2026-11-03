#!/bin/sh
# firewall common.sh v1.7 — 各腳本共用的路徑與函式

BASE="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$BASE/firewall.log"
PIDFILE="/var/run/firewall_resolver.pid"
UPSTART_CONF="/etc/upstart/firewall.conf"

# 允許連線的網域，HTTP (80) 與 HTTPS (443) 都放行。
# 為什麼兩個埠都開：KOReader OTA 走 http://（80），字典下載多半走 https://（443）。
# 來源與查證（2026-11-04）見 README「Why these sites are allowed」。
#   KOReader OTA（frontend/ui/otamanager.lua，預設＋4 個鏡像；更新檔就在同一台，不轉址）
#   KOReader 字典下載（frontend/ui/data/dictionaries.lua 的下載網址主機）
#   github.com 的 Release 檔會 302 轉到 release-assets.githubusercontent.com（實測），
#   objects.githubusercontent.com 是 GitHub 較舊的下載網域，保留以防其他檔案仍用它。
ALLOW_DOMAINS="
ota.koreader.rocks
koreader-fr.ak-team.com
koreader-pl.ak-team.com
koreader-na.ak-team.com
koreader.ak-team.com
build.koreader.rocks
gitlab.com
github.com
api.github.com
release-assets.githubusercontent.com
objects.githubusercontent.com
cyphar.github.io
"
ALLOW_PORTS="80 443"

# 背景重試解析的間隔 (s)
RESOLVE_RETRY_INTERVAL=30
# 還有網域沒解析成功時，每隔幾輪在 log 記一次清單（避免每 30 秒寫一行）
RESOLVE_PENDING_LOG_ROUNDS=10

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
