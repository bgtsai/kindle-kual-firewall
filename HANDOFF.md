# 交接：firewall 下一版要改的三件事（2026-11-04）

來源：小程式集合對話串「Kindle calibre 無線連線插件」需求討論（【6_話】～【8_話】）。這三項是為了配合即將開發的新插件 `kindle-kual-calibre-wireless`（calibre 無線傳書）而提出，使用者已同意方案，**動手改 code 前仍要先跟使用者確認一次**。做完、使用者實測通過後，刪除本檔。

## 目前狀態

- firewall 只管 OUTPUT 鏈：放行 lo、192.168.0.0/16、DNS、ESTABLISHED/RELATED，其餘 DROP；allow-list 網域由 `enable.sh` 背景迴圈每 30 秒重試解析後插入。
- 開機掛 `start on starting lab126`（`autostart_install.sh`）。

## 要做的事

### 1. 放行 calibre 無線連線的 UDP 廣播

- 新插件用 UNCaGED 函式庫找 calibre，它把廣播目標寫死成 `255.255.255.255`，目標埠是 calibre 的 5 個廣播埠：`54982 48123 39001 44044 59678`（出處：UNCaGED `calibre/calibre.go` 第 35、75 行；calibre `smart_device_app/driver.py` 的 `BROADCAST_PORTS`）。
- 現行規則只放行 192.168.0.0/16，這個廣播會被最後的 DROP 擋掉。
- 要加：OUTPUT `-p udp -d 255.255.255.255 --dport <上面 5 個埠> -j ACCEPT`（放在 DROP 之前）。
- 不用處理的：連到 calibre 的 TCP（目標是 192.168.x.x，已放行）、回應封包（ESTABLISHED 已放行）。calibre 回覆廣播是送進來的方向（INPUT），firewall 不管 INPUT；那條由新插件自己在連線期間開、斷線時關（同 KOReader `platform/kindle/koreader.sh` 第 207、423 行的做法），**不要**放進 firewall。
- README 的「為什麼放行這些」表要同步加一列。

### 2. 開機與關機都進飛行模式

- 切換指令：`lipc-set-prop com.lab126.cmd wirelessEnable 0`（0 = 飛行模式／Wi-Fi 關，1 = 開）。出處：KOReader `frontend/device/kindle/device.lua` 第 280、284 行。
- **關機時**設成 0：推測 Kindle 會記住飛行模式狀態，下次開機一開始就在飛行模式，Wi-Fi 不會先連上。⚠️「狀態會被記住」未驗證，要在使用者的 5.13.5 上確認。
- **開機時**也設成 0（保險，防沒電直接斷電時關機那條沒跑到）：`starting lab126` 時 lipc 服務還沒起來，不能在那裡直接下指令；要另起背景程序等 `com.lab126.cmd` 可用後再設，**不能拖住開機**（同既有「Boot job must never block boot」原則）。
- 掛關機的 upstart 事件名稱、等 lipc 就緒的方法，都要先在 diagnose 裡確認（可把 `/etc/upstart/` 裡與 shutdown／lab126 相關的觸發條件、`lipc-get-prop com.lab126.cmd wirelessEnable` 的值加進 diagnose.sh）。
- 這是新功能，要跟使用者討論：是否做成 KUAL 選單開關（firewall 選單只有一個頂層項目，加在 submenu 裡）、還是跟 Autostart 綁在一起。

### 3. 背景重試迴圈改成「等 Wi-Fi 連上才解析」

- 問題：飛行模式下 DNS 永遠失敗，`enable.sh` 第 22～48 行的迴圈永遠不會結束，螢幕亮著時每 30 秒喚醒一次（休眠時 CPU 停住不耗電），耗電小但不是零。
- 改法：改成等系統的 Wi-Fi 已連線事件（推測是 `lipc-wait-event com.lab126.wifid cmConnected` 之類，⚠️ 事件名稱未驗證，要用 diagnose 確認），連上才去解析；飛行模式期間完全不動。連上後若解析仍失敗，可保留短暫重試。
- Wi-Fi 斷了又連上時，IP 可能變了，要考慮重新解析並更新規則（舊規則要清掉，不能只一直插新的）。
- 維持 single-instance（pid 檔）與 Disable 能殺掉它。

## 怎麼測

- 依 CLAUDE.md「After editing」七步。
- 第 3 項用 stub 的 `iptables`／`nslookup`／`lipc-wait-event` 放在 PATH 上模擬（先不給連線事件 → 確認不解析；給事件 → 確認解析並插規則）。
- 只能實機確認的：飛行模式狀態是否跨重開機保留、關機事件名稱、Wi-Fi 連線事件名稱、廣播規則加了之後 calibre 能否被找到（要等新插件做出來才能端到端測）。
- 開機設定有改的話，提醒使用者先用舊版 **Remove Autostart** 再裝新版。

## 進度

- 2026-11-04 v1.9：第 1 項完成（calibre 廣播放行）；diagnose.sh 擴充（lipc 狀態、shutdown／wifi 相關 upstart 全文、背景錄 120 秒 Wi-Fi 事件），等使用者實機跑 Diagnose 回傳結果，再做第 3、2 項。
- 第 2 項使用者選定：**獨立的選單開關**（Install／Remove Airplane-on-Boot），不跟 Autostart 綁在一起；動手前仍要先問。
- KOReader `frontend/device/kindle/device.lua` 註解記錄的 wifid 事件：連上 `cmConnected`＋`cmStateChange "CONNECTED"`，斷線 `cmDisconnected`＋`cmStateChange "NA"`；屬性 `com.lab126.wifid cmState`。5.13.5 待 diagnose 確認。
- 2026-11-04 v1.10：第 3 項完成（等 cmStateChange→CONNECTED 才解析、FW_ALLOW 鏈每次連線重建、同 IP 只加一次、lipc 失敗時退回輪詢）；區網改放行 RFC 1918 三段（使用者同意）。log 改成每次連線一行摘要，超過 100 KB 自動截半。
- 5.13.5 實測（diagnose）：連上 `cmStateChange "CONNECTED"`／`InternetConnected 1`；斷線 `cmDisconnected`＋`cmStateChange "NA"`；飛行模式 `wirelessEnableChanged 0/1`（com.lab126.cmd）；`cmConnected` 連線中每 ~30 秒重複。關機 `shutdown.conf`（runlevel [06]）先寫 /tmp/shutdown_in_progress 再停 `x wifid wifis lab126…`。**飛行模式會跨重開機保留**（使用者實測）。
- 第 2 項待做（動手前先問）：關機掛 `stopping wifid` 且 /tmp/shutdown_in_progress 存在時設 wirelessEnable 0（加 timeout，不能卡關機）；開機掛 `started cmd`，等 lipc 回應再設 0；做成獨立選單 Install／Remove Airplane-on-Boot。
- 2026-11-04 v1.11：第 2 項完成（Install／Remove Airplane-on-Boot，兩個 upstart 設定：關機 `stopping wifid`＋/tmp/shutdown_in_progress、開機 `started cmd`）。三項都已實作，等使用者實機測 v1.10＋v1.11 通過後刪除本檔。
- 2026-11-04 實測 v1.11：Airplane-on-Boot 關機段、開機段都正常（log 有 Shutdown／Boot 兩筆）；一般連線解析正常。**問題**：Autostart 開機後第一次連線 12 個網域全失敗、之後切 Wi-Fi 背景程序完全沒反應。
- 2026-11-04 v1.12：net_up() 在 cmState 讀不到時改看 wlan0 IP＋DNS；每次等事件最多 300 秒；重試不提前放棄；log 記下狀態、每輪失敗與 nslookup 錯誤、背景程序啟動／被結束；Diagnose 加「background process」段。待使用者照測試流程（重開機→關飛航等 1 分→切 Wi-Fi 等 1 分→Diagnose）回傳 firewall.log＋diagnose.txt。
