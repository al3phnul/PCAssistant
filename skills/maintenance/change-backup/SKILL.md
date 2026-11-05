---
name: change-backup
summary: Back up and restore files, folders, and Windows registry keys, tied to a change ID.
triggers:
  - "before editing any config file" (mandatory: CLAUDE.md §4.1)
  - "undo / roll back change C-XXXX"
  - "what did change C-XXXX back up?"
platforms: [linux, macos, bsd, windows]
scope: shared
tier: 1
needs_admin: only when the file or key requires it
command: pca-backup
scripts:
  posix: pca-backup.sh
  windows: pca-backup.ps1
version: 1.0
updated: 2026-11-04
---

# change-backup

## Purpose
Makes "backup before edit" one consistent command, so every change can be undone exactly. Backups live under the change's ID, which links each one to its CHANGELOG entry.

## Usage
```
pca-backup <ID> <path>...                 # back up before change <ID>
pca-backup <ID> --private <path>...       # file contains secrets → logging/backups-private/ (never committed)
pca-backup <ID> --reg <key>...            # Windows only: reg export (e.g. HKCU\Software\Foo)
pca-backup --list <ID>                    # what <ID> backed up (original mode/owner or ACL)
pca-backup --verify <ID>                  # check SHA-256 checksums
pca-backup --restore <ID> [path...]       # restore everything, or only the listed paths
```
- Storage: `logging/backups/<ID>/<absolute path>`. Unix directories are stored as `<path>.tar` so owners and permissions survive. On Windows the path is `<ID>\C\Windows\...`, and registry keys go in `<ID>\registry\*.reg`.
- `METADATA` records the original mode/owner/group (Unix) or ACL SDDL (Windows). `SHA256SUMS` holds the hashes.
- Backing up the same path twice under one ID keeps the **first** (original) copy.
- Unix: if the current user can't read or write the file, the script uses `sudo -n`. When elevation isn't cached, it fails with a clear message instead of prompting. Copies are re-owned to the user so git can read them.
- Windows: run from an elevated shell when backing up or restoring protected files or HKLM.

## Steps (for Claude)
1. Reserve the next change ID from `logging/CHANGELOG.md`.
2. `pca-backup <ID> <every file you will modify>`. Use `--private` if any of them hold secrets (credentials, Wi-Fi PSKs, tokens, keys).
3. Make the change. Record the backup path in the CHANGELOG entry.
4. **Undoing a change:** reserve a new ID, back up the *current* state first (`pca-backup <NEW-ID> <files>`), then `pca-backup --restore <OLD-ID> [files]`. Log the revert and mark the old entry `reverted by <NEW-ID>`.

## Verification
`pca-backup --verify <ID>` after backing up. After a restore, diff the restored file against its backup, or check that the service or setting behaves as it did before.

## Rollback
Backups are additive. Deleting `logging/backups/<ID>/` removes them (never needed in normal use).

## Platform status
- POSIX (`pca-backup.sh`): tested on Linux (GNU coreutils). Written to also work on macOS/BSD (`stat -f` fallback, `shasum`).
- Windows (`pca-backup.ps1`): **not yet tested on a real Windows machine.** Validate on first use and fix anything that's off.

## Changelog
- 1.0 (2026-11-04): created.
