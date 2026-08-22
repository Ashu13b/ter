# ── TER HUD Prompt (Dynamic Theme S2 Trench) ──

# Load dynamic colors if they exist, fallback to Nord blue (4) and Green (2)
[ -f ~/.shell.d/core/theme_colors.sh ] && source ~/.shell.d/core/theme_colors.sh
# Per-user theme override written by 'ter theme' — survives reinstalls.
[ -f "$HOME/.config/ter/prompt_colors.sh" ] && source "$HOME/.config/ter/prompt_colors.sh"
L_CLR=${TER_P_LINE:-4}
A_CLR=${TER_P_ACCENT:-2}

_p_context() {
    local name=""
    local repo_root; repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$repo_root" ]; then
        name=$(basename "$repo_root")
    else
        name=$(basename "$PWD")
        [ -z "$name" ] || [ "$name" = "/" ] && name="ROOT"
    fi
    echo "$name" | sed 'y/abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ/ᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀsᴛᴜᴠᴡxʏᴢᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀsᴛᴜᴠᴡxʏᴢ/'
}

_p_git() {
    local branch; branch=$(git branch --show-current 2>/dev/null)
    [ -n "$branch" ] && echo -e " %F{36}◈%f %F{5}$branch%f" || true
}

if [ -n "$ZSH_VERSION" ]; then
    setopt PROMPT_SUBST
    PROMPT='%B%F{$L_CLR}▬▬ %f%F{36}$(_p_context)%f$(_p_git) %F{$L_CLR}▬▬%f %F{6}%~%f
%F{$A_CLR}➤%f%b '
elif [ -n "$BASH_VERSION" ]; then
    _b_git() {
        local b; b=$(git branch --show-current 2>/dev/null)
        [ -n "$b" ] && echo -e " \e[1;36m◈\e[0m \e[1;35m$b\e[0m" || true
    }
    # Colors expand at source time so 'ter theme' changes apply on reload.
    PS1="\n\[\e[38;5;${L_CLR}m\]▬▬ \[\e[38;5;36m\]\$(_p_context)\[\e[0m\]\$(_b_git) \[\e[38;5;${L_CLR}m\]▬▬ \[\e[0;36m\]\w\[\e[0m\]\n\[\e[38;5;${A_CLR}m\]➤\[\e[0m\] "
fi

