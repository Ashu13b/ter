export C_RESET='\e[0m'; export C_BOLD='\e[1m'; export C_DIM='\e[2m'
export C_BLUE='\e[34m'; export C_CYAN='\e[36m'; export C_GREEN='\e[32m'
export C_YELLOW='\e[33m'; export C_RED='\e[31m'; export C_MAGENTA='\e[35m'
export B_BLUE='\e[1;34m'; export B_GREEN='\e[1;32m'; export B_MAGENTA='\e[1;35m'

style_header() {
    local label="══ $1 ══"
    local w=${COLUMNS:-$(tput cols 2>/dev/null || echo 40)}
    local pad=$(( (w - ${#label}) / 2 ))
    [ $pad -lt 0 ] && pad=0
    printf "\n%${pad}s${B_MAGENTA}%s${C_RESET}\n" "" "$label"
}
