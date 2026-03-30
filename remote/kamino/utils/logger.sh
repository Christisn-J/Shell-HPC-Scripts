#!/bin/bash
log() {
  local level="$1"
  local color="${2:-}"
  shift 2
  local prefix="[$level]"

  # Prozess- oder Phasen-ID anzeigen, falls verfügbar
  if [[ -n "$PHASE_ID" ]]; then
    prefix="($PHASE_ID)$prefix"
  fi

  if [[ "${flag_color:-false}" == true ]]; then
    case "$color" in
      red)    prefix="\033[0;31m$prefix\033[0m" ;;
      yellow) prefix="\033[0;33m$prefix\033[0m" ;;
      blue)   prefix="\033[0;34m$prefix\033[0m" ;;
      green)  prefix="\033[0;32m$prefix\033[0m" ;;
      cyan)   prefix="\033[0;36m$prefix\033[0m" ;;
      gray)   prefix="\033[0;37m$prefix\033[0m" ;;
      white)  prefix="\033[0;37m$prefix\033[0m" ;;
    esac
  fi

  echo -e "$prefix $*"
}



info()   { log "INFO"    blue    "$@"; }
warn()   { log "WARNING" yellow  "$@"; }
error()  { log "ERROR"   red     "$@"; exit 1; }
trace()  { log "TRACE"   green   "$@"; }
debug()  { local lvl=$1; shift; (( flag_verbose >= lvl )) && log "DEBUG" gray "$@"; }
success()  { log "SUCCESS"  green   "$@"; }

verbose() {
  local lvl="$1"
  shift
  if (( flag_verbose >= lvl )); then
    log "EXTRA" white "$*"
  fi
}

execute() {
  local run=false
  local last_arg="${!#}"
  local args=("${@:1:$(($#-1))}")

  if [[ "$last_arg" == "--exe" ]]; then
    run=true
  else
    args=("$@")
  fi

  if (( flag_verbose > 0 )); then
    if $run; then
      log "EXECUTE" cyan "${args[*]}"
    else
      log "NOT EXECUTE" yellow "${args[*]}"
    fi
  fi

  $run && "${args[@]}"
}