#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${(%):-%N}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/utils.zsh"
check_color_support && flag_color=true

# --- Default Config ---
SSH_PORT=22
CONSOLE="bash"

# --- Usage ---
usage() {
  print -P "\n%B%F{cyan}Usage:%f%b\n  $0 --user <remoteUser> --host <remoteHost> [--port <port>] [--option <ssh-option> ...] [--path <remotePath>] [--shell <shell>]\n"
  print "Connect to a remote SSH host using."
  print -P "\n%B%F{cyan}Options:%f%b"
  print -P "  %B%F{yellow}--user%f%b             Required: remote username"
  print -P "  %B%F{yellow}--host%f%b             Required: remote hostname"
  print -P "\n%B%F{cyan}Flags:%f%b"
  print -P "  %B%F{yellow}--port%f%b             Optional: SSH port (default: 22)"
  print -P "  %B%F{yellow}--option%f%b           Optional: Additional ssh options (can be repeated)"
  print -P "  %B%F{yellow}--path%f%b             Optional: Remote path to start in (default: user's home directory)"
  print -P "  %B%F{yellow}--shell%f%b            Optional: Shell to use on remote (default: bash)"
  print -P "  %F{yellow}-v, --verbose%f          Optional: verbose output (default: off)"
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
port=$SSH_PORT
console=$CONSOLE

sshOpts=()
remoteUser=""
remoteHost=""
remotePath=""
user_set=0
host_set=0
flag_verbose=0
: ${flag_color:=false}

# --- Parse CLI arguments ---
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
    --user)
      shift
      check_arg "--user" "$1"
      validate_name "$1"
      if (( user_set )); then
        error "Duplicate --user option"
      fi
      remoteUser="$1"
      user_set=1
      shift
      ;;
    --host)
      shift
      check_arg "--host" "$1"
      if (( host_set )); then
        error "Duplicate --host option"
      fi
      remoteHost="$1"
      host_set=1
      shift
      ;;
    --port)
      shift
      check_arg "--port" "$1"
      validate_natural_numbers "--port" $1 1 65535
      port="$1"
      shift
      ;;
    --option)
      shift
#      check_arg "--option" "$1"
      sshOpts+=("$1")
      shift
      ;;
    --path)
      shift
      check_arg "--path" "$1"
      remotePath="$1"
      shift
      ;;
    --shell)
      shift
      check_arg "--shell" "$1"
      if ! [[ "$1" =~ ^[a-zA-Z0-9/_-]+$ ]]; then
        error "Invalid shell name: $1"
      fi
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
      warn "Ignoring unexpected argument: $1"
      shift
      ;;
  esac
done


# --- Validate required options ---
if [[ -z "$remoteUser" || -z "$remoteHost" ]]; then
  warn "Missing required options: --user and --host are required."
  usage
fi

# --- Verify netcat is available ---
if ! command -v nc &>/dev/null; then
  error "'nc' (netcat) is required but not installed or not in $PATH."
fi

# --- Check port connectivity ---
info "Checking SSH connectivity to $remoteHost on port $port..."
if ! nc -z -w 5 "$remoteHost" "$port" >/dev/null 2>&1; then
  error "SSH connection to $remoteHost failed: port $port is not open."
fi

# --- Show connection info ---
show_connection_info

# --- Build remote command ---
if [[ -n "$remotePath" ]]; then
  remoteCmd="cd "$remotePath" && exec $console -l"
else
  remoteCmd="exec $console -l"
fi

# --- Fehlerausgabe in temporäre Datei umleiten ---
local ssh_stderr_file
ssh_stderr_file=$(mktemp /tmp/ssh-stderr.XXXXXX)

# Bei Exit: temporäre Datei automatisch löschen
trap 'rm -f "$ssh_stderr_file"' EXIT

# --- Connect ---
info "SSH port $port is open. Establishing SSH connection now..."

# --- Run the command ---
cmd+=(ssh ${remoteUser}@${remoteHost} -p ${port} ${sshOpts[*]} -t "${remoteCmd}")
execute "${cmd[@]}" --exe 2> "$ssh_stderr_file"
ssh_exit=$?
ssh_output=$(<"$ssh_stderr_file")
ssh_exit=$?

if [[ $ssh_exit -ne 0 ]]; then
  if echo "$ssh_output" | grep -qi "connection refused"; then
    error "SSH connection refused — the server is reachable, but port $port is closed or SSH is not running."
  elif echo "$ssh_output" | grep -qi "closed by remote host"; then
    error "SSH connection closed by remote host — check for session timeouts or shell startup issues (e.g. .bashrc/.zshrc errors)."
  elif echo "$ssh_output" | grep -qi "broken pipe"; then
    error "SSH broken pipe — connection was unexpectedly closed. This can happen due to inactivity or server-side policies."
  elif echo "$ssh_output" | grep -qi "no route to host"; then
    error "SSH failed: No route to host — check your network connection or VPN."
  elif echo "$ssh_output" | grep -qi "connection timed out"; then
    error "SSH timed out — the server may be offline, slow, or behind a firewall."
  else
    error "SSH failed (exit code $ssh_exit):\n$ssh_output"
  fi
fi

