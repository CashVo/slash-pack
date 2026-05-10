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