import os

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

    out = []
    
    # Title
    out.append(f"{GRAY}╭─────────────────────────────────────────────────────────────────╮{RESET}")
    out.append(f"{GRAY}│{RESET}  {CYAN}▀█▀ █▀▀ █▀█   █▀█ █▀{RESET}  {YELLOW}v1.2{RESET}                                  {GRAY}│{RESET}")
    out.append(f"{GRAY}│{RESET}  {CYAN} █  ██  █▀▄   █▄█ ▄█{RESET}  {DIM}Type 'welcome' for dashboard{RESET}            {GRAY}│{RESET}")
    out.append(f"{GRAY}├─────────────────────────────────────────────────────────────────┤{RESET}")
    
    # Headers
    h1 = f"{PINK}[ SYSTEM ]{RESET}"
    h2 = f"{PINK}[ NETWORK & TOOLS ]{RESET}"
    h3 = f"{PINK}[ NEXUS ]{RESET}"
    out.append(f"{GRAY}│{RESET}  {h1:<21} {h2:<30} {h3:<20} {GRAY}│{RESET}")
    
    def make_row(c1, c2, c3):
        # Column 1: 2 + 4 + 1 + 9 = 16
        col1 = f"› {GREEN}{c1[0]:<4}{RESET} {WHITE}{c1[1]:<9}{RESET}"
        # Column 2: 2 + 6 + 1 + 10 = 19
        col2 = f"› {GREEN}{c2[0]:<6}{RESET} {WHITE}{c2[1]:<10}{RESET}"
        # Column 3: 2 + 7 + 1 + 9 = 19
        col3 = f"› {GREEN}{c3[0]:<7}{RESET} {WHITE}{c3[1]:<9}{RESET}"
        # 16 + 19 + 19 = 54 + padding = 65
        return f"{GRAY}│{RESET} {col1}   {col2}   {col3}   {GRAY}│{RESET}"

    out.append(make_row(("re", "Reload"), ("scan", "Find IPs"), ("watch", "Monitor")))
    out.append(make_row(("up", "Update"), ("apps", "Modules"), ("portal", "Web GUI")))
    out.append(make_row(("cls", "Clear"), ("ts", "Themes"), ("cld2net", "Cloud Tnl")))
    out.append(make_row(("cd", "Back"), ("adbcon", "Wizard"), ("lcl2net", "Local Tnl")))

    out.append(f"{GRAY}├─────────────────────────────────────────────────────────────────┤{RESET}")
    
    # Explainers
    out.append(f"{GRAY}│{RESET}  {ORANGE}[ optimize ]{RESET} {WHITE}Fix BG limits & disable battery restrictions{RESET}     {GRAY}│{RESET}")
    out.append(f"{GRAY}│{RESET}  {ORANGE}[ adbcon ]{RESET}   {WHITE}Smart Wizard for Wireless ADB & Pairing{RESET}          {GRAY}│{RESET}")
    
    out.append(f"{GRAY}╰─────────────────────────────────────────────────────────────────╯{RESET}")
    
    motd_path = "/data/data/com.termux/files/home/ter/motd"
    with open(motd_path, "w") as f:
        f.write("\n".join(out) + "\n")
    
    sys_motd = "/data/data/com.termux/files/usr/etc/motd"
    os.system(f"cp {motd_path} {sys_motd}")
    print("MOTD generated successfully.")

if __name__ == "__main__":
    main()
