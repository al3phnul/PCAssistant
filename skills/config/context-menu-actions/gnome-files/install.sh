#!/bin/sh
# Install / uninstall the PC Assistant context-menu extension for GNOME Files (Nautilus).
#   sh install.sh            symlink the extension into ~/.local/share/nautilus-python/extensions/
#   sh install.sh --remove   remove that symlink
# Afterwards restart Files:  nautilus -q   (closes open Files windows)
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
src="$here/pca_context_menu.py"
dir="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions"
dst="$dir/pca_context_menu.py"

if [ "${1:-}" = "--remove" ]; then
  if [ -L "$dst" ]; then rm "$dst"; echo "removed $dst"; else echo "not installed"; fi
  exit 0
fi

python3 -c 'import gi
try: gi.require_version("Nautilus","4.1")
except ValueError: gi.require_version("Nautilus","4.0")
from gi.repository import Nautilus' 2>/dev/null || {
  echo "nautilus-python is missing. Install it with your package manager:" >&2
  echo "  Debian/Ubuntu: python3-nautilus   Fedora: nautilus-python   Arch: python-nautilus" >&2
  exit 1; }

mkdir -p "$dir"
if [ -e "$dst" ] && [ ! -L "$dst" ]; then echo "refusing: $dst exists and is not our symlink" >&2; exit 1; fi
ln -sfn "$src" "$dst"
echo "installed $dst -> $src"
case "${XDG_SESSION_TYPE:-}" in
  wayland) command -v wl-copy >/dev/null || echo "NOTE: install wl-clipboard for the Copy actions" ;;
  *) command -v xclip >/dev/null || command -v xsel >/dev/null || echo "NOTE: install xclip for the Copy actions" ;;
esac
echo "Restart Files to load it:  nautilus -q"
