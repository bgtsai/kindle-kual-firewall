[Switch to English](README.md)

# kindle-kual-firewall

給已越獄 Kindle 用的 KUAL 插件。它會擋掉所有對外網路連線（包含 Amazon 的 OTA 韌體更新），但保留：

- 區域網路（`192.168.x.x`）
- DNS 查詢
- 連到 GitHub 的 HTTPS（讓 KOReader 照樣能自我更新）

也可以設定成開機自動啟用，讓防火牆比 Wi-Fi 與 OTA 服務更早生效。

> **實測機型：** Kindle 韌體 5.13.5（核心 4.1.15）。其他機型可能要調整，見[請 AI 幫你改成適合你的 Kindle](#請-ai-幫你改成適合你的-kindle)。

## 需要的東西

- 已**越獄**的 Kindle
- 已安裝 **KUAL**（Kindle Unified Application Launcher）
- 一條可以傳檔的 USB 線

## 安裝

1. 到 [Releases](../../releases/latest) 下載 **`firewall.zip`**。
   （不要用 GitHub 綠色的「Code → Download ZIP」，那個會多包一層資料夾。）
2. 解壓縮，會得到一個叫 `firewall` 的資料夾。
3. 用 USB 把 Kindle 接上電腦，Kindle 會出現成一個磁碟。
4. 把**整個 `firewall` 資料夾**複製到那個磁碟的 `extensions` 資料夾裡。
5. 退出 Kindle，打開 KUAL，應該會看到 **Firewall** 這一項。

### 資料夾結構一定要長這樣

```
Kindle 磁碟（根目錄）
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
| `extensions/firewall/firewall/config.xml` | 多了一層，KUAL 找不到。解壓到一個本來就叫 `firewall` 的資料夾時最常發生。 |
| `extensions/firewall-main/...` | 用 GitHub「Download ZIP」下載時資料夾被改名。資料夾名稱必須跟 `config.xml` 裡的 `<id>`（`firewall`）一致。 |
| `config.xml` 直接放在 `extensions/` 底下 | 每個插件都要有自己的資料夾。 |

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
| **Enable Firewall** | 立刻擋掉外網。接著在背景每 30 秒嘗試查詢 GitHub 的 IP，Wi-Fi 一連上就放行。所以 Wi-Fi 沒開時按也沒關係。 |
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
| 連到 `api.github.com`、`github.com`、`objects.githubusercontent.com` 的 HTTPS | 按下 Enable 時查到的 IP |
| 已放行連線的回應 | |

其他所有對外流量都擋掉。

## 會產生哪些檔案

| 檔案 | 位置（USB 看到的路徑） | 用途 |
| --- | --- | --- |
| `firewall.log` | `extensions/firewall/firewall.log` | 每個動作一行：規則已套用、GitHub 已放行、開機設定已安裝、錯誤訊息。 |
| `diagnose.txt` | `extensions/firewall/diagnose.txt` | **Diagnose** 的輸出。 |
| `firewall.conf` | `/etc/upstart/firewall.conf`（系統分區，USB 看不到） | 開機設定，按過 **Install Autostart** 才會有。 |

### 確認有沒有生效

1. Firewall ▸ **Enable Firewall**，然後打開 Wi-Fi。
2. 等約一分鐘，接上 USB，打開 `extensions/firewall/firewall.log`。
3. 應該會看到類似：
   ```
   基本規則已套用（WAN 已阻斷）
   已放行 github.com: 140.82.x.x
   GitHub 放行完成
   ```

如果一直沒出現「GitHub 放行完成」，代表 Kindle 查不到 GitHub，通常是 Wi-Fi 還沒連上。它會持續重試，直到成功為止。

## 已知限制

- **沒裝開機自動執行的話，重開機後規則會消失。** 再按一次 Enable，或使用 Install Autostart。
- **GitHub 的 IP 會變。** 如果幾天後 KOReader 更新失敗，再按一次 Enable。
- **只處理 IPv4。** 實測的 Kindle 沒有 IPv6（沒有 `ip6tables`），所以沒有處理 IPv6。
- **韌體更新會清掉開機設定**，因為更新會覆蓋系統分區（不過這個防火牆本來就是要擋更新）。
- 萬一開機設定出問題導致 Kindle 無法正常開機，用 SSH 刪除 `/etc/upstart/firewall.conf`。開機設定本身寫成「找不到插件資料夾就什麼都不做」。

## 移除

1. Firewall ▸ **Remove Autostart**（如果有裝）。
2. Firewall ▸ **Disable Firewall**。
3. 用 USB 刪除 `extensions/firewall`。

## 請 AI 幫你改成適合你的 Kindle

開機時機（`starting lab126`）等細節，是依照實測那台 Kindle 的 `diagnose.txt` 決定的，你的機型可能不一樣。不會寫程式也沒關係，可以請 AI 助理（Claude、ChatGPT 等）幫你改。

### 第 1 步：從你的 Kindle 收集資訊

1. 照上面的方式安裝插件。
2. Firewall ▸ **Enable Firewall**，打開 Wi-Fi，等一分鐘（讓紀錄檔顯示 GitHub 有沒有放行成功）。
3. Firewall ▸ **Diagnose**。
4. 用 USB 把 `extensions/firewall/diagnose.txt` 複製出來。

`diagnose.txt` 裡有 Kindle 的韌體版本、系統檔案清單與防火牆規則，不含帳號資料，但分享前請自己看過一遍。

### 第 2 步：把這些交給 AI

開一個**新的**對話，附上：

1. `firewall.zip`（Release 下載的原始檔）
2. 你的 `diagnose.txt`

然後貼上這段文字（最後一段改成你的需求）：

```
我在已越獄的 Kindle 上使用 KUAL 插件「kindle-kual-firewall」（https://github.com/bgtsai/kindle-kual-firewall）。附件是插件（firewall.zip）和我 Kindle 的 diagnose.txt。

請先讀 repo 裡的 CLAUDE.md（或 README 的「Notes for AI」），再逐段檢查我的 diagnose.txt：
- 「upstart start/stop triggers」：wifid／otaupd／otav3 是不是在 lab126 之後才啟動？「starting lab126」對我的 Kindle 還是正確的開機掛點嗎？
- 「nslookup github.com」：輸出格式跟 bin/common.sh 的解析寫法對得上嗎？
- 「tools」：有沒有 ip6tables？有的話也要擋 IPv6 對外。
- 「conntrack / state modules」：哪一個能用？
- 「firewall.log」：Enable 之後 GitHub 有沒有放行成功？
- 「mounts」：根目錄是不是唯讀（需要 mntroot rw）？

動手修改之前，先告訴我針對我的 Kindle 要改哪些地方、為什麼。之後給我一個新的 firewall.zip，資料夾結構維持一樣（extensions/firewall/...），並把 config.xml 的版本號往上加。

我的需求：<寫你要的，例如「我家的網段是 10.0.0.x」，或「沒有額外需求，讓它在我的 Kindle 上正常運作就好」>
```

### 第 3 步：裝上改好的版本

用新的資料夾取代 Kindle 上的 `extensions/firewall`，再照[確認有沒有生效](#確認有沒有生效)測一次。如果之前裝過開機自動執行，而 AI 改動了開機設定，要先用**舊版**按 **Remove Autostart**，換上新版後再按 **Install Autostart**。

## 給 AI 的說明

見 [CLAUDE.md](CLAUDE.md)：列出哪些地方跟機型相關、改完要檢查什麼。

## 授權

[MIT](LICENSE)
