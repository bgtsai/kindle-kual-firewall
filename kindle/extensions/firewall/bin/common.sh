#!/bin/sh
# firewall common.sh v1.12 — 各腳本共用的路徑與函式

BASE="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$BASE/firewall.log"
PIDFILE="/var/run/firewall_resolver.pid"
# 背景程序目前正在等的 lipc-wait-event，Disable 時要一併停掉
WAITER_PIDFILE="/var/run/firewall_waiter.pid"
UPSTART_CONF="/etc/upstart/firewall.conf"
# Airplane-on-Boot：關機時、開機時各一個 upstart 設定（一個 .conf 只能有一組 start on）
AIRPLANE_SHUTDOWN_CONF="/etc/upstart/firewall_airplane_shutdown.conf"
AIRPLANE_BOOT_CONF="/etc/upstart/firewall_airplane_boot.conf"
# 開機時最多等 com.lab126.cmd 回應幾秒
AIRPLANE_BOOT_WAIT_S=60

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
# 放行網域的規則都放在這條鏈，OUTPUT 在 DROP 前跳過來；Wi-Fi 重新連上時整條清空重建，舊 IP 不殘留
ALLOW_CHAIN="FW_ALLOW"

# 區域網路：RFC 1918 三段私有網段，網際網路上不會被路由，不可能是 Amazon 的伺服器。
# 不放 100.64.0.0/10（電信業者 CGNAT，不在家裡）、169.254.0.0/16（DHCP 失敗才出現）、群播。
LAN_RANGES="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12"

# calibre 無線連線（給 kindle-kual-calibre-wireless 插件）找 calibre 用的 UDP 廣播。
# UNCaGED 把目標寫死成 255.255.255.255（calibre/calibre.go）；埠號＝calibre
# smart_device_app/driver.py 的 BROADCAST_PORTS。calibre 的回覆是 INPUT 方向，
# 由那個插件自己在連線期間開、斷線時關，不放在這裡。
CALIBRE_BROADCAST_PORTS="54982 48123 39001 44044 59678"

# Wi-Fi 連上後，還有網域解析失敗時的重試間隔 (s) 與次數；用完就停，等下一次連線
RESOLVE_RETRY_INTERVAL=10
RESOLVE_RETRY_MAX=6
# lipc-wait-event 無法使用時（例如開機初期 wifid 還沒起來）改用輪詢的間隔 (s)
WAIT_FALLBACK_POLL_S=30
# 每次等事件最多等多久 (s)。保險：萬一 lipc-wait-event 卡住收不到事件（v1.11 開機後實測疑似發生），
# 至少每這麼久會醒來重新檢查一次連線狀態。飛行模式時就是每這麼久醒一次，耗電可忽略。
WAIT_MAX_S=300
# lipc-wait-event 在這麼短的時間內就結束且失敗，視為「不能用」，改用輪詢 (s)
WAIT_FAST_FAIL_S=2
# firewall.log 超過這個大小 (bytes) 就只保留後半段；每次 Wi-Fi 重連都會寫 log
LOG_MAX_BYTES=100000

# 雙語 log：log "<English>" "<中文>"
# 英文行帶時間；中文行縮排、以「Chinese | 」開頭，看不懂中文的人一眼知道可以跳過。
# 網域、IP、路徑只放英文行，中文行不重複，避免兩邊內容不一致。
log() {
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt "$LOG_MAX_BYTES" ]; then
        tail -c $((LOG_MAX_BYTES / 2)) "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "$ts  $1" >> "$LOG"
    [ -n "$2" ] && echo "                     Chinese | $2" >> "$LOG"
}

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

# 進飛行模式（關 Wi-Fi）。-i：wirelessEnable 是整數屬性（KOReader frontend/device/kindle/device.lua 同寫法）
airplane_on() { lipc-set-prop -i com.lab126.cmd wirelessEnable 0 2>/dev/null; }

# 寫入系統分區的共用流程：mntroot rw → 動作 → mntroot ro
# 為什麼一定要 ro 回去：根目錄平常唯讀，留在 rw 狀態萬一斷電可能損毀系統分區
with_rootfs_rw() {
    mntroot rw || { log "ERROR: mntroot rw failed" "錯誤：mntroot rw 失敗"; return 1; }
    "$@"
    rc=$?
    mntroot ro
    return $rc
}

# Wi-Fi 連線狀態（CONNECTED／NA／READY／PENDING…）；讀不到時是空字串
wifi_state() { lipc-get-prop com.lab126.wifid cmState 2>/dev/null; }

# wlan0 的 IPv4 位址；沒有就空字串
wlan_ip() {
    ifconfig wlan0 2>/dev/null | awk '/inet addr:/ { sub("addr:", "", $2); print $2; exit }'
}

# 目前設定的 DNS 伺服器（resolv.conf 第一個 nameserver）；沒有就空字串
dns_server() { awk '/^nameserver/ { print $2; exit }' /etc/resolv.conf 2>/dev/null; }

# 一行描述目前網路狀態，寫 log 用
net_desc() { echo "cmState=$(wifi_state) wlan0=$(wlan_ip) dns=$(dns_server)"; }

# 判斷 Wi-Fi 是否已連上。
# 主要看 cmState；但 cmState 讀不到（空值）時不能就當成沒連上——v1.11 開機後實測，
# 疑似因為讀不到狀態而一直判斷成「沒連上」，切 Wi-Fi 也沒反應。這時改看 wlan0 有 IP 且有 DNS 伺服器。
# cmState 明確不是 CONNECTED（NA、READY…）時照它判斷。
net_up() {
    st="$(wifi_state)"
    [ "$st" = CONNECTED ] && return 0
    [ -n "$st" ] && return 1
    [ -n "$(wlan_ip)" ] && [ -n "$(dns_server)" ]
}

# 停掉先前留下的背景程序與它正在等的 lipc-wait-event（重按 Enable 或 Disable 時用）
stop_resolver() {
    for f in "$PIDFILE" "$WAITER_PIDFILE"; do
        if [ -f "$f" ]; then
            kill "$(cat "$f")" 2>/dev/null
            rm -f "$f"
        fi
    done
}
