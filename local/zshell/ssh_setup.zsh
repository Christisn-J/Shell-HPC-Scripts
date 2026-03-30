#!/bin/zsh
SCRIPT_DIR="$(cd "$(dirname "${(%):-%N}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/utils.zsh"

check_color_support && flag_color=true

# --- Defaults ---
SSH_KEY="$HOME/.ssh/id_rsa"
SSH_PORT=22

usage() {
  echo
  echo "Usage: $0 <hostalias> [OPTIONS]"
  echo
  echo "Establish or manage an SSH connection using a predefined host alias."
  echo
  echo "Arguments:"
  echo "  hostalias             Name of the SSH host alias (must be defined in remoteHost.info or managed by ssh_manage_alias.zsh)"
  echo
  echo "Options:"
  echo "  --skip PHASES         Comma-separated list of phases to skip."
  echo "                        Phases:"
  echo "                          0 - SSH alias creation"
  echo "                          1 - SSH key generation (if missing)"
  echo "                          2 - Start ssh-agent and add key"
  echo "                          3 - Show public key and optionally upload"
  echo "                          4 - Connect via SSH"
  echo "  -h, --help            Show this help message and exit"
  echo

  local info_file="$SCRIPT_DIR/remoteHost.info"
  if [[ -f "$info_file" ]]; then
    echo "Available SSH aliases:"
    grep '^\[.*\]$' "$info_file" | sort | uniq | sed 's/^/  - /'
    echo
  else
    echo "No SSH alias file found at $info_file"
    echo
  fi

  exit 0
}


# --- Argumente parsen ---
skip_phases=()
hostalias=""
flag_verbose=0
: ${flag_color:=false}

# Wenn kein Argument oder erstes Argument mit '-' beginnt, dann ist kein Hostalias gesetzt
if [[ $# -eq 0 ]] || [[ "$1" == -* ]]; then
  error "No host alias specified."
else
  hostalias=$1
  shift
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip)
      shift
      check_arg "--skip" "$1"
      IFS=',' read -r skip_phases_str <<< "$1"
      skip_phases=(${(s:,:)skip_phases_str})
      for s in "${skip_phases[@]}"; do
        if ! [[ "$s" =~ ^[0-4]$ ]]; then
          error "Invalid skip phase: $s. Must be in range 0-4."
        fi
      done
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      error "Unknown option: $1"
      ;;
  esac
done

if (( ${#skip_phases[@]} > 0 )); then
  info "Skipping phases: ${skip_phases[*]}"
fi

# Phase 0: SSH Alias anlegen, nur wenn er noch nicht existiert
if ! check_skip_phase 0; then
  if check_hostalias_exists "$SCRIPT_DIR/remoteHost.info" "$hostalias"; then
    info "SSH alias '$hostalias' already exists. Skipping creation."
  else
    info "Creating SSH alias '$hostalias'..."
    cmd=("$SCRIPT_DIR/ssh_manage_alias.zsh" --add "$hostalias")
    execute "${cmd[@]}" --exe || error "Failed to add alias"
  fi
else
  warn "Skipping phase 0: SSH alias creation."
fi

# Prüfen ob hostalias existiert
check_hostalias_exists "$SCRIPT_DIR/remoteHost.info" "$hostalias"

# ---  SSH Host Konfiguration laden ---
remoteUser=""
remoteHost=""
remotePath=""
sshOptions=()
port=22
console="bash"
load_remoteHost_config "$SCRIPT_DIR/remoteHost.info" "$hostalias"

# Phase 1: SSH-Key generieren falls nicht vorhanden
if ! check_skip_phase 1; then
  if [[ ! -f "$SSH_KEY" ]]; then
    info "SSH key not found. Creating new SSH key at $SSH_KEY ..."
    ssh-keygen -t rsa -b 4096 -C "$USER@$(hostname)" -f "$SSH_KEY" -N "" || error "Failed to create SSH key."
  else
    info "SSH key found at $SSH_KEY"
  fi
else
  warn "Skipping phase 1: SSH key generation."
fi

# Phase 2: ssh-agent starten und Key hinzufügen
if ! check_skip_phase 2; then
  info "Starting ssh-agent and adding SSH key..."
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add "$SSH_KEY" || error "Failed to add SSH key."
else
  warn "Skipping phase 2: ssh-agent start and ssh-add."
fi

# Phase 3: Public key anzeigen und ggf. hochladen
if ! check_skip_phase 3; then
  info "Public SSH key (copy it to the server's ~/.ssh/authorized_keys if needed):"
  echo "---------------------------------------------------"
  cat "${SSH_KEY}.pub"
  echo "---------------------------------------------------"

  if response_ask "Upload your public key to $remoteUser@$remoteHost now?"; then
    if ! command -v ssh-copy-id &>/dev/null; then
      warn "'ssh-copy-id' not found. Please install it or upload the key manually."
    else
      info "Uploading public key with ssh-copy-id..."
      ssh-copy-id -i "${SSH_KEY}.pub" "$remoteUser@$remoteHost" || warn "ssh-copy-id failed. Upload key manually."
    fi
  else
    info "Skipping key upload. Ensure your public key is on the server for key-based login."
  fi
else
  warn "Skipping phase 3: public key output and upload."
fi

# Phase 4: SSH Verbindung herstellen
if ! check_skip_phase 4; then
  if response_ask "Do you want to connect now?"; then
    # --- Call SSH login wrapper ---
    cmd=($SCRIPT_DIR/ssh_login.zsh --user "$remoteUser" --host "$remoteHost" --port "$port" --shell "$console")
    for opt in "${sshOptions[@]}"; do
      cmd+=(--option "$opt")
    done

    cmd+=(--path "$remotePath")

    if [[ "$flag_verbose" -ne 0 ]]; then
      cmd+=(-v "$flag_verbose")
    fi

    # --- Run the command ---
    execute "${cmd[@]}" --exe
  else
      info "Skipping SSH connection."
  fi
else
  warn "Skipping phase 4: SSH connection."
fi
total_duration=$(end_timer "$overall_start")
info "Total duration: $total_duration seconds"
exit 0
