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