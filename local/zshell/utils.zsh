setopt NO_NOMATCH

strip_zsh_styles() {
  local line="$1"
  local clean="$line"

  # Entferne alle Stil-Codes (Groß- und Kleinbuchstaben)
  for code in B b f u U k K; do
    clean="${clean//%$code/}"
  done

  # Entferne Farbcodes wie %F{...} und %K{...}
  clean=$(echo "$clean" | sed -E 's/%F\{[^}]+\}//g; s/%K\{[^}]+\}//g')

  print -- "$clean"
}


print_usage_line() {
  if [[ "$flag_color" == true ]]; then
    print -P "$1"
  else
    strip_zsh_styles "$1"
  fi
}


# Haupt-Logfunktion
log() {
  local level="$1"
  local color="$2"
  shift 2

#  local bold=false
#  local no_newline=false
#  # Flags auslesen, beliebig sortiert
#  while [[ "$1" == --* ]]; do
#    case "$1" in
#      --bold)       bold=true ;;
#      --no-newline) no_newline=true ;;
#      *)            break ;;
#    esac
#    shift
#  done

  # Rest ist die Nachricht
  local message="$*"

  # Styles aufbauen
  local style_open=""
  local style_close=""

#  if [[ "$bold" == "true" ]]; then
#    style_open="%B"
#    style_close+="%b"
#  fi

  if [[ -n "$color" && "$flag_color" == "true" ]]; then
    style_open+="${style_open:+}""%F{$color}"
    style_close+="%f"
  fi

  local prefix="${style_open}[$level]${style_close}"

#  if [[ "$no_newline" == "true" ]]; then
#    print -nP "${prefix} ${message}"
#  else
    print -P "${prefix} ${message}"
#  fi
}


# Hilfsfunktionen
info()     { log "INFO"     blue    "$@";}
warn()     { log "WARNING"  yellow  "$@"; }
error()    { log "ERROR"    red     "$@"; exit 1; }
fatal()    { log "FATAL"    red     "$@"; }
success()  { log "SUCCESS"  green   "$@"; }
trace()    { log "TRACE"    white   "$@"; }

debug() {
  local level="$1"
  shift
  if (( flag_verbose >= level )); then
    log "DEBUG" white "$@"
  fi
}

verbose() {
  local level="$1"
  shift
  if (( flag_verbose >= level )); then
    log "EXTRA" grey "$@"
  fi
}

confirm() {
  local prompt="$1"
  local default_answer="${2:-no}"
  local reply

  if [[ "$flag_quiet" == true ]]; then
    if [[ "$default_answer" =~ ^(yes|y)$ ]]; then
      log "CONFIRM" cyan "Auto-confirmed: $prompt (yes)"
      return 0
    else
      log "CONFIRM" cyan "Auto-confirmed: $prompt (no)"
      return 1
    fi
  fi

  while true; do
    local suffix=""
    if [[ "$default_answer" =~ ^(yes|y)$ ]]; then
      suffix="%B%F{white}[Y/n]%f%b"
    else
      suffix="%B%F{white}[y/N]%f%b"
    fi

    # Ausgabe über log() ohne Zeilenumbruch
    log "WAIT" cyan "$prompt $suffix"

    read -r reply
    [[ -z "$reply" ]] && reply="$default_answer"

    case "$reply" in
      y|Y|yes|Yes) return 0 ;;
      n|N|no|No)   return 1 ;;
      *)           log "INPUT" red "Bitte mit 'y' oder 'n' antworten." ;;
    esac
  done
}

execute() {
  local run_cmd=false
  local -a args
  local last_arg="${(@)argv[-1]}"
  local -a all_args=("${(@)argv}")

  if [[ "$last_arg" == "--exe" ]]; then
    args=("${(@)all_args[1,-2]}")
    run_cmd=true
  else
    args=("${(@)all_args}")
  fi

  if (( flag_verbose != 0 )); then
    if $run_cmd; then
      log "EXECUTE" cyan "${args[*]}"
    else
      log "NOT EXECUTE" yellow "${args[*]}"
    fi
  fi

  if $run_cmd; then
    "${args[@]}"
  fi
}

check_skip_phase() {
  local phase_id="$1"
  for p in "${skip_phases[@]}"; do
    if [[ "$p" -eq "$phase_id" ]]; then
      return 0  # skip
    fi
  done
  return 1  # do not skip
}

# --- Helper functions ---
check_arg() {
  local name="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == --* || "$value" == -* ]]; then
    error "Missing or invalid argument for $name"
  fi
}

check_shell_exists() {
  local user=$1
  local host=$2
  local shell=$3
  # Check if shell exists on remote host by ssh'ing and running 'which'
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$user@$host" "which $shell" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    warn "Shell '$shell' does not seem to exist on remote host. Defaulting to user's login shell."
    console=""
  fi
}

check_color_support() {
  if ! [ -t 1 ]; then
    warn "No color support: stdout is not a terminal."
    return 1
  fi
  if [[ "$TERM" == "dumb" ]]; then
    warn "No color support: TERM is set to 'dumb'."
    return 1
  fi
  local colors
  colors=$(tput colors 2>/dev/null || echo 0)
  if [[ "$colors" -lt 8 ]]; then
    warn "No color support: only $colors colors available."
    return 1
  fi
  return 0
}


validate_natural_numbers() {
  local name="$1"
  local value="$2"
  local minRange="$3"
  local maxRange="$4"

  if ! [[ "$value" =~ ^[0-9]+$ ]] || (( $value < $minRange || $value > $maxRange )); then
    error "Invalid $name number: $value. Must be an integer between $minRange and $maxRange"
  fi
}

validate_name() {
  if ! [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Invalid: $1. Allowed characters: letters, digits, underscore, hyphen."
  fi
}

check_hostalias_exists() {
  local config_file="$1"
  local remoteAlias=$2

  if [[ ! -f $config_file ]]; then
    error "Config file '$config_file' not found."
  fi

  if ! grep -qE "^\[${remoteAlias}\]" "$config_file"; then
    error "Host alias '$remoteAlias' not found in $config_file."
  fi
}


load_remoteHost_config() {
  local config_file="$1"
  local remoteAlias="$2"
  local section_found=0
  local current_section=""

  [[ ! -f "$config_file" ]] && error "Host config file not found: $config_file"
  debug 3 "$config_file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%\#*}"           # Kommentare entfernen
    line="$(echo "$line" | xargs)"  # Whitespace trimmen

    [[ -z "$line" ]] && continue

    # Abschnitt erkennen: [section]
    if [[ "$line" == "["*"]" ]]; then
      current_section="${line:1:-1}"
      debug 3 "Found section: [$current_section]"

      if [[ "$current_section" == "$remoteAlias" ]]; then
        section_found=1
        debug 3 "→ Entering section [$current_section]"
      else
        section_found=0
      fi
      continue
    fi

    if (( section_found )); then
      key="${line%%=*}"
      val="${line#*=}"
      key="$(echo "$key" | xargs)"
      val="$(echo "$val" | xargs)"

      case "$key" in
        user) remoteUser="$val" ;;
        host) remoteHost="$val" ;;
        path) remotePath="$val" ;;
        sshOpts)
          val="${val//[\(\)]/}"
          IFS=' ' read -rA sshOptions <<< "$val"
          ;;
      esac
    fi
  done < "$config_file"

  debug 3 "FINAL: user=$remoteUser, host=$remoteHost, path=$remotePath"

  if [[ -z "$remoteUser" || -z "$remoteHost" || -z "$remotePath" ]]; then
    error "Missing values in host config for [$remoteAlias]"
  fi
}

show_sync_target_info() {
  verbose 3 "Using SSH user: $remoteUser"
  verbose 3 "Using SSH host: $remoteHost"
  verbose 3 "Using SSH port: $SSH_PORT"
  verbose 3 "Using SSH path: $remotePath"
}

show_environment_info(){
  verbose 3 "Current shell: $SHELL"
  verbose 3 "Invoked by user: $USER"
  if [[ $flag_verbose -eq 3 ]]; then
    verbose 3 "Effective PATH:"
    echo "$PATH" | tr ':' '\n' | while IFS= read -r line; do
    echo "    $line"
    done
  fi
}

show_connection_info() {
  verbose 3 "User: ${remoteUser:-'(not set)'}"
  verbose 3 "Host: ${remoteHost="":-'(not set)'}"
  verbose 3 "Port: ${port:-'(not set)'}"
  verbose 3 "Path: ${remotePath:-'(home directory)'}"
  verbose 3 "Shell: ${console:-default}"
}

start_timer() {
  gdate +%s.%N
}

end_timer() {
  local start="$1"
  local end=$(gdate +%s.%N)
  echo "scale=6; $end - $start" | bc
}

format_timer() {
  local secs="$1"
  printf '%02d:%02d:%05.2f\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))
}






