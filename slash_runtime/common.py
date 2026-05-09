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