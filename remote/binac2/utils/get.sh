#!/bin/bash
get_filePath(){
  local description="$1"
  local path="$2"
  local extension="$3"
  local filepath=""

  if [[ -z "$path" ]]; then
    error "No path provided for $description."
  elif [[ -f "$path" ]]; then
    # Direct file path given
    filepath="$path"
  elif [[ -d "$path" ]]; then
    # Search for files with given extension
    shopt -s nullglob
    files=("$path"/*"$extension")
    shopt -u nullglob
    if (( ${#files[@]} == 0 )); then
      error "No *$extension files found in directory: $path (for $description)"
    fi
    filepath="${files[0]}"
  else
    error "Invalid path for $description: $path is neither a file nor a directory."
  fi

  echo "$filepath"
  return 0
}

get_cmd_mpirun(){
    local mode="$1"
    local outdir="$2"
    local initialPath="$3"
    local configPath="$4"
    local materialPath="$5"
    local numProcess="${6:-1}"
    local steps="${7:-10}"
    local verbose="${8:-3}"
    local ranks_per_node="${9:-1}"

    local date="${execute_date:-$(date +%Y%m%d)}"
    execute_date="$date"

    # Validate required input
    [[ -z "$mode" ]] && error "get_cmd_mpirun: mode not set"
    [[ -z "$outdir" ]] && error "get_cmd_mpirun: output directory not set"
    [[ -z "$initialPath" ]] && error "get_cmd_mpirun: init file not set"
    [[ -z "$configPath" ]] && error "get_cmd_mpirun: config file not set"

    # --- Determine binary ---
    local binary_name
    binary_name="$(get_name_binary "$mode")" || error "Could not determine binary name for mode: $mode"

    # --- Associate input variables ---
    declare -A path_vars=(
        [initialConditionPath]="$initialPath"
        [configPath]="$configPath"
        [materialPath]="$materialPath"
    )

    # --- Resolve paths ---
    for varname in "${!path_vars[@]}"; do
        # Prüfen, ob diese Variable in Skip-Liste steht
        local skip_list="${SKIP_PATHS_MAP[$mode]}"
        if [[ ",$skip_list," == *",$varname,"* ]]; then
#            info "Skipping $varname for mode=$mode"
            unset path_vars[$varname]
            continue
        fi

        local value="${path_vars[$varname]}"
        if [[ -n "$value" ]]; then
            # Versuche Pfad zu finden
            local resolved
            resolved="$(get_filePath "--$varname" "$value" "${SUFFIX[$varname]}" 2>/dev/null || true)"
            if [[ -z "$resolved" || ! -f "$resolved" ]]; then
                warn "Could not locate ${SUFFIX[$varname]} file for $varname in $value, skipping."
                unset path_vars[$varname]
            else
                path_vars[$varname]="$resolved"
            fi
        else
            warn "No path provided for $varname, skipping."
            unset path_vars[$varname]
        fi
    done

    # --- Check binary ---
    local binary_path="$outdir/compiled/$binary_name"
    [[ ! -x "$binary_path" ]] && error "Binary not found or not executable: $binary_path"

    # --- Build mpirun command ---
    local cmd=(
#        srun
#        --mpi=pmix_v3
        mpirun
#        --np "$numProcess"
#        --map-by ppr:${ranks_per_node}:node
#        --bind-to none
#        --map-by core
#        --report-bindings
        --np "$numProcess"
        --map-by socket
        --report-bindings
        "$binary_path"
        -n "$steps"
        -f "${path_vars[initialConditionPath]}"
        -C "${path_vars[configPath]}"
        -o "$outdir"
        -v "$verbose"
    )

    # Append material path if available
    [[ -n "${path_vars[materialPath]}" ]] && cmd+=( -m "${path_vars[materialPath]}" )

    # --- Return command ---
    printf '%q ' "${cmd[@]}"
    return 0
}


get_name_completeMode(){
  local modealias="$1"
  local mode=""

  case "$modealias" in
    disc)   mode="alloy_disc_colliding_plate" ;;
    rings)   mode="colliding_rings" ;;
    kelvin)  mode="kelvin-helmholtz" ;;
    all) mode="${VALID_MODES[*]}";;
    *) mode="$modealias" ;;
  esac

  echo "$mode"
  return 0
}

get_layer(){
  local kind="${1:-"-"}"
  local lvl="$2"
  local mode="${3:-"-"}"
  local typ="${4:-"-"}"
  local sep="${5:-"-"}"

  local date="${execute_date:-$(date +%Y%m%d)}"
  local branch="${git_branch:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git-branch")}"

  case "$kind" in
    short)
      case "$lvl" in
        0)
          echo ""
          ;;
        1)
          echo "${date}"
          ;;
        2)
          echo "${branch}"
          ;;
        3)
          echo "${mode}"
          ;;
        4)
          echo "${typ}"
          ;;
        *)
          echo "Invalid level: $lvl" >&2
          return 1
          ;;
      esac
    ;;
    long)
      case "$lvl" in
        0)
          echo ""
          ;;
        1)
          echo "${date}"
          ;;
        2)
          echo "${date}${sep}${branch}"
          ;;
        3)
          echo "${date}${sep}${branch}${sep}${mode}"
          ;;
        4)
          echo "${date}${sep}${branch}${sep}${mode}${sep}${typ}"
          ;;
        *)
          echo "Invalid level: $lvl" >&2
          return 1
          ;;
      *)
        echo "Invalid case: $kind" >&2
        return 1
      esac
    ;;
  esac
}

get_name_binary(){
  local mode="$1"
  local lvl="${2:-"3"}"
  local typ="${3:-"-"}"
  local sep="${4:-${SEPARATOR[name]}}"
  local prefix="${5:-"exe"}"

  echo "${prefix}${sep}$(get_layer "short" "$lvl" "$mode" "$typ" "$sep")"
  return 0
}

get_name_submitFile() {
  local prefix="${1:-"submit"}"
  local lvl="$2"
  local mode="${3:-"-"}"
  local typ="${4:-"-"}"
  local extension="${5:-"slurm"}"
  local sep="${6:-${SEPARATOR[name]}}"

  echo "$(get_name_job "$prefix" "$lvl" "$mode" "$typ" "$sep")${SEPARATOR[extension]}${extension}"
  return 0
}

get_name_job() {
  local prefix="${1:-""}"
  local lvl="$2"
  local mode="${3:-"-"}"
  local typ="${4:-"-"}"
  local sep="${5:-${SEPARATOR[name]}}"

  echo "${prefix}${sep}$(get_layer "short" "$lvl" "$mode" "$typ" "$sep" )"
  return 0
}

get_name_logFile() {
  local prefix="${1:-""}"
  local lvl="$2"
  local mode="${3:-"-"}"
  local typ="${4:-"-"}"
  local extension="${5:-"log"}"
  local sep="${6:-${SEPARATOR[name]}}"

  echo "$(get_name_job "$prefix" "$lvl" "$mode" "$typ" "$sep" )${SEPARATOR[extension]}${extension}"
  return 0
}

get_path_outputRootDir() {
  local prefix="${1:-"output"}"
  local lvl="$2"
  local mode="${3:-"-"}"
  local typ="${4:-"-"}"
  local sep="${5:-${SEPARATOR[path]}}"

  echo "${prefix}${sep}$(get_layer "long" "$lvl" "$mode" "$typ" "$sep")${sep}"
  return 0
}

get_path_logDir(){
  local prefix="${1:-"output"}"
  local lvl="$2"
  local mode="${3:-"-"}"
  local typ="${4:-"-"}"
  local sep="${5:-${SEPARATOR[path]}}"
  local extension="${6:-"log"}"

  echo "$(get_path_outputRootDir "$prefix" "$lvl" "$mode" "$typ" "$sep")${sep}${extension}${sep}"
  return 0
}

get_range_min() {
  local key="$1"
  [[ -z "${RANGES[$key]}" ]] && return 1
  local min
  min=$(echo "${RANGES[$key]}" | grep -oE 'min=[0-9]+' | cut -d= -f2)
  echo "$min"
}

get_range_max() {
  local key="$1"
  [[ -z "${RANGES[$key]}" ]] && return 1
  local max
  max=$(echo "${RANGES[$key]}" | grep -oE 'max=[0-9]*' | cut -d= -f2)
  echo "$max"
}

get_acronym() {
    local name="$1"
    local count="${2:-2}"  # Anzahl Buchstaben, standardmäßig 2
    local short=""

    IFS="_" read -ra parts <<< "$name"

    for part in "${parts[@]}"; do
        [[ -n "$part" ]] && short+="${part:0:1}"
        (( ${#short} >= count )) && break
    done

    # Falls kein Unterstrich, nur ersten Buchstaben
    [[ -z "$short" && -n "$name" ]] && short="${name:0:1}"

    echo "$short"
}
