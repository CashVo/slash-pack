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
        print("DRY RUN â€” would execute:")
        for c in plan:
            print("  " + " ".join(c))
        return

    for c in plan:
        run_ok(c, cwd=repo_root)