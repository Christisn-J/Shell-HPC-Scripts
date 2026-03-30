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

get_cmd_mpirun() {
    local mode="$1"
    local outdir="$2"
    local initialPath="$3"
    local configPath="$4"
    local materialPath="$5"
    local n="${steps:-10}"
    local verbose="${flag_verbose:-3}"

    local date="${execute_date:-$(date +%Y%m%d)}"
    execute_date="$date"

    # Validate input parameters
    [[ -z "$mode" ]] && error "get_cmd_mpirun: mode not set"
    [[ -z "$outdir" ]] && error "get_cmd_mpirun: output directory not set"
    [[ -z "$initialPath" ]] && error "get_cmd_mpirun: init file not set"
    [[ -z "$configPath" ]] && error "get_cmd_mpirun: config file not set"
    [[ -z "$materialPath" ]] && error "get_cmd_mpirun: material file not set"

    # Determine binary name
    local binary_name
    binary_name="$(get_name_binary "$mode")" || error "Could not determine binary name for mode: $mode"

    # Determine initial condition file path
    local initial_path
    initial_path="$(get_filePath "--inFile" "$initialPath" ".h5")" || error "Could not locate .h5 initial condition file"
    [[ ! -f "$initialPath" ]] && error "Missing init file: $initialPath"

    # Validate config files
    local config_path
    config_path="$(get_filePath "--inFile" "$configPath" ".info")" || error "Could not locate .info initial condition file"

    [[ ! -f "$config_path" ]] && error "Missing config file: $config_path"
    local material_path
    material_path="$(get_filePath "--inFile" "$materialPath" ".cfg")" || error "Could not locate .cfg initial condition file"

    [[ ! -f "$material_path" ]] && error "Missing material file: $material_path"

    # Check binary existence
    local binary_path="./bin/$binary_name"
    if [[ ! -x "$binary_path" ]]; then
        error "Binary not found or not executable: $binary_path"
    fi

    # Build mpirun command as an array
    local cmd=(
        mpirun
        --map-by socket
        --bind-to core
        --report-bindings
        "$binary_path"
        -n "$n"
        -f "$initial_path"
        -C "$config_path"
        -m "$material_path"
        -o "$outdir"
        -v "$verbose"
    )

    # Output the command as a safe, quoted string
    printf '%q ' "${cmd[@]}"
    echo
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

get_name_binary(){
  local mode="$1"
  local date="${execute_date:-$(date +%Y%m%d)}"
  local branch="${git_branch:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git-branch")}"
  local prefix="exe"
  echo "${prefix}_${date}_${branch}_${mode}"
  return 0
}

get_name_submitFile() {
  local lvl="$1"
  local mode="${2:-"-"}"
  local scale="${3:-"scale"}"
  local extension="${4:-slurm}"
  local prefix="submit"

  local date="${execute_date:-$(date +%Y%m%d)}"
  local branch="${git_branch:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git-branch")}"

  case "$lvl" in
    0)
      echo "${prefix}${extension}"
      ;;
    1)
      echo "${prefix}_${date}${sep}${extension}"
      ;;
    2)
      echo "${prefix}_${date}_${branch}${extension}"
      ;;
    3)
      echo "${prefix}_${date}_${branch}_${mode}${extension}"
      ;;
    4)
      echo "${prefix}_${date}_${branch}_${mode}_${scale}${extension}"
      ;;
    *)
      echo "Invalid level: $lvl" >&2
      return 1
      ;;
  esac

  return 0
}

get_name_jop() {
  local lvl="$1"
  local mode="${2:-"-"}"
  local scale="${3:-"scale"}"

  # Gemeinsame Variablen
  local date="${execute_date:-$(date +%Y%m%d)}"
  local branch="${git_branch:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git-branch")}"

  case "$lvl" in
    1)
      echo "${date}_execute"
#      echo "${date}"
      ;;
    2)
      echo "${branch}_branch"
#      echo "${branch}_${date}"
      ;;
    3)
      echo "${mode}_testcase"
#      echo "${mode}_${branch}_${date}"
      ;;
    4)
      echo "${scale}_${mode}"
#      echo "${mode}_${branch}_${date}_scale"
      ;;
    *)
      echo "Invalid level: $lvl" >&2
      return 1
      ;;
  esac
  return 0
}

get_name_logFile() {
  local lvl="$1"
  local mode="${2:-"-"}"
  local scale="${3:-"scale"}"
  local extension="${4:-".log"}"

  echo "$(get_name_jop "$lvl" "$mode" "$scale")${extension}"

  return 0
}

get_path_outputRootDir() {
  local lvl="$1"
  local mode="${2:-"-"}"
  local scale="${3:-"scale"}"
  local prefix="output/"


  local date="${execute_date:-$(date +%Y%m%d)}"
  local branch="${git_branch:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git-branch")}"

  case "$lvl" in
    0)
      echo "${prefix}/"
      ;;
    1)
      echo "${prefix}/${date}/"
      ;;
    2)
      echo "${prefix}/${date}/${branch}/"
      ;;
    3)
      echo "${prefix}/${date}/${branch}/${mode}/"
      ;;
    4)
      echo "${prefix}/${date}/${branch}/${mode}/${scale}/"
      ;;
    *)
      echo "Invalid level: $lvl" >&2
      return 1
      ;;
  esac
  return 0
}

get_path_logDir(){
  local lvl="$1"
  local mode="${2:-"-"}"
  local prefix="output/"
  local extension="log/"

  echo "$(get_path_outputRootDir "$lvl" "$mode" "$prefix")/${extension}/"
}