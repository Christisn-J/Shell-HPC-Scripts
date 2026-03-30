#!/bin/zsh

######################################################################
# sync.zsh
#
# Synchronize files or directories between local and remote systems
# using rsync over SSH with connection multiplexing.
#
# Features:
#   - Push or pull mode
#   - Persistent SSH connection
#   - Git branch mismatch detection
#   - Lockfile protection
#   - Extension-based exclusion
#
# Author: Your Name
######################################################################

SCRIPT_DIR="$(cd "$(dirname "${(%):-%N}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/utils.zsh"

overall_start=$(start_timer)
check_color_support && flag_color=true

######################################################################
# Default Configuration
######################################################################

SSH_PORT=22
mode="auto"

######################################################################
# Usage Information
######################################################################

usage() {
cat << EOF

Usage:
  $0 --direction <push|pull> --user <username> --host <hostname> [options] <path> [...]

Description:
  Synchronize files or directories between local and remote systems
  using rsync over SSH.

Required Flags:
  --direction <push|pull>      Sync direction
                               push = local → remote
                               pull = remote → local
  --user <username>           SSH username
  --host <hostname>           Remote host (DNS or IP)

Optional Flags:
  --port <port>               SSH port (default: 22)
  --local <path>              Local base directory (default: \$HOME)
  --remote <path>             Remote base directory (default: \$HOME)
  -m, --mode <file|dir|auto>  Sync mode (default: auto)
  -e, --exclude-extension     Exclude file extension (can be used multiple times)
                               Example: -e log -e tmp
  -v, --verbose <level>       Verbosity level (0–3)
  -q, --quiet                 Suppress most output
  -h, --help                  Show this help message

Arguments:
  <path> [...]                One or more relative paths to sync

Examples:
  $0 --direction push --user dev --host server project/
  $0 --direction pull --user dev --host server -e log -e tmp project/

EOF
exit 0
}

######################################################################
# Run rsync with SSH multiplexing
######################################################################

run_rsync() {
  local src_path="$1"
  local dest_path="$2"

  debug 3 "Direction: $direction"
  debug 3 "Source: $src_path"
  debug 3 "Destination: $dest_path"

  if [[ "$branch_mismatch" == true ]]; then
    warn "Git branch mismatch detected."

    if ! confirm "Continue syncing '$arg' despite branch mismatch?" "no"; then
      warn "Sync aborted by user."
      rm -f "$lockfile"
      return
    fi
  fi

  local ssh_cmd="ssh -T -p $SSH_PORT \
    -o ControlMaster=auto \
    -o ControlPath=$control_path \
    -o ControlPersist=10m"

  local rsync_cmd
  rsync_cmd=("rsync" "-avz" "-e" "$ssh_cmd")

  # Extension exclusion logging
  if (( ${#exclude_extensions[@]} > 0 )); then
    debug 2 "Excluding extensions: ${(j:,:)exclude_extensions}"
  fi

  for ext in "${exclude_extensions[@]}"; do
    rsync_cmd+=("--exclude=*.${ext}" "--exclude=**/*.${ext}")
  done

  rsync_cmd+=("--rsync-path=LC_ALL=C rsync")
  rsync_cmd+=("$src_path" "$dest_path")

  execute "${rsync_cmd[@]}" --exe
}

######################################################################
# Cleanup on Exit
######################################################################

lockfiles=()

cleanup() {

  for f in "${lockfiles[@]}"; do
    [[ -e "$f" ]] && {
      info "Removing lockfile: $f"
      rm -f "$f"
    }
  done

  info "Closing persistent SSH connection..."

  ssh -O exit -p "$SSH_PORT" \
    -o ControlPath="$control_path" \
    "$remoteUser@$remoteHost" 2>/dev/null

  if [[ -e "$control_path" ]]; then
    warn "ControlPath socket still exists: $control_path"
  else
    success "SSH ControlPath closed."
  fi

  total_duration=$(end_timer "$overall_start")
  trace "Total duration: $(format_timer "$total_duration")"

  exit 0
}

trap cleanup EXIT

######################################################################
# Git Branch Check
######################################################################

branch_mismatch=false

check_git_status() {

  if [[ -d "$localPath/.git" ]]; then
    local local_branch=$(git -C "$localPath" rev-parse --abbrev-ref HEAD)
  else
    return
  fi

  if ssh -p "$SSH_PORT" -o ControlPath="$control_path" \
     "$remoteUser@$remoteHost" "[ -d '$remotePath/.git' ]"; then

    local remote_branch=$(ssh -p "$SSH_PORT" \
      -o ControlPath="$control_path" \
      "$remoteUser@$remoteHost" \
      "git -C '$remotePath' rev-parse --abbrev-ref HEAD 2>/dev/null")

    [[ "$local_branch" != "$remote_branch" ]] && branch_mismatch=true
  fi
}

main(){
  ######################################################################
  # Argument Parsing
  ######################################################################

  remoteUser=""
  remoteHost=""
  remotePath="$HOME"
  localPath="$HOME"
  direction="push"
  mode="auto"
  flag_verbose=0
  flag_quiet=false
  exclude_extensions=()
  args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --direction) shift; direction="$1"; shift ;;
      --user) shift; remoteUser="$1"; shift ;;
      --host) shift; remoteHost="$1"; shift ;;
      --port) shift; SSH_PORT="$1"; shift ;;
      --local) shift; localPath="$1"; shift ;;
      --remote) shift; remotePath="$1"; shift ;;
      -m|--mode) shift; mode="$1"; shift ;;
      -e|--exclude-extension)
        shift
        ext="${1#.}"
        exclude_extensions+=("$ext")
        shift ;;
      -v|--verbose) shift; flag_verbose="$1"; shift ;;
      -q|--quiet) flag_quiet=true; shift ;;
      -h|--help) usage ;;
      *) args+=("$1"); shift ;;
    esac
  done

  ######################################################################
  # Validation
  ######################################################################

  [[ -z "$remoteUser" ]] && error "Missing --user"
  [[ -z "$remoteHost" ]] && error "Missing --host"
  [[ ${#args[@]} -eq 0 ]] && error "No path specified"
  [[ "$direction" != "push" && "$direction" != "pull" ]] && error "Invalid direction"

  ######################################################################
  # SSH Setup
  ######################################################################

  control_path="$HOME/.ssh/cm-${remoteUser}@${remoteHost}:${SSH_PORT}"

  command -v nc >/dev/null || error "'nc' (netcat) is required but not installed."

  info "Checking SSH connectivity to $remoteHost on port $SSH_PORT..."
  nc -z -w 5 "$remoteHost" "$SSH_PORT" >/dev/null 2>&1 \
    || error "SSH port $SSH_PORT on $remoteHost is not reachable"

  info "Establishing persistent SSH connection..."
  ssh -f -N -T -p "$SSH_PORT" \
    -o ControlMaster=auto \
    -o ControlPath="$control_path" \
    -o ControlPersist=10m \
    "$remoteUser@$remoteHost" \
    || error "Failed to establish persistent SSH connection."

  success "SSH multiplex connection established."

  check_git_status

  ######################################################################
  # Sync Loop
  ######################################################################

  for arg in "${args[@]}"; do
      lockfile="/tmp/sync_${arg//[^a-zA-Z0-9]/_}_$direction.lock"
      lockfiles+=("$lockfile")

      if [[ -e "$lockfile" ]]; then
        warn "Lock file exists for '$arg'. Another sync may be running. Skipping."
        continue
      fi

      touch "$lockfile"
      info "→ Syncing: $arg (mode: $mode)"

      # --- Quelle/Ziel vorbereiten ---
      if [[ "$direction" == "push" ]]; then
          src_path="$localPath/$arg"
          dest_path="$remoteUser@$remoteHost:$remotePath/$arg"

          # Prüfen, ob File oder Directory lokal
          if [[ -f "$src_path" ]]; then
              path_type="file"
              # Zielparent auf Remote anlegen
              ssh -p "$SSH_PORT" -o ControlPath="$control_path" "$remoteUser@$remoteHost" \
                  "mkdir -p '$(dirname "$remotePath/$arg")'"
          elif [[ -d "$src_path" ]]; then
              path_type="dir"
              # Zielverzeichnis auf Remote anlegen
              ssh -p "$SSH_PORT" -o ControlPath="$control_path" "$remoteUser@$remoteHost" \
                  "mkdir -p '$remotePath/$arg'"
          else
              warn "Local path '$src_path' does not exist. Skipping."
              rm -f "$lockfile"
              continue
          fi

      else # pull
          src_path="$remoteUser@$remoteHost:$remotePath/$arg"
          dest_path="$localPath/$arg"

          # Prüfen, ob File oder Directory remote
          if ssh -p "$SSH_PORT" -o ControlPath="$control_path" "$remoteUser@$remoteHost" "[ -f '$remotePath/$arg' ]"; then
              path_type="file"
              [[ ! -d "$(dirname "$dest_path")" ]] && mkdir -p "$(dirname "$dest_path")"
          elif ssh -p "$SSH_PORT" -o ControlPath="$control_path" "$remoteUser@$remoteHost" "[ -d '$remotePath/$arg' ]"; then
              path_type="dir"
              [[ ! -d "$dest_path" ]] && mkdir -p "$dest_path"
          else
              warn "Remote path '$remotePath/$arg' is neither a file nor a directory. Skipping."
              rm -f "$lockfile"
              continue
          fi
      fi

      # --- Mode Handling ---
      case "$mode" in
          file)
              [[ "$path_type" != "file" ]] && { warn "'$arg' is not a file. Skipping."; rm -f "$lockfile"; continue; }
              run_rsync "$src_path" "$dest_path"
              ;;
          dir)
              [[ "$path_type" != "dir" ]] && { warn "'$arg' is not a directory. Skipping."; rm -f "$lockfile"; continue; }
              run_rsync "$src_path"/ "$dest_path"/
              ;;
          auto)
              if [[ "$path_type" == "file" ]]; then
                  run_rsync "$src_path" "$dest_path"
              elif [[ "$path_type" == "dir" ]]; then
                  run_rsync "$src_path"/ "$dest_path"/
              fi
              ;;
          *)
              warn "Unknown mode: $mode. Skipping '$arg'."
              ;;
      esac

      rm -f "$lockfile"
  done

}
######################################################################
# Execute only if script is run directly (not sourced)
######################################################################

if [[ "${(%):-%N}" == "$0" ]]; then
  main "$@"
  exit 0
fi

return 0