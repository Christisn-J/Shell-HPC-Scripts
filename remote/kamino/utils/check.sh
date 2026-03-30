#!/bin/bash
check_arg() {
  local name="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    error "Missing or invalid argument for $name"
  fi
}

validate_float() {
    local val="$1"
    # Akzeptiert:
    # 10000, 0.003, .003, 1e-3, 2.5E6, -1e-3, +0.01
    if ! [[ "$val" =~ ^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$ ]]; then
        error "Invalid number: $val"
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
  local input="$1"
  local array_name="$2"
  local value
  local i=0

  eval "set -- \"\${${array_name}[@]}\""
  for value in "$@"; do
    if [[ "$input" == "$value" ]]; then
      return 0
    fi
  done
  return 1
}

check_valid_path() {
  local path="$1"
  local argname="$2"

  if [[ ! -e "$path" ]]; then
    error "Invalid path for $argname: '$path' does not exist."
  elif [[ ! -f "$path" && ! -d "$path" ]]; then
    error "Invalid path for $argname: '$path' is neither a file nor a directory."
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
  local range_max="$1"
  local input="$2"
  local result_var_name="$3"
  local phase

  local temp_array  # Just declare; array creation comes next

  # Safely read into a real array (Bash 3-compatible)
  IFS=',' read -r -a temp_array <<< "$input"

  for phase in "${temp_array[@]}"; do
    if ! [[ "$phase" =~ ^[0-9]+$ ]] || (( phase < 0 || phase > range_max )); then
      error "Invalid skip phase: $phase. Must be in range 0–$range_max."
    fi
  done

  # Dynamically assign array by name (eval needed in Bash 3)
  eval "$result_var_name=(\"\${temp_array[@]}\")"
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

    # --- Prüfung auf leere Liste ---
    if [[ -z "$list" ]]; then
        error "No modes specified. Must be one of: $valid_list"
        return 1
    fi

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