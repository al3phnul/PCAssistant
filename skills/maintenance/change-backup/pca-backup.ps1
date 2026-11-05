<#
pca-backup (Windows) — back up / restore files and registry keys tied to a PC Assistant change ID.
Works with Windows PowerShell 5.1+ and PowerShell 7+. Part of the change-backup skill.

  pca-backup <ID> [--private] <path>...          back up files/folders before change <ID>
  pca-backup <ID> [--private] --reg <key>...     export registry keys (e.g. HKLM\SOFTWARE\Foo)
  pca-backup --restore <ID> [--private] [path|key...]   restore all (or listed) items
  pca-backup --list <ID> [--private]             show what <ID> backed up
  pca-backup --verify <ID> [--private]           check backup checksums

Files go to logging\backups\<ID>\<Drive>\<path>; registry keys to logging\backups\<ID>\registry\*.reg.
METADATA records kind, original path, and ACL (SDDL); SHA256SUMS holds hashes.
--private uses logging\backups-private\ (never committed) for anything containing secrets.
#>
$ErrorActionPreference = 'Stop'

function Die($msg) { Write-Error "pca-backup: $msg" -ErrorAction Continue; exit 1 }
function Say($msg) { Write-Host "pca-backup: $msg" }

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not (Test-Path (Join-Path $Root 'CLAUDE.md'))) { Die "cannot find project root (looked in $Root)" }

# --- args (--private and --reg may appear anywhere) ---
$private = $false; $reg = $false; $rest = @()
foreach ($a in $args) {
    switch ($a) { '--private' { $private = $true } '--reg' { $reg = $true } default { $rest += $a } }
}
$mode = 'backup'
if ($rest.Count -eq 0 -or $rest[0] -in @('-h', '--help')) {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 14; exit 0
}
if ($rest[0] -in @('--restore', '--list', '--verify')) { $mode = $rest[0].TrimStart('-'); $rest = $rest[1..($rest.Count)] | Where-Object { $_ } }
if ($rest.Count -eq 0) { Die 'missing change ID (e.g. C-0042)' }
$id = $rest[0]; $items = @($rest | Select-Object -Skip 1)
if ($id -notmatch '^C-\d+$') { Die "change ID should look like C-0042 (got '$id')" }

$base = Join-Path $Root ($(if ($private) { 'logging\backups-private' } else { 'logging\backups' }))
$dest = Join-Path $base $id
$metaFile = Join-Path $dest 'METADATA'
$sumFile = Join-Path $dest 'SHA256SUMS'

function Get-BackupPath([string]$full) {
    # C:\Windows\x -> <dest>\C\Windows\x ; \\server\share\x -> <dest>\UNC\server\share\x
    if ($full -match '^([A-Za-z]):\\(.*)$') { return Join-Path $dest (Join-Path $Matches[1] $Matches[2]) }
    if ($full -match '^\\\\(.*)$') { return Join-Path $dest (Join-Path 'UNC' $Matches[1]) }
    Die "unsupported path: $full"
}
function Get-RegBackupPath([string]$key) {
    $safe = ($key -replace '[\\/:*?"<>|]', '_')
    return Join-Path $dest (Join-Path 'registry' "$safe.reg")
}
function Add-Sum([string]$file) {
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLower()
    Add-Content -LiteralPath $sumFile -Value "$h  $($file.Substring($dest.Length))"
}

function Backup-Item([string]$p) {
    if ($reg) {
        $out = Get-RegBackupPath $p
        if (Test-Path -LiteralPath $out) { Say "already backed up in $id (keeping original): $p"; return }
        New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
        & reg.exe export $p $out /y | Out-Null
        if ($LASTEXITCODE -ne 0) { Die "reg export failed for $p (does the key exist? HKLM may need an elevated shell)" }
        Add-Content -LiteralPath $metaFile -Value "reg`t-`t$p"
        Add-Sum $out; Say "exported $p -> $($out.Substring($Root.Length + 1))"; return
    }
    $full = (Resolve-Path -LiteralPath $p).Path
    $out = Get-BackupPath $full
    if (Test-Path -LiteralPath $out) { Say "already backed up in $id (keeping original): $full"; return }
    New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
    try {
        $isDir = (Get-Item -LiteralPath $full -Force).PSIsContainer
        Copy-Item -LiteralPath $full -Destination $out -Recurse:$isDir -Force
        $sddl = try { (Get-Acl -LiteralPath $full).Sddl } catch { '-' }
    } catch [System.UnauthorizedAccessException] { Die "access denied for $full — run from an elevated (Administrator) shell" }
    $kind = $(if ($isDir) { 'dir' } else { 'file' })
    Add-Content -LiteralPath $metaFile -Value "$kind`t$sddl`t$full"
    if ($isDir) { Get-ChildItem -LiteralPath $out -Recurse -File | ForEach-Object { Add-Sum $_.FullName } } else { Add-Sum $out }
    Say "backed up $full -> $($out.Substring($Root.Length + 1))"
}

function Test-Sums {
    if (-not (Test-Path -LiteralPath $sumFile)) { Say "no checksums for $id"; return }
    $bad = $false
    foreach ($line in Get-Content -LiteralPath $sumFile) {
        $h, $f = $line -split '  ', 2
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath ($dest + $f)).Hash.ToLower()
        if ($actual -ne $h) { Write-Warning "MISMATCH: $f"; $bad = $true }
    }
    if ($bad) { Die "checksum mismatch in $id" } else { Say "checksums OK for $id" }
}

function Restore-Entry([string]$kind, [string]$sddl, [string]$path) {
    if ($kind -eq 'reg') {
        Say "importing registry key $path"
        & reg.exe import (Get-RegBackupPath $path) | Out-Null
        if ($LASTEXITCODE -ne 0) { Die "reg import failed for $path (HKLM needs an elevated shell)" }
        return
    }
    $src = Get-BackupPath $path
    Say "restoring $path"
    try {
        if ($kind -eq 'dir') {
            if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
            Copy-Item -Path (Join-Path $src '*') -Destination $path -Recurse -Force -ErrorAction Stop
        } else {
            Copy-Item -LiteralPath $src -Destination $path -Force
        }
        if ($sddl -and $sddl -ne '-') {
            try { $acl = Get-Acl -LiteralPath $path; $acl.SetSecurityDescriptorSddlForm($sddl); Set-Acl -LiteralPath $path -AclObject $acl }
            catch { Write-Warning "could not restore ACL on $path (needs elevation?)" }
        }
    } catch [System.UnauthorizedAccessException] { Die "access denied for $path — run from an elevated (Administrator) shell" }
}

switch ($mode) {
    'backup' {
        if ($items.Count -eq 0) { Die 'nothing to back up' }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach ($i in $items) { Backup-Item $i }
    }
    'list' {
        if (-not (Test-Path -LiteralPath $metaFile)) { Die "no backups recorded for $id" }
        "KIND`tACL`tPATH"; Get-Content -LiteralPath $metaFile
    }
    'verify' { Test-Sums }
    'restore' {
        if (-not (Test-Path -LiteralPath $metaFile)) { Die "no backups recorded for $id" }
        Test-Sums
        $want = @($items | ForEach-Object { if (Test-Path -LiteralPath $_) { (Resolve-Path -LiteralPath $_).Path } else { $_ } })
        $found = $false
        foreach ($line in Get-Content -LiteralPath $metaFile) {
            $kind, $sddl, $path = $line -split "`t", 3
            if ($want.Count -gt 0 -and $path -notin $want) { continue }
            Restore-Entry $kind $sddl $path; $found = $true
        }
        if (-not $found) { Die "none of the requested items are in $id" }
    }
}
