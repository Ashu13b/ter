# ── TER HUD Prompt (Dynamic Theme S2 Trench) ──

# Load dynamic colors if they exist, fallback to Nord blue (4) and Green (2)
[ -f ~/.shell.d/core/theme_colors.sh ] && source ~/.shell.d/core/theme_colors.sh
L_CLR=${TER_P_LINE:-4}
A_CLR=${TER_P_ACCENT:-2}

_p_git() {
    local branch; branch=$(git branch --show-current 2>/dev/null)
    [ -n "$branch" ] && echo -e " %F{36}◈%f %F{5}$branch%f" || true
}

if [ -n "$ZSH_VERSION" ]; then
    setopt PROMPT_SUBST
    PROMPT='%B%F{$L_CLR}▬▬ %f%F{36}ᴛᴇʀ%f$(_p_git) %F{$L_CLR}▬▬%f %F{6}%~%f
%F{$A_CLR}➤%f%b '
elif [ -n "$BASH_VERSION" ]; then
    _b_git() {
        local b; b=$(git branch --show-current 2>/dev/null)
        [ -n "$b" ] && echo -e " \e[1;36m◈\e[0m \e[1;35m$b\e[0m" || true
    }
    PS1='\n\[\e[1;34m\]▬▬ \[\e[1;36m\]ᴛᴇʀ\[\e[0m\]$(_b_git) \[\e[1;34m\]▬▬ \[\e[0;36m\]\w\[\e[0m\]\n\[\e[1;32m\]➤\[\e[0m\] '
fi

