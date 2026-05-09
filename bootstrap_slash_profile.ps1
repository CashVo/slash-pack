# install_slash_pack.ps1
$ErrorActionPreference = "Stop"

function Write-File($Path, $Content) {
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Set-Content -Path $Path -Value $Content -Encoding utf8 -NoNewline
}

# 0) SLASH_HOME default (Choice B)
if (-not $env:SLASH_HOME -or $env:SLASH_HOME.Trim() -eq "") {
  $default = Join-Path $env:USERPROFILE "slash-pack"
  [Environment]::SetEnvironmentVariable("SLASH_HOME", $default, "User")
  $env:SLASH_HOME = $default
}
$SlashHome = $env:SLASH_HOME
Write-Host "SLASH_HOME = $SlashHome"

# 1) Optional tooling
try { Install-Module PSReadLine -Scope CurrentUser -Force -ErrorAction SilentlyContinue } catch { }
try { Install-Module PSFzf -Scope CurrentUser -Force -ErrorAction SilentlyContinue } catch { }
try { Install-Module Rich -Scope CurrentUser -Force -ErrorAction SilentlyContinue } catch { }

# 2) Create canonical pack
$PkgRoot = Join-Path $SlashHome "slash_runtime"
$CommandsDir = Join-Path $PkgRoot "commands"
New-Item -ItemType Directory -Path $CommandsDir -Force | Out-Null

# registry.json (NO Windows backslashes; use placeholders)
$registryJson = @'
{
  "version": 1,
  "commands": {
    "help": {
      "summary": "Show slash command help and examples.",
      "options": [],
      "examples": ["/help"]
    },
    "merge-branches": {
      "summary": "Merge branches into main in order. If --branches omitted, defaults to current branch.",
      "options": [
        {"name":"--remote","type":"str","default":"origin"},
        {"name":"--main","type":"str","default":"main"},
        {"name":"--branches","type":"list","nargs":"*","default":"<current-branch>"},
        {"name":"--push-first","type":"flag"},
        {"name":"--no-tests","type":"flag"},
        {"name":"--dry-run","type":"flag"}
      ],
      "examples": [
        "/merge-branches",
        "/merge-branches --dry-run",
        "/merge-branches --branches chunk002 chunk3-warden chunk4-identity",
        "/merge-branches --push-first --no-tests"
      ]
    },
    "new-slash-shim": {
      "summary": "Create/update utils/slash/shim.py in a git repo so /commands are enabled in that repo.",
      "options": [
        {"name":"--force","type":"flag"},
        {"name":"--repo","type":"str","default":null}
      ],
      "examples": [
        "/new-slash-shim",
        "/new-slash-shim --repo <repo-path>",
        "/new-slash-shim --repo <repo-path> --force"
      ]
    }
  }
}
'@
Write-File (Join-Path $PkgRoot "registry.json") $registryJson

Write-File (Join-Path $PkgRoot "__init__.py") "# slash_runtime package`n"

Write-File (Join-Path $PkgRoot "common.py") @'
from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

class SlashError(RuntimeError):
    pass

@dataclass(frozen=True)
class CmdResult:
    returncode: int
    stdout: str
    stderr: str

def run(cmd: list[str], cwd: Path | None = None) -> CmdResult:
    p = subprocess.run(cmd, cwd=str(cwd) if cwd else None, text=True, capture_output=True)
    return CmdResult(p.returncode, p.stdout, p.stderr)

def run_ok(cmd: list[str], cwd: Path | None = None) -> CmdResult:
    r = run(cmd, cwd=cwd)
    if r.returncode != 0:
        raise SlashError(
            f"Command failed: {' '.join(cmd)}\\n\\nSTDOUT:\\n{r.stdout}\\n\\nSTDERR:\\n{r.stderr}"
        )
    return r

def git_root(start: Path) -> Path:
    r = run_ok(["git", "rev-parse", "--show-toplevel"], cwd=start)
    return Path(r.stdout.strip()).resolve()

def load_registry() -> dict[str, Any]:
    home = os.environ.get("SLASH_HOME", "").strip()
    if not home:
        raise SlashError("SLASH_HOME is not set.")
    reg_path = Path(home) / "slash_runtime" / "registry.json"
    if not reg_path.exists():
        raise SlashError(f"registry.json not found at: {reg_path}")
    # utf-8-sig tolerates BOM
    return json.loads(reg_path.read_text(encoding="utf-8-sig"))

def venv_python(repo_root: Path) -> Path | None:
    py = repo_root / ".venv" / "Scripts" / "python.exe"
    return py if py.exists() else None

def require_clean_worktree(repo_root: Path) -> None:
    r = run_ok(["git", "status", "--porcelain"], cwd=repo_root)
    if r.stdout.strip():
        raise SlashError("Working tree is not clean. Commit/stash changes first.")
'@

# help_cmd.py (Rich for /help only + options listing)
Write-File (Join-Path $CommandsDir "help_cmd.py") @'
from __future__ import annotations
from ..common import load_registry

def _fmt_option_plain(o: dict, plain: bool) -> str:
    name = o.get("name", "")
    typ = o.get("type", "")
    default = o.get("default", None)
    nargs = o.get("nargs", None)

    meta = []
    if typ:
        meta.append(str(typ))
    if nargs is not None:
        meta.append(f"nargs={nargs}")
    if default is not None:
        meta.append(f"default={default}")
    if plain:
        suffix = f" ({', '.join(meta)})" if meta else ""
        return f"    {name}{suffix}"
    else:
        suffix = f" [dim]({', '.join(meta)})[/dim]" if meta else ""
        return f"  [bold bright_cyan]{name}[/bold bright_cyan]{suffix}"
                    

def render_help_plain() -> str:
    reg = load_registry()
    cmds: dict = reg.get("commands", {})

    lines: list[str] = []
    lines.append("Slash Commands")
    lines.append("=" * 14)
    lines.append("")
    lines.append("Usage")
    lines.append("  /help")
    lines.append("  /<command> [options]")
    lines.append("")

    for name in sorted(cmds.keys()):
        meta = cmds[name] or {}
        summary = meta.get("summary", "")
        lines.append(f"/{name}")
        if summary:
            lines.append(f"  {summary}")

        opts = meta.get("options", []) or []
        if opts:
            lines.append("  Options:")
            for o in opts:
                lines.append(_fmt_option_plain(o, True))
        else:
            lines.append("  Options: (none)")

        ex = meta.get("examples", []) or []
        if ex:
            lines.append("  Examples:")
            for e in ex[:3]:
                lines.append(f"    {e}")

        lines.append("")

    lines.append("Notes")
    lines.append("  - /commands only run inside git repos that contain utils/slash/shim.py")
    lines.append("  - SLASH_HOME points to the canonical slash pack location")
    lines.append("")
    return "\\n".join(lines)

def print_help() -> None:
    reg = load_registry()
    cmds: dict = reg.get("commands", {})

    try:
        from rich.console import Console
        from rich.table import Table
        from rich.panel import Panel

        # force_terminal helps when Rich can't detect terminal capability
        console = Console(force_terminal=True)
        console.print(f"\n\n{"=" * 33} Help Docs {"=" * 33}")

        table = Table(title="Slash Commands")
        table.add_column("Command", style="bold bright_cyan", no_wrap=True)
        table.add_column("Summary", style="white")
		
        for name in sorted(cmds.keys()):
            meta = cmds[name] or {}
            table.add_row(f"/{name}", meta.get("summary", ""))

        console.print(table)

        # Usage Example
        lines = []
        lines.append("Examples")
        lines.append("  /help")
        lines.append("  /<command> [options]")
        console.print(Panel.fit("\n".join(lines), title=f"[bold]/Usage[/bold]", border_style="dim"))
        
        console.print(f"\n\n{"=" * 33} Options {"=" * 33}")

        for name in sorted(cmds.keys()):
            meta = cmds[name] or {}
            opts = meta.get("options", []) or []
            ex = meta.get("examples", []) or []

            lines = []
            lines.append(meta.get("summary"))
            lines.append("")
            if opts:
                lines.append("[bold]Options[/bold]")
                for o in opts:
                    lines.append(_fmt_option_plain(o, False))
            else:
                lines.append("[bold]Options[/bold]\\n  [dim](none)[/dim]")

            if ex:
                lines.append("")
                lines.append("[bold]Examples[/bold]")
                for e in ex[:3]:
                    lines.append(f"  [dim]{e}[/dim]")

            console.print(Panel.fit("\n".join(lines), title=f"[bold]/{name}[/bold]", border_style="dim"))

        console.print("")
        console.print("[dim]NOTES:[/dim]")
        console.print("[dim]* /commands only run inside git repos that contain utils/slash/shim.py[/dim]")
        console.print("[dim]* SLASH_HOME points to the canonical slash pack location[/dim]")

    except Exception:
        print(render_help_plain())
'@

# merge_branches.py (with dry-run + plan)
Write-File (Join-Path $CommandsDir "merge_branches.py") @'
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from ..common import run_ok, require_clean_worktree, venv_python

@dataclass(frozen=True)
class Opts:
    remote: str
    main: str
    branches: tuple[str, ...]
    push_first: bool
    run_tests: bool
    dry_run: bool = False

def run(repo_root: Path, opts: Opts) -> None:
    require_clean_worktree(repo_root)

    plan: list[list[str]] = []
    plan += [["git", "fetch", opts.remote]]
    plan += [["git", "checkout", opts.main]]
    plan += [["git", "pull", opts.remote, opts.main]]

    if opts.push_first:
        for br in opts.branches:
            plan += [["git", "push", "-u", opts.remote, br]]

    for br in opts.branches:
        plan += [["git", "merge", "--no-ff", br]]

        if opts.run_tests:
            py = venv_python(repo_root)
            if py:
                plan += [[str(py), "-m", "pytest"]]
            else:
                plan += [["python", "-m", "pytest"]]

        plan += [["git", "push", opts.remote, opts.main]]

    if opts.dry_run:
        print("DRY RUN — would execute:")
        for c in plan:
            print("  " + " ".join(c))
        return

    for c in plan:
        run_ok(c, cwd=repo_root)
'@

# new_slash_shim.py (--repo support + shim uses -m slash_runtime)
Write-File (Join-Path $CommandsDir "new_slash_shim.py") @'
from __future__ import annotations

from pathlib import Path
from typing import Optional

from ..common import SlashError, git_root

SHIM_CONTENT = '''
# utils/slash/shim.py
# Repo-local shim that dispatches to the canonical slash pack at SLASH_HOME.

import os
import sys
import subprocess

def main(argv: list[str]) -> int:
    home = os.environ.get("SLASH_HOME", "").strip()
    if not home:
        print("ERROR: SLASH_HOME is not set.")
        return 1

    # Run as module from SLASH_HOME so package imports work
    return subprocess.call(
        [sys.executable, "-m", "slash_runtime", *argv],
        cwd=home,
    )

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
'''

def run(start: Path, *, force: bool, repo: Optional[Path]) -> None:
    target = repo if repo is not None else start
    repo_root = git_root(target)

    out = repo_root / "utils" / "slash" / "shim.py"
    out.parent.mkdir(parents=True, exist_ok=True)

    if out.exists() and not force:
        raise SlashError(f"shim already exists: {out} (use --force to overwrite)")

    out.write_text(SHIM_CONTENT, encoding="utf-8", newline="\\n")
    print(f"Created: {out}")
'@

# __main__.py (runner)
Write-File (Join-Path $PkgRoot "__main__.py") @'
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .common import SlashError, git_root, load_registry, run_ok
from .commands.help_cmd import print_help
from .commands.merge_branches import Opts as MergeOpts, run as run_merge
from .commands.new_slash_shim import run as run_new_shim

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="slash", add_help=False)
    sub = p.add_subparsers(dest="cmd")

    sub.add_parser("help")

    m = sub.add_parser("merge-branches")
    m.add_argument("--remote", default="origin")
    m.add_argument("--main", default="main")
    m.add_argument("--branches", nargs="*", default=None)
    m.add_argument("--push-first", action="store_true", default=False)
    m.add_argument("--no-tests", action="store_true", default=False)
    m.add_argument("--dry-run", action="store_true", default=False)

    n = sub.add_parser("new-slash-shim")
    n.add_argument("--force", action="store_true", default=False)
    n.add_argument("--repo", default=None)

    return p

def normalize(argv: list[str]) -> list[str]:
    if not argv:
        return ["help"]
    if argv[0].startswith("/"):
        argv[0] = argv[0][1:]
    return argv

def main(argv: list[str]) -> int:
    _ = load_registry()  # validates registry exists + JSON parses
    parser = build_parser()

    argv = normalize(argv)
    args = parser.parse_args(argv)

    if args.cmd in (None, "help"):
        print_help()
        return 0

    if args.cmd == "merge-branches":
        repo = git_root(Path("."))

        branches = args.branches
        if branches is None or len(branches) == 0:
            r = run_ok(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo)
            current = r.stdout.strip()
            if current in (args.main, "master"):
                raise SlashError("You are on main/master. Pass --branches <name> explicitly.")
            branches = [current]

        opts = MergeOpts(
            remote=args.remote,
            main=args.main,
            branches=tuple(branches),
            push_first=bool(args.push_first),
            run_tests=not bool(args.no_tests),
            dry_run=bool(args.dry_run),
        )
        run_merge(repo, opts)
        print("Done.")
        return 0

    if args.cmd == "new-slash-shim":
        repo_path = Path(args.repo).resolve() if args.repo else None
        run_new_shim(Path("."), force=bool(args.force), repo=repo_path)
        return 0

    print_help()
    return 2

if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except SlashError as e:
        print(f"ERROR: {e}")
        raise SystemExit(1)
'@

# 3) Update PowerShell profile block (safe append)
$MarkerStart = "# >>> SLASH_PACK >>>"
$MarkerEnd   = "# <<< SLASH_PACK <<<"

$ProfileDir = Split-Path -Parent $PROFILE
New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }

$Block = @'
$MarkerStart
Import-Module PSReadLine -ErrorAction SilentlyContinue
Import-Module PSFzf -ErrorAction SilentlyContinue

try { Set-PSReadLineOption -PredictionSource HistoryAndPlugin } catch { }
try { Set-PSReadLineOption -PredictionViewStyle ListView } catch { }
try { Set-PsFzfOption -PSReadlineChordReverseHistory 'Ctrl+r' } catch { }

function Get-SlashGitRoot {
  try { return (git rev-parse --show-toplevel).Trim() } catch { return $null }
}

function Get-SlashShimPath {
  $root = Get-SlashGitRoot
  if (-not $root) { return $null }
  $shim = Join-Path $root "utils\slash\shim.py"
  if (Test-Path $shim) { return $shim }
  return $null
}

function Invoke-SlashLine {
  param([string]$Line)

  $t = $Line.Trim()
  if (-not $t.StartsWith('/')) { return $false }

  $shim = Get-SlashShimPath
  if (-not $shim) { return $false }

  $args = $t.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)

  # Force output to show even under PSReadLine
  & py.exe $shim @args 2>&1 | Out-Host
  return $true
}

Set-PSReadLineKeyHandler -Key Enter -ScriptBlock {
  $line = $null
  $cursor = $null
  [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

  if ($line -and (Invoke-SlashLine $line)) {
    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, "")
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    return
  }

  [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

function Get-SlashRegistry {
  $home = $env:SLASH_HOME
  if (-not $home) { return $null }
  $reg = Join-Path $home "slash_runtime\registry.json"
  if (-not (Test-Path $reg)) { return $null }
  try { Get-Content -Raw $reg | ConvertFrom-Json } catch { return $null }
}

function Complete-SlashLine {
  param([string]$WordToComplete, [string]$FullLine)

  if (-not $FullLine.StartsWith('/')) { return @() }
  if (-not (Get-SlashShimPath)) { return @() }

  $reg = Get-SlashRegistry
  if (-not $reg) { return @() }

  $parts = $FullLine.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)

  if ($parts.Count -le 1) {
    $names = $reg.commands.PSObject.Properties.Name
    return $names | ForEach-Object {
      $cand = "/" + $_
      if ($cand -like "$WordToComplete*") {
        [System.Management.Automation.CompletionResult]::new($cand, $_, 'ParameterValue', $_)
      }
    }
  }

  $cmd = $parts[0].TrimStart('/')
  $cur = $WordToComplete
  $results = @()

  try {
    $opts = $reg.commands.$cmd.options
    if ($opts) {
      foreach ($o in $opts) {
        $name = [string]$o.name
        if ($name -and $name -like "$cur*") {
          $results += [System.Management.Automation.CompletionResult]::new($name, $name, 'ParameterValue', $name)
        }
      }
    }
  } catch { }

  if ($parts -contains "--branches") {
    try {
      $branches = git branch --format="%(refname:short)"
      foreach ($b in $branches) {
        if ($b -like "$cur*") {
          $results += [System.Management.Automation.CompletionResult]::new($b, $b, 'ParameterValue', $b)
        }
      }
    } catch { }
  }

  return $results
}

if (-not $script:SlashPack_OriginalTabExpansion2) {
  $script:SlashPack_OriginalTabExpansion2 = (Get-Command TabExpansion2 -ErrorAction SilentlyContinue).ScriptBlock
}

function TabExpansion2 {
  param($inputScript, $cursorColumn)

  $line = [string]$inputScript
  $prefix = $line.Substring(0, [Math]::Min($cursorColumn, $line.Length))

  if ($prefix.TrimStart().StartsWith('/')) {
    $tokens = $prefix.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    $word = if ($tokens.Count -gt 0) { $tokens[-1] } else { "" }
    $comps = Complete-SlashLine -WordToComplete $word -FullLine $prefix.Trim()
    if ($comps.Count -gt 0) {
      return [System.Management.Automation.CommandCompletion]::CompleteInput($inputScript, $cursorColumn, $null, $comps)
    }
  }

  & $script:SlashPack_OriginalTabExpansion2 $inputScript $cursorColumn
}
$MarkerEnd
'@

$Existing = Get-Content -Raw $PROFILE
if ($Existing -match [regex]::Escape($MarkerStart) -and $Existing -match [regex]::Escape($MarkerEnd)) {
    # Replace existing block
    $startEsc = [regex]::Escape($MarkerStart)
    $endEsc   = [regex]::Escape($MarkerEnd)
    $pattern  = "(?s)$startEsc.*?$endEsc"   # (?s) = singleline, dot matches newline

    if ($Existing -match $startEsc -and $Existing -match $endEsc) {
        $updated = [regex]::Replace($Existing, $pattern, $Block)
        Set-Content -Path $PROFILE -Value $updated -Encoding utf8
        Write-Host "Replaced existing SLASH_PACK profile block."
    } else {
        Add-Content -Path $PROFILE -Value "`r`n$Block`r`n"
        Write-Host "Added SLASH_PACK profile block."
    }
}

Write-Host ""
Write-Host "INSTALL COMPLETE."
Write-Host "Next:"
Write-Host "  1) Restart PowerShell OR run: . `$PROFILE"
Write-Host "  2) Enable a repo:"
Write-Host "       cd `$env:SLASH_HOME"
Write-Host "       python -m slash_runtime new-slash-shim --repo <repo-path>"
Write-Host "  3) cd back to that repo, type:"
Write-Host "       /help"
Write-Host "       /merge-branches --dry-run"

