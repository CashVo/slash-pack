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