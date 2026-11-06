#!/bin/sh
# pca-pi-find — find Raspberry Pis on your local network. Linux/macOS/BSD. Part of the raspberry-pi-headless skill.
#   pca-pi-find [hostname]   resolve <hostname>.local (also the -2..-9 names avahi picks after a name
#                            conflict), then scan the local IPv4 subnet for Raspberry Pi MAC prefixes
#   pca-pi-find --no-scan <hostname>   name lookup only
# Read-only: it only pings addresses on your own subnet and reads the neighbour (ARP) table.
# Use it on networks you own or administer.
set -u
SCAN=1
case ${1:-} in
  -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --no-scan) SCAN=0; shift ;;
esac
NAME=${1:-}
has() { command -v "$1" >/dev/null 2>&1; }
# Raspberry Pi Foundation / Raspberry Pi Trading / Raspberry Pi Ltd OUIs
OUIS="b8:27:eb dc:a6:32 e4:5f:01 28:cd:c1 d8:3a:dd 2c:cf:67 88:a2:9e"
found=0
# 1-second ping timeout: Linux -W is seconds; macOS/BSD use -t (seconds)
if [ "$(uname -s)" = Linux ]; then PW="-W 1"; else PW="-t 1"; fi
ip2a() { awk -v n="$1" 'BEGIN{printf "%d.%d.%d.%d", int(n/16777216)%256, int(n/65536)%256, int(n/256)%256, n%256}'; }

resolve() {  # print the IPv4 address of $1, if any
  if has getent; then getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1{print $1}'
  elif has dscacheutil; then dscacheutil -q host -a name "$1" 2>/dev/null | awk '/^ip_address:/{print $2; exit}'
  elif has avahi-resolve-host-name; then avahi-resolve-host-name -4 "$1" 2>/dev/null | awk '{print $2}'
  fi
}

if [ -n "$NAME" ]; then
  NAME=${NAME%.local}
  echo "== Name lookup ($NAME.local)"
  # a failed .local lookup can take ~5 s, so look all variants up in parallel
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t pcapifind); trap 'rm -rf "$tmp"' EXIT
  variants="$NAME $NAME-2 $NAME-3 $NAME-4 $NAME-5 $NAME-6 $NAME-7 $NAME-8 $NAME-9"
  for n in $variants; do ( r=$(resolve "$n.local"); [ -n "$r" ] && echo "$r" > "$tmp/$n" ) & done
  wait
  for n in $variants; do
    [ -f "$tmp/$n" ] || continue
    ip=$(cat "$tmp/$n")
    if [ "$n" != "$NAME" ] && ! ping -c 1 $PW "$ip" >/dev/null 2>&1; then
      echo "  $n.local -> $ip (stale cached name, not responding; ignore)"; continue
    fi
    echo "  $n.local -> $ip"; found=1
    [ "$n" != "$NAME" ] && echo "  NOTE: the Pi renamed itself to $n.local after a name conflict. Usual cause: it's on Ethernet AND Wi-Fi on the same network. Disable one, then restart avahi-daemon."
  done
  [ $found -eq 0 ] && echo "  not found by name (mDNS may be blocked, or the Pi is still booting: first boot takes 2-3 min)"
fi

[ $SCAN -eq 1 ] || exit $((1 - found))

# ---- subnet(s) to sweep: "network-int prefix" pairs, capped at 1024 hosts
nets=""
if has ip; then
  nets=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}')
elif has ifconfig; then
  nets=$(ifconfig 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {
      ip=$2; m=$4; p=0
      if (m ~ /^0x/) { m=substr(m,3); for (i=1;i<=8;i++){ d=index("0123456789abcdef", tolower(substr(m,i,1)))-1; while (d>0){p+=d%2; d=int(d/2)} } }
      else { n=split(m,o,"."); for (i=1;i<=n;i++){ d=o[i]+0; while (d>0){p+=d%2; d=int(d/2)} } }
      print ip "/" p }')
fi
[ -n "$nets" ] || { echo "pca-pi-find: no IPv4 network found" >&2; exit 1; }

echo "== Scanning for Raspberry Pi hardware"
for cidr in $nets; do
  range=$(echo "$cidr" | awk -F'[./]' '{
      ip=(($1*256+$2)*256+$3)*256+$4; p=$5; if (p<22) p=24   # wider than /22: sweep only our own /24
      size=2^(32-p); net=ip-(ip%size); first=net+1; last=net+size-2
      printf "%d %d\n", first, last }')
  set -- $range; first=$1; last=$2
  echo "  sweeping $cidr ($((last - first + 1)) addresses)…"
  # parallel 1-second pings (128 at a time). Even a Pi that drops ICMP answers ARP, so it lands in the neighbour table.
  i=$first
  while [ "$i" -le "$last" ]; do
    ping -c 1 $PW "$(ip2a "$i")" >/dev/null 2>&1 &
    i=$((i + 1))
    [ $(( (i - first) % 128 )) -eq 0 ] && wait
  done
  wait
done

# ---- neighbour table -> "ip mac" (MACs normalised to lower-case, two digits per byte)
if has ip; then
  neigh=$(ip -4 neigh show 2>/dev/null | awk '/lladdr/{for (i=1;i<=NF;i++) if ($i=="lladdr") print $1, $(i+1)}')
else
  neigh=$(arp -an 2>/dev/null | awk '{ip=$2; gsub(/[()]/,"",ip); if ($4 ~ /:/) print ip, $4}')
fi
hits=$(printf '%s\n' "$neigh" | awk -v ouis="$OUIS" '
  BEGIN { n=split(ouis, o, " "); for (i=1;i<=n;i++) want[o[i]]=1 }
  NF==2 { m=tolower($2); k=split(m, b, ":"); if (k!=6) next
          mac=""; for (i=1;i<=6;i++) mac=mac (i>1?":":"") (length(b[i])==1 ? "0" b[i] : b[i])
          if (substr(mac,1,8) in want) print $1 "  " mac }' | sort -u -t. -k1,1n -k2,2n -k3,3n -k4,4n)
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | while read -r ip mac; do
    nm=""; has getent && nm=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}')
    echo "  $ip  $mac${nm:+  ($nm)}  -> try: ssh <user>@$ip"
  done
  found=1
else
  echo "  no Raspberry Pi MAC addresses seen (is it powered, cabled, and done booting?)"
fi
exit $((1 - found))
