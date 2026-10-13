# ── TER OS: Unified App Manager & Sideloading Utility ──
# Provides intuitive 'app' frontend for installing APKs, freezing bloat, and listing packages.

app() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "help" ]]; then
        echo -e "\033[1;36mTER OS: UNIFIED APP MANAGER & SIDELOADER\033[0m"
        echo ""
        echo "Usage: app <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  app install [file.apk|search]  Smart APK installer (browse, fuzzy pick, batch)"
        echo "  app audit [file.apk|pkg]       Deep security, cert & privacy audit of an APK"
        echo "  app freeze <pkg>               Disable/freeze an app completely (0 RAM/CPU)"
        echo "  app unfreeze <pkg>             Re-enable/unfreeze a frozen app"
        echo "  app list [-a|-d]               List installed apps (-a all, -d disabled/frozen)"
        echo "  app export <pkg>               Extract & pull base APK to current directory"
        echo "  app open <pkg>                 Launch app on device screen"
        echo ""
        echo "Examples:"
        echo "  app audit netmirror             Audit NetMirror security & permissions"
        echo "  app audit app.apk               Audit APK file before installing"
        echo "  app install                     Interactive APK file browser from ~/Download"
        echo "  app install myapp.apk           Install specific APK"
        echo "  app freeze com.bloat.app        Disable bloatware"
        echo "  app unfreeze com.bloat.app      Re-enable bloatware"
        echo "  app list -d                     Show all frozen apps"
        return 0
    fi

    local sub="$1"
    shift 2>/dev/null || true

    case "$sub" in
        audit|analyze|scan)
            local script="$HOME/.shell.d/user/apk-audit.py"
            [ -f "$script" ] || script="${TER_REPO:-$HOME/ter}/user/apk-audit.py"
            python3 "$script" "$@"
            ;;
        install|in|i)
            adb-apk "$@"
            ;;
        freeze|fz|disable)
            if [ -z "$1" ]; then
                echo -e "\033[1;31m❌ Error: Missing package name or search term.\033[0m"
                echo "Usage: app freeze <package_name>"
                return 1
            fi
            python3 "$HOME/.shell.d/user/adb-manage.py" -f "$@"
            ;;
        unfreeze|ufz|enable)
            if [ -z "$1" ]; then
                echo -e "\033[1;31m❌ Error: Missing package name or search term.\033[0m"
                echo "Usage: app unfreeze <package_name>"
                return 1
            fi
            python3 "$HOME/.shell.d/user/adb-manage.py" -u "$@"
            ;;
        list|ls)
            local dev; dev=$(_get_adb_device 2>/dev/null)
            if [ -z "$dev" ]; then
                echo -e "\033[1;31m❌ No active ADB device found. Run adbcon first.\033[0m"
                return 1
            fi
            local flag="-3"
            if [ "$1" = "-a" ] || [ "$1" = "--all" ]; then
                flag=""
            elif [ "$1" = "-d" ] || [ "$1" = "--disabled" ] || [ "$1" = "--frozen" ]; then
                flag="-d"
            fi
            echo -e "\n\033[1;35m📦 Installed Packages:\033[0m"
            adb -s "$dev" shell pm list packages $flag 2>/dev/null | sed 's/^package:/  • /' | sort
            echo ""
            ;;
        export|extract)
            if [ -z "$1" ]; then
                echo -e "\033[1;31m❌ Error: Missing package name.\033[0m"
                echo "Usage: app export <package_name>"
                return 1
            fi
            python3 "$HOME/.shell.d/user/adb-manage.py" -e "$@"
            ;;
        open|launch|start)
            if [ -z "$1" ]; then
                echo -e "\033[1;31m❌ Error: Missing package name.\033[0m"
                echo "Usage: app open <package_name>"
                return 1
            fi
            local dev; dev=$(_get_adb_device 2>/dev/null)
            if [ -z "$dev" ]; then
                echo -e "\033[1;31m❌ No active ADB device found. Run adbcon first.\033[0m"
                return 1
            fi
            echo -e "🚀 Launching \033[1;32m$1\033[0m..."
            adb -s "$dev" shell monkey -p "$1" 1 >/dev/null 2>&1 || adb -s "$dev" shell am start -n "$1" >/dev/null 2>&1
            ;;
        "")
            echo -e "\033[1;36mTER OS App Utility\033[0m (Use 'app -h' for help)"
            echo "Quick actions:"
            echo "  app install           Install APK"
            echo "  app freeze <pkg>      Freeze app"
            echo "  app unfreeze <pkg>    Unfreeze app"
            echo "  app list [-a|-d]      List apps"
            ;;
        *)
            echo -e "\033[1;31m❌ Unknown app command: $sub\033[0m"
            echo "Run 'app -h' to see available subcommands."
            return 1
            ;;
    esac
}
