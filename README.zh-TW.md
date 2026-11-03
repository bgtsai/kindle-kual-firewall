[Switch to English](README.md)

# kindle-kual-firewall

給已越獄 Kindle 用的 KUAL 插件。它會擋掉所有對外網路連線（包含 Amazon 的 OTA 韌體更新），但保留：

- 區域網路（`192.168.x.x`）
- DNS 查詢
- KOReader 自己的更新伺服器與字典下載網站（讓 KOReader 照樣能自我更新、下載字典），見[為什麼放行這些網站](#為什麼放行這些網站)

也可以設定成開機自動啟用，讓防火牆比 Wi-Fi 與 OTA 服務更早生效。

> **實測機型：** Kindle 韌體 5.13.5（核心 4.1.15），包含防火牆開著時連 Wi-Fi。其他機型可能要調整，見[請 AI 幫你改成適合你的 Kindle](#請-ai-幫你改成適合你的-kindle)。

## 需要的東西

- 已**越獄**的 Kindle
- 已安裝 **KUAL**（Kindle Unified Application Launcher）
- 一條可以傳檔的 USB 線

## 安裝

1. 到 [Releases](../../releases/latest) 下載 **`firewall.zip`**。
   （不要用 GitHub 綠色的「Code → Download ZIP」，那是原始碼，資料夾結構不一樣。）
2. 解壓縮，裡面會有**兩樣東西**：`extensions` 資料夾，和一個叫 `WIFI_NO_NET_PROBE` 的檔案。
3. 用 USB 把 Kindle 接上電腦，Kindle 會出現成一個磁碟。
4. 把這**兩樣都**複製到那個磁碟的**根目錄**（最上層，`documents` 資料夾所在的那一層）。如果磁碟上已經有 `extensions` 資料夾，讓電腦**合併**即可，你其他的插件不會受影響。
5. 退出 Kindle，**重新開機**（原因見下方）。
6. 打開 KUAL，應該會看到 **Firewall** 這一項。

### 安裝後一定要重開機

一般的 KUAL 插件放進去就能用，不用重開機。這個插件不一樣，原因是 `WIFI_NO_NET_PROBE`：

- Kindle 連上 Wi-Fi 後，平常會去 Amazon 下載一個測試頁（`spectrum.s3.amazonaws.com`），確認真的能上網。**防火牆會擋掉這個測試頁，所以沒有 `WIFI_NO_NET_PROBE` 的話，Kindle 會顯示 Wi-Fi 錯誤、拒絕連線。**
- `WIFI_NO_NET_PROBE` 是一個空檔案，告訴 Kindle 的 Wi-Fi 服務跳過這個檢查。但 Wi-Fi 服務只在**啟動時**（也就是開機時）讀這個檔。

所以順序是：複製檔案 → 重開機 → 再啟用防火牆、連 Wi-Fi。

為什麼不直接放行那個測試頁？因為它放在 Amazon S3，韌體更新檔也放在 S3。防火牆是用 IP 判斷，分不出兩者，放行測試頁就可能連韌體更新一起放行。

### Kindle 上的結構一定要長這樣

```
Kindle 磁碟（根目錄）
├── WIFI_NO_NET_PROBE          ← 空檔案，沒有副檔名（不是 .txt）
├── documents/                 （本來就有）
└── extensions/
    └── firewall/              ← 這個資料夾名稱一定要是 firewall
        ├── config.xml
        ├── menu.json
        └── bin/
            ├── common.sh
            ├── enable.sh
            ├── disable.sh
            ├── autostart_install.sh
            ├── autostart_remove.sh
            └── diagnose.sh
```

常見的錯誤：

| 錯誤的樣子 | 為什麼不行 |
| --- | --- |
| Kindle 上變成 `firewall/extensions/firewall/...` | 解壓縮工具多建了一層以 zip 檔名命名的資料夾。要複製的是它**裡面**的東西，放到 Kindle 根目錄。 |
| `extensions/firewall/firewall/config.xml` | 多了一層，KUAL 找不到。 |
| `WIFI_NO_NET_PROBE.txt` | Windows 可能隱藏或自動加上 `.txt`。檔名必須剛好是 `WIFI_NO_NET_PROBE`，可以在檔案總管開啟「副檔名」顯示來確認。 |
| `WIFI_NO_NET_PROBE` 放在 `extensions/` 裡面 | 必須放在磁碟根目錄，跟 `extensions/` 同一層。 |
| 沒有重開機 | 連線檢查還開著 → 防火牆啟用時 Wi-Fi 會出錯。 |

## 選單

在 KUAL 裡只佔一項，功能都在裡面：

```
Firewall ▸
    Enable Firewall (Block WAN)
    Disable Firewall (Allow WAN)
    Install Autostart (enable on boot)
    Remove Autostart
    Diagnose (write diagnose.txt)
```

| 選項 | 做什麼 |
| --- | --- |
| **Enable Firewall** | 立刻擋掉外網。接著在背景每 30 秒嘗試查詢放行網站的 IP，Wi-Fi 一連上就放行。所以 Wi-Fi 沒開時按也沒關係。 |
| **Disable Firewall** | 移除所有阻擋規則，恢復全部放行。 |
| **Install Autostart** | 安裝開機設定（`/etc/upstart/firewall.conf`），每次開機都自動啟用防火牆，而且比 Wi-Fi 與 OTA 服務更早。這會寫入 Kindle 的系統分區。 |
| **Remove Autostart** | 刪除那個開機設定。 |
| **Diagnose** | 把系統資訊寫進 `diagnose.txt`（只讀取、不改任何東西）。用來排查問題，或把插件改成適合其他機型。 |

## 到底放行了哪些

| 放行 | 說明 |
| --- | --- |
| 本機（`lo`） | Kindle 內部程式之間的溝通 |
| `192.168.0.0/16` | 區域網路，所有埠。`10.x.x.x`、`172.16～31.x.x` **沒有**放行。 |
| DNS（53 埠） | 任何 DNS 伺服器 |
| 連到 KOReader 相關網站的 HTTP 與 HTTPS，清單見[為什麼放行這些網站](#為什麼放行這些網站) | 按下 Enable 後查到的 IP |
| 已放行連線的回應 | |

其他所有對外流量都擋掉。

## 為什麼放行這些網站

目標是：**擋掉 Amazon（韌體更新、回傳資料），但 KOReader 要能完整使用**，包括它內建的更新功能和內建的字典下載。下面是 KOReader 實際會連的主機，取自 KOReader 自己的原始碼，2026-11-04 查證：

| 主機 | 埠 | 用途 | 來源／怎麼查證的 |
| --- | --- | --- | --- |
| `ota.koreader.rocks` | 80 | KOReader OTA 更新，**預設伺服器**。版本檢查和更新檔都在同一台，不會轉址。 | [otamanager.lua](https://github.com/koreader/koreader/blob/master/frontend/ui/otamanager.lua) 的 `ota_servers`；實際抓了 Kindle 用的 `.zsync` 檔，裡面的下載網址是相對路徑（同一台） |
| `koreader-fr.ak-team.com`、`koreader-pl.ak-team.com`、`koreader-na.ak-team.com`、`koreader.ak-team.com` | 80 | KOReader OTA 鏡像（可以在 KOReader 的更新設定裡切換） | 同一份 `ota_servers` 清單 |
| `gitlab.com` | 443 | 字典下載：大部分字典，包含 KOReader 自己維護的那一批 | [dictionaries.lua](https://github.com/koreader/koreader/blob/master/frontend/ui/data/dictionaries.lua) 的下載網址；不轉址 |
| `github.com` | 443 | 字典下載（維基詞典系列與其他幾本） | dictionaries.lua |
| `release-assets.githubusercontent.com` | 443 | `github.com/…/releases/download/…` 的檔案實際從這裡下載 | 實測：github.com 回應 **302 → release-assets.githubusercontent.com** |
| `objects.githubusercontent.com` | 443 | GitHub 較舊的下載網域，以防還有檔案使用它 | 實測沒看到，預防性保留 |
| `api.github.com` | 443 | 舊版留下的（GitHub API） | — |
| `cyphar.github.io` | 443 | 日文字典（JMdict、JMnedict） | dictionaries.lua；不轉址 |
| `build.koreader.rocks` | 80 | 少數幾本字典（CIA Factbook、GCIDE、Pape） | dictionaries.lua；不轉址 |

上面每個主機都同時放行 80 和 443 埠（KOReader OTA 用 `http://`，大部分字典用 `https://`）。

沒有放行：dictionaries.lua 裡另外兩個只供單一字典用的主機（`dicionario-aberto.net`、`http.debian.net`）。需要那兩本字典的話，把它們加進 `bin/common.sh` 的 `ALLOW_DOMAINS`。

要知道的事：

- `ota.koreader.rocks`、`build.koreader.rocks` 架在 **Cloudflare** 後面，GitHub 的下載網域也是共用 CDN。放行它們的 IP，等於同一組 CDN IP 上的其他網站也一起放行。但這些都不是 Amazon 的更新伺服器，所以不影響擋 OTA 的效果。
- 安裝 KOReader **外掛**不經過 Kindle 連網：外掛是在電腦上下載、用 USB 複製進去，所以這裡不需要放行任何東西。

## 會產生哪些檔案

| 檔案 | 位置（USB 看到的路徑） | 用途 |
| --- | --- | --- |
| `firewall.log` | `extensions/firewall/firewall.log` | 每個動作一行：規則已套用、網站已放行、開機設定已安裝、錯誤訊息。 |
| `diagnose.txt` | `extensions/firewall/diagnose.txt` | **Diagnose** 的輸出。 |
| `firewall.conf` | `/etc/upstart/firewall.conf`（系統分區，USB 看不到） | 開機設定，按過 **Install Autostart** 才會有。 |

磁碟根目錄的 `WIFI_NO_NET_PROBE` 不是插件產生的，是 zip 裡附的（見[安裝](#安裝)）。

### 確認有沒有生效

1. Firewall ▸ **Enable Firewall**，然後打開 Wi-Fi。
2. 等約一分鐘，接上 USB，打開 `extensions/firewall/firewall.log`。
3. 應該會看到類似：
   ```
   2026-11-04 05:31:20  Basic rules applied (WAN blocked)
                        Chinese | 基本規則已套用（WAN 已阻斷）
   2026-11-04 05:31:21  Allowed ota.koreader.rocks: 104.21.x.x 172.67.x.x
                        Chinese | 已放行上一行的網域
   2026-11-04 05:31:21  Allowed gitlab.com: 172.65.x.x
                        Chinese | 已放行上一行的網域
   …
   2026-11-04 05:31:22  All domains allowed
                        Chinese | 全部網域放行完成
   ```
   每筆紀錄寫兩行：第一行是英文、帶時間；下一行縮排、以 `Chinese |` 開頭，是同一句的中文。網域、IP 只寫在英文那一行。

如果看到 `Not resolved yet, retrying: <網站>`（中文行是「上一行的網域尚未解析，持續重試」），代表那些網站查不到 IP，通常是 Wi-Fi 還沒連上。它每 30 秒重試一次，大約每 5 分鐘寫一次這行。如果長時間只剩某一個鏡像在清單裡，多半是那個鏡像掛了，其他網站已經可以用。

## 已知限制

- **沒裝開機自動執行的話，重開機後規則會消失。** 再按一次 Enable，或使用 Install Autostart。
- **IP 會變**，尤其是架在 Cloudflare／CDN 後面的網站。如果之後 KOReader 更新或字典下載失敗，再按一次 Enable。
- **只處理 IPv4。** 實測的 Kindle 沒有 IPv6（沒有 `ip6tables`），所以沒有處理 IPv6。
- **防火牆開著時 Wi-Fi 出錯** → `WIFI_NO_NET_PROBE` 不存在、檔名不對，或放進去之後沒有重開機。見[安裝後一定要重開機](#安裝後一定要重開機)。
- **韌體更新會清掉開機設定**，因為更新會覆蓋系統分區（不過這個防火牆本來就是要擋更新）。
- 萬一開機設定出問題導致 Kindle 無法正常開機，用 SSH 刪除 `/etc/upstart/firewall.conf`。開機設定本身寫成「找不到插件資料夾就什麼都不做」。

## 移除

1. Firewall ▸ **Remove Autostart**（如果有裝）。
2. Firewall ▸ **Disable Firewall**。
3. 用 USB 刪除 `extensions/firewall`。
4. 刪除磁碟根目錄的 `WIFI_NO_NET_PROBE` 並重開機，讓 Kindle 恢復正常的連線檢查。（可省略，留著也沒有壞處。）

## 請 AI 幫你改成適合你的 Kindle

開機時機（`starting lab126`）等細節，是依照實測那台 Kindle 的 `diagnose.txt` 決定的，你的機型可能不一樣。不會寫程式也沒關係，可以請 AI 助理（Claude、ChatGPT 等）幫你改。

### 第 1 步：從你的 Kindle 收集資訊

1. 照上面的方式安裝插件。
2. Firewall ▸ **Enable Firewall**，打開 Wi-Fi，等一分鐘（讓紀錄檔顯示放行的網站有沒有查到 IP）。
3. Firewall ▸ **Diagnose**。
4. 用 USB 把 `extensions/firewall/diagnose.txt` 複製出來。

`diagnose.txt` 裡有 Kindle 的韌體版本、系統檔案清單與防火牆規則，不含帳號資料，但分享前請自己看過一遍。

### 第 2 步：把這些交給 AI

開一個**新的**對話，附上：

1. `firewall.zip`（Release 下載的原始檔，裡面有 `extensions/firewall/` 和 `WIFI_NO_NET_PROBE`）
2. 你的 `diagnose.txt`

然後貼上這段文字（最後一段改成你的需求）：

```
我在已越獄的 Kindle 上使用 KUAL 插件「kindle-kual-firewall」（https://github.com/bgtsai/kindle-kual-firewall）。附件是插件（firewall.zip）和我 Kindle 的 diagnose.txt。

請先讀 repo 裡的 CLAUDE.md（或 README 的「Notes for AI」），再逐段檢查我的 diagnose.txt：
- 「upstart start/stop triggers」：wifid／otaupd／otav3 是不是在 lab126 之後才啟動？「starting lab126」對我的 Kindle 還是正確的開機掛點嗎？
- 「nslookup github.com」：輸出格式跟 bin/common.sh 的解析寫法對得上嗎？
- 「tools」：有沒有 ip6tables？有的話也要擋 IPv6 對外。
- 「conntrack / state modules」：哪一個能用？
- 「firewall.log」：Enable 之後放行的網站是不是都查到 IP 了？
- 「mounts」：根目錄是不是唯讀（需要 mntroot rw）？

動手修改之前，先告訴我針對我的 Kindle 要改哪些地方、為什麼。之後給我一個新的 firewall.zip，結構維持一樣（extensions/firewall/... 加上最上層的 WIFI_NO_NET_PROBE），並把 config.xml 的版本號往上加。

我的需求：<寫你要的，例如「我家的網段是 10.0.0.x」，或「沒有額外需求，讓它在我的 Kindle 上正常運作就好」>
```

### 第 3 步：裝上改好的版本

用新的資料夾取代 Kindle 上的 `extensions/firewall`（根目錄的 `WIFI_NO_NET_PROBE` 保留），如果改到跟 Wi-Fi 有關的部分就重開機，再照[確認有沒有生效](#確認有沒有生效)測一次。如果之前裝過開機自動執行，而 AI 改動了開機設定，要先用**舊版**按 **Remove Autostart**，換上新版後再按 **Install Autostart**。

## 給 AI 的說明

見 [CLAUDE.md](CLAUDE.md)：列出哪些地方跟機型相關、改完要檢查什麼。

## 參考資料

設計這個插件時查證過的資料：

- Wi-Fi 連線檢查（`spectrum.s3.amazonaws.com/kindle-wifi/wifistub.html`），以及檢查失敗時 Kindle 不會連上網路：[MobileRead – wifistub connectivity check](https://www.mobileread.com/forums/showthread.php?p=2874926)、[MobileRead – Kindle Touch phoning home when first connecting to a WiFi network](https://www.mobileread.com/forums/showthread.php?p=2962466)
- `WIFI_NO_NET_PROBE` 旗標檔（`/mnt/us/WIFI_NO_NET_PROBE` → `wifid -n`）：[MobileRead – Kindle Touch phoning home…](https://www.mobileread.com/forums/showthread.php?p=2962466)、[Kindle联网问题分析（heary.cn）](https://heary.cn/posts/Kindle%E8%81%94%E7%BD%91%E9%97%AE%E9%A2%98%E5%88%86%E6%9E%90/)
- 韌體更新檔放在 Amazon S3：[KindleModding – Manually Downloading Firmware Update Files](https://kindlemodding.org/firmware-and-flashing/downloading-updates.html)
- KUAL 插件 `config.xml`／`menu.json` 格式：[Kindle + Python = e-Ink Dashboard（4DCu.be）](https://blog.4dcu.be/diy/2020/09/27/PythonKindleDashboard_1.html)、[MobileRead Wiki – KUAL](https://wiki.mobileread.com/wiki/KUAL)
- 另一種擋 OTA 的方式：把更新程式改名（本插件未採用）：[GitHub – Darthagnon/BlockKindleOTA](https://github.com/Darthagnon/BlockKindleOTA)、[MobileRead – OTA blocking on recent firmware](https://www.mobileread.com/forums/showthread.php?p=4329911)
- KOReader OTA 伺服器（`ota_servers`）：[koreader/koreader – frontend/ui/otamanager.lua](https://github.com/koreader/koreader/blob/master/frontend/ui/otamanager.lua)
- KOReader 字典下載網址：[koreader/koreader – frontend/ui/data/dictionaries.lua](https://github.com/koreader/koreader/blob/master/frontend/ui/data/dictionaries.lua)
- KOReader OTA 檔案目錄：[ota.koreader.rocks](http://ota.koreader.rocks/)
- KOReader 外掛是用 USB 手動安裝：[Project Title 外掛 – Installation](https://github.com/joshuacant/ProjectTitle/wiki/Installation)
- Amazon 官方的 Wi-Fi 疑難排解：[Resolve Wi-Fi Connection Issues on Your Kindle E-Reader](https://digprjsurvey.amazon.com/csad/help/node/G5HYWUVWRXFSCH7E)

## 授權

[MIT](LICENSE)
