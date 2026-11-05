# logging/

The record of everything the PC Assistant does to this machine, so any change can be reviewed or rolled back. Claude logs without asking permission.

## Layout
| Path | What | Committed to git? |
|---|---|---|
| `CHANGELOG.md` | **Ledger**: one entry per change to the system, with undo steps | yes* |
| `journal/YYYY-MM.md` | **Journal**: dated notes on tasks, diagnostics, findings, decisions | yes* |
| `backups/<ID>/` | File copies made by `pca-backup` before change `<ID>`, at their full original path, plus `SHA256SUMS` | yes* |
| `backups-private/<ID>/` | Same, for files containing secrets (mode 700) | **never** |
| `baseline/<date>/` | System state snapshots: package lists, services, settings exports | yes* |
| `templates/` | Starter files used by first-time setup | yes |

\* Personal: committed only to your own private backup repo, never to the shared tool repo.

`CHANGELOG.md` and `journal/` are created from `templates/` during first-time setup.

## What goes where
- **CHANGELOG**: anything that changes system state — installs/removals, config edits, services, settings, scheduled tasks, created tools/commands, rollback-tool setup, reverts. If in doubt, log it here.
- **Journal**: read-only investigations and their results, task notes, decisions and the reasons for them, things to monitor, ideas. Link to change IDs where relevant.

## Change IDs
`C-0001`, `C-0002`, … sequential, never reused. Reserve the next ID **before** making the change so the backup folder and the entry share it. A revert is a new entry (`C-0042: revert C-0037`), and the original's status is updated to `reverted by C-0042`.

## CHANGELOG entry format
```markdown
### C-0001 — Short title
- **When:** 2026-01-31 14:05 (local)
- **Why:** user request / reason
- **Tier / approval:** 2 / approved by user  (or: 1 / not required)
- **Changes:**
  - `exact command run` (and its effect)
  - edited `/path/to/file`: what changed
- **Backups:** `logging/backups/C-0001/` (or: none needed — why)
- **Snapshot:** tool + name/ID (or: none)
- **Undo:**
  1. exact steps/commands to reverse it
- **Verified:** how it was checked + result
- **Status:** applied | failed | partially applied | reverted by C-XXXX
```

## Journal entry format
```markdown
## 2026-01-31
### 14:00 — Investigated slow boot
- Findings…
- Decision / next step… (related: C-0001)
```

## How to roll back
Pick the narrowest tool that covers the change:
1. **Follow the entry's Undo steps**: always the first option.
2. **File backup**: `pca-backup --restore C-0001` (or a single file: `pca-backup --restore C-0001 /etc/foo.conf`).
3. **Config-directory history** (if set up, e.g. etckeeper on Linux): `sudo etckeeper vcs log`, then `sudo etckeeper vcs checkout <commit> -- <file>`.
4. **This project's git history** (if this folder is a git repo): `git log`, `git checkout <commit> -- <path>`.
5. **System snapshot** (Timeshift/Snapper/Time Machine/System Restore), for broad or risky changes. A restore is itself Tier 2: ask first, and log it.

## Retention
Keep everything forever unless the profile says otherwise. Flag it to the user if this folder grows large (over about 1 GB).
