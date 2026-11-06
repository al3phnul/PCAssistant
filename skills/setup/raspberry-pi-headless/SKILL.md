---
name: raspberry-pi-headless
summary: Image a Raspberry Pi with no monitor or keyboard. Install Raspberry Pi Imager, create an SSH key, flash a pre-configured OS to SD/USB/NVMe, find the Pi on the network, then do first-boot setup over SSH (admin access, updates, auto-updates, firewall, bootloader, Wi-Fi off if wired).
triggers:
  - "set up / reimage / reflash my Raspberry Pi"
  - "Raspberry Pi without a monitor / keyboard", "headless Pi"
  - "install Raspberry Pi Imager"
  - "find my Pi on the network", "can't reach my Pi"
platforms: [linux, macos, windows] (host side; the Pi runs Raspberry Pi OS)
scope: shared
tier: 2
needs_admin: to install Imager; on the Pi for first-boot setup
command: pca-pi-find
scripts:
  posix: pca-pi-find.sh
  windows: pca-pi-find.ps1
version: 1.0
updated: 2026-11-05
---

# raspberry-pi-headless

## Purpose
Get a Raspberry Pi from "blank (or forgotten-password) media" to "managed remotely over SSH" without ever plugging in a screen, keyboard, or mouse. Re-imaging later takes a few clicks, because Imager remembers the settings.

**Golden rule:** the user types every password (the Pi account password, the Wi-Fi password, the sudo prompt) into Imager or their own terminal. Claude never asks for, sees, or logs them (CLAUDE.md §3, §4.5).

## Inputs (ask the user, with recommendations)
| Question | Recommendation / notes |
|---|---|
| Pi model | Check it after the first boot (`cat /proc/device-tree/model`); users often guess wrong. USB boot: Pi 5 yes; Pi 4/400 yes on boards since about 2020 (older ones: flash *Misc utility images → Bootloader → USB Boot* to an SD card first); Pi 3B+ yes; Pi 3B / Zero 2 W: use an SD card. |
| Network | **Ethernet** if it will stay cabled (most reliable first boot). Wi-Fi: the user enters SSID, password, and **Wi-Fi country** in Imager. **Not both** on the same network (see Gotchas). |
| OS | **Raspberry Pi OS Lite (64-bit)** for headless. Desktop only if they want a remote GUI (via Raspberry Pi Connect screen sharing). |
| Remote access | **SSH with public-key only** (default). Optional *Raspberry Pi Connect*: browser shell/screen from anywhere; needs a Raspberry Pi ID that the user signs into in Imager. |
| SSH key passphrase | Passphrase (recommended; the desktop keyring agent remembers it) or none (convenient; anyone who can read the key files owns the Pi). |
| Admin on the Pi | Imager 2.x users must type a password for sudo. Options: full passwordless sudo (common for headless), a scoped list, or keep the password (user runs admin commands). |
| Hostname / username | Hostname: letters, digits, `-`. Matching the laptop username makes `ssh <host>` work without `user@`. |

## Steps
### 1. Install Raspberry Pi Imager (Tier 2) on the host
Use **Imager 2.0 or later**. Older versions (e.g. distro packages at 1.8.x) can't reliably apply customisation to current Raspberry Pi OS (Debian 13 "trixie" uses cloud-init), and a headless image then boots with no user, no SSH, and no Wi-Fi.
- **Linux:** check the distro version first (`apt-cache policy rpi-imager`, `dnf info rpi-imager`, …). If it's below 2.0, recommend the official release from `github.com/raspberrypi/rpi-imager/releases`: a `.deb` for Debian/Ubuntu (install with `apt install ./file.deb`, which adds no repo; it updates manually) or the AppImage. Flathub `org.raspberrypi.rpi-imager` is the auto-updating alternative (sandboxed drive access has had bugs). **Verify the download** against the release's `SHA256SUMS` (CLAUDE.md §4.4) and inspect the package (`dpkg-deb -I`, `-c`, maintainer scripts) before installing. The `.deb` adds a polkit action (Imager asks for the user's password at launch) and a udev rule for Pi USB-boot devices.
- **macOS:** `brew install --cask raspberry-pi-imager`, or the `.dmg` from raspberrypi.com/software.
- **Windows:** `winget search "Raspberry Pi Imager"`, then `winget install <id>`, or the `.exe` from raspberrypi.com/software.

### 2. SSH key and shortcut (Tier 1)
- No key yet: `ssh-keygen -t ed25519 -C "<user>@<host> (pca)"`. Without a passphrase, add `-N ""`; with one, **the user runs it** and types the passphrase. Windows 10/11 ships OpenSSH (`ssh-keygen` in PowerShell).
- Add a `~/.ssh/config` entry (back it up first if it exists):
  ```
  Host <hostname-lowercase> <short-alias>
      HostName <hostname>.local
      User <pi-username>
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      ServerAliveInterval 30
      AddressFamily inet        # if the Pi firewall allows only the IPv4 LAN
  ```
- Show the user the **public** key (`cat ~/.ssh/id_ed25519.pub`) to paste into Imager. Never print the private key.

### 3. The user flashes (Claude can't drive the GUI)
Give exact values: **Device** → **OS** (Raspberry Pi OS (other) → Lite 64-bit) → **Storage** (warn: it's wiped, so double-check the drive). Then **customisation**: hostname; username + password (user types it); Wi-Fi SSID/password/country, or skip for Ethernet; time zone + keyboard (take them from the host: `timedatectl`, `localectl`); **SSH on, public-key only**, paste the key; Pi Connect off unless chosen. Write. Then: **remove other boot media** (SD card) if booting from USB, use a **USB 3 (blue) port** on a Pi 4, and power on. The first boot takes 2–3 min and reboots once.

### 4. Find it and connect (Tier 0)
- `pca-pi-find <hostname>`: resolves `<hostname>.local` (and the `-2`…`-9` conflict names), then sweeps the local subnet for Raspberry Pi MAC prefixes. Run it with no argument if the name is unknown.
- Re-imaged Pi, same name: first `ssh-keygen -R <hostname>.local`, because the new host key would otherwise be refused.
- First connection: `ssh -o StrictHostKeyChecking=accept-new <alias> true`, then record the host key fingerprint (`ssh-keygen -lF <hostname>.local`) in the profile.
- If mDNS fails, connect by IP with `-o HostKeyAlias=<hostname>.local`, so the known_hosts entry still matches.

### 5. Inspect (Tier 0)
Model, OS, kernel, boot device (`findmnt /`, `lsblk`), addresses per interface, `sudo -n true`, SSH auth (`sshd -T` needs root; a quick check is `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password …`, which should say `Permission denied (publickey)`), package-list age, `rpi-eeprom-update`, `vcgencmd get_throttled`, failed units, listening ports.

### 6. Admin access on the Pi (Tier 2, the user's choice)
Stage the rule in the Pi user's home and validate it, then have the **user** install it (sudo asks for the Pi password once):
```
ssh <alias> 'printf "%s\n" "<user> ALL=(ALL:ALL) NOPASSWD: ALL" > ~/pca-sudoers && chmod 0440 ~/pca-sudoers && /usr/sbin/visudo -cf ~/pca-sudoers'
# the user runs:
ssh -t <alias> 'sudo install -m 0440 -o root -g root ~/pca-sudoers /etc/sudoers.d/020_pca && sudo visudo -c && rm -f ~/pca-sudoers && echo DONE'
```
(Use `rm -f`: plain `rm` stops to ask about the read-only file, which confuses people.) For a scoped rule, list absolute command paths as in first-time-setup's sudoers guidance.

### 7. First-boot setup menu (Tier 2: offer as a pick list, do the chosen ones)
1. **Updates:** `sudo apt-get update && sudo env DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold` (preview with `apt-get -s` first). Kernel updates need the reboot in step 7.5.
2. **Automatic security updates:** `apt-get install unattended-upgrades apt-listchanges`. Check `apt-config dump | grep Periodic` and `unattended-upgrade --dry-run -v` (Debian + security origins; Raspberry Pi repo packages stay manual).
3. **Firewall** (ufw, SSH from the LAN only), with a **failsafe against lockout**:
   ```
   sudo apt-get install -y ufw
   sudo ufw default deny incoming; sudo ufw default allow outgoing
   sudo ufw allow from <LAN-CIDR> to any port 22 proto tcp comment "SSH from LAN"
   sudo systemd-run --on-active=5min --unit=pca-ufw-failsafe /usr/sbin/ufw disable   # failsafe first
   sudo ufw --force enable
   # test with a NEW ssh connection, then:  sudo systemctl stop pca-ufw-failsafe.timer
   ```
   ufw's `before.rules` already allows mDNS, so `<hostname>.local` keeps working.
4. **Wired only? Disable Wi-Fi:** first check the SSH session runs over Ethernet (`echo $SSH_CONNECTION`). Then append `[all]` + `dtoverlay=disable-wifi` to `/boot/firmware/config.txt` (back it up via `scp`), run `sudo nmcli radio wifi off` now, and `sudo systemctl restart avahi-daemon`.
5. **Bootloader (Pi 4/5):** save `sudo rpi-eeprom-config` output to the backups, then `sudo rpi-eeprom-update -a` and `sudo systemctl reboot`. Wait for SSH to return (about 25 s on a Pi 5), then check that `rpi-eeprom-update` reports up to date and `BOOT_ORDER` is unchanged.
6. Verify: no failed units, ufw active, the expected boot device, `get_throttled=0x0`, `ssh <alias>` by name.

### 8. Record the device
Add the Pi to `profile/SYSTEM.md` → *Managed devices* (model, OS, boot media, hostname, access, host key fingerprint, sudo mode, firewall, auto-updates). Tag its CHANGELOG entries `[<hostname>]`. Keep copies of edited Pi files under `logging/backups/<ID>/<hostname>/<path>`.

## Gotchas (learned the hard way)
- **Ethernet + Wi-Fi on the same LAN makes avahi rename the Pi** to `<name>-2.local`, `-3`, …: it sees its own announcement on the other interface as a conflict. `<name>.local` then stops resolving once the host's cache expires. Fix: use one interface (wired → step 7.4), then restart avahi-daemon. `pca-pi-find` detects and explains this.
- **Imager 2.x doesn't give the user passwordless sudo** (older Raspberry Pi OS did). Plan step 6.
- **Old Imager versions silently skip customisation** on trixie images: no SSH and no user, so the Pi is unreachable. Use Imager ≥ 2.0.
- **No snapshot tool on the Pi:** re-flashing the media with Imager's saved settings is the rollback. Say so before Tier 2 changes (CLAUDE.md §4.3).
- **The Pi firewall's LAN rule is IPv4:** pin `AddressFamily inet` in the host's ssh config, or add IPv6 rules.
- **The host's own firewall** (e.g. ufw deny incoming) doesn't block outgoing SSH or mDNS replies; nothing to change on the host.

## Verification
`ssh <alias> 'hostname; uname -r; sudo -n ufw status | head -1; systemctl --failed --no-legend'` works by name; `pca-pi-find <hostname>` shows a single name (no `-N` variants) and one Pi MAC.

## Rollback
Re-flash the media in Imager (saved settings). Host side: `apt purge rpi-imager` (or the OS equivalent), delete the ssh config entry and key. Individual Pi changes: undo steps in each CHANGELOG entry.

## Logging
One CHANGELOG entry per change, on the host and on the Pi (Pi entries tagged `[<hostname>]`), plus a journal note. Never log Wi-Fi or account passwords; SSIDs and host key fingerprints are fine in the personal log.

## Platform status
- Host: Linux (Ubuntu 26.04, Imager 2.0.12 .deb) tested end-to-end with a Pi 5 booting Raspberry Pi OS Lite 64-bit (trixie) from a USB thumb drive, 2026-11-05. macOS/Windows host steps are written from docs, untested.
- `pca-pi-find.sh` tested on Linux; the macOS/BSD branches (`ifconfig`/`arp`/`dscacheutil`) are untested. `pca-pi-find.ps1` is untested.

## Changelog
- 1.0 (2026-11-05): created from the first headless re-image.
