# PC Assistant

Turn [Claude Code](https://claude.com/claude-code) into a personal PC assistant for **your** computer. It handles configuration, cleanup, troubleshooting, performance tuning, and builds small tools that automate the things you keep doing by hand. Every change it makes is **logged with undo steps** and backed up first, so you can always look back or roll back.

It works on any OS. On first use it scans your system and asks how you want it to behave, then adapts to whatever it finds: Ubuntu, Fedora, Arch, an obscure distro, macOS, Windows 10/11, or Windows Server.

> **Status:** designed and tested on Linux (Ubuntu). macOS and Windows support is written but has had less real-world use. If something doesn't work, tell Claude; it's told to fix and log issues like that.

---

## What you need
- **Claude Code.** The **VS Code extension** is recommended. The CLI (`claude` in a terminal), desktop app, and JetBrains plugin also work. You need a Claude account with Claude Code access.
- **git**, to download the tool and get updates. (Windows: [git-scm.com](https://git-scm.com). macOS: `xcode-select --install`. Linux: your package manager.)
- **Admin rights on your computer**, for the system-level things you approve (sudo on Linux/macOS, Administrator on Windows). The assistant never asks for your password. You stay in control of elevation.
- **Windows:** PowerShell 5.1 or newer, which is built in.
- *Optional:* the [GitHub CLI](https://cli.github.com) (`gh`), if you want to back up your own copy to a private GitHub repo.

## Install
```bash
git clone https://github.com/al3phnul/PCAssistant.git
```
Open the `PCAssistant` folder in VS Code (**File → Open Folder…**) and open Claude Code (the Claude icon / Spark in the sidebar). If you use the CLI, `cd PCAssistant` and run `claude`.

> Always start Claude Code **in this folder**. That's how it loads the rulebook (`CLAUDE.md`) and your profile.

## First use: say "First time setup"
Type:

```
First time setup
```

(or `/first-time-setup`). The assistant will:
1. **Scan your system**, read-only: OS, hardware, disks, package managers, available tools. Nothing is changed.
2. **Ask about 8 quick questions:** how much freedom it gets, how admin rights are handled, which package sources you prefer, how chatty it should be, which rollback tools you want, how long to keep backups, and whether to back up your copy to a private repo.
3. **Set itself up:** it writes your profile (`profile/SYSTEM.md`, `profile/PREFERENCES.md`), starts your change log, records a baseline of your system, and installs a few `pca-*` helper commands.
4. **Offer rollback tools for your OS**, each only with your approval: for example Timeshift/Snapper and etckeeper on Linux, Time Machine local snapshots on macOS, System Restore on Windows.

It takes about 5–10 minutes. You can change any answer later ("change my autonomy to ask-first").

## Using it day to day
Open the folder in VS Code, start Claude Code, and ask in plain language:

| You say | What happens |
|---|---|
| "My disk is almost full, what can I clean up?" | Read-only analysis first, then a list of what it would remove. Nothing is deleted until you approve. |
| "Why is boot so slow?" | Diagnoses with your OS's tools (`systemd-analyze`, startup items, Event Viewer…) and suggests fixes. |
| "Update everything" | Runs your system's updates. Takes a snapshot first if that's set up. |
| "Install a good PDF editor" | Recommends one, uses your preferred package source, and logs exactly what it installed. |
| "Undo C-0012" | Follows that change's logged undo steps and restores its backups. |
| "Make this a skill" / "automate this" | Turns a repeated task into a reusable skill and a `pca-*` command. |
| "Add a rule: never touch my Steam folder" | Adds it to your personal rules. |
| "Re-scan my system" | Refreshes your system profile after hardware or OS changes. |

### How it keeps you safe
- **Tiered autonomy:** it looks around freely, makes small easy-to-undo personal changes and tells you about them, and **asks before** anything admin-level, destructive, or hard to reverse. (You pick the level.)
- **Backup before every config edit** (`pca-backup`), plus a system snapshot before risky changes when you have a snapshot tool.
- **Dry runs:** a preview before bulk or destructive operations.
- **No `curl | bash`:** downloads are inspected first, and official sources are preferred.
- **Secrets stay out of the logs.**

## Where things live
```
CLAUDE.md            the rulebook (same for everyone, loads automatically)
profile/             YOUR system profile and preferences (created by setup)
skills/              reusable procedures and scripts; INDEX.md lists them all
  personal/          your own machine-specific skills
logging/
  CHANGELOG.md       every change: what, why, how to undo (C-0001, C-0002, …)
  journal/           notes on tasks and diagnostics
  backups/           file copies made before each change
  baseline/          system state snapshots
```
Ask "what have you changed this week?" or open `logging/CHANGELOG.md` directly.

## Updating
```bash
git pull
```
Your personal files (`profile/`, logs, backups, personal skills) are git-ignored, so updates never conflict with them, and your data never leaves your machine through this repo. Put your own rule changes in `profile/PREFERENCES.md` (the assistant does this for you). That keeps `CLAUDE.md` clean for updates.

## Backing up your own copy (optional)
During setup, choose **"back up this folder to a private repo."** The assistant will:
- rename this repo's remote to `upstream`
- create a **private** repo on your GitHub account
- start tracking your personal files there

After that, get tool updates with `git pull upstream main`. Never push your personal data to this shared repo.

## Troubleshooting
- **It didn't offer setup / it doesn't seem to know the rules:** make sure Claude Code was started in the `PCAssistant` folder.
- **`pca-*` commands not found:** open a new terminal. On Windows, `%USERPROFILE%\.pca\bin` is added to your PATH, and new terminals pick it up.
- **Linux/macOS: admin commands keep failing, or it keeps asking you to run `sudo -v`:** Claude's shell usually can't see a sudo login you made in another terminal. During setup it offers a fix that suits your system: a small sudoers tweak, a scoped passwordless rule for specific commands (needed with **sudo-rs**, the default on newer Ubuntu), or you running the admin commands yourself. It explains the trade-offs first, and **you** install any sudoers change yourself.
- **Windows: scripts are blocked:** the helpers run with `-ExecutionPolicy Bypass` for that single command. Your system policy isn't changed.

## License
MIT. See [LICENSE](LICENSE).
