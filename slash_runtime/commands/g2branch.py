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