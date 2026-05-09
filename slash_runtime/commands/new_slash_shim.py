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