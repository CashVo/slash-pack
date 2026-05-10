# install_slash_commands_git.ps1
$ErrorActionPreference = "Stop"

function Write-File($Path, $Content) {
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Set-Content -Path $Path -Value $Content -Encoding utf8 -NoNewline
}

if (-not $env:SLASH_HOME -or $env:SLASH_HOME.Trim() -eq "") {
  throw "SLASH_HOME is not set. Set it or rerun your bootstrapper."
}

$SlashHome   = $env:SLASH_HOME
$PkgRoot     = Join-Path $SlashHome "slash_runtime"
$CommandsDir = Join-Path $PkgRoot "commands"

if (-not (Test-Path $PkgRoot)) {
  throw "slash_runtime not found at: $PkgRoot"
}

New-Item -ItemType Directory -Path $CommandsDir -Force | Out-Null

# ----------------------------
# 1) Add command implementations
# ----------------------------

Write-File (Join-Path $CommandsDir "gcommit.py") @'
from __future__ import annotations

from pathlib import Path
from dataclasses import dataclass

from ..common import run_ok, git_root, SlashError

@dataclass(frozen=True)
class Opts:
    message: str

def run(start: Path, opts: Opts) -> None:
    repo = git_root(start)

    msg = (opts.message or "").strip()
    if not msg:
        raise SlashError('gcommit requires a commit message. Example: /gcommit "fix: update docs"')

    run_ok(["git", "add", "."], cwd=repo)
    run_ok(["git", "commit", "-m", msg], cwd=repo)
    print("Committed.")
'@

Write-File (Join-Path $CommandsDir "g2branch.py") @'
from __future__ import annotations

from pathlib import Path
from dataclasses import dataclass

from ..common import run_ok, git_root, require_clean_worktree, SlashError

@dataclass(frozen=True)
class Opts:
    branch: str

def run(start: Path, opts: Opts) -> None:
    repo = git_root(start)
    require_clean_worktree(repo)

    br = (opts.branch or "").strip()
    if not br:
        raise SlashError("g2branch requires a branch name. Example: /g2branch feature/foo")

    run_ok(["git", "checkout", br], cwd=repo)
    print(f"Checked out: {br}")
'@

Write-File (Join-Path $CommandsDir "greset.py") @'
from __future__ import annotations

from pathlib import Path
from dataclasses import dataclass

from ..common import run_ok, git_root, require_clean_worktree, SlashError

@dataclass(frozen=True)
class Opts:
    target: str
    remote: str

def run(start: Path, opts: Opts) -> None:
    repo = git_root(start)
    require_clean_worktree(repo)

    target = (opts.target or "").strip() or "main"
    remote = (opts.remote or "").strip() or "origin"

    # If user passes "main", we prefer resetting to remote/main if available.
    # If they pass "origin/main" or "somebranch", we'll use exactly that.
    if "/" not in target:
        remote_ref = f"{remote}/{target}"
    else:
        remote_ref = target

    # Make sure refs are fresh
    run_ok(["git", "fetch", remote], cwd=repo)

    # Hard reset current branch to target ref
    run_ok(["git", "reset", "--hard", remote_ref], cwd=repo)
    print(f"Reset --hard to: {remote_ref}")
'@

# ----------------------------
# 2) Update registry.json (merge new commands)
# ----------------------------
$regPath = Join-Path $PkgRoot "registry.json"
if (-not (Test-Path $regPath)) { throw "registry.json not found at: $regPath" }

# Load/modify registry with PowerShell JSON tooling (avoids manual escaping mistakes)
$reg = Get-Content -Raw $regPath | ConvertFrom-Json
if (-not $reg.commands) { $reg | Add-Member -NotePropertyName commands -NotePropertyValue (@{}) }

# Add/overwrite command entries
$reg.commands | Add-Member -Force -NotePropertyName "gcommit" -NotePropertyValue ([pscustomobject]@{
  summary  = 'Stage all changes and commit with a message.'
  options  = @(
    [pscustomobject]@{ name = "<message>"; type="str"; default=$null }
  )
  examples = @(
    '/gcommit "fix: update docs"',
    '/gcommit "wip: checkpoint"'
  )
})

$reg.commands | Add-Member -Force -NotePropertyName "g2branch" -NotePropertyValue ([pscustomobject]@{
  summary  = 'Checkout a branch (requires clean worktree).'
  options  = @(
    [pscustomobject]@{ name = "<branch>"; type="str"; default=$null }
  )
  examples = @(
    "/g2branch main",
    "/g2branch feature/foo"
  )
})

$reg.commands | Add-Member -Force -NotePropertyName "greset" -NotePropertyValue ([pscustomobject]@{
  summary  = "Hard reset the current branch to another branch (default: main). Fetches remote first; requires clean worktree."
  options  = @(
    [pscustomobject]@{ name = "[branch]"; type="str"; default="main" },
    [pscustomobject]@{ name = "--remote"; type="str"; default="origin" }
  )
  examples = @(
    "/greset",
    "/greset main",
    "/greset develop",
    "/greset origin/main",
    "/greset main --remote origin"
  )
})

# Write registry back (UTF-8 no BOM)
$json = $reg | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($regPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Updated registry: $regPath"

# ----------------------------
# 3) Patch __main__.py to register & dispatch commands
# ----------------------------
$mainPath = Join-Path $PkgRoot "__main__.py"
if (-not (Test-Path $mainPath)) { throw "__main__.py not found at: $mainPath" }

$main = Get-Content -Raw $mainPath

# Inject imports if missing
if ($main -notmatch "from .commands.gcommit import") {
  $main = $main -replace '(from .commands.new_slash_shim import run as run_new_shim\s*)',
@'
$1
from .commands.gcommit import Opts as GCommitOpts, run as run_gcommit
from .commands.g2branch import Opts as G2BranchOpts, run as run_g2branch
from .commands.greset import Opts as GResetOpts, run as run_greset

'@
}

# Add argparse subcommands if missing
if ($main -notmatch 'sub.add_parser("gcommit")') {
  $main = $main -replace '(n = sub.add_parser("new-slash-shim")[\s\S]*?return p)',
@'
n = sub.add_parser("new-slash-shim")
n.add_argument("--force", action="store_true", default=False)
n.add_argument("--repo", default=None)

gc = sub.add_parser("gcommit")
gc.add_argument("message", nargs="?", default="")

g2 = sub.add_parser("g2branch")
g2.add_argument("branch", nargs="?", default="")

gr = sub.add_parser("greset")
gr.add_argument("target", nargs="?", default="main")
gr.add_argument("--remote", default="origin")

return p
'@
}

# Add dispatch handlers if missing
if ($main -notmatch 'if args.cmd == "gcommit":') {
  $main = $main -replace '(if args.cmd == "new-slash-shim"[\s\S]*?return 0\s*)',
@'
$1

if args.cmd == "gcommit":
    opts = GCommitOpts(message=args.message)
    run_gcommit(Path("."), opts)
    return 0

if args.cmd == "g2branch":
    opts = G2BranchOpts(branch=args.branch)
    run_g2branch(Path("."), opts)
    return 0

if args.cmd == "greset":
    opts = GResetOpts(target=args.target, remote=args.remote)
    run_greset(Path("."), opts)
    return 0

'@
}

# Normalize indentation: tabs -> 4 spaces (prevents TabError)
$main = $main -replace "`t", "    "

Set-Content -Path $mainPath -Value $main -Encoding utf8
Write-Host "Patched runner: $mainPath"

# ----------------------------
# 4) Write README.md at SLASH_HOME
# ----------------------------
$readmePath = Join-Path $SlashHome "README.md"
Write-File $readmePath @'
# slash-pack

A project-agnostic “slash command” toolkit for running common developer workflows from your terminal using commands like:

- `/help`
- `/new-slash-shim`
- `/merge-branches`
- `/gcommit "message"`
- `/greset [branch]`
- `/g2branch <branch>`

## How it works

- You keep a canonical command pack at `$SLASH_HOME` (this repo/folder).
- Each git repo opts-in by having a small shim at `utils/slash/shim.py`.
- Your PowerShell profile intercepts lines starting with `/` and dispatches them to the repo shim.
- The repo shim runs the canonical pack via `python -m slash_runtime ...`.

## Dependencies

Required:
- Python (invoked via `py.exe` or `python`)
- Git

Optional (for prettier `/help` output):
- `rich`
  - Install (for the interpreter used by `py.exe`): `py -m pip install rich`

PowerShell UX (optional):
- PSReadLine
- PSFzf (for better reverse history search)

## Install / Update

Typical flow:
1. Set `SLASH_HOME` (example): `C:\Users\<you>\slash-pack`
2. Run your bootstrapper to create/update the pack and PowerShell hooks.
3. In any repo you want to enable:
   - `cd $env:SLASH_HOME`
   - `python -m slash_runtime new-slash-shim --repo <repo-path> --force`

## Usage

Inside an enabled repo (has `utils/slash/shim.py`):

- `/help`
- `/gcommit "fix: update docs"`
- `/g2branch feature/foo`
- `/greset` (defaults to main via origin/main)
- `/greset develop`
- `/merge-branches --dry-run`

## Adding a new command (developer guide)

### 1) Create a command module
Add a file under:

`slash_runtime/commands/<your_command>.py`

Expose a `run(start: Path, opts: Opts) -> None` function. Keep it project-agnostic.

### 2) Register it in the runner
Edit `slash_runtime/__main__.py`:

- Add an argparse subcommand (parser + args)
- Dispatch to your module’s `run(...)`

### 3) Add it to registry.json
Edit `slash_runtime/registry.json` to add:

- `summary`
- `options`
- `examples`

`/help` and tab completion rely on this registry.

### 4) Test
From SLASH_HOME:

`python -m slash_runtime help`

From an enabled repo:

`/help`
'@

Write-Host "Wrote README: $readmePath"

Write-Host ""
Write-Host "DONE."
Write-Host "Next:"
Write-Host "  - Reload profile if needed: . `$PROFILE"
Write-Host "  - Test in an enabled repo: /help"