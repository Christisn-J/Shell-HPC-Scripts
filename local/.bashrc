# Farben aktivieren
if [ -t 1 ]; then
    export GREEN="\033[0;32m"
    export MAGENTA="\033[0;35m"
    export CYAN="\033[0;36m"
    export YELLOW="\033[0;33m"
    export BLUE="\033[0;34m"
    export RESET="\033[0m"
fi

# Funktion zum Anzeigen des aktuellen Git-Branches
function git_branch_prompt {
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    [[ -n $branch ]] && echo -e " ${RESET}(${branch})${RESET}"
  fi
}

# PS1 (Prompt) mit Farben und Git-Branch
PS1="[${MAGENTA}\$(basename $0)${RESET}] ${GREEN}\u${RESET}@${GREEN}\h${RESET}: ${BLUE}\w\$(git_branch_prompt) ${RESET}> "

# Color für ls (macOS)
alias ls='ls -G'  # macOS
alias ll='ls -laG'

# Alias: 'clc' für 'clear'
alias clc='clear'

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Applications/anaconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Applications/anaconda3/etc/profile.d/conda.sh" ]; then
        . "/Applications/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Applications/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# Automatisch conda base aktivieren
conda activate base
