<#
pca-pi-find (Windows) - find Raspberry Pis on your local network. Part of the raspberry-pi-headless skill.
  pca-pi-find [hostname]            resolve <hostname>.local (and the -2..-9 conflict names), then scan
                                    the local IPv4 subnet for Raspberry Pi MAC prefixes
  pca-pi-find -NoScan <hostname>    name lookup only
Read-only: pings addresses on your own subnet and reads the neighbour (ARP) table. Use it on networks you own.
STATUS: untested (written without a Windows machine).
#>
[CmdletBinding()]
param([Parameter(Position = 0)][string]$Name, [switch]$NoScan)
$ErrorActionPreference = 'SilentlyContinue'
$ouis = @('b8-27-eb', 'dc-a6-32', 'e4-5f-01', '28-cd-c1', 'd8-3a-dd', '2c-cf-67', '88-a2-9e')
$found = $false

if ($Name) {
  $Name = $Name -replace '\.local$', ''
  Write-Host "== Name lookup ($Name.local)"
  foreach ($n in @($Name) + (2..9 | ForEach-Object { "$Name-$_" })) {
    $r = Resolve-DnsName "$n.local" -Type A -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress } | Select-Object -First 1
    if (-not $r) { continue }
    if ($n -ne $Name -and -not (Test-Connection $r.IPAddress -Count 1 -Quiet)) { Write-Host "  $n.local -> $($r.IPAddress) (stale, not responding; ignore)"; continue }
    Write-Host "  $n.local -> $($r.IPAddress)"; $found = $true
    if ($n -ne $Name) { Write-Host "  NOTE: the Pi renamed itself to $n.local after a name conflict (usually Ethernet AND Wi-Fi on the same network). Disable one." }
  }
  if (-not $found) { Write-Host '  not found by name (mDNS may be blocked, or the Pi is still booting)' }
}
if ($NoScan) { if ($found) { exit 0 } else { exit 1 } }

Write-Host '== Scanning for Raspberry Pi hardware'
$addrs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -ne 'WellKnown' -and $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }
foreach ($a in $addrs) {
  $p = [int]$a.PrefixLength; if ($p -lt 22) { $p = 24 }
  $b = [System.Net.IPAddress]::Parse($a.IPAddress).GetAddressBytes(); [array]::Reverse($b)
  $ip = [BitConverter]::ToUInt32($b, 0); $size = [math]::Pow(2, 32 - $p)
  $net = [uint32]($ip - ($ip % $size)); $first = $net + 1; $last = $net + $size - 2
  Write-Host ("  sweeping {0}/{1} ({2} addresses)..." -f $a.IPAddress, $p, ($last - $first + 1))
  $tasks = for ($i = $first; $i -le $last; $i++) {
    $x = [BitConverter]::GetBytes([uint32]$i); [array]::Reverse($x)
    (New-Object System.Net.NetworkInformation.Ping).SendPingAsync((New-Object System.Net.IPAddress (, $x)), 1000)
  }
  try { [System.Threading.Tasks.Task]::WaitAll($tasks) } catch {}
}
$hits = Get-NetNeighbor -AddressFamily IPv4 | Where-Object { $_.LinkLayerAddress -and $ouis -contains $_.LinkLayerAddress.Substring(0, 8).ToLower() } |
  Sort-Object IPAddress -Unique
if ($hits) {
  foreach ($h in $hits) { Write-Host ("  {0}  {1}  -> try: ssh <user>@{0}" -f $h.IPAddress, $h.LinkLayerAddress.ToLower().Replace('-', ':')) }
  $found = $true
} else { Write-Host '  no Raspberry Pi MAC addresses seen (is it powered, cabled, and done booting?)' }
if ($found) { exit 0 } else { exit 1 }
