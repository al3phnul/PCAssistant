#!/bin/sh
# pca-baseline — capture a READ-ONLY snapshot of system state into logging/baseline/<stamp>/,
# or diff two snapshots. Linux/macOS/BSD. Part of the system-baseline skill.
#   pca-baseline [label]            capture (dir: YYYY-MM-DD_HHMM[_label])
#   pca-baseline --list             list baselines
#   pca-baseline --diff <a> <b>     unified diff between two baselines (dir names)
set -u
resolve() { p=$1; while [ -L "$p" ]; do l=$(ls -ld "$p" | sed 's/.* -> //'); case $l in /*) p=$l ;; *) p=$(dirname "$p")/$l ;; esac; done; (cd "$(dirname "$p")" && pwd -P); }
ROOT=$(cd "$(resolve "$0")/../../.." && pwd -P)
BASE="$ROOT/logging/baseline"
has() { command -v "$1" >/dev/null 2>&1; }

case ${1:-} in
  --list) ls -1 "$BASE" 2>/dev/null; exit 0 ;;
  --diff) [ $# -eq 3 ] || { echo "usage: pca-baseline --diff <a> <b>" >&2; exit 1; }
          diff -ru "$BASE/$2" "$BASE/$3"; exit 0 ;;
  -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

stamp=$(date +%Y-%m-%d_%H%M)${1:+_$1}
OUT="$BASE/$stamp"; mkdir -p "$OUT"
cap() { f=$1; shift; "$@" > "$OUT/$f" 2>/dev/null || true; [ -s "$OUT/$f" ] || rm -f "$OUT/$f"; }

# system
cap system.txt sh -c 'uname -a; cat /etc/os-release 2>/dev/null; sw_vers 2>/dev/null; uptime'
has lsblk && cap disks.txt lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
has diskutil && cap disks.txt diskutil list
cap df.txt df -h
[ -r /etc/fstab ] && cap fstab.txt cat /etc/fstab
[ -r /proc/cmdline ] && cap kernel-cmdline.txt cat /proc/cmdline
has lsmod && cap kernel-modules.txt sh -c 'lsmod | awk "NR>1{print \$1}" | sort'

# packages
has apt-mark   && cap pkg-apt-manual.txt sh -c 'apt-mark showmanual | sort'
has dpkg-query && cap pkg-dpkg-all.txt dpkg-query -W -f '${Package}\t${Version}\n'
has dnf        && cap pkg-dnf-userinstalled.txt sh -c 'dnf repoquery --userinstalled --qf "%{name}" 2>/dev/null | sort'
has rpm        && cap pkg-rpm-all.txt sh -c 'rpm -qa | sort'
has pacman     && cap pkg-pacman-explicit.txt pacman -Qqe
has zypper     && cap pkg-zypper.txt sh -c 'zypper --quiet search --installed-only | sort'
has apk        && cap pkg-apk-world.txt cat /etc/apk/world
has xbps-query && cap pkg-xbps-manual.txt xbps-query -m
has brew       && cap pkg-brew-leaves.txt brew leaves
has brew       && cap pkg-brew-casks.txt brew list --cask
has snap       && cap pkg-snap.txt snap list
has flatpak    && cap pkg-flatpak.txt flatpak list --app --columns=application,version,origin
has pkg && [ "$(uname -s)" = FreeBSD ] && cap pkg-freebsd.txt pkg prime-list
[ -d /etc/apt ] && cap apt-sources.txt sh -c 'for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && { echo "== $f"; grep -v "^#" "$f" | grep -v "^$"; }; done'

# services & scheduled jobs
if has systemctl; then
  cap services-enabled.txt systemctl list-unit-files --state=enabled --no-legend --no-pager
  cap services-user-enabled.txt systemctl --user list-unit-files --state=enabled --no-legend --no-pager
  cap services-failed.txt systemctl --failed --no-legend --no-pager
  cap timers.txt systemctl list-timers --all --no-legend --no-pager
fi
has rc-update && cap services-openrc.txt rc-update show
has launchctl && cap launchd-user.txt sh -c 'launchctl list | awk "NR>1{print \$3}" | sort'
[ -d "$HOME/Library/LaunchAgents" ] && cap launchagents-user.txt ls -1 "$HOME/Library/LaunchAgents"
cap crontab-user.txt crontab -l

# desktop settings
has dconf && cap dconf-dump.ini dconf dump /
if [ "$(uname -s)" = Darwin ]; then
  for d in NSGlobalDomain com.apple.dock com.apple.finder; do cap "defaults-$d.txt" defaults read "$d"; done
fi

# redact obvious secrets in config-type captures (package/service lists are left alone)
for f in "$OUT"/dconf-dump.ini "$OUT"/crontab-user.txt "$OUT"/fstab.txt "$OUT"/apt-sources.txt "$OUT"/defaults-*.txt; do
  [ -f "$f" ] || continue
  awk '{
    l = tolower($0)
    if (match(l, /[a-z0-9_.-]*(password|passwd|secret|token|api[_-]?key|psk|credentials)[a-z0-9_.-]*[ \t]*[=:][ \t]*/))
      $0 = substr($0, 1, RSTART + RLENGTH - 1) "[REDACTED]"
    gsub(/:\/\/[^\/@ :]+:[^\/@ ]+@/, "://[REDACTED]@")
    print
  }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

echo "pca-baseline: captured $(ls -1 "$OUT" | wc -l | tr -d ' ') files -> ${OUT#"$ROOT"/}"
