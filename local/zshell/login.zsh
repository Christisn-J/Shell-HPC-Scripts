#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${(%):-%N}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/utils.zsh"
check_color_support && flag_color=true

# --- Default Config ---
SSH_PORT=22
CONSOLE="bash"

# --- Usage function ---
usage() {
  print -P "\n%B%F{cyan}Usage:%f%b\n  $0 <hostalias> [--port <port>] [--shell <shell>]\n"
  print "Connect to a remote SSH host using."
  print -P "\n%B%F{cyan}Flags:%f%b"
  print -P "  %B%F{yellow}--port%f%b             Optional: SSH port (default: %B22%b)"
  print -P "  %B%F{yellow}--shell%f%b            Optional: Shell to use on remote host (default: %Bbash%b)"
  print -P "  %F{yellow}-v, --verbose%f      Optional: verbose output (default: off)"
  print -P "  %B%F{yellow}-h, --help%f%b         Display this help message and exit"

  local info_file="$SCRIPT_DIR/remoteHost.info"
  if [[ -f "$info_file" ]]; then
    # Extrahiere alle Aliasnamen ohne Klammern
    local aliases=$(grep -o '\[[^]]\+\]' "$info_file" | tr -d '[]' | xargs)
    print -P "\n%F{cyan}Available Host Aliases:%f $aliases"
  else
    print -P "\n%F{cyan}Available Host Aliases:%f %F{red}(remoteHost.info not found)%f"
  fi

  exit 0
}

# --- Initialize variables ---
hostalias=""
port=$SSH_PORT
console=$CONSOLE
flag_verbose=0
: ${flag_color:=false}

# --- Parse command line arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      shift
      check_arg "--verbose" "$1"
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        flag_verbose="$1"
      else
        error "Invalid value for --verbose: must be a positive integer."
      fi
      shift
      ;;
    --port)
      shift
      check_arg "--port" $1
      validate_natural_numbers "--port" $1 1 65535
      port="$1"
      shift
      ;;
    --shell)
      shift
      check_arg "--shell" $1
      console="$1"
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      error "Unknown option: $1"
      ;;
    *)
      if [[ -z "$hostalias" ]]; then
        validate_name "$1"
        hostalias="$1"
      else
        warn "Unexpected extra argument: $1"
      fi
      shift
      ;;
  esac
done

## --- Setup SSH user and host based on mode ---
remoteUser=""
remoteHost=""
remotePath=""
sshOptions=()
load_remoteHost_config "$SCRIPT_DIR/remoteHost.info" "$hostalias"

# --- Show connection info ---
show_connection_info

# --- Build remote command ---
if [[ -n "$remotePath" ]]; then
  if [[ -n "$console" ]]; then
    remote_cmd="cd \"$remotePath\" && exec $console -l"
  else
    remote_cmd="cd \"$remotePath\" && exec \$SHELL -l"
  fi
else
  if [[ -n "$console" ]]; then
    remote_cmd="exec $console -l"
  else
    remote_cmd="exec \$SHELL -l"
  fi
fi

# --- Call SSH login wrapper ---
cmd=(./ssh_login.zsh --user "$remoteUser" --host "$remoteHost" --port "$port" --shell "$console")
for opt in "${sshOptions[@]}"; do
  cmd+=(--option "$opt")
done

cmd+=(--path "$remotePath")

if [[ "$flag_verbose" -ne 0 ]]; then
  cmd+=(-v "$flag_verbose")
fi

# --- Run the command ---
execute "${cmd[@]}" --exe
