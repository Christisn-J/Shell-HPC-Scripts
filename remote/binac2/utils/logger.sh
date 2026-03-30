#!/bin/bash
log() {
  local level="$1"
  local color="${2:-}"
  shift 2
  local prefix="[$level]"

  # Kombinierte Kontextanzeige: (variant, prozess)
  local context_parts=()
  [[ -n "${VARIANT_KEY:-}" ]] && context_parts+=("$VARIANT_KEY")
  [[ -n "${SCALE_KEY:-}" ]] && context_parts+=("$SCALE_KEY")
  [[ -n "${POST_KEY:-}" ]] && context_parts+=("$POST_KEY")

  if (( ${#context_parts[@]} > 0 )); then
    local context_str
    context_str="$(IFS=','; echo "(${context_parts[*]})")"
    prefix="$context_str$prefix"
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
compute() { log "COMPUTE"  grey   "$@"; }

verbose() {
  local lvl="$1"
  shift
  if (( flag_verbose >= lvl )); then
    log "EXTRA" white "$*"
  fi
}

execute() {
  local execute_flag=false
  local silence_flag=false
  local args=("$@")

  # Flags aus args entfernen und Status setzen
  local filtered_args=()
  for arg in "${args[@]}"; do
    case "$arg" in
      --exe)
        execute_flag=true
        ;;
      --silence)
        silence_flag=true
        ;;
      *)
        filtered_args+=("$arg")
        ;;
    esac
  done

 args=("${filtered_args[@]}")

 if (( flag_verbose > 0 )); then
   if $run; then
     log "EXECUTE" cyan "${args[*]}"
   else
     log "NOT EXECUTE" yellow "${args[*]}"
   fi
 fi

 if $execute_flag; then
   if $silence_flag; then
     # Ausgabe unterdrücken
     "${args[@]}" > /dev/null 2>&1
   else
     # Ausgabe normal anzeigen
     "${args[@]}"
   fi
 fi
}