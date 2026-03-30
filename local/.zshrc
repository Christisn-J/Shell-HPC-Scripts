export PATH="/Library/TeX/texbin:$PATH"
# Farben aktivieren
autoload -U colors && colors
# --- Zsh Completion aktivieren ---
autoload -U compinit
compinit

# Funktion zum Anzeigen des aktuellen Git-Branches
function git_branch_prompt {
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    [[ -n $branch ]] && echo " %{$fg[white]%}(${branch})%{$reset_color%}"
  fi
}

# Prompt Substitution aktivieren
setopt PROMPT_SUBST

# Farbiger Prompt mit Git-Branch
PROMPT='[%{$fg[magenta]%}$ZSH_NAME%{$reset_color%}] %{$fg[green]%}%n%{$reset_color%}@%{$fg[green]%}%m%{$reset_color%}: %{$fg[cyan]%}%~ $(git_branch_prompt) %{$reset_color%}> '

# Enable color for ls command
alias ls='ls -G'  # -G is for enabling color (on macOS)
alias ll='ls -laG'  # This will make 'll' use colored long listing format

# Alias: 'clc' für 'clear'
alias clc='clear'

# --- login Funktion ---
function login() {
  if [ $# -eq 0 ]; then
    echo "[ERROR]: no argument specified!"
    echo "Usage: login <host> [args]"
    return 1
  fi

  /Users/jetter/Uni/milupHPC/login.zsh "$@"
}

# --- Tab-Completion für 'login' (liest Hosts aus ~/.ssh/config) ---
_login_completions() {
  # Alle Hostnamen aus SSH config einlesen
  local -a hosts
  hosts=($(awk '/^Host / && !/\*/ {for (i=2; i<=NF; i++) print $i}' ~/.ssh/config 2>/dev/null))

  if (( CURRENT == 2 )); then
    _describe 'SSH hosts' hosts
  else
    _files  # danach normale Datei-Vervollständigung
  fi
}

# Diese Completion-Funktion mit 'login' verknüpfen
compdef _login_completions login


function sync() {
  case "$1" in
    push)
      shift
      local to="binac2"

      if [ $# -eq 0 ]; then
        echo "[ERROR]: please specify at least one path to push!"
        echo "Usage: local push <path>"
        return 1
      fi

      /Users/jetter/Uni/milupHPC/sync.zsh push --remote "$to" "$@"
      return 0
      ;;

    pull)
      shift
      local from="binac2"
      local target_path

      if [ $# -eq 0 ]; then
        target_path="output/$(date +%Y%m%d)/"
        echo "[WARN] No path specified — using default target: '$target_path'"
      else
        target_path="$1"
      fi

      /Users/jetter/Uni/milupHPC/sync.zsh pull --remote "$from" "$target_path"
      return 0
      ;;

    *)
      echo "Usage: sync {push|pull} <path>"
      return 1
      ;;
  esac
}

# --- Tab-Completion für 'sync' ---
_sync_completions() {
  local -a subcommands
  local remote="binac2"
  subcommands=('push:Upload to remote "$remote"' 'pull:Download from remote "$remote"')

  # Wenn du gerade "sync" + <Tab> tippst (also erstes Argument fehlt)
  if (( CURRENT == 2 )); then
    _describe 'subcommand' subcommands
  else
    # Danach normale Dateipfade vervollständigen
    _files
  fi
}

# Diese Funktion mit dem Befehl 'sync' verknüpfen
compdef _sync_completions sync

