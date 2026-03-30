# .bashrc

export PATH=$HOME/.TinyTeX/bin/x86_64-linux:$PATH

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Farben für Prompt (escaped für PS1)
if [ -t 1 ]; then
    export GREEN="\[\033[0;32m\]"
    export MAGENTA="\[\033[0;35m\]"
    export CYAN="\[\033[0;36m\]"
    export YELLOW="\[\033[0;33m\]"
    export BLUE="\[\033[0;34m\]"
    export WHITE="\[\033[1;37m\]"
    export RESET="\[\033[0m\]"
fi

# Module für miluphpc (Stand Jan 2025)
module purge
module load devel/cuda/11.8                         #1) devel/cuda/11.8
module load compiler/gnu/11.4                       #2) compiler/gnu/11.4
module load mpi/openmpi/4.1-gnu-11.4                #3) mpi/openmpi/4.1-gnu-11.4
module load lib/boost/1.78-openmpi-4.1-gnu-11.4     #4) lib/boost/1.78-openmpi-4.1-gnu-11.4
module load lib/hdf5/1.12-gnu-11.4-openmpi-4.1      #5) lib/hdf5/1.12-gnu-11.4-openmpi-4.1
module load vis/ffmpeg/ffmpeg-5.1                   #6) vis/ffmpeg/ffmpeg-5.1

# Farb-Prompt erzwingen (optional)
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        color_prompt=yes
    else
        color_prompt=
    fi
fi

# Virtuelle Python-Umgebung im Prompt anzeigen
function venv_prompt {
    local venv=""
    if [ -n "$CONDA_DEFAULT_ENV" ]; then
        venv+="(${CONDA_DEFAULT_ENV}) "
    fi
    if [ -n "$VIRTUAL_ENV" ]; then
        venv+="($(basename "$VIRTUAL_ENV")) "
    fi
    echo -n -e "${WHITE}${venv}${RESET}"
}

function git_branch_prompt {
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
        [[ -n $branch ]] && echo -n " ${YELLOW}(${branch})${RESET}"
    fi
}

function set_bash_prompt {
    local shell_tag="[${MAGENTA}bash${RESET}]"
    local user_host="${GREEN}\u${RESET}@${GREEN}\h${RESET}"
    local dir="${BLUE}\w${RESET}"
    local git_branch="$(git_branch_prompt)"
    local venv_env="$(venv_prompt)"

    local titlebar="\[\e]0;\u@\h: \w\a\]"

    PS1="${titlebar}${venv_env}${shell_tag} ${user_host}: ${dir}${git_branch} > "
}

export PROMPT_COMMAND=set_bash_prompt

# Kein automatisches (venv) im Prompt (weil wir es selbst steuern)
export VIRTUAL_ENV_DISABLE_PROMPT=1

unset color_prompt force_color_prompt

# Terminal Titel setzen für xterm und rxvt
case "$TERM" in
    xterm*|rxvt*)
        TITLEBAR="\[\e]0;\u@\h: \w\a\]"
        PS1="${TITLEBAR}${PS1}"
        ;;
    *)
        ;;
esac

# Farbunterstützung für ls und nützliche Aliase
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Weitere nützliche Aliase
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias clc='clear'



# User specific aliases and functions aus ~/.bashrc.d laden
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi

unset rc
