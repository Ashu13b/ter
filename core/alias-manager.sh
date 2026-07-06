#!/bin/bash
# 🛠️ TER: Alias Manager
# Part of TER Core - Manages ~/.shell.d/user/aliases.sh

alias_manager_help() {
    echo -e "\e[34m╔════════════════════════════════════════════╗\e[0m"
    echo -e "\e[34m║\e[0m \e[32mTER ALIAS MANAGER (alm)\e[0m              \e[34m║\e[0m"
    echo -e "\e[34m╠════════════════════════════════════════════╣\e[0m"
    echo -e "\e[34m║\e[0m \e[33malm list\e[0m   - Show all custom aliases       \e[34m║\e[0m"
    echo -e "\e[34m║\e[0m \e[33malm add\e[0m    - Interactively add a new alias \e[34m║\e[0m"
    echo -e "\e[34m║\e[0m \e[33malm edit\e[0m   - Open alias file in editor     \e[34m║\e[0m"
    echo -e "\e[34m║\e[0m \e[33malm reload\e[0m - Refresh shell aliases         \e[34m║\e[0m"
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
        echo -e "\e[33m⚠ Note: This alias is saved to the deployed copy. To persist across reinstalls, also add it to ~/ter/user/aliases.sh\e[0m"
    else
        echo -e "\e[31m✘ Error: Name and command cannot be empty.\e[0m"
    fi
}

alm() {
    if [[ -z "$1" ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "help" ]]; then
        alias_manager_help
        return 0
    fi

    case "$1" in
        list)   alias_manager_list ;;
        add)    alias_manager_add ;;
        edit)   ${EDITOR:-nano} ~/.shell.d/user/aliases.sh && source ~/.shell.d/user/aliases.sh ;;
        reload) source ~/.shell.d/user/aliases.sh && echo -e "\e[32m✔ Aliases reloaded.\e[0m" ;;
        *)
            echo -e "\e[31m❌ Unknown option: $1\e[0m"
            alias_manager_help
            return 1
            ;;
    esac
}
