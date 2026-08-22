import json
import os
import re
import shutil

_ANSI = re.compile(r"\x1b\[[0-9;]*m")
INNER_W = 65  # visible characters between the box borders


def vis_len(s):
    return len(_ANSI.sub("", s))


def main():
    GRAY = "\x1b[38;5;239m"
    RESET = "\x1b[0m"
    CYAN = "\x1b[38;5;51m"
    YELLOW = "\x1b[38;5;226m"
    DIM = "\x1b[3;38;5;245m"
    PINK = "\x1b[1;38;5;205m"
    GREEN = "\x1b[38;5;118m"
    WHITE = "\x1b[38;5;253m"
    ORANGE = "\x1b[38;5;214m"

    repo_dir = os.path.dirname(os.path.abspath(__file__))

    # Version from manifest.json — single source of truth.
    try:
        with open(os.path.join(repo_dir, "manifest.json")) as f:
            version = json.load(f).get("version", "?")
    except (OSError, ValueError):
        version = "?"

    def edge(l, m, r):
        return f"{GRAY}{l}{m}{r}{RESET}"

    def row(content):
        """Content line, padded to INNER_W visible columns."""
        pad = INNER_W - vis_len(content)
        return f"{GRAY}│{RESET}{content}{' ' * max(pad, 0)}{GRAY}│{RESET}"

    out = []

    # Title
    out.append(edge("╭", "─" * INNER_W, "╮"))
    out.append(row(f"  {CYAN}▀█▀ █▀▀ █▀█   █▀█ █▀{RESET}  {YELLOW}v{version}{RESET}"))
    out.append(row(f" {CYAN} █  ██  █▀▄   █▄█ ▄█{RESET}  {DIM}ter = controller · welcome = dashboard{RESET}"))
    out.append(edge("├", "─" * INNER_W, "┤"))

    # Third column depends on what is actually installed: NEXUS commands only
    # exist when the NEXUS app is registered under ~/.shell.d/apps/.
    if os.path.isdir(os.path.expanduser("~/.shell.d/apps/nexus")):
        h3 = "[ NEXUS ]"
        col3 = [
            ("watch", "Monitor"),
            ("portal", "Web GUI"),
            ("cld2net", "Cloud Tnl"),
            ("lcl2net", "Local Tnl"),
        ]
    else:
        h3 = "[ MORE TOOLS ]"
        col3 = [
            ("ter", "Control"),
            ("alm", "Alias Mgr"),
            ("dvop", "Dev Opts"),
            ("tabname", "Rename"),
        ]

    headers = f"  {PINK}[ SYSTEM ]{RESET}      {PINK}[ NETWORK & TOOLS ]{RESET}   {PINK}{h3}{RESET}"
    out.append(row(headers))

    def make_row(c1, c2, c3):
        col1 = f"› {GREEN}{c1[0]:<4}{RESET} {WHITE}{c1[1]:<9}{RESET}"
        col2 = f"› {GREEN}{c2[0]:<6}{RESET} {WHITE}{c2[1]:<10}{RESET}"
        col3s = f"› {GREEN}{c3[0]:<7}{RESET} {WHITE}{c3[1]:<9}{RESET}"
        return row(f" {col1}   {col2}   {col3s} ")

    col1_rows = [("re", "Reload"), ("up", "Update"), ("cls", "Clear"), ("cd", "Back")]
    col2_rows = [
        ("scan", "Find IPs"),
        ("apps", "Modules"),
        ("theme", "Themes"),  # was dead 'ts'
        ("adbcon", "Wizard"),
    ]
    for i in range(4):
        out.append(make_row(col1_rows[i], col2_rows[i], col3[i]))

    out.append(edge("├", "─" * INNER_W, "┤"))

    # Explainers
    out.append(row(f"  {ORANGE}[ optimize ]{RESET} {WHITE}Fix BG limits & disable battery restrictions{RESET}"))
    out.append(row(f"  {ORANGE}[ adbcon ]{RESET}   {WHITE}Smart Wizard for Wireless ADB & Pairing{RESET}"))

    out.append(edge("╰", "─" * INNER_W, "╯"))

    motd_path = os.path.join(repo_dir, "motd")
    with open(motd_path, "w") as f:
        f.write("\n".join(out) + "\n")

    sys_motd = "/data/data/com.termux/files/usr/etc/motd"
    try:
        shutil.copy(motd_path, sys_motd)
    except OSError:
        pass  # not writable (or not on Termux) — repo copy is still updated
    print("MOTD generated successfully.")

if __name__ == "__main__":
    main()
