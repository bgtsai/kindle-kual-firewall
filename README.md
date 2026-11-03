[切換中文](README.zh-TW.md)

# kindle-kual-firewall

A KUAL extension for jailbroken Kindles. It blocks all outbound internet traffic — including Amazon OTA firmware updates — while still allowing:

- your local network (`192.168.x.x`)
- DNS lookups
- HTTPS to GitHub (so KOReader can still update itself)

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
    Diagnose (write diagnose.txt)
```

| Item | What it does |
| --- | --- |
| **Enable Firewall** | Blocks the internet immediately. Then keeps trying (every 30 s, in the background) to look up GitHub's IP addresses, and allows them as soon as Wi-Fi is up. So it's fine to press this while Wi-Fi is off. |
| **Disable Firewall** | Removes all blocking rules and allows all traffic again. |
| **Install Autostart** | Installs a boot job (`/etc/upstart/firewall.conf`) so the firewall turns on at every boot, before Wi-Fi and the OTA service start. This writes to the Kindle's system partition. |
| **Remove Autostart** | Deletes that boot job. |
| **Diagnose** | Writes system information to `diagnose.txt` (read-only, changes nothing). Used for troubleshooting and for customizing the extension for another model. |

## What exactly is allowed

| Allowed | Notes |
| --- | --- |
| Loopback (`lo`) | Internal communication between programs on the Kindle |
| `192.168.0.0/16` | Your local network, any port. `10.x.x.x` and `172.16–31.x.x` are **not** allowed. |
| DNS (port 53) | To any DNS server |
| HTTPS to `api.github.com`, `github.com`, `objects.githubusercontent.com` | IPs looked up when you press Enable |
| Replies to allowed connections | |

Everything else outbound is dropped.

## Files it creates

| File | Where (on the USB drive) | Purpose |
| --- | --- | --- |
| `firewall.log` | `extensions/firewall/firewall.log` | One line per action: rules applied, GitHub allowed, autostart installed, errors. |
| `diagnose.txt` | `extensions/firewall/diagnose.txt` | Output of **Diagnose**. |
| `firewall.conf` | `/etc/upstart/firewall.conf` (system partition, not visible over USB) | Boot job, only after **Install Autostart**. |

`WIFI_NO_NET_PROBE` at the drive root is not created by the extension — it comes in the zip (see [Installation](#installation)).

### Checking that it works

1. Firewall ▸ **Enable Firewall**, then turn Wi-Fi on.
2. Wait about a minute, connect USB, open `extensions/firewall/firewall.log`.
3. You should see lines like:
   ```
   基本規則已套用（WAN 已阻斷）
   已放行 github.com: 140.82.x.x
   GitHub 放行完成
   ```
   (The log messages are in Chinese: "basic rules applied (WAN blocked)", "allowed github.com", "GitHub allowed — done".)

If "GitHub 放行完成" never appears, the Kindle couldn't look up GitHub — usually because Wi-Fi isn't connected yet. It keeps retrying until it succeeds.

## Known limitations

- **Without Autostart, rules are lost on reboot.** Press Enable again, or use Install Autostart.
- **GitHub IPs can change.** If KOReader updates start failing days later, press Enable again.
- **IPv4 only.** The tested Kindle has no IPv6 (`ip6tables` not present), so IPv6 is not handled.
- **Wi-Fi error while the firewall is on** → `WIFI_NO_NET_PROBE` is missing, misnamed, or the Kindle wasn't rebooted after adding it. See [A reboot is required](#a-reboot-is-required-after-installing).
- **Firmware updates remove Autostart**, since they overwrite the system partition (but the firewall's purpose is to block those updates).
- If an Autostart mistake ever stops the Kindle from booting normally, delete `/etc/upstart/firewall.conf` over SSH. The boot job is written to do nothing if the extension folder is missing.

## Uninstall

1. Firewall ▸ **Remove Autostart** (if you installed it).
2. Firewall ▸ **Disable Firewall**.
3. Delete `extensions/firewall` over USB.
4. Delete `WIFI_NO_NET_PROBE` from the drive root and reboot, so the Kindle checks the internet connection normally again. (Optional — keeping it does no harm.)

## Customizing for your Kindle with AI

The boot timing (`starting lab126`) and some other details were chosen based on the tested Kindle's `diagnose.txt`. Your model may differ. You can have an AI assistant (Claude, ChatGPT, etc.) adapt it, even if you can't code.

### Step 1 — Collect information from your Kindle

1. Install the extension as above.
2. Firewall ▸ **Enable Firewall**, turn Wi-Fi on, wait a minute (so the log shows whether GitHub works).
3. Firewall ▸ **Diagnose**.
4. Over USB, copy out `extensions/firewall/diagnose.txt`.

`diagnose.txt` contains your Kindle's firmware version, system file list and firewall rules. It contains no account data, but look through it before sharing it.

### Step 2 — Send these to the AI

Start a **new** conversation and attach:

1. `firewall.zip` (the original release file — it contains `extensions/firewall/` and `WIFI_NO_NET_PROBE`)
2. your `diagnose.txt`

Then paste this message (edit the last part):

```
I'm using the KUAL extension "kindle-kual-firewall" (https://github.com/bgtsai/kindle-kual-firewall) on my jailbroken Kindle. Attached are the extension (firewall.zip) and diagnose.txt from my Kindle.

Please read CLAUDE.md in the repo (or the "Notes for AI" section of the README) first, then check my diagnose.txt section by section:
- "upstart start/stop triggers": do wifid / otaupd / otav3 start after lab126? Is "starting lab126" still the right boot hook for my Kindle?
- "nslookup github.com": does the output format match the parser in bin/common.sh?
- "tools": is ip6tables present? If yes, block IPv6 outbound too.
- "conntrack / state modules": which one works?
- "firewall.log": did GitHub get allowed after Enable?
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
- Amazon's own Wi-Fi troubleshooting page: [Resolve Wi-Fi Connection Issues on Your Kindle E-Reader](https://digprjsurvey.amazon.com/csad/help/node/G5HYWUVWRXFSCH7E)

## License

[MIT](LICENSE)
