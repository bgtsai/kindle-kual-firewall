[切換中文](README.zh-TW.md)

# kindle-kual-firewall

A KUAL extension for jailbroken Kindles. It blocks all outbound internet traffic — including Amazon OTA firmware updates — while still allowing:

- your local network (`192.168.x.x`, `10.x.x.x`, `172.16–31.x.x`)
- DNS lookups
- KOReader's own update servers and dictionary download sites (so KOReader can still update itself and download dictionaries) — see [Why these sites are allowed](#why-these-sites-are-allowed)

It can also start automatically on boot, so the firewall is active before Wi-Fi and the OTA service start.

> **Tested on:** Kindle firmware 5.13.5 (kernel 4.1.15), including Wi-Fi connecting with the firewall on. Other models may need adjustments — see [Customizing for your Kindle with AI](#customizing-for-your-kindle-with-ai).

## Requirements

- A **jailbroken** Kindle
- **KUAL** (Kindle Unified Application Launcher) installed
- A USB cable to copy files

## Installation

1. Go to [Releases](../../releases/latest) and download **`firewall.zip`**.
   (Do not use GitHub's green "Code → Download ZIP" button — that is the source code, with a different folder layout.)
2. Unzip it. Inside you get **two things**: an `extensions` folder and a file named `WIFI_NO_NET_PROBE`.
3. Connect the Kindle to your computer with USB. The Kindle shows up as a drive.
4. Copy **both** of them to the **root** of that drive (the top level, where the `documents` folder is). If the drive already has an `extensions` folder, let your computer **merge** them — your other extensions stay untouched.
5. Eject the Kindle and **reboot it** (see below why this is required).
6. Open KUAL. You should see a **Firewall** entry.

### A reboot is required after installing

Most KUAL extensions work right away without a reboot. This one is different because of `WIFI_NO_NET_PROBE`:

- After joining a Wi-Fi network, the Kindle normally tries to download a test page from Amazon (`spectrum.s3.amazonaws.com`) to check that the internet works. **The firewall blocks that page, so without `WIFI_NO_NET_PROBE` the Kindle shows a Wi-Fi error and refuses to connect.**
- `WIFI_NO_NET_PROBE` is an empty file that tells the Kindle's Wi-Fi service to skip that check. The Wi-Fi service only looks for it **when it starts**, i.e. at boot.

So: copy the files → reboot → then enable the firewall and connect to Wi-Fi.

Why not just allow the test page? It is hosted on Amazon S3, and so are the firmware update files. The firewall works by IP address and can't tell the two apart, so allowing the test page could also let firmware updates through.

### The structure on the Kindle must look exactly like this

```
Kindle drive (root)
├── WIFI_NO_NET_PROBE          ← empty file, no extension (not .txt)
├── documents/                 (already there)
└── extensions/
    └── firewall/              ← this folder name must stay "firewall"
        ├── config.xml
        ├── menu.json
        └── bin/
            ├── common.sh
            ├── enable.sh
            ├── disable.sh
            ├── autostart_install.sh
            ├── autostart_remove.sh
            ├── airplane_install.sh
            ├── airplane_remove.sh
            ├── airplane_apply.sh
            └── diagnose.sh
```

Common mistakes:

| Wrong | Why it fails |
| --- | --- |
| `firewall/extensions/firewall/...` on the Kindle | Your unzip tool created an extra folder named after the zip. Copy what is **inside** it to the Kindle root. |
| `extensions/firewall/firewall/config.xml` | One folder level too deep — KUAL won't find it. |
| `WIFI_NO_NET_PROBE.txt` | Windows may hide or add a `.txt` extension. The file name must be exactly `WIFI_NO_NET_PROBE`. Turn on "File name extensions" in Explorer to check. |
| `WIFI_NO_NET_PROBE` inside `extensions/` | It must be at the drive root, next to `extensions/`. |
| Didn't reboot | The Wi-Fi check is still on → Wi-Fi error while the firewall is enabled. |

## Menu

Everything is under one entry in KUAL:

```
Firewall ▸
    Enable Firewall (Block WAN)
    Disable Firewall (Allow WAN)
    Install Autostart (enable on boot)
    Remove Autostart
    Install Airplane-on-Boot (Wi-Fi off at every boot)
    Remove Airplane-on-Boot
    Diagnose (write diagnose.txt)
```

| Item | What it does |
| --- | --- |
| **Enable Firewall** | Blocks the internet immediately. Then waits in the background until Wi-Fi connects, looks up the IP addresses of the allowed sites and allows them. It does this again every time Wi-Fi reconnects (so changed IPs are picked up), and stays idle in airplane mode. So it's fine to press this while Wi-Fi is off. |
| **Disable Firewall** | Removes all blocking rules and allows all traffic again. |
| **Install Autostart** | Installs a boot job (`/etc/upstart/firewall.conf`) so the firewall turns on at every boot, before Wi-Fi and the OTA service start. This writes to the Kindle's system partition. |
| **Remove Autostart** | Deletes that boot job. |
| **Install Airplane-on-Boot** | Optional second layer. Turns on airplane mode (Wi-Fi off) during every shutdown, and again right after boot as a safety net (e.g. after the battery died). The Kindle remembers airplane mode across reboots, so it starts with Wi-Fi off and never connects on its own. **Side effect: Wi-Fi is off after every boot — turn it on yourself when you need it.** Writes two small boot jobs to the system partition. Independent of Autostart: the firewall already starts before Wi-Fi, so this is extra protection, not a requirement. |
| **Remove Airplane-on-Boot** | Deletes those two boot jobs. Wi-Fi then behaves normally at boot again. |
| **Diagnose** | Writes system information to `diagnose.txt` (read-only, changes nothing). Then, for 2 minutes in the background, records Wi-Fi events to `diagnose_wifi_events.txt` — turn Wi-Fi off and on again during that time. Used for troubleshooting and for customizing the extension for another model. |

## What exactly is allowed

| Allowed | Notes |
| --- | --- |
| Loopback (`lo`) | Internal communication between programs on the Kindle |
| `192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12` | Your local network, any port. These three private ranges (RFC 1918) are never routed on the internet, so no Amazon server can be in them. Not allowed: `100.64.0.0/10` (carrier-grade NAT, outside your home), `169.254.0.0/16` (only appears when DHCP fails), multicast. |
| DNS (port 53) | To any DNS server |
| HTTP and HTTPS to the KOReader-related sites listed in [Why these sites are allowed](#why-these-sites-are-allowed) | IPs looked up after you press Enable |
| UDP broadcast to `255.255.255.255`, ports `54982 48123 39001 44044 59678` | So a calibre wireless-connection plugin on the Kindle can find calibre on your computer. See [Why these sites are allowed](#why-these-sites-are-allowed). |
| Replies to allowed connections | |

Everything else outbound is dropped.

## Why these sites are allowed

The goal is: **block Amazon (firmware updates, phoning home), but keep KOReader fully usable** — its built-in updater and its built-in dictionary downloader. These are the hosts KOReader actually contacts, taken from KOReader's own source code and checked on 2026-11-04:

| Host | Port | Needed for | Source / how verified |
| --- | --- | --- | --- |
| `ota.koreader.rocks` | 80 | KOReader OTA update — **default server**. Version check and update files are on this same host (no redirect). | `ota_servers` in [otamanager.lua](https://github.com/koreader/koreader/blob/master/frontend/ui/otamanager.lua); fetched the Kindle `.zsync` file, its download URL is relative (same host) |
| `koreader-fr.ak-team.com`, `koreader-pl.ak-team.com`, `koreader-na.ak-team.com`, `koreader.ak-team.com` | 80 | KOReader OTA mirrors (selectable in KOReader's update settings) | same `ota_servers` list |
| `gitlab.com` | 443 | Dictionary downloads — most dictionaries, including KOReader's own set | download URLs in [dictionaries.lua](https://github.com/koreader/koreader/blob/master/frontend/ui/data/dictionaries.lua); no redirect |
| `github.com` | 443 | Dictionary downloads (Wiktionary series and some others) | dictionaries.lua |
| `release-assets.githubusercontent.com` | 443 | Where `github.com/…/releases/download/…` files actually come from | tested: github.com answers **302 → release-assets.githubusercontent.com** |
| `objects.githubusercontent.com` | 443 | GitHub's older download host, kept in case some files still use it | not seen in testing; kept as a precaution |
| `api.github.com` | 443 | Kept from earlier versions (GitHub API) | — |
| `cyphar.github.io` | 443 | Japanese dictionaries (JMdict, JMnedict) | dictionaries.lua; no redirect |
| UDP broadcast `255.255.255.255` (not a site) | 54982, 48123, 39001, 44044, 59678 | Finding calibre on the local network for wireless book transfer (for the planned companion plugin `kindle-kual-calibre-wireless`). The broadcast never leaves your local network. | The UNCaGED library hard-codes the target `255.255.255.255` (`calibre/calibre.go`); the ports are calibre's `BROADCAST_PORTS` (`src/calibre/devices/smart_device_app/driver.py`). calibre's reply comes **in** (INPUT), which this firewall does not filter; the TCP connection to calibre goes to `192.168.x.x`, already allowed. |
| `build.koreader.rocks` | 80 | A few dictionaries (CIA Factbook, GCIDE, Pape) | dictionaries.lua; no redirect |

Both ports 80 and 443 are opened for every host above (KOReader OTA uses plain `http://`, most dictionaries use `https://`).

Not included: two hosts used by single dictionaries in dictionaries.lua (`dicionario-aberto.net`, `http.debian.net`). Add them to `ALLOW_DOMAINS` in `bin/common.sh` if you need those dictionaries.

Things to know:

- `ota.koreader.rocks` and `build.koreader.rocks` sit behind **Cloudflare**, and the GitHub download hosts behind a shared CDN. Allowing their IPs also allows other sites on the same CDN IPs. None of them are Amazon's update servers, so this doesn't weaken the OTA block.
- Installing KOReader **plugins** does not go through the Kindle: plugins are downloaded on a computer and copied over USB, so they need nothing allowed here.

## Files it creates

| File | Where (on the USB drive) | Purpose |
| --- | --- | --- |
| `firewall.log` | `extensions/firewall/firewall.log` | One line per action: rules applied, sites allowed, autostart installed, errors. |
| `diagnose.txt` | `extensions/firewall/diagnose.txt` | Output of **Diagnose**. |
| `diagnose_wifi_events.txt` | `extensions/firewall/diagnose_wifi_events.txt` | Wi-Fi events recorded for 2 minutes after **Diagnose**. |
| `firewall.conf` | `/etc/upstart/firewall.conf` (system partition, not visible over USB) | Boot job, only after **Install Autostart**. |
| `firewall_airplane_shutdown.conf`, `firewall_airplane_boot.conf` | `/etc/upstart/` (system partition) | Only after **Install Airplane-on-Boot**. The shutdown one runs only during a real shutdown/reboot and is limited to 10 s, so it can't hang shutdown. |

`WIFI_NO_NET_PROBE` at the drive root is not created by the extension — it comes in the zip (see [Installation](#installation)).

### Checking that it works

1. Firewall ▸ **Enable Firewall**, then turn Wi-Fi on.
2. Wait about a minute, connect USB, open `extensions/firewall/firewall.log`.
3. You should see lines like:
   ```
   2026-11-04 05:31:20  Basic rules applied (WAN blocked)
                        Chinese | 基本規則已套用（WAN 已阻斷）
   2026-11-04 05:31:20  Background process started (pid 1234, cmState=NA wlan0= dns=)
                        Chinese | 背景程序已啟動（狀態見上一行）
   2026-11-04 05:31:23  Wi-Fi up, resolving (cmState=CONNECTED wlan0=192.168.1.50 dns=192.168.1.1)
                        Chinese | Wi-Fi 已連上，開始查詢放行網域（狀態見上一行）
   2026-11-04 05:31:24  Wi-Fi connected: allowed 12 domains, IPs: 104.21.x.x 172.67.x.x 172.65.x.x …
                        Chinese | Wi-Fi 已連上：已放行上一行的網域
   ```
   Every entry is written twice: an English line with the time, then an indented line starting with `Chinese |` — the same message in Chinese. You can skip the `Chinese |` lines.

While Wi-Fi is off the extension just waits (it checks again at least every 5 minutes as a safety net). `Wi-Fi down` / `Round n/6: … not resolved` lines show what happened if something goes wrong — the `nslookup` error at the end of a `Round` line is the useful part. If you see `Could not resolve (will retry on next connection): <sites>`, those sites couldn't be looked up even after a minute of retrying while connected; they are tried again the next time Wi-Fi connects. If it is always the same mirror, that mirror is probably down; everything else already works. `firewall.log` is trimmed automatically when it grows past about 100 KB.

## Known limitations

- **Without Autostart, rules are lost on reboot.** Press Enable again, or use Install Autostart.
- **IP addresses can change**, especially for sites behind Cloudflare/CDNs. They are looked up again each time Wi-Fi reconnects; if downloads fail while staying connected for a long time, turn Wi-Fi off and on (or press Enable again).
- **IPv4 only.** The tested Kindle has no IPv6 (`ip6tables` not present), so IPv6 is not handled.
- **Wi-Fi error while the firewall is on** → `WIFI_NO_NET_PROBE` is missing, misnamed, or the Kindle wasn't rebooted after adding it. See [A reboot is required](#a-reboot-is-required-after-installing).
- **Firmware updates remove Autostart and Airplane-on-Boot**, since they overwrite the system partition (but the firewall's purpose is to block those updates).
- If a boot job ever stops the Kindle from booting normally, delete `/etc/upstart/firewall.conf` (and `firewall_airplane_*.conf`) over SSH. The boot job is written to do nothing if the extension folder is missing.

## Uninstall

1. Firewall ▸ **Remove Autostart** and **Remove Airplane-on-Boot** (if you installed them).
2. Firewall ▸ **Disable Firewall**.
3. Delete `extensions/firewall` over USB.
4. Delete `WIFI_NO_NET_PROBE` from the drive root and reboot, so the Kindle checks the internet connection normally again. (Optional — keeping it does no harm.)

## Customizing for your Kindle with AI

The boot timing (`starting lab126`) and some other details were chosen based on the tested Kindle's `diagnose.txt`. Your model may differ. You can have an AI assistant (Claude, ChatGPT, etc.) adapt it, even if you can't code.

### Step 1 — Collect information from your Kindle

1. Install the extension as above.
2. Firewall ▸ **Enable Firewall**, turn Wi-Fi on, wait a minute (so the log shows whether the allowed sites resolved).
3. Firewall ▸ **Diagnose**, then within 2 minutes turn Wi-Fi off and on again.
4. Wait until the 2 minutes are over, then over USB copy out `extensions/firewall/diagnose.txt` and `extensions/firewall/diagnose_wifi_events.txt`.

`diagnose.txt` contains your Kindle's firmware version, system file list and firewall rules. It contains no account data, but look through it before sharing it.

### Step 2 — Send these to the AI

Start a **new** conversation and attach:

1. `firewall.zip` (the original release file — it contains `extensions/firewall/` and `WIFI_NO_NET_PROBE`)
2. your `diagnose.txt` and `diagnose_wifi_events.txt`

Then paste this message (edit the last part):

```
I'm using the KUAL extension "kindle-kual-firewall" (https://github.com/bgtsai/kindle-kual-firewall) on my jailbroken Kindle. Attached are the extension (firewall.zip) and diagnose.txt from my Kindle.

Please read CLAUDE.md in the repo (or the "Notes for AI" section of the README) first, then check my diagnose.txt section by section:
- "upstart start/stop triggers": do wifid / otaupd / otav3 start after lab126? Is "starting lab126" still the right boot hook for my Kindle?
- "nslookup github.com": does the output format match the parser in bin/common.sh?
- "tools": is ip6tables present? If yes, block IPv6 outbound too.
- "conntrack / state modules": which one works?
- "firewall.log": did all allowed sites get resolved after Enable?
- "mounts": is the root filesystem read-only (needs mntroot rw)?

Tell me what needs to change for my Kindle and why, before changing anything. Then give me a new firewall.zip with the same structure (extensions/firewall/... plus WIFI_NO_NET_PROBE at the top level) and bump the version in config.xml.

My changes: <describe what you want, e.g. "my home network is 10.0.0.x", or "nothing extra, just make it work on my Kindle">
```

### Step 3 — Install the result

Replace `extensions/firewall` on your Kindle with the new folder (keep `WIFI_NO_NET_PROBE` at the root), reboot if anything about Wi-Fi changed, then run through [Checking that it works](#checking-that-it-works) again. If you used Autostart before and the AI changed the boot job, press **Remove Autostart** with the old version first, then **Install Autostart** with the new one.

## Notes for AI

See [CLAUDE.md](CLAUDE.md) — it lists which parts are model-specific and what to check after editing.

## References

Sources used while designing this extension:

- Wi-Fi connectivity check (`spectrum.s3.amazonaws.com/kindle-wifi/wifistub.html`) and that the Kindle won't join a network when it fails: [MobileRead – wifistub connectivity check](https://www.mobileread.com/forums/showthread.php?p=2874926), [MobileRead – Kindle Touch phoning home when first connecting to a WiFi network](https://www.mobileread.com/forums/showthread.php?p=2962466)
- `WIFI_NO_NET_PROBE` flag file (`/mnt/us/WIFI_NO_NET_PROBE` → `wifid -n`): [MobileRead – Kindle Touch phoning home…](https://www.mobileread.com/forums/showthread.php?p=2962466), [Kindle联网问题分析 (heary.cn)](https://heary.cn/posts/Kindle%E8%81%94%E7%BD%91%E9%97%AE%E9%A2%98%E5%88%86%E6%9E%90/)
- Firmware update files are hosted on Amazon S3: [KindleModding – Manually Downloading Firmware Update Files](https://kindlemodding.org/firmware-and-flashing/downloading-updates.html)
- KUAL extension `config.xml` / `menu.json` format: [Kindle + Python = e-Ink Dashboard (4DCu.be)](https://blog.4dcu.be/diy/2020/09/27/PythonKindleDashboard_1.html), [MobileRead Wiki – KUAL](https://wiki.mobileread.com/wiki/KUAL)
- Alternative OTA blocking by renaming the update binaries (not used here): [GitHub – Darthagnon/BlockKindleOTA](https://github.com/Darthagnon/BlockKindleOTA), [MobileRead – OTA blocking on recent firmware](https://www.mobileread.com/forums/showthread.php?p=4329911)
- KOReader OTA servers (`ota_servers`): [koreader/koreader – frontend/ui/otamanager.lua](https://github.com/koreader/koreader/blob/master/frontend/ui/otamanager.lua)
- KOReader dictionary download URLs: [koreader/koreader – frontend/ui/data/dictionaries.lua](https://github.com/koreader/koreader/blob/master/frontend/ui/data/dictionaries.lua)
- KOReader OTA file listing: [ota.koreader.rocks](http://ota.koreader.rocks/)
- KOReader plugins are installed manually over USB: [Project Title plugin – Installation](https://github.com/joshuacant/ProjectTitle/wiki/Installation)
- Amazon's own Wi-Fi troubleshooting page: [Resolve Wi-Fi Connection Issues on Your Kindle E-Reader](https://digprjsurvey.amazon.com/csad/help/node/G5HYWUVWRXFSCH7E)

## License

[MIT](LICENSE)
