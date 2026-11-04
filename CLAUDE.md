# CLAUDE.md — notes for AI assistants

This repo is a KUAL extension for jailbroken Kindles. Users usually come with **`firewall.zip` + their own `diagnose.txt`** and ask you to adapt it to their Kindle. Read this file first.

## Layout

`kindle/` mirrors the root of the Kindle drive; `firewall.zip` is exactly its contents.

```
kindle/
├── WIFI_NO_NET_PROBE     empty flag file; wifid reads /mnt/us/WIFI_NO_NET_PROBE at start → runs with -n (no connectivity probe)
└── extensions/
    └── firewall/             ← the extension; folder name must equal <id> in config.xml
        ├── config.xml            KUAL metadata (<information> + <menus>); bump <version> on every change
        ├── menu.json             one top-level "Firewall" item; all actions in its "items" submenu
        └── bin/
            ├── common.sh         shared paths, ALLOW_DOMAINS, resolve_ipv4(), log(), notify()
            ├── enable.sh         base rules now, allow-list (KOReader OTA + dictionary hosts) added later by a background retry loop
            ├── disable.sh        stop retry loop, flush OUTPUT, policy ACCEPT
            ├── autostart_install.sh   mntroot rw → write /etc/upstart/firewall.conf → mntroot ro
            ├── autostart_remove.sh    mntroot rw → delete it → mntroot ro
            └── diagnose.sh       read-only; writes firewall/diagnose.txt, then records Wi-Fi/cmd lipc events for 120 s in background → diagnose_wifi_events.txt
.github/workflows/release.yml   on push to main touching kindle/**: zips kindle/ contents into firewall.zip, releases v<version> (skips if exists)
```

Always deliver the result as `firewall.zip` whose top level is `extensions/` + `WIFI_NO_NET_PROBE` (users copy both to the Kindle drive root, then reboot).

## Model-specific parts — check these against the user's diagnose.txt

| Part | Where | What to check in diagnose.txt |
| --- | --- | --- |
| Boot hook `start on starting lab126` | `autostart_install.sh` | `upstart start/stop triggers`: `wifid`, `otaupd`, `otav3` must start on `started lab126` (or later). If OTA or Wi-Fi starts earlier, pick an earlier event. If `/etc/upstart/` doesn't exist (firmware < 5.x), upstart autostart does not apply at all. |
| `nslookup` output parsing | `common.sh` `resolve_ipv4()` | `nslookup github.com` section. Parser takes IPv4 tokens on `Address` lines **after** the `Name:` line (the first Address is the DNS server, `127.0.0.1` on the tested device). |
| conntrack vs state | `enable.sh` | `conntrack / state modules`. Code already falls back from conntrack to state. |
| IPv6 | not implemented | `tools`: if `ip6tables` exists and `IPv6 addresses` is non-empty, add equivalent ip6tables rules (tested device had neither). |
| Root fs read-only | `autostart_*.sh` | `mounts`: `/dev/root on / ... (ro,...)` → `mntroot rw/ro` needed. Check `mntroot` exists in `tools`. |
| Wi-Fi connectivity probe | `kindle/WIFI_NO_NET_PROBE` | Kindle probes `spectrum.s3.amazonaws.com/kindle-wifi/wifistub.html` after joining Wi-Fi; the firewall blocks it → Wi-Fi error. The flag file disables the probe (confirmed on 5.13.5; read only when wifid starts → reboot needed). If the user's Kindle ignores the flag, look for how `wifid.conf` builds its arguments. Do **not** solve it by allowing S3 IPs: firmware updates are also on S3. |
| calibre broadcast | `common.sh` `CALIBRE_BROADCAST_PORTS`, `enable.sh` | OUTPUT UDP to `255.255.255.255` on calibre's 5 broadcast ports (UNCaGED hard-codes 255.255.255.255). INPUT (calibre's reply) is the calibre plugin's job, not this firewall's. |
| LAN range | `enable.sh` | User's network may be `10.0.0.0/8` or `172.16.0.0/12` instead of `192.168.0.0/16`. Ask. |

Tested device: firmware 5.13.5, kernel 4.1.15-lab126, busybox nslookup, `iptables` at `/usr/sbin/iptables`, no `ip6tables`.

## Design decisions (don't undo without a reason)

- **Base rules first, allow-list later.** With Wi-Fi off, DNS fails; the old version then added no allow rule and never recovered. Allow rules are inserted with `-I OUTPUT 1` so they sit before the final DROP.
- **Allow-list = what KOReader actually contacts** (OTA servers from `otamanager.lua`, dictionary hosts from `dictionaries.lua`), ports 80 and 443. Before adding a host, check it in KOReader's source and test for redirects (`curl -sI`); github.com release downloads redirect to `release-assets.githubusercontent.com`. Keep README's "Why these sites are allowed" table in sync.
- **Boot job must never block boot.** It only calls `enable.sh` if the file exists, and `enable.sh` backgrounds the slow part. Keep it a `task` on `starting lab126` so it finishes before Wi-Fi/OTA start.
- **Retry loop is single-instance** via `/var/run/firewall_resolver.pid`; Enable and Disable kill the previous one.
- Errors are written to `firewall.log`, never silently swallowed.
- **Bilingual log**: `log "<English>" "<中文>"` writes an English line with timestamp, then an indented `Chinese | …` line. Data (domains, IPs, paths) goes only in the English line. Every new log call must pass both strings; update README "Checking that it works" if messages change.

## After editing

1. `sh -n` every script in `kindle/extensions/firewall/bin/`.
2. Validate `menu.json` (JSON) and `config.xml` (XML). Keep `kindle/WIFI_NO_NET_PROBE` present (empty).
3. Bump `<version>` in `config.xml` and the `vX.Y` in each changed script's header comment.
4. If you changed `enable.sh` logic, test it with stub `iptables`/`nslookup` scripts on PATH (simulate DNS failing a few times, then succeeding).
5. Grep for leftover old names/paths if you renamed anything (folder name, `/etc/upstart/firewall.conf`, `firewall.log`).
6. Tell the user what was verified by you vs. what only the real device can confirm.
7. If the boot job changed, tell the user to run **Remove Autostart** with the old version before installing the new one.
