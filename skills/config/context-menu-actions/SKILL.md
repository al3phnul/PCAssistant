---
name: context-menu-actions
summary: Add custom right-click actions (Copy Path, Copy Name, quoted path, parent path, SHA-256, Open in VS Code, Open Terminal Here) to the file manager. GNOME Files is implemented; the other OSes are covered by documented recipes.
triggers:
  - "add X to the right-click menu"
  - "copy path from the file manager"
  - "open terminal / VS Code from Files"
platforms: [linux-gnome (implemented), linux-kde, windows, macos (recipes)]
scope: shared
tier: 2
needs_admin: only to install the nautilus-python package
command: none
scripts:
  gnome: gnome-files/pca_context_menu.py, gnome-files/install.sh
version: 1.0
updated: 2026-11-05
---

# context-menu-actions

## Purpose
Puts handy actions in the file manager's right-click menu. The same set of actions on every desktop, using whatever mechanism that desktop supports.

## GNOME Files / Nautilus 43+ (implemented)
A **nautilus-python** extension: `gnome-files/pca_context_menu.py`.

| Menu item | Does |
|---|---|
| Copy Path | Full path(s), one per line. Non-local files (trash, network) fall back to their URI. |
| Copy Other ▸ Name | File name(s). |
| Copy Other ▸ Path (shell-quoted) | Paths quoted for a terminal, separated by spaces. |
| Copy Other ▸ Parent Folder Path | The containing folder(s), with duplicates removed. |
| Copy Other ▸ SHA-256 | Checksums of the selected files, computed in a background thread. Shown only for local regular files. |
| Open in VS Code | `code` / `codium` with the selection. Hidden if neither is installed. |
| Open Terminal Here | The selected folder, or the selected file's folder (single selection). Uses the first terminal it finds: ptyxis, kgx, gnome-terminal, konsole, … |
| *(empty space)* Open Folder in VS Code | The current folder. The built-in menu already has Copy Location and Open in Terminal. |

Each copy action shows a notification (`notify-send`) with a preview. The clipboard goes through `wl-copy` (Wayland) or `xclip`/`xsel` (X11), which keep serving the text after Files moves on.

### Install
1. Install the package (Tier 2): `python3-nautilus` on Debian/Ubuntu, `nautilus-python` on Fedora, `python-nautilus` on Arch. Also `wl-clipboard` or `xclip`, if they're missing.
2. `sh skills/config/context-menu-actions/gnome-files/install.sh`. This symlinks the extension into `~/.local/share/nautilus-python/extensions/`, so edits to the source take effect after a restart.
3. Restart Files: `nautilus -q`. **This closes any open Files windows**, so tell the user first and let them pick the moment.
4. Verify: right-click a file and check the items appear. Test Copy Path with `wl-paste`.

### Add or change an action
Write an `_act_*` function and register it in `get_file_items` (or `get_background_items`). Test the logic outside Files with stand-in file objects: anything with `get_location()`, `get_uri()`, `get_name()`, `get_parent_uri()`, and `is_directory()`. Then run `nautilus -q`. Errors show up in `journalctl --user -b | grep -i nautilus`, or run `nautilus` from a terminal to see Python tracebacks.

### Uninstall
`sh …/gnome-files/install.sh --remove && nautilus -q`. Then optionally `apt purge python3-nautilus gir1.2-nautilus-4.1`.

## Other desktops (recipes, to build when needed)
- **KDE Dolphin:** service menus. Put a `.desktop` file in `~/.local/share/kio/servicemenus/` with `Type=Service`, `X-KDE-ServiceTypes=KonqPopupMenu/Plugin`, `MimeType=all/all;`, and `Actions=copyPath;…`. Each `[Desktop Action copyPath]` gets `Exec=sh -c 'printf %s "$1" | wl-copy' _ %f`. Mark the file executable (`chmod +x`).
- **Other GTK file managers** (Nemo, Caja, Thunar): Nemo uses `~/.local/share/nemo/actions/*.nemo_action`. Thunar uses its Custom Actions (`~/.config/Thunar/uca.xml`).
- **Windows 10/11:** per-user verbs under `HKCU\Software\Classes\*\shell\<Name>\command` (files) and `HKCU\Software\Classes\Directory\shell\<Name>\command` (folders). No admin needed. **Back up first** with `pca-backup <ID> --reg HKCU\Software\Classes\*\shell`. Note that Windows 11 shows "Copy as path" built in (Ctrl+Shift+C), and puts custom verbs under "Show more options".
- **macOS:** Finder already has *Option-right-click → Copy "<name>" as Pathname* (⌥⌘C). For other actions, use a Shortcuts/Automator **Quick Action** ("Receives files or folders in Finder", with a Run Shell Script step) saved in `~/Library/Services/`.

## Rollback
Remove the symlink (or `.desktop` / registry key / Quick Action), restart the file manager, and optionally remove the package. Each install is logged with its own undo steps.

## Platform status
- GNOME Files 50 (Ubuntu 26.04, Wayland): the actions were unit-tested against the live clipboard. Checking the menu in Files itself is pending a Files restart.
- The other desktops are documented recipes only, not yet built or tested.

## Changelog
- 1.0 (2026-11-05): created (GNOME implementation plus recipes for other platforms).
