#!/bin/sh
# pca-backup — back up / restore files tied to a PC Assistant change ID.
# POSIX sh; works on Linux, macOS, BSD. Part of the change-backup skill.
#
#   pca-backup <ID> [--private] <path>...      back up files/dirs before change <ID>
#   pca-backup --restore <ID> [--private] [path...]   restore all (or listed) paths from <ID>
#   pca-backup --list <ID> [--private]         show what <ID> backed up
#   pca-backup --verify <ID> [--private]       check backup checksums
#
# Files are copied to logging/backups/<ID>/<absolute path> (dirs as <path>.tar to keep
# owners/permissions). Original mode/owner/group recorded in METADATA; hashes in SHA256SUMS.
# --private uses logging/backups-private/ (mode 700, never committed) for files with secrets.
set -eu

die() { echo "pca-backup: $*" >&2; exit 1; }
say() { echo "pca-backup: $*"; }

# --- locate project root from this script's real location (follows symlinks) ---
resolve() {
  p=$1
  while [ -L "$p" ]; do
    l=$(ls -ld "$p" | sed 's/.* -> //')
    case $l in /*) p=$l ;; *) p=$(dirname "$p")/$l ;; esac
  done
  (cd "$(dirname "$p")" && pwd -P)
}
SCRIPT_DIR=$(resolve "$0")
ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd -P)
[ -f "$ROOT/CLAUDE.md" ] || die "cannot find project root (looked in $ROOT)"

# --- portability helpers ---
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }
if stat -c '%a' / >/dev/null 2>&1; then STAT_FMT="-c"; STAT_SPEC='%a %U %G'; else STAT_FMT="-f"; STAT_SPEC='%Lp %Su %Sg'; fi
need_root() { # run a command; escalate with sudo -n only if it fails as the current user
  if "$@" 2>/dev/null; then return 0; fi
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    sudo -n true 2>/dev/null || die "needs admin rights for: $* — run 'sudo -v' first, then retry"
    sudo -n "$@" || die "failed even with sudo: $*"
  else
    "$@"  # re-run to show the real error
  fi
}
meta() { need_root stat -L $STAT_FMT "$STAT_SPEC" "$1"; } # prints: mode owner group
abspath() {
  case $1 in /*) a=$1 ;; *) a=$(pwd -P)/$1 ;; esac
  printf '%s\n' "$a" | sed 's#/\./#/#g; s#//*#/#g; s#/$##'
}

# --- args (--private may appear anywhere) ---
MODE=backup; PRIVATE=0; ID=""
n=$#; i=0
while [ $i -lt $n ]; do
  a=$1; shift; i=$((i+1))
  if [ "$a" = "--private" ]; then PRIVATE=1; else set -- "$@" "$a"; fi
done
case ${1:-} in
  --restore|--list|--verify) MODE=${1#--}; shift ;;
  -h|--help|"") sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
ID=${1:-}; [ -n "$ID" ] || die "missing change ID (e.g. C-0042)"; shift
case $ID in C-[0-9]*) ;; *) die "change ID should look like C-0042 (got '$ID')" ;; esac

BASE="$ROOT/logging/backups"; [ $PRIVATE -eq 1 ] && BASE="$ROOT/logging/backups-private"
DEST="$BASE/$ID"
ME_U=$(id -un); ME_G=$(id -gn)

backup_one() {
  src=$(abspath "$1")
  [ -e "$src" ] || [ -L "$src" ] || die "no such file: $src"
  if [ -d "$src" ] && [ ! -L "$src" ]; then out="$DEST$src.tar"; kind=dir; else out="$DEST$src"; kind=file; fi
  if [ -e "$out" ]; then say "already backed up in $ID (keeping the original copy): $src"; return; fi
  mkdir -p "$(dirname "$out")"
  if [ $kind = dir ]; then
    need_root tar -cpf "$out" -C "$(dirname "$src")" "$(basename "$src")"
  else
    need_root cp -pP "$src" "$out"
  fi
  # make the copy readable by the user (git, viewing); originals' perms are in METADATA
  if [ ! -O "$out" ]; then need_root chown -h "$ME_U:$ME_G" "$out"; fi
  [ -L "$out" ] || chmod u+rw "$out"
  m=$(meta "$src")
  printf '%s\t%s\t%s\n' "$kind" "$m" "$src" >> "$DEST/METADATA"
  if [ ! -L "$out" ]; then printf '%s  %s\n' "$(sha "$out")" "${out#"$DEST"}" >> "$DEST/SHA256SUMS"; fi
  say "backed up $src -> ${out#"$ROOT"/}"
}

verify() {
  [ -f "$DEST/SHA256SUMS" ] || { say "no checksums for $ID"; return 0; }
  bad=0
  while IFS= read -r line; do
    h=${line%%  *}; f=${line#*  }
    if [ "$(sha "$DEST$f")" != "$h" ]; then echo "MISMATCH: $f" >&2; bad=1; fi
  done < "$DEST/SHA256SUMS"
  [ $bad -eq 0 ] && say "checksums OK for $ID" || die "checksum mismatch in $ID"
}

restore_one() { # args: kind mode owner group path
  kind=$1 mode=$2 owner=$3 group=$4 dst=$5
  if [ "$kind" = dir ]; then
    say "restoring directory $dst"
    need_root tar -xpf "$DEST$dst.tar" -C "$(dirname "$dst")"
  else
    say "restoring $dst"
    need_root cp -P "$DEST$dst" "$dst"
    if [ ! -L "$dst" ]; then
      need_root chmod "$mode" "$dst"
      [ "$owner:$group" = "$ME_U:$ME_G" ] || need_root chown "$owner:$group" "$dst"
    fi
  fi
}

case $MODE in
  backup)
    [ $# -gt 0 ] || die "nothing to back up"
    mkdir -p "$DEST"; [ $PRIVATE -eq 1 ] && chmod 700 "$BASE" "$DEST"
    for f in "$@"; do backup_one "$f"; done
    ;;
  list)
    [ -f "$DEST/METADATA" ] || die "no backups recorded for $ID in ${BASE#"$ROOT"/}"
    printf 'KIND\tMODE OWNER GROUP\tPATH\n'; cat "$DEST/METADATA"
    ;;
  verify) verify ;;
  restore)
    [ -f "$DEST/METADATA" ] || die "no backups recorded for $ID in ${BASE#"$ROOT"/}"
    verify
    WANT=""; NL='
'
    for f in "$@"; do WANT="$WANT$(abspath "$f")$NL"; done
    found=0
    while IFS="$(printf '\t')" read -r kind m path; do
      set -- $m; mode=$1 owner=$2 group=$3
      if [ -n "$WANT" ]; then
        case "$NL$WANT" in *"$NL$path$NL"*) ;; *) continue ;; esac
      fi
      restore_one "$kind" "$mode" "$owner" "$group" "$path"; found=1
    done <<EOF
$(cat "$DEST/METADATA")
EOF
    [ $found -eq 1 ] || die "none of the requested paths are in $ID"
    ;;
esac
