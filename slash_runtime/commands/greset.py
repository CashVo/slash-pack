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