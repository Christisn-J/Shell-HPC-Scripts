#!/bin/zsh

setopt NO_NOMATCH

SCRIPT_DIR="$(cd "$(dirname "${(%):-%N}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/utils.zsh"

REMOTE_INFO_FILE="$SCRIPT_DIR/remoteHost.info"
SSH_CONFIG="$HOME/.ssh/config"

check_color_support && flag_color=true
: ${flag_color:=false}

# --- Usage ---
usage() {
    echo "Usage: $(basename "$0") [option]"
    echo
    echo "Options:"
    echo "  -a, --add            Add a new SSH alias"
    echo "  -r,  --rm          Remove an existing SSH alias"
    echo "  -l, --list    List all SSH aliases"
    echo "  -h, --help    Show this help message"
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

# --- List aliases ---
list_ssh_alias() {
    local have_ssh_config=false
    local have_remote_info=false

    # Check if SSH config file exists
    if [[ -f $SSH_CONFIG ]]; then
        have_ssh_config=true
    else
        warn "SSH config file not found: $SSH_CONFIG"
    fi

    # Check if remoteHost.info file exists
    if [[ -f "$REMOTE_INFO_FILE" ]]; then
        have_remote_info=true
    else
        warn "remoteHost.info file not found: $REMOTE_INFO_FILE"
    fi

    echo
    info "Aliases in remoteHost.info:"
    if $have_remote_info; then
        grep "^\[" "$REMOTE_INFO_FILE" | sed 's/^\[\(.*\)\]$/\1/' | while read -r alias_name; do
            host=$(awk -v alias="[$alias_name]" '
                $0 == alias {found=1; next}
                found && /^host=/ {gsub(/^host=/, "", $0); print $0; exit}
            ' "$REMOTE_INFO_FILE")
            printf "  %-15s → %s\n" "$alias_name" "$host"
        done
    else
        info "  (none)"
    fi

    echo
    info "Aliases in ~/.ssh/config:"
    if $have_ssh_config; then
        grep '^Host ' "$SSH_CONFIG" | awk '{print "  - " $2}'
    else
        info "  (none)"
    fi
    echo
}

# --- Add alias ---
create_ssh_alias() {
    info "Please enter SSH connection details"
    question "Enter SSH host: "; read ssh_host
    question "Enter SSH user: "; read ssh_user
    question "Enter SSH port (default 22): "; read ssh_port
    ssh_port=${ssh_port:-22}
    question "Give this connection a shortcut name (e.g., myserver): "; read ssh_alias
    question "Enter default remote path (e.g., ~ or /home/user/dir): "; read ssh_path
    question "Enter SSH options (e.g., -X -o StrictHostKeyChecking=no), or leave empty: "; read ssh_opts

    echo
    info "Creating SSH config entry:"
    echo "Alias:   $ssh_alias"
    echo "Host:    $ssh_host"
    echo "User:    $ssh_user"
    echo "Port:    $ssh_port"

    if response_ask "Do you want to save this in $SSH_CONFIG?"; then
        mkdir -p ~/.ssh
        touch "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"

        if grep -q "^Host $ssh_alias\$" "$SSH_CONFIG"; then
            warn "An entry for '$ssh_alias' already exists. Skipping save."
        else
            cat <<EOF >> "$SSH_CONFIG"

Host $ssh_alias
    HostName $ssh_host
    User $ssh_user
    Port $ssh_port
EOF
            info "SSH config saved successfully."
        fi
    fi

    # Write to remoteHost.info
    if [[ -n "$ssh_alias" ]]; then
      if response_ask "Do you want to save this in $REMOTE_INFO_FILE?"; then
        mkdir -p "$SCRIPT_DIR"
        touch "$REMOTE_INFO_FILE"

        if grep -q "^\[$ssh_alias\]$" "$REMOTE_INFO_FILE"; then
            warn "Alias '$ssh_alias' already exists in remoteHost.info. Skipping write."
        else
            cat <<EOF >> "$REMOTE_INFO_FILE"

[$ssh_alias]
user=$ssh_user
host=$ssh_host
path=$ssh_path
sshOpts=($ssh_opts)
port=$ssh_port
EOF
            info "Entry added to remoteHost.info."
        fi
      fi
    fi

    if response_ask "Do you want to test the SSH connection now?"; then
        info "Trying to connect to $ssh_alias..."
        ssh "$ssh_alias"
    else
        info "You can now connect anytime using: ssh $ssh_alias"
    fi
}

# --- Remove alias ---
remove_ssh_alias() {
     # Check if files exist
     if [[ -f $SSH_CONFIG ]]; then
         have_ssh_config=true
     else
         warn "SSH config file not found: $SSH_CONFIG"
     fi

     if [[ -f "$REMOTE_INFO_FILE" ]]; then
         have_remote_info=true
     else
         warn "remoteHost.info file not found: $REMOTE_INFO_FILE"
     fi

     # Use existing function to list aliases
      list_ssh_alias

     # Ask user which alias to remove
     question "Enter the SSH alias you want to remove: "
     read alias_to_remove
     if [[ -z $alias_to_remove ]]; then
         warn "No alias entered, aborting removal."
         return
     fi

     # Confirm removal
     if ! response_ask "Are you sure you want to remove the alias form $SSH_CONFIG '$alias_to_remove'?"; then
         info "Aborted removal."
         return
     fi

     # Remove from SSH config if exists
     if $have_ssh_config && grep -q "^Host $alias_to_remove\$" "$SSH_CONFIG"; then
         cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"
         info "Backup created at ${SSH_CONFIG}.bak"

         awk -v host="Host $alias_to_remove" '
         $0 == host {skip=1; next}
         /^Host / && skip {skip=0}
         !skip {print}
         ' "$SSH_CONFIG" > "${SSH_CONFIG}.tmp" && mv "${SSH_CONFIG}.tmp" "$SSH_CONFIG"

         info "Alias '$alias_to_remove' has been removed from $SSH_CONFIG."
     else
         warn "Alias '$alias_to_remove' not found in $SSH_CONFIG."
     fi


    # Confirm removal
         if ! response_ask "Are you sure you want to remove the alias  form $REMOTE_INFO_FILE '$alias_to_remove'?"; then
             info "Aborted removal."
             return
         fi
     # Remove from remoteHost.info if exists
     if $have_remote_info && grep -q "^\[$alias_to_remove\]$" "$REMOTE_INFO_FILE"; then
         cp "$REMOTE_INFO_FILE" "${REMOTE_INFO_FILE}.bak"
         info "Backup of remoteHost.info created at ${REMOTE_INFO_FILE}.bak"

         awk -v alias="[$alias_to_remove]" '
         $0 == alias {skip=1; next}
         /^\[.*\]/ && skip {skip=0}
         !skip {print}
         ' "$REMOTE_INFO_FILE" > "${REMOTE_INFO_FILE}.tmp" && mv "${REMOTE_INFO_FILE}.tmp" "$REMOTE_INFO_FILE"

         info "Alias '$alias_to_remove' removed from remoteHost.info."
     else
         warn "Alias '$alias_to_remove' not found in remoteHost.info."
     fi
 }


# --- Main control ---
case "$1" in
    -a|--add) create_ssh_alias ;;
    -r|--rm) remove_ssh_alias ;;
    -l|--list) list_ssh_alias ;;
    -h|--help) usage ;;
    "")  # Interactive fallback
        question "Do you want to (a)dd a new SSH alias or (r)emove an existing one? [a/r]: "
        read  action
        case $action in
            a|A) create_ssh_alias ;;
            r|R) remove_ssh_alias ;;
            *) warn "Invalid choice, exiting."; usage ;;
        esac
        ;;
    *) warn "Unknown option: $1"; usage ;;
esac
