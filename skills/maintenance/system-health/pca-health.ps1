<#
pca-health (Windows) - READ-ONLY health report: pending reboot, updates, services, memory, disk,
firewall & exposed ports, battery, startup items. Changes nothing. Part of the system-health skill.
  pca-health             full report
  pca-health -Offline    skip checks that contact the network (winget, Windows Update)
Windows PowerShell 5.1+ or PowerShell 7. Works unelevated; a few checks show more when elevated.
STATUS: untested (written without a Windows machine). Report problems so the skill can be fixed.
#>
[CmdletBinding()]
param([switch]$Offline)
$ErrorActionPreference = 'SilentlyContinue'
$script:Warns = New-Object System.Collections.Generic.List[string]
function Sec($t)  { Write-Host ""; Write-Host "== $t" }
function Ok($m)   { Write-Host "  [ok]   $m" }
function Info($m) { Write-Host "  [info] $m" }
function Warn($m) { Write-Host "  [WARN] $m"; $script:Warns.Add($m) }
function Fmt($bytes) { if ($bytes -ge 1GB) { '{0:N1}G' -f ($bytes / 1GB) } elseif ($bytes -ge 1MB) { '{0:N0}M' -f ($bytes / 1MB) } else { '{0:N0}K' -f ($bytes / 1KB) } }
function DirSize($p) { if (Test-Path $p) { (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } else { 0 } }

# ---------------------------------------------------------------- system
Sec 'System'
$os = Get-CimInstance Win32_OperatingSystem
Info ("{0} (build {1}) | {2}" -f $os.Caption, $os.BuildNumber, $os.OSArchitecture)
$up = (Get-Date) - $os.LastBootUpTime
Info ("up {0} days, {1} hours" -f $up.Days, $up.Hours)
$reboot = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reboot += 'servicing' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reboot += 'Windows Update' }
if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations).PendingFileRenameOperations) { $reboot += 'pending file renames' }
if ($reboot.Count) { Warn ("reboot pending (" + ($reboot -join ', ') + ")") } else { Ok 'no reboot pending' }

# ---------------------------------------------------------------- services
Sec 'Services'
$stopped = Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" |
  Where-Object { $_.Name -notmatch '^(gupdate|edgeupdate|MapsBroker|sppsvc|RemoteRegistry|WbioSrvc|tiledatamodelsvc|clr_optimization)' -and $_.ExitCode -ne 0 }
if ($stopped) { Warn ("auto-start services stopped with an error: " + (($stopped | Select-Object -ExpandProperty Name) -join ' ')) } else { Ok 'no auto-start services stopped with an error' }

# ---------------------------------------------------------------- memory
Sec 'Memory'
$tot = $os.TotalVisibleMemorySize * 1KB; $free = $os.FreePhysicalMemory * 1KB
$pct = [int](100 * $free / $tot)
$msg = "RAM: {0} available of {1} ({2}%)" -f (Fmt $free), (Fmt $tot), $pct
if ($pct -lt 10) { Warn "low memory: $msg" } else { Ok $msg }
$pf = Get-CimInstance Win32_PageFileUsage
if ($pf) { Info ("page file: {0} MiB used of {1} MiB" -f ($pf | Measure-Object CurrentUsage -Sum).Sum, ($pf | Measure-Object AllocatedBaseSize -Sum).Sum) }
Info 'top memory users (summed by program):'
Get-Process | Group-Object ProcessName | ForEach-Object {
  [pscustomobject]@{ Name = $_.Name; WS = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum; N = $_.Count } } |
  Sort-Object WS -Descending | Select-Object -First 8 | ForEach-Object {
    $n = if ($_.N -gt 1) { " ($($_.N) processes)" } else { '' }
    Write-Host ("           {0,8}  {1}{2}" -f (Fmt $_.WS), $_.Name, $n) }

# ---------------------------------------------------------------- disk
Sec 'Disk'
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
  $used = [int](100 * ($_.Size - $_.FreeSpace) / [math]::Max($_.Size, 1))
  $m = "{0} {1}% used, {2} free of {3}" -f $_.DeviceID, $used, (Fmt $_.FreeSpace), (Fmt $_.Size)
  if ($used -ge 85) { Warn "$m" } else { Ok $m } }
Info ("user temp folder: " + (Fmt (DirSize $env:TEMP)))
$wu = "$env:windir\SoftwareDistribution\Download"
if (Test-Path $wu) { Info ("Windows Update download cache: " + (Fmt (DirSize $wu))) }
try { $rb = (New-Object -ComObject Shell.Application).Namespace(10).Items() | Measure-Object -Property Size -Sum; Info ("recycle bin: " + (Fmt $rb.Sum)) } catch {}

# ---------------------------------------------------------------- updates
Sec 'Updates'
if (-not $Offline) {
  try {
    $s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $r = $s.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    if ($r.Updates.Count) { Warn ("Windows Update: {0} update(s) available" -f $r.Updates.Count) } else { Ok 'Windows Update: up to date' }
  } catch { Info 'Windows Update: check failed' }
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    $w = winget upgrade --accept-source-agreements 2>$null | Select-String -Pattern '^\S.*\s+\S+\s+\S+\s+\S+\s*$' | Where-Object { $_ -notmatch '^(Name|-{3,})' }
    $n = ($w | Where-Object { $_ -notmatch 'upgrades available' }).Count
    if ($n -gt 0) { Warn "winget: about $n upgrade(s) available (winget upgrade)" } else { Ok 'winget: no upgrades' }
  }
} else { Info 'network update checks skipped (-Offline)' }

# ---------------------------------------------------------------- security
Sec 'Firewall, antivirus & network exposure'
$profiles = Get-NetFirewallProfile
$off = $profiles | Where-Object { -not $_.Enabled } | Select-Object -ExpandProperty Name
if ($off) { Warn ("firewall OFF for profile(s): " + ($off -join ', ')) } elseif ($profiles) { Ok 'firewall: on for all profiles' } else { Info 'firewall: state unknown' }
$mp = Get-MpComputerStatus
if ($mp) {
  if ($mp.RealTimeProtectionEnabled) { Ok ("Defender real-time protection on (signatures {0} days old)" -f [int]((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays) }
  else { Warn 'Defender real-time protection is off (fine only if another antivirus is active)' } }
$lst = Get-NetTCPConnection -State Listen | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') } |
  ForEach-Object { $p = (Get-Process -Id $_.OwningProcess).ProcessName; "{0}:{1} ({2})" -f $_.LocalAddress, $_.LocalPort, $p } | Sort-Object -Unique
if ($lst) { Info ("TCP ports listening beyond localhost: " + ($lst -join ' ')) } else { Ok 'no TCP ports listening beyond localhost' }

# ---------------------------------------------------------------- battery & power
$bat = Get-CimInstance Win32_Battery
if ($bat) {
  Sec 'Battery & power'
  foreach ($b in $bat) { Ok ("{0}: {1}% charge" -f $b.Name, $b.EstimatedChargeRemaining) }
  $full = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity
  $des  = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData
  if ($full -and $des -and $des.DesignedCapacity) {
    $h = [int](100 * $full.FullChargedCapacity / $des.DesignedCapacity)
    if ($h -lt 70) { Warn "battery worn: health $h% of design" } else { Ok "battery health: $h% of design" } }
}
$plan = powercfg /getactivescheme 2>$null
if ($plan) { Info ("power plan: " + ($plan -replace '^.*\((.*)\).*$', '$1')) }

# ---------------------------------------------------------------- startup
Sec 'Startup items'
$st = Get-CimInstance Win32_StartupCommand
Info ("startup commands: {0} ({1})" -f @($st).Count, (($st | Select-Object -ExpandProperty Name) -join ', '))
$tasks = Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' }
Info ("non-Microsoft scheduled tasks enabled: {0}" -f @($tasks).Count)

# ---------------------------------------------------------------- summary
Write-Host ""; Write-Host '== Summary'
if ($script:Warns.Count -eq 0) { Write-Host '  No warnings.' } else {
  Write-Host "  $($script:Warns.Count) warning(s):"; $script:Warns | ForEach-Object { Write-Host "  - $_" } }
exit 0
