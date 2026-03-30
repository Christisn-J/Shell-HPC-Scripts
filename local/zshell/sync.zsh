#!/bin/zsh

######################################################################
# sync.zsh
#
# High-level wrapper for ssh_sync.zsh.
#
# Features:
#   - push / pull mode
#   - Host alias resolution
#   - Extension exclusion via comma-separated list (-e)
#   - Verbosity control
#   - Quiet mode
#   - Clean forwarding to ssh_sync.zsh
#   - Safe execution guard (works when sourced)
#
######################################################################

SCRIPT_DIR="$(cd "$(dirname "${(%):-%N}")" &> /dev/null && pwd)"
source "$SCRIPT_DIR/utils.zsh"

check_color_support && flag_color=true

####################################################################
# Usage
####################################################################

usage() {
cat << EOF

Usage:
  $0 <push|pull> -r <hostAlias> -p <path> [options]

Description:
  Synchronize files or directories using rsync over SSH.
  Host settings are resolved via remoteHost.info.

Required:
  <push|pull>                 Direction of sync
  -r, --remote <hostAlias>    Remote host alias
  -p, --path <path>           Path to sync (can be used multiple times)

Options:
  -m, --mode <mode>           file | dir | auto (default: auto)
  --port <port>               SSH port (default: 22)
  -e, --exclude-extension     Comma-separated list of extensions to exclude
                              Example: -e log,tmp,pdf
  -v, --verbose <level>       Verbosity level 0–3
  -q, --quiet                 Suppress output
  -h, --help                  Show this help message

Examples:
  $0 push -r serverAlias -p project/ -p logs/
  $0 pull -r serverAlias -p output/ -e log,tmp
EOF
exit 0
}

######################################################################
# Main Function
######################################################################

main() {

  ####################################################################
  # Default Configuration
  ####################################################################

  SSH_PORT=22
  mode="auto"

  localHost="$(hostname)"
  localUser="$USER"
  localPath="$HOME/Uni/milupHPC/"

  exclude_extensions=()
  direction=""
  remoteAlias=""
  flag_verbose=0
  flag_quiet=false
  paths=()
  remoteAlias=""

  ####################################################################
  # Basic Validation
  ####################################################################

  if (( $# < 1 )); then
    usage
  fi

  ####################################################################
  # Direction
  ####################################################################

  case "$1" in
    push) direction="push" ;;
    pull) direction="pull" ;;
    *) error "First argument must be 'push' or 'pull'." ;;
  esac
  shift

  ####################################################################
  # Argument Parsing
  ####################################################################

  ####################################################################
  # Parse Remaining Arguments
  ####################################################################

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--mode)
        shift
        check_arg "--mode" "$1"
        mode="$1"
        ;;
      --port)
        shift
        check_arg "--port" "$1"
        SSH_PORT="$1"
        ;;
      -e|--exclude-extension)
        shift
        check_arg "--exclude-extension" "$1"

        IFS=',' read -rA ext_list <<< "$1"

        for ext in "${ext_list[@]}"; do
          ext="${ext#.}"    # Remove leading dot
          exclude_extensions+=("$ext")
        done
        ;;
      -v|--verbose)
        shift
        check_arg "--verbose" "$1"
        validate_natural_numbers "--verbose" "$1" 0 3
        flag_verbose="$1"
        ;;
      -q|--quiet)
        flag_quiet=true
        ;;
      -p|--path)
        shift
        check_arg "--path" "$1"
        paths+=("$1")
        ;;
      -r|--remote)
        if [[ -n "$remoteAlias" ]]; then
          error "--remote can only be specified once"
        fi
        shift
        check_arg "--remote" "$1"
        remoteAlias="$1"
        ;;
      -h|--help)
        usage
        ;;
      -*)
        warn "Unknown option: $1."
        usage
        ;;
      *)
        warn "Unknown option: $1."
        usage
        ;;
    esac
    shift
  done

  ####################################################################
  # Load Remote Configuration
  ####################################################################

  remoteUser=""
  remoteHost=""
  remotePath=""
  sshOptions=()

  load_remoteHost_config "$SCRIPT_DIR/remoteHost.info" "$remoteAlias"

  ####################################################################
  # Validation
  ####################################################################

  # Push: prüfen, dass lokale Pfade existieren
  if [[ "$direction" == "push" ]]; then
    valid_paths=()
    for p in "${paths[@]}"; do
      if [[ -e "$localPath/$p" ]]; then
        valid_paths+=("$p")
      else
        warn "Source path does not exist: $localPath/$p — skipping."
      fi
    done

    if (( ${#valid_paths[@]} == 0 )); then
      error "No valid files or directories to sync."
    fi
  else
    valid_paths=("${paths[@]}")
  fi

  ####################################################################
  # Info Output
  ####################################################################

  show_environment_info
  show_sync_target_info

  if [[ "$direction" == "push" ]]; then
    info "Starting push: $localUser@$localHost → $remoteUser@$remoteHost"
  else
    info "Starting pull: $remoteUser@$remoteHost → $localUser@$localHost"
  fi

  ####################################################################
  # Build Command
  ####################################################################

  cmd=("$SCRIPT_DIR/ssh_sync.zsh"
    --user "$remoteUser"
    --host "$remoteHost"
    --port "$SSH_PORT"
    --direction "$direction"
    --local "$localPath"
    --remote "$remotePath"
    -m "$mode"
  )

  if (( ${#exclude_extensions[@]} > 0 )); then
    for ext in "${exclude_extensions[@]}"; do
      cmd+=(-e "$ext")
    done
  fi

  if [[ "$flag_quiet" == true ]]; then
    cmd+=(--quiet)
  fi

  if (( flag_verbose > 0 )); then
    cmd+=(-v "$flag_verbose")
  fi

  cmd+=("${valid_paths[@]}")

  ####################################################################
  # Execute
  ####################################################################

  execute "${cmd[@]}" --exe
}

######################################################################
# Zsh Execution Guard
######################################################################

if [[ "${(%):-%N}" == "$0" ]]; then
  main "$@"
  exit 0
fi

return 0