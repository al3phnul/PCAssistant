#!/bin/sh
# scan.sh — READ-ONLY system scan for PC Assistant first-time setup (Linux, macOS, BSD, other Unix).
# Prints a markdown report to stdout. Changes nothing. Every probe is optional: missing tools are skipped.
# Usage: sh scan.sh > /some/scratch/scan.md
set -u
has() { command -v "$1" >/dev/null 2>&1; }
kv() { [ -n "${2:-}" ] && printf -- '- **%s:** %s\n' "$1" "$2"; return 0; }
sec() { printf '\n## %s\n' "$1"; }
first() { sed -n '1p'; }

OS=$(uname -s 2>/dev/null)
printf '# System scan\n\n- **Scanned:** %s\n- **Scanner:** scan.sh\n' "$(date '+%Y-%m-%d %H:%M %Z')"

sec "Operating system"
kv "Kernel" "$(uname -srm 2>/dev/null)"
if [ -r /etc/os-release ]; then
  . /etc/os-release 2>/dev/null
  kv "Distribution" "${PRETTY_NAME:-${NAME:-}}"
  kv "ID / family" "${ID:-?}${ID_LIKE:+ (like: $ID_LIKE)}"
  kv "Version" "${VERSION_ID:-}${VERSION_CODENAME:+ ($VERSION_CODENAME)}"
  kv "Variant" "${VARIANT:-}"
fi
has sw_vers && kv "macOS" "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
has freebsd-version && kv "FreeBSD" "$(freebsd-version 2>/dev/null)"
[ -r /etc/alpine-release ] && kv "Alpine" "$(cat /etc/alpine-release)"
[ -e /run/ostree-booted ] && kv "Immutable/atomic" "yes (ostree)"
[ -r /proc/version ] && grep -qi microsoft /proc/version && kv "WSL" "yes (Linux under Windows)"
has systemd-detect-virt && kv "Virtualization" "$(systemd-detect-virt 2>/dev/null)"
kv "Hostname" "$(hostname 2>/dev/null || uname -n)"
kv "Uptime" "$(uptime 2>/dev/null | sed 's/^ *//')"

sec "User & shell"
kv "User" "$(id -un) (uid $(id -u), groups: $(id -Gn | tr ' ' ','))"
kv "Login shell" "${SHELL:-?}"
kv "Shells available" "$(for s in bash zsh fish dash ksh tcsh nu pwsh; do has $s && printf '%s ' $s; done)"
kv "Home" "$HOME"
case ":$PATH:" in *":$HOME/.local/bin:"*) lb="yes" ;; *) lb="no" ;; esac
kv "~/.local/bin on PATH" "$lb"
kv "~/bin on PATH" "$(case ":$PATH:" in *":$HOME/bin:"*) echo yes ;; *) echo no ;; esac)"

sec "Hardware"
if has lscpu; then
  kv "CPU" "$(lscpu | awk -F: '/Model name/{gsub(/^ +/,"",$2);print $2;exit}') — $(nproc 2>/dev/null) threads"
elif [ "$OS" = Darwin ]; then
  kv "CPU" "$(sysctl -n machdep.cpu.brand_string 2>/dev/null) — $(sysctl -n hw.ncpu) threads"
else
  kv "CPU" "$(sysctl -n hw.model 2>/dev/null) — $(sysctl -n hw.ncpu 2>/dev/null) threads"
fi
if [ -r /proc/meminfo ]; then
  kv "RAM" "$(awk '/MemTotal/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)"
  kv "Swap" "$(awk '/SwapTotal/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)$(has swapon && swapon --show=NAME,TYPE --noheadings 2>/dev/null | tr '\n' ' ' | sed 's/^/ — /')"
elif [ "$OS" = Darwin ]; then
  kv "RAM" "$(( $(sysctl -n hw.memsize) / 1073741824 )) GiB"
else
  kv "RAM" "$(( $(sysctl -n hw.physmem 2>/dev/null || echo 0) / 1073741824 )) GiB"
fi
if has lspci; then
  kv "GPU" "$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | sed 's/^[^ ]* //' | tr '\n' ';')"
elif [ "$OS" = Darwin ]; then
  kv "GPU" "$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F: '/Chipset Model/{print $2}' | tr '\n' ';')"
fi
[ -r /sys/class/dmi/id/product_name ] && kv "Model" "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/class/dmi/id/product_name)"
[ "$OS" = Darwin ] && kv "Model" "$(sysctl -n hw.model 2>/dev/null)"
ls /sys/class/power_supply/BAT* >/dev/null 2>&1 && kv "Battery" "present (laptop)"
[ -d /sys/firmware/efi ] && kv "Firmware" "UEFI" || { [ "$OS" = Linux ] && kv "Firmware" "BIOS/legacy"; }

sec "Storage"
if has lsblk; then
  printf '```\n'; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS -e 7 2>/dev/null || lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT -e 7; printf '```\n'
elif [ "$OS" = Darwin ]; then
  printf '```\n'; diskutil list 2>/dev/null | grep -v '^$'; printf '```\n'
elif has geom; then
  printf '```\n'; geom disk list 2>/dev/null | grep -E 'Name|Mediasize'; printf '```\n'
fi
if has findmnt; then
  kv "/ filesystem" "$(findmnt -no FSTYPE,SOURCE /)"
  kv "/home filesystem" "$(findmnt -no FSTYPE,SOURCE -T "$HOME")"
else
  kv "/ filesystem" "$(df -T / 2>/dev/null | awk 'NR==2{print $2}' || mount | awk '$3=="/"{print $5}')"
fi
printf '```\n'; df -h / "$HOME" 2>/dev/null | awk '!seen[$0]++'; printf '```\n'

sec "Desktop / session"
kv "Desktop" "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}"
kv "Session type" "${XDG_SESSION_TYPE:-}"
[ "$OS" = Darwin ] && kv "Desktop" "macOS (Aqua)"
[ -z "${XDG_CURRENT_DESKTOP:-}${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ "$OS" != Darwin ] && kv "Display" "none detected (server/headless?)"

sec "Service manager"
init=$(ps -p 1 -o comm= 2>/dev/null)
kv "PID 1" "$init"
[ "$OS" = Darwin ] && kv "Service manager" "launchd (launchctl)"
has systemctl && kv "systemd" "$(systemctl --version 2>/dev/null | first)"
has rc-service && kv "OpenRC" "present"
has sv && kv "runit" "present"
has s6-rc && kv "s6" "present"

sec "Package managers"
pm=""
for p in apt dnf yum rpm-ostree zypper pacman yay paru apk xbps-install emerge eopkg swupd nix guix pkg pkg_add pkgin brew port snap flatpak; do
  has $p && pm="$pm $p"
done
kv "Found" "${pm# }"
has apt && kv "apt sources" "$(ls /etc/apt/sources.list.d 2>/dev/null | tr '\n' ' ')"
has flatpak && kv "Flatpak remotes" "$(flatpak remotes --columns=name 2>/dev/null | tr '\n' ' ')"
has dpkg-query && kv "Packages (dpkg)" "$(dpkg-query -f '.\n' -W 2>/dev/null | wc -l | tr -d ' ')"
has rpm && kv "Packages (rpm)" "$(rpm -qa 2>/dev/null | wc -l | tr -d ' ')"
has pacman && kv "Packages (pacman)" "$(pacman -Q 2>/dev/null | wc -l | tr -d ' ')"
has brew && kv "Packages (brew)" "$(brew list 2>/dev/null | wc -l | tr -d ' ')"
has snap && kv "Snaps" "$(snap list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
has flatpak && kv "Flatpaks" "$(flatpak list --app 2>/dev/null | wc -l | tr -d ' ')"

sec "Elevation"
el=""; for e in sudo doas pkexec run0; do has $e && el="$el $e"; done
kv "Tools" "${el# }"
if has sudo; then
  kv "sudo implementation" "$(sudo -V 2>/dev/null | first)$(sudo -V 2>/dev/null | grep -qi 'sudo-rs' && echo ' (sudo-rs: per-terminal cache, no timestamp_type=global)')"
  if sudo -n true 2>/dev/null; then kv "sudo now" "available without prompt (cached or NOPASSWD)"; else kv "sudo now" "needs authentication"; fi
  kv "In admin group" "$(id -Gn | tr ' ' '\n' | grep -Ex 'sudo|wheel|admin' | tr '\n' ' ')"
fi
[ "$(id -u)" -eq 0 ] && kv "Running as root" "YES"

sec "Rollback / snapshot tools"
rb=""; for t in timeshift snapper btrfs zfs etckeeper tmutil lvs restic borg rsnapshot; do has $t && rb="$rb $t"; done
kv "Installed" "$( [ -n "$rb" ] && echo "${rb# }" || echo none)"
[ -d /etc/.git ] && kv "/etc under git" "yes"
has tmutil && kv "Time Machine destination" "$(tmutil destinationinfo 2>/dev/null | awk -F': ' '/^Name/{print $2}' | tr '\n' ' ')"

sec "Security"
has ufw && kv "ufw" "installed"
has firewall-cmd && kv "firewalld" "installed"
has nft && kv "nftables" "installed"
[ -d /sys/kernel/security/apparmor ] && kv "AppArmor" "enabled"
has getenforce && kv "SELinux" "$(getenforce 2>/dev/null)"
[ "$OS" = Darwin ] && kv "SIP" "$(csrutil status 2>/dev/null)" && kv "FileVault" "$(fdesetup status 2>/dev/null)"
if has lsblk; then lsblk -o TYPE 2>/dev/null | grep -q crypt && kv "Disk encryption" "LUKS volume present"; fi

sec "Tools"
for t in git gh python3 node pwsh curl wget rsync jq; do
  has $t && kv "$t" "$($t --version 2>&1 | first | cut -c1-80)"
done
git config --global user.name >/dev/null 2>&1 && kv "git identity" "configured (global)"

printf '\n_End of scan._\n'
