#!/bin/sh
# pca-health — READ-ONLY health report: reboot/updates, boot, memory, disk, firewall & exposed ports,
# battery, power, startup items. Changes nothing. Linux/macOS/BSD. Part of the system-health skill.
#   pca-health            full report
#   pca-health --offline  skip checks that contact the network (snap/flatpak/dnf/pacman/firmware/macOS updates)
set -u
OFFLINE=0
case ${1:-} in
  --offline) OFFLINE=1 ;;
  -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "pca-health: unknown option: $1 (try --help)" >&2; exit 1 ;;
esac

has()  { command -v "$1" >/dev/null 2>&1; }
OS=$(uname -s)
NW=0; WARNS=""
sec()  { printf '\n== %s\n' "$1"; }
ok()   { printf '  [ok]   %s\n' "$*"; }
info() { printf '  [info] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; NW=$((NW + 1)); WARNS="$WARNS
  - $*"; }
tl()   { s=$1; shift; if has timeout; then timeout "$s" "$@"; else "$@"; fi; }  # time-limited run
kb()   { awk '{k=$1; if (k>=1048576) printf "%.1fG", k/1048576; else if (k>=1024) printf "%.0fM", k/1024; else printf "%dK", k}'; }
dsize(){ du -sk "$1" 2>/dev/null | awk '{print $1}' | kb; }
join() { paste -sd' ' -; }

# ---------------------------------------------------------------- system
sec "System"
if [ -r /etc/os-release ]; then info "$(. /etc/os-release; echo "${PRETTY_NAME:-$NAME}") | kernel $(uname -r) | $(uname -m)"
elif has sw_vers; then info "macOS $(sw_vers -productVersion) | $(uname -m)"
else info "$OS $(uname -r) | $(uname -m)"; fi
up=$(uptime -p 2>/dev/null || uptime | sed 's/.*up \([^,]*\),.*/up \1/')
info "$up"

if [ -f /var/run/reboot-required ]; then
  pk=$(sort -u /var/run/reboot-required.pkgs 2>/dev/null | join)
  warn "reboot pending${pk:+ (for: $pk)}"
elif has needs-restarting; then
  if needs-restarting -r >/dev/null 2>&1; then ok "no reboot pending"; else warn "reboot pending (needs-restarting -r)"; fi
elif [ "$OS" = Linux ] && [ -d /usr/lib/modules ] && [ ! -d "/usr/lib/modules/$(uname -r)" ] && [ ! -d "/lib/modules/$(uname -r)" ]; then
  warn "running kernel $(uname -r) is no longer installed; reboot to use the new one"
else
  ok "no reboot pending"
fi

# ---------------------------------------------------------------- boot & services
if has systemctl; then
  sec "Boot & services"
  has systemd-analyze && { t=$(systemd-analyze 2>/dev/null | head -1 | sed 's/^Startup finished in //'); [ -n "$t" ] && info "boot: $t"; }
  f=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | join)
  if [ -n "$f" ]; then warn "failed system units: $f"; else ok "no failed system units"; fi
  f=$(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | join)
  if [ -n "$f" ]; then warn "failed user units: $f"; else ok "no failed user units"; fi
fi

# ---------------------------------------------------------------- memory
sec "Memory"
if [ -r /proc/meminfo ]; then
  set -- $(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
                END{printf "%d %d %d %d", t/1024, a/1024, st/1024, (st-sf)/1024}' /proc/meminfo)
  pct=$(( $2 * 100 / ($1 > 0 ? $1 : 1) ))
  msg="RAM: $2 MiB available of $1 MiB (${pct}%); swap: $4 of $3 MiB used"
  if [ "$pct" -lt 10 ]; then warn "low memory: $msg"; else ok "$msg"; fi
  if [ -r /proc/pressure/memory ]; then
    p=$(awk '/^some/{sub("avg300=","",$4); print $4}' /proc/pressure/memory)
    if awk -v p="$p" 'BEGIN{exit !(p > 5)}'; then warn "memory pressure: tasks stalled ${p}% of the last 5 min"; fi
  fi
elif [ "$OS" = Darwin ]; then
  has memory_pressure && info "$(memory_pressure 2>/dev/null | tail -1)"
  info "swap: $(sysctl -n vm.swapusage 2>/dev/null)"
fi
info "top memory users (summed by program):"
ps -A -o rss= -o comm= 2>/dev/null | awk '{r=$1; $1=""; sub(/^ +/,""); n=$0; sub(/.*\//,"",n); s[n]+=r; c[n]++}
  END{for (n in s) printf "%d\t%s\t%d\n", s[n]/1024, n, c[n]}' | sort -rn | head -8 |
  awk -F'\t' '{printf "           %6d MiB  %s%s\n", $1, $2, ($3 > 1 ? " (" $3 " processes)" : "")}'

# ---------------------------------------------------------------- disk
sec "Disk"
dfl=$(df -kP / "$HOME" 2>/dev/null | awk 'NR>1 && !seen[$1]++ {print $5, $4, $2, $6}')
while read -r pct avail size mnt; do
  [ -n "${pct:-}" ] || continue
  p=${pct%\%}; a=$(echo "$avail" | kb); s=$(echo "$size" | kb)
  if [ "$p" -ge 85 ]; then warn "$mnt is ${pct} full ($a free of $s)"; else ok "$mnt: ${pct} used, $a free of $s"; fi
done <<EOF
$dfl
EOF
if has journalctl; then
  j=$(journalctl --disk-usage 2>/dev/null | sed -n 's/.*take up \([^ ]*\) .*/\1/p')
  if [ -n "$j" ]; then
    case $j in *G) info "system journal: $j (consider capping it: SystemMaxUse= in a journald.conf.d drop-in)" ;; *) info "system journal: $j" ;; esac
  fi
fi
[ -d "$HOME/.cache" ] && {
  top=$(du -sk "$HOME"/.cache/* 2>/dev/null | sort -rn | head -4 | while read -r k d; do printf '%s %s, ' "${d##*/}" "$(echo "$k" | kb)"; done)
  info "~/.cache: $(dsize "$HOME/.cache")${top:+ (largest: ${top%, })}"
}
for t in "$HOME/.local/share/Trash" "$HOME/.Trash"; do [ -d "$t" ] && info "trash: $(dsize "$t")"; done
[ -d /var/cache/apt/archives ] && info "apt download cache: $(dsize /var/cache/apt/archives)"
if has snap; then
  dis=$(snap list --all 2>/dev/null | awk '/disabled/{print $1 "_" $3}')
  if [ -n "$dis" ]; then
    n=$(printf '%s\n' "$dis" | wc -l | tr -d ' ')
    k=$(for x in $dis; do du -sk "/var/lib/snapd/snaps/$x.snap" 2>/dev/null; done | awk '{s+=$1} END{print s+0}' | kb)
    info "snap: $n old (disabled) revision(s) using $k (removable with: snap remove <name> --revision=<rev>)"
  fi
fi
if has dpkg-query; then
  kn=$(dpkg-query -W -f '${Status} ${Package}\n' 'linux-image-[0-9]*' 2>/dev/null | awk '/install ok installed/{print $NF}')
  n=$(printf '%s\n' "$kn" | grep -c . || true)
  [ "$n" -gt 2 ] && info "$n kernels installed ($(printf '%s\n' "$kn" | sed 's/linux-image-//' | join)); running $(uname -r)"
fi

# ---------------------------------------------------------------- updates
sec "Updates"
if has apt-get; then
  out=$(apt-get -s upgrade 2>/dev/null)
  up=$(printf '%s\n' "$out" | awk '/^Inst /{print $2}' | join)
  ph=$(printf '%s\n' "$out" | awk '/deferred due to phasing/{f=1; next} f && /^  /{n+=NF; next} f{f=0} END{print n+0}')
  kb_=$(printf '%s\n' "$out" | awk '/have been kept back/{f=1; next} f && /^  /{n+=NF; next} f{f=0} END{print n+0}')
  if [ -n "$up" ]; then warn "apt: $(echo "$up" | wc -w | tr -d ' ') upgrade(s) ready: $up"; else ok "apt: no upgrades ready"; fi
  [ "$ph" -gt 0 ] && info "apt: $ph phased update(s) deferred (rolled out gradually; they arrive on their own)"
  [ "$kb_" -gt 0 ] && info "apt: $kb_ package(s) kept back (need new dependencies; apt full-upgrade, review first)"
  if [ -d /var/lib/apt/lists ] && ! find /var/lib/apt/lists -maxdepth 1 -name '*Release' -mtime -7 2>/dev/null | grep -q .; then
    warn "apt package lists are over 7 days old (apt update)"
  fi
  ar=$(apt-get -s autoremove 2>/dev/null | awk '/^Remv /{print $2}' | join)
  [ -n "$ar" ] && info "apt autoremove would remove: $ar (review; it can catch packages you still use)"
fi
has zypper && { n=$(zypper -q --no-refresh lu 2>/dev/null | grep -c '^v ' || true); if [ "$n" -gt 0 ]; then warn "zypper: $n update(s)"; else ok "zypper: no updates in cache"; fi; }
has apk    && { n=$(apk version -l '<' 2>/dev/null | tail -n +2 | grep -c . || true); if [ "$n" -gt 0 ]; then warn "apk: $n update(s)"; else ok "apk: up to date"; fi; }
has brew   && { n=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated -q 2>/dev/null | grep -c . || true); if [ "$n" -gt 0 ]; then warn "brew: $n outdated"; else ok "brew: up to date"; fi; }
if [ $OFFLINE -eq 0 ]; then
  if has dnf; then tl 90 dnf -q check-update >/dev/null 2>&1; rc=$?
    case $rc in 100) warn "dnf: updates available (dnf check-update)" ;; 0) ok "dnf: up to date" ;; *) info "dnf: check failed (rc $rc)" ;; esac; fi
  has checkupdates && { n=$(tl 90 checkupdates 2>/dev/null | grep -c . || true); if [ "$n" -gt 0 ]; then warn "pacman: $n update(s)"; else ok "pacman: up to date"; fi; }
  has snap && { s=$(tl 60 snap refresh --list 2>&1); case $s in *"up to date"*) ok "snap: up to date" ;; *error*|"") info "snap: check failed" ;; *) warn "snap: updates ready: $(printf '%s\n' "$s" | awk 'NR>1{print $1}' | join)" ;; esac; }
  has flatpak && { n=$(tl 60 flatpak remote-ls --updates 2>/dev/null | grep -c . || true); if [ "$n" -gt 0 ]; then warn "flatpak: $n update(s)"; else ok "flatpak: up to date"; fi; }
  has fwupdmgr && { tl 60 fwupdmgr get-updates --no-unreported-check >/dev/null 2>&1; rc=$?
    case $rc in 0) warn "firmware updates available (fwupdmgr get-updates)" ;; 2) ok "firmware: no updates" ;; *) info "firmware: check failed (rc $rc)" ;; esac; }
  has softwareupdate && { s=$(tl 120 softwareupdate -l 2>&1); case $s in *"No new software"*) ok "macOS: no updates" ;; *"*"*) warn "macOS updates available (softwareupdate -l)" ;; *) info "macOS: update check failed" ;; esac; }
else
  info "network update checks skipped (--offline)"
fi

# ---------------------------------------------------------------- firewall & exposure
sec "Firewall & network exposure"
fw=unknown; fwn=""
if [ -r /etc/ufw/ufw.conf ] && has ufw; then
  fwn=ufw; if grep -q '^ENABLED=yes' /etc/ufw/ufw.conf; then fw=on; else fw=off; fi
elif has firewall-cmd; then
  fwn=firewalld; case $(firewall-cmd --state 2>&1) in running) fw=on ;; *) fw=off ;; esac
elif [ -x /usr/libexec/ApplicationFirewall/socketfilterfw ]; then
  fwn="macOS firewall"; case $(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null) in *enabled*) fw=on ;; *) fw=off ;; esac
elif has systemctl && systemctl is-active -q nftables 2>/dev/null; then
  fwn=nftables; fw=on
fi
case $fw in
  on)  ok "firewall: $fwn is on" ;;
  off) warn "firewall: $fwn is OFF" ;;
  *)   info "firewall: state unknown (no ufw/firewalld/nftables service detected, or needs admin to read)" ;;
esac
lst=""
if has ss; then
  lst=$(ss -H -tlnp 2>/dev/null | awk '{a=$4; if (a ~ /^(127\.|\[::1\]|::1)/) next; p="?";
        if (match($0, /users:\(\("[^"]*"/)) p=substr($0, RSTART+9, RLENGTH-10); print a " (" p ")"}' | sort -u | join)
elif has lsof; then
  lst=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 && $9 !~ /^(127\.|\[::1\])/ {print $9 " (" $1 ")"}' | sort -u | join)
elif has netstat; then
  lst=$(netstat -an 2>/dev/null | awk '/LISTEN/ && $4 !~ /^(127\.|::1|\[::1\])/ {print $4}' | sort -u | join)
fi
if [ -n "$lst" ]; then
  if [ "$fw" = off ]; then warn "TCP ports open to the network with no firewall: $lst"
  else info "TCP ports listening beyond localhost (\"?\" = another user's process): $lst"; fi
else
  ok "no TCP ports listening beyond localhost"
fi

# ---------------------------------------------------------------- battery & power
bats=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null)
if [ -n "$bats" ] || { [ "$OS" = Darwin ] && pmset -g batt 2>/dev/null | grep -q InternalBattery; }; then
  sec "Battery & power"
  for b in $bats; do
    cap=$(cat "$b/capacity" 2>/dev/null); st=$(cat "$b/status" 2>/dev/null)
    full=$(cat "$b/energy_full" 2>/dev/null || cat "$b/charge_full" 2>/dev/null)
    des=$(cat "$b/energy_full_design" 2>/dev/null || cat "$b/charge_full_design" 2>/dev/null)
    cyc=$(cat "$b/cycle_count" 2>/dev/null); [ "${cyc:-0}" = 0 ] && cyc=""
    h=""; [ -n "$full" ] && [ -n "$des" ] && [ "$des" -gt 0 ] && h=$((full * 100 / des))
    msg="${b##*/}: ${cap}% ${st}${h:+, health ${h}% of design}${cyc:+, $cyc cycles}"
    if [ -n "$h" ] && [ "$h" -lt 70 ]; then warn "battery worn: $msg"; else ok "$msg"; fi
  done
  [ "$OS" = Darwin ] && info "$(pmset -g batt 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')"
fi
has powerprofilesctl && info "power profile: $(powerprofilesctl get 2>/dev/null)"
[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver ] && info "CPU frequency driver: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver) / $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
if has sensors; then
  t=$(sensors 2>/dev/null | awk -F: '/°C/ && /^(Tctl|Tdie|Package id 0|edge|Composite)/ {v=$2; sub(/^[ \t]*\+/, "", v); sub(/°C.*/, "", v); printf "%s %s°C, ", $1, v; if (v+0 > 90) hot=1} END{exit hot}'); rc=$?
  [ -n "$t" ] && { if [ $rc -ne 0 ]; then warn "running hot: ${t%, }"; else info "temperatures: ${t%, }"; fi; }
fi

# ---------------------------------------------------------------- startup items
sec "Startup items"
if [ -d /etc/xdg/autostart ] || [ -d "$HOME/.config/autostart" ]; then
  ua=""; hid=0
  for f in "$HOME"/.config/autostart/*.desktop; do
    [ -f "$f" ] || continue
    if grep -qiE '^(Hidden=true|X-GNOME-Autostart-enabled=false)' "$f"; then hid=$((hid + 1)); else ua="$ua ${f##*/}"; fi
  done
  sys=$(ls /etc/xdg/autostart/*.desktop 2>/dev/null | wc -l | tr -d ' ')
  info "login items: $sys system-wide (/etc/xdg/autostart), $hid of them hidden for you${ua:+; your own:$ua}"
fi
if has systemctl; then
  us=$(systemctl --user list-unit-files --type=service --state=enabled --no-legend 2>/dev/null | wc -l | tr -d ' ')
  info "enabled user services: $us (systemctl --user list-unit-files --state=enabled)"
fi
if [ "$OS" = Darwin ]; then
  for d in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
    [ -d "$d" ] && info "$d: $(ls "$d" 2>/dev/null | wc -l | tr -d ' ') item(s)"
  done
fi

# ---------------------------------------------------------------- summary
printf '\n== Summary\n'
if [ $NW -eq 0 ]; then echo "  No warnings."; else echo "  $NW warning(s):$WARNS"; fi
exit 0
