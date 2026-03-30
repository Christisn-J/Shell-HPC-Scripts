#!/bin/bash
check_arg() {
  local name="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    error "Missing or invalid argument for $name"
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

check_valid_mode() {
  local mode="$1"
  shift
  local modes=("$@")  # alle weiteren Parameter als Array

  for value in "${modes[@]}"; do
      if [[ "$mode" == "$value" ]]; then
          return 0
      fi
  done

  error " Invalid mode '$mode'. Available modes: ${modes[*]}" >&2
  return 1
}


check_valid_path() {
  local name="$1"
  local path="$2"

  if [[ ! -e "$path" ]]; then
    error "Invalid path for $name: '$path' does not exist."
  elif [[ ! -f "$path" && ! -d "$path" ]]; then
    error "Invalid path for $name: '$path' is neither a file nor a directory."
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

check_ffmpeg() {
  if ! command -v ffmpeg &>/dev/null; then
    return 1
  else
    return 0
  fi
}

check_skip() {
  local var="$1"
  local list="$2"
  local minRange="${3:-0}"
  local maxRange="${4:-}"

  local phase
  local temp_array  # Just declare; array creation comes next

  # Safely read into a real array (Bash 3-compatible)
  IFS="${SEPARATOR[list]}" read -r -a temp_array <<< "$list"

  for phase in "${temp_array[@]}"; do
    if ! [[ "$phase" =~ ^[0-9]+$ ]] || (( $phase < $minRange || $phase > $maxRange )); then
      error "Invalid skip phase: $phase. Must be in range $minRange–$maxRange."
    fi
  done

  # Dynamically assign array by name (eval needed in Bash 3)
  eval "$var=(\"\${temp_array[@]}\")"
  return 0
}

check_select() {
    local var="$1"
    local list="$2"
    shift 2
    local valid_modes=("$@")

    local temp_array=()
    local ele found valid_list expanded_modes=()

    # Liste der gültigen Modi für Fehlermeldung
    valid_list=$(IFS=','; echo "${valid_modes[*]}")

    # Ersetze Kommas durch Leerzeichen, dann splitte nach Leerzeichen
    list="${list//,/ }"
    list="$(echo "$list" | xargs)"          # trim leading/trailing whitespace
    list="$(echo "$list" | tr -s ' ')"      # mehrere Leerzeichen zusammenfassen
    read -r -a temp_array <<< "$list"

    for mode in "${temp_array[@]}"; do
        # Trim whitespace
        mode="$(echo "$mode" | xargs)"
        # Konvertiere evtl. Aliase in vollständige Mode-Namen
        expanded="$(get_name_completeMode "$mode")"
        # expanded kann mehrere Modi enthalten → splitten
        read -r -a split_modes <<< "$expanded"

        for m in "${split_modes[@]}"; do
            found=false
            for valid_mode in "${valid_modes[@]}"; do
                if [[ "$valid_mode" == "$m" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == false ]]; then
                error "Invalid mode: '$m'. Must be one of: $valid_list"
            fi
            expanded_modes+=("$m")
        done
    done

    # Wenn alles gültig ist → Array zurückgeben
    eval "$var=(\"\${expanded_modes[@]}\")"
    return 0
}


check_natural_numbers() {
  local name="$1"
  local value="$2"
  local minRange="${3:-0}"        # Standard: 0, wenn nichts angegeben
  local maxRange="${4:-}"         # maxRange darf leer sein (= kein Limit)

  # 1. Prüfen, ob Wert wirklich eine ganze Zahl ist
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    error "Invalid $name number: '$value'. Must be a natural number."
  fi

  # 2. Prüfen untere Grenze
  if (( $value < $minRange )); then
    error "Invalid $name number: $value. Must be >= $minRange"
  fi

  # 3. Prüfen obere Grenze nur, wenn angegeben
  if [[ -n "$maxRange" ]]; then
    if (( $value > $maxRange )); then
      error "Invalid $name number: $value. Must be <= $maxRange"
    fi
  fi

  return 0
}
