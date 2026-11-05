#!/bin/sh
# install-commands.sh — expose every skills/**/pca-*.sh script as a `pca-*` command (Linux/macOS/BSD).
# Idempotent: re-run after adding a skill. Only manages symlinks that point into this project;
# never overwrites anything else. Removes dangling pca-* links that pointed into this project.
#   sh install-commands.sh [BIN_DIR]     (default: ~/.local/bin)
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$here/../../.." && pwd -P)
BIN=${1:-$HOME/.local/bin}
mkdir -p "$BIN"

find "$ROOT/skills" -type f -name 'pca-*.sh' | sort | while IFS= read -r src; do
  name=$(basename "$src" .sh)
  link="$BIN/$name"
  chmod +x "$src"
  if [ -L "$link" ]; then
    cur=$(readlink "$link")
    [ "$cur" = "$src" ] && { echo "ok       $name"; continue; }
    case $cur in "$ROOT"/*) ln -sf "$src" "$link"; echo "updated  $name -> $src"; continue ;; esac
    echo "SKIPPED  $name: $link already points to $cur (not ours)" >&2; continue
  elif [ -e "$link" ]; then
    echo "SKIPPED  $name: $link exists and is not a symlink" >&2; continue
  fi
  ln -s "$src" "$link"; echo "linked   $name -> $src"
done

# prune dangling links that pointed into this project
for l in "$BIN"/pca-*; do
  [ -L "$l" ] || continue
  t=$(readlink "$l")
  case $t in "$ROOT"/*) [ -e "$t" ] || { rm "$l"; echo "removed  $(basename "$l") (target gone)"; } ;; esac
done

case ":$PATH:" in *":$BIN:"*) ;; *) echo "NOTE: $BIN is not on PATH — add it in your shell profile." ;; esac
