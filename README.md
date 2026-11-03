[切換中文](README.zh-TW.md)

# kindle-kual-firewall

A KUAL extension for jailbroken Kindles. It blocks all outbound internet traffic — including Amazon OTA firmware updates — while still allowing:

- your local network (`192.168.x.x`)
- DNS lookups
- HTTPS to GitHub (so KOReader can still update itself)

It can also start automatically on boot, so the firewall is active before Wi-Fi and the OTA service start.

> **Tested on:** Kindle firmware 5.13.5 (kernel 4.1.15). Other models may need adjustments — see [Customizing for your Kindle with AI](#customizing-for-your-kindle-with-ai).

## Requirements

- A **jailbroken** Kindle
- **KUAL** (Kindle Unified Application Launcher) installed
- A USB cable to copy files

## Installation

1. Go to [Releases](../../releases/latest) and download **`firewall.zip`**.
   (Do not use GitHub's green "Code → Download ZIP" button — it adds an extra folder level.)
2. Unzip it. You get a folder named `firewall`.
3. Connect the Kindle to your computer with USB. The Kindle shows up as a drive.
4. Copy the **whole `firewall` folder** into the `extensions` folder on that drive.
5. Eject the Kindle, open KUAL. You should see a **Firewall** entry.

### The folder structure must look exactly like this

```
Kindle drive (root)
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
| `extensions/firewall/firewall/config.xml` | One folder level too deep — KUAL won't find it. Happens when unzipping into a folder that is already named `firewall`. |
| `extensions/firewall-main/...` | Folder renamed by GitHub's "Download ZIP". The folder name must match the `<id>` in `config.xml` (`firewall`). |
| `config.xml` directly inside `extensions/` | Every extension needs its own folder. |

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
- **Firmware updates remove Autostart**, since they overwrite the system partition (but the firewall's purpose is to block those updates).
- If an Autostart mistake ever stops the Kindle from booting normally, delete `/etc/upstart/firewall.conf` over SSH. The boot job is written to do nothing if the extension folder is missing.

## Uninstall

1. Firewall ▸ **Remove Autostart** (if you installed it).
2. Firewall ▸ **Disable Firewall**.
3. Delete `extensions/firewall` over USB.

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

1. `firewall.zip` (the original release file)
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

Tell me what needs to change for my Kindle and why, before changing anything. Then give me a new firewall.zip with the same folder structure (extensions/firewall/...) and bump the version in config.xml.

My changes: <describe what you want, e.g. "my home network is 10.0.0.x", or "nothing extra, just make it work on my Kindle">
```

### Step 3 — Install the result

Replace `extensions/firewall` on your Kindle with the new folder, then run through [Checking that it works](#checking-that-it-works) again. If you used Autostart before and the AI changed the boot job, press **Remove Autostart** with the old version first, then **Install Autostart** with the new one.

## Notes for AI

See [CLAUDE.md](CLAUDE.md) — it lists which parts are model-specific and what to check after editing.

## License

[MIT](LICENSE)
