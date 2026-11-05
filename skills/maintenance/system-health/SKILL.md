---
name: system-health
summary: Read-only health check covering pending reboot, updates, boot and failed services, memory hogs, disk and reclaimable space, firewall and exposed ports, battery, power, and startup items. Ends with a list of warnings.
triggers:
  - "health check" / "check my system" / "how's my PC doing"
  - "any suggestions to improve performance / quality of life"
  - "why is it slow" (as a first look)
  - periodic check-ups, and before/after a batch of changes
platforms: [linux, macos, bsd, windows (untested)]
scope: shared
tier: 0
needs_admin: false
command: pca-health
scripts:
  posix: pca-health.sh
  windows: pca-health.ps1
version: 1.0
updated: 2026-11-05
---

# system-health

## Purpose
A quick report (about 5 s, or under 1 s with `--offline`) that turns "any suggestions?" into concrete findings. It **changes nothing**. Each check runs only if its tool exists (`command -v` / `Get-Command`), so the same script works on Debian/Fedora/Arch/openSUSE/Alpine, macOS, and the BSDs. It works without admin rights.

## Usage
- `pca-health`: full report.
- `pca-health --offline`: skip checks that contact the network (snap, flatpak, dnf, pacman, firmware, macOS/Windows Update, winget).
- Windows: `pca-health` / `pca-health -Offline` (via the `.cmd` shim).

Output: one section per area. Each line is `[ok]`, `[info]` (worth knowing), or `[WARN]` (worth acting on), then a summary of the warnings.

| Section | Checks |
|---|---|
| System | OS, kernel, uptime, **pending reboot** (`/var/run/reboot-required`, `needs-restarting -r`, running kernel no longer installed; Windows: CBS / WU / pending file renames) |
| Boot & services | `systemd-analyze` time, failed system and user units (Windows: auto-start services stopped with an error) |
| Memory | available RAM and swap, PSI memory pressure, **top 8 programs by RAM**, summed across processes |
| Disk | use of `/` and `$HOME` (warn at 85% or more), journal size, the largest `~/.cache` folders, trash, apt cache, old snap revisions, number of installed kernels |
| Updates | apt (ready / phased / kept back / list age / **autoremove preview**), zypper, apk, brew, dnf, pacman, snap, flatpak, fwupd, macOS `softwareupdate`; Windows Update and winget |
| Firewall & exposure | ufw / firewalld / nftables / macOS firewall / Windows profiles plus Defender; **TCP ports listening beyond localhost**, with the owning program |
| Battery & power | charge, **health versus design capacity**, cycles, power profile, CPU driver and governor, temperatures (`sensors`) |
| Startup items | XDG autostart (system-wide, hidden, the user's own), enabled user services; macOS LaunchAgents/Daemons; Windows startup commands and non-Microsoft scheduled tasks |

## Steps (when the user asks for a check-up or suggestions)
1. Run `pca-health` (Tier 0). Dig deeper with targeted read-only commands where a line needs context. For example, *who* owns an exposed port, or *what* depends on a big memory user (such as a database container used by another project).
2. Turn the findings into suggestions, each with a one-line why and its tier. Present them as a pick list (recommendation first). Don't fix anything not asked for (CLAUDE.md §4.6).
3. Carry out the chosen items, each under its own change ID, with backups and undo steps. Use the specific skills where they exist.
4. Run `pca-health` again and compare it with the first run.

## Interpreting common findings (lessons learned)
- **Phased updates** (Ubuntu): `apt` holds back a gradually rolled-out update. Don't force it; it arrives on its own.
- **`apt autoremove` preview**: check every package. It can list libraries that are still in use (e.g. a VPN client's plugin). Protect them with `apt-mark manual <pkg>` instead of removing them.
- **Old snap revisions**: before running `snap remove --revision`, check that no running app maps that revision (`grep -l /snap/<name>/<rev>/ /proc/*/maps`). A long-running Firefox often still runs from the "disabled" one, and removing it can crash the browser.
- **Freed space doesn't appear in `df`** right after a cleanup when rsync-mode Timeshift snapshots exist: they hard-link the deleted files. The space comes back as snapshots rotate.
- **Caches locked by running tools** (e.g. `uv cache prune` waits for running `uv run` processes): skip the prune; don't `--force` it.
- **Port listening on 0.0.0.0 with the firewall off**: turn on the firewall (default deny incoming) and suggest the app bind to `127.0.0.1`. Changing another project's code is out of scope.

## Verification
The script exits 0 and prints `== Summary`. If a section is missing on an OS, its tools weren't found. That's expected, not an error.

## Rollback
Nothing to roll back: the script is read-only.

## Logging
Running it doesn't need a CHANGELOG entry. Record notable findings, and the suggestions the user chose or declined, in the journal.

## Platform status
- Linux (Ubuntu 26.04, GNOME, systemd, apt/snap/flatpak, ufw): tested 2026-11-05.
- Other distros, macOS, BSD: branches written with guards, not yet tested.
- Windows `pca-health.ps1`: **untested** (no PowerShell on the dev machine).

## Changelog
- 1.0 (2026-11-05): created from the first manual health check.
