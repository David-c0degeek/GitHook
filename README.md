# GitHook

Shared Git hooks, versioned in this repo and installed on each developer
machine via a **symbolic link**. A `git pull` here updates the hook for
everyone who has run `install.ps1` once.

## Layout

- `hooks/` — the actual hook scripts (standard Git hook names, no extension).
  - `pre-commit` — sh shim that launches PowerShell.
  - `pre-commit.ps1` — strips UTF‑8 BOM from staged files; blocks the commit
    if any literal `U+FEFF` (ZWNBSP) characters remain inside files.
- `install.ps1` — creates a directory symlink and points Git at it.

## How it works

```
$HOME\.githooks   ──symlink──►   <this repo>\hooks
                                       ▲
                                  git pull here
                                  updates everyone
```

`install.ps1`:
1. Creates a directory symlink `<LinkPath>` → `<repo>\hooks`.
2. Sets `git config --global core.hooksPath = <LinkPath>` (unless `-NoGitConfig`).

The symlink approach (instead of pointing `core.hooksPath` straight at the
repo) keeps the Git config stable when the repo is moved or re-cloned —
just re-run the installer to repoint the link.

## Requirements

Creating symlinks on Windows requires **one** of:
- Running PowerShell **as Administrator**, or
- **Developer Mode** enabled (Settings → Privacy & Security → For developers).

## Usage

Clone this repo somewhere stable, then from its root:

```powershell
# Default: symlink $HOME\.githooks -> .\hooks  and  set core.hooksPath
.\install.ps1

# Custom link location
.\install.ps1 -LinkPath C:\Tools\githooks

# Replace whatever (file/folder/symlink) is at the link path
.\install.ps1 -Force

# Only create the symlink, don't touch Git config
.\install.ps1 -NoGitConfig

# Remove the symlink and clear core.hooksPath (if it points at LinkPath)
.\install.ps1 -Uninstall
```

## Updating hooks on a machine

```powershell
cd <path-to-this-repo>
git pull
```
That's it — the symlink resolves to the freshly pulled files.

## Adding a new hook

1. Drop a file into `hooks/` named exactly like the Git hook (e.g.
   `commit-msg`, `pre-push`). No extension. Start with `#!/bin/sh` (or
   another interpreter) and make it executable on POSIX systems.
2. Commit & push. Other machines pick it up on their next `git pull`.

