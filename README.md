# slash-pack

A project-agnostic â€œslash commandâ€ toolkit for running common developer workflows from your terminal using commands like:

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
- Dispatch to your moduleâ€™s `run(...)`

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