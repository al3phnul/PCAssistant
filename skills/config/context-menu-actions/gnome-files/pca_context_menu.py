"""
PC Assistant: extra right-click actions for GNOME Files (Nautilus 43+, nautilus-python 4.x).

Adds to the file/folder context menu:
  Copy Path                         - full path(s), one per line
  Copy Other >  Name                - file name(s)
                Path (shell-quoted) - paths quoted for pasting into a terminal
                Parent Folder Path  - containing folder(s)
                SHA-256             - checksum(s) of selected files (computed in background)
  Open in VS Code                   - if `code` (or codium) is installed
  Open Terminal Here                - the selected folder, or a selected file's folder

Install: symlink/copy into ~/.local/share/nautilus-python/extensions/, then restart Files (`nautilus -q`).
Requires: python3-nautilus (Debian/Ubuntu) / nautilus-python (Fedora/Arch); wl-clipboard (Wayland) or xclip/xsel (X11).
Part of the PC Assistant skill: skills/config/context-menu-actions/
"""
import hashlib
import os
import shlex
import shutil
import subprocess
import threading

import gi

try:
    gi.require_version("Nautilus", "4.1")
except ValueError:
    gi.require_version("Nautilus", "4.0")
from gi.repository import GLib, GObject, Nautilus  # noqa: E402

PREFIX = "PCA::"

# ---------- helpers ----------

def _local_path(f):
    loc = f.get_location()
    return loc.get_path() if loc is not None else None


def _path_or_uri(f):
    return _local_path(f) or f.get_uri()


def _spawn(argv, cwd=None, stdin_text=None):
    """Start a detached process; never block Files."""
    try:
        p = subprocess.Popen(
            argv, cwd=cwd, start_new_session=True,
            stdin=subprocess.PIPE if stdin_text is not None else subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if stdin_text is not None:
            p.stdin.write(stdin_text.encode("utf-8"))
            p.stdin.close()
        return True
    except (OSError, ValueError):
        return False


def _notify(title, body=""):
    if shutil.which("notify-send"):
        _spawn(["notify-send", "--app-name=Files", "--icon=edit-copy", title, body])


def _copy(text, what="Copied"):
    """Copy text to the clipboard. wl-copy/xclip keep serving it after we return."""
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-copy"):
        ok = _spawn(["wl-copy", "--type", "text/plain;charset=utf-8"], stdin_text=text)
    elif shutil.which("xclip"):
        ok = _spawn(["xclip", "-selection", "clipboard"], stdin_text=text)
    elif shutil.which("xsel"):
        ok = _spawn(["xsel", "--clipboard", "--input"], stdin_text=text)
    else:
        ok = False
    if not ok:
        _notify("Copy failed", "Install wl-clipboard (Wayland) or xclip (X11).")
        return
    preview = text if len(text) <= 120 else text[:117] + "..."
    _notify(what, preview)


def _terminal_argv(directory):
    candidates = [
        ("ptyxis", ["ptyxis", "--new-window", "-d", directory]),
        ("kgx", ["kgx", "--working-directory", directory]),
        ("gnome-terminal", ["gnome-terminal", "--working-directory", directory]),
        ("konsole", ["konsole", "--workdir", directory]),
        ("xfce4-terminal", ["xfce4-terminal", "--working-directory", directory]),
        ("tilix", ["tilix", "--working-directory", directory]),
        ("kitty", ["kitty", "--directory", directory]),
        ("alacritty", ["alacritty", "--working-directory", directory]),
        ("wezterm", ["wezterm", "start", "--cwd", directory]),
        ("xdg-terminal-exec", ["xdg-terminal-exec"]),  # uses cwd
        ("x-terminal-emulator", ["x-terminal-emulator"]),
    ]
    for exe, argv in candidates:
        if shutil.which(exe):
            return argv
    return None


def _editor():
    for exe in ("code", "codium", "code-insiders"):
        if shutil.which(exe):
            return exe
    return None


def _sha256_job(paths):
    lines = []
    for p in paths:
        try:
            h = hashlib.sha256()
            with open(p, "rb") as fh:
                for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                    h.update(chunk)
            lines.append(h.hexdigest() if len(paths) == 1 else f"{h.hexdigest()}  {os.path.basename(p)}")
        except OSError as e:
            lines.append(f"ERROR  {os.path.basename(p)}: {e.strerror}")
    GLib.idle_add(_copy, "\n".join(lines), "SHA-256 copied")


# ---------- actions ----------

def _act_copy_path(_item, files):
    _copy("\n".join(_path_or_uri(f) for f in files), "Path copied")


def _act_copy_name(_item, files):
    _copy("\n".join(f.get_name() for f in files), "Name copied")


def _act_copy_quoted(_item, files):
    _copy(" ".join(shlex.quote(_path_or_uri(f)) for f in files), "Quoted path copied")


def _act_copy_parent(_item, files):
    parents = []
    for f in files:
        p = _local_path(f)
        parent = os.path.dirname(p) if p else (f.get_parent_uri() or "")
        if parent and parent not in parents:
            parents.append(parent)
    _copy("\n".join(parents), "Parent folder path copied")


def _act_sha256(_item, files):
    paths = [p for p in (_local_path(f) for f in files if not f.is_directory()) if p]
    if not paths:
        return
    _notify("Computing SHA-256…", f"{len(paths)} file(s)")
    threading.Thread(target=_sha256_job, args=(paths,), daemon=True).start()


def _act_vscode(_item, files):
    exe = _editor()
    paths = [p for p in (_local_path(f) for f in files) if p]
    if exe and paths:
        _spawn([exe, *paths])


def _act_terminal(_item, files):
    p = _local_path(files[0])
    if not p:
        return
    directory = p if os.path.isdir(p) else os.path.dirname(p)
    argv = _terminal_argv(directory)
    if argv:
        _spawn(argv, cwd=directory)
    else:
        _notify("No terminal found", "Install a terminal emulator (e.g. ptyxis or gnome-terminal).")


# ---------- menu provider ----------

class PCAContextMenu(GObject.GObject, Nautilus.MenuProvider):
    def _item(self, name, label, tip, cb, files):
        item = Nautilus.MenuItem(name=PREFIX + name, label=label, tip=tip)
        item.connect("activate", cb, files)
        return item

    def get_file_items(self, *args):
        files = args[-1]  # nautilus-python 4.x: (files); 3.x: (window, files)
        if not files:
            return []
        all_local = all(_local_path(f) for f in files)
        has_files = any(not f.is_directory() for f in files)

        items = [self._item("copy_path", "Copy Path", "Copy the full path to the clipboard", _act_copy_path, files)]

        more = Nautilus.MenuItem(name=PREFIX + "copy_more", label="Copy Other", tip="More copy options")
        sub = Nautilus.Menu()
        sub.append_item(self._item("copy_name", "Name", "Copy the file name", _act_copy_name, files))
        sub.append_item(self._item("copy_quoted", "Path (shell-quoted)", "Copy the path quoted for a terminal", _act_copy_quoted, files))
        sub.append_item(self._item("copy_parent", "Parent Folder Path", "Copy the containing folder's path", _act_copy_parent, files))
        if has_files and all_local:
            sub.append_item(self._item("copy_sha256", "SHA-256", "Compute and copy the SHA-256 checksum", _act_sha256, files))
        more.set_submenu(sub)
        items.append(more)

        if all_local and _editor():
            items.append(self._item("vscode", "Open in VS Code", "Open in Visual Studio Code", _act_vscode, files))
        if len(files) == 1 and all_local:
            items.append(self._item("terminal", "Open Terminal Here", "Open a terminal in this folder", _act_terminal, files))
        return items

    def get_background_items(self, *args):
        folder = args[-1]
        if folder is None or not _local_path(folder) or not _editor():
            return []
        # Built-in menu already has "Copy Location" / "Open in Terminal" for the current folder.
        return [self._item("vscode_bg", "Open Folder in VS Code", "Open this folder in Visual Studio Code", _act_vscode, [folder])]
