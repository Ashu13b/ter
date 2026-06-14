#!/bin/bash
# 🛠️ NEXUS OS: Alias Manager
# Part of NEXUS OS Core - Manages ~/.shell.d/user/aliases.sh

alias_manager_help() {
    echo -e "\e[34m╔════════════════════════════════════════════╗\e[0m"
    echo -e "\e[34m║\e[0m \e[32mNEXUS OS ALIAS MANAGER (am)\e[0m               \e[34m║\e[0m"
    echo -e "\e[34m╠════════════════════════════════════════════╣\e[0m"
    echo -e "\e[34m║\e[0m \e[33mam list\e[0m   - Show all custom aliases        \e[34m║\e[0m"
    echo -e "\e[34m║\e[0m \e[33mam add\e[0m    - Interactively add a new alias  \e[34m║\e[0m"
    echo -e "\e[34m║\e[0m \e[33mam edit\e[0m   - Open alias file in editor      \e[34m║\e[0m"
    echo -e "\e[34m║\e[0m \e[33mam reload\e[0m - Refresh shell aliases          \e[34m║\e[0m"
    echo -e "\e[34m╚════════════════════════════════════════════╝\e[0m"
}

alias_manager_list() {
    echo -e "\e[32mCurrent Custom Aliases:\e[0m"
    grep "^alias " ~/.shell.d/user/aliases.sh | sed 's/alias //g' | column -t -s '='
}

alias_manager_add() {
    echo -n "Enter alias name (e.g., gs): "
    read name
    echo -n "Enter command (e.g., git status): "
    read cmd
    if [ -n "$name" ] && [ -n "$cmd" ]; then
        echo "alias $name='$cmd'" >> ~/.shell.d/user/aliases.sh
        echo -e "\e[32m✔ Added alias $name for '$cmd'\e[0m"
        source ~/.shell.d/user/aliases.sh
    else
        echo -e "\e[31m✘ Error: Name and command cannot be empty.\e[0m"
    fi
}

am() {
    case "$1" in
        list)   alias_manager_list ;;
        add)    alias_manager_add ;;
        edit)   ${EDITOR:-nano} ~/.shell.d/user/aliases.sh && source ~/.shell.d/user/aliases.sh ;;
        reload) source ~/.shell.d/user/aliases.sh && echo -e "\e[32m✔ Aliases reloaded.\e[0m" ;;
        *)      alias_manager_help ;;
    esac
}
