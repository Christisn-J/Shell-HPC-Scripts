#!/bin/bash
usage() {
  echo -e "Usage: $0 <mode> [OPTIONS]"
  echo
  echo "Run postprocessing for simulation data."
  echo
  echo "Available modes:"
  for m in "${VALID_MODES[@]}"; do
    echo "  $m"
  done
  echo
  echo "Options:"
  echo "  -d, --directory <folder>   Output folder path (relative or absolute)"
  echo "  -v, --verbose <N>          Verbosity level (integer, default: 3)"
  echo "  -c, --color                Enable color output"
  echo "  --date <YYYYMMDD>          Override execution date (default: today)"
  echo "  --plane <plane>            Specify slice plane (e.g., xy, yz, xz)"
  echo "  --skip <phases>            Skip processing phases (comma-separated list, e.g., 1,3)"
  for i in "${!PHASES[@]}"; do
        printf "                                %d - %s\n" "$i" "${PHASES[$i]}"
  done
  echo "  -h, --help                 Show this help message and exit"
  echo
  echo "Example:"
  echo "  $0 sedov -d output/sim1 -v 4 --plane xy --skip 1,3"
  echo
}

contain_files() {
  local mode="${1:---all}"    # either --all or --only
  local ext="$2"

  info "Contained files in folder: $folder"

  shopt -s nullglob
  for file in "$folder"/*; do
    if [ -f "$file" ]; then
      filename=$(basename "$file")
      name_without_extension="${filename%.*}"
      extension="${filename##*.}"

      if [[ "$mode" == "--only" && "$extension" != "$ext" ]]; then
        continue
      fi

      verbose 4 "File: $name_without_extension (.$extension)"
    fi
  done
  shopt -u nullglob
}

create_or_activate_env(){
  if [ ! -d ".venv" ]; then
    warn "Virtual environment '.venv' not found. Creating now..."

    if ! command -v python3 &>/dev/null; then
      error "python3 is not installed. Please install python3."
    fi

    python3 -m venv .venv || error "Failed to create virtual environment."

    info "Upgrading pip..."
    source .venv/bin/activate
    pip install --upgrade pip || warn "Could not upgrade pip."

    info "Installing required Python packages..."
    pip install numpy matplotlib h5py scipy || error "Failed to install required Python packages."

  else
    info "Activating existing virtual environment '.venv'"
    source .venv/bin/activate
  fi
}

main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
   DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
   SOURCE="$(readlink "$SOURCE")"
   [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"
  source "${LOCATIONS[script]}/execute_snapshot2png.sh"

  mode="$(get_name_completeMode "$1")"
  check_valid_mode "$mode" "${VALID_MODES[@]}"
  shift

  layer=3
  scriptPath="${LOCATIONS[script]}/execute_snapshot2png.sh"

  # Parse flags
  while [[ $# -gt 0 && "$1" == -* ]]; do
    case "$1" in
      -c|--color)
         flag_color=true
         shift
         ;;
      --layer)
        shift
        check_arg "--layer" "$1"
        check_natural_numbers "--layer" "$1" "$(get_range_min layer)" "$(get_range_max layer)"
        layer="$1"
        shift
        ;;
       -v|--verbose)
         shift
         check_arg "--skip" "$1"
         check_natural_numbers "--verbose" "$(get_range_min skip)" "$(get_range_max skip)"
         flag_verbose="$1"
         shift
         ;;
       --skip)
         shift
         check_arg "--skip" "$1"
         check_skip skip_phases "$1" "$(get_range_min skip)" $(( ${#PHASES[@]} - 1 ))
         shift
         ;;
       -h|--help)
         usage "$flag_color"
         exit 0
         ;;

      --date)
        shift
        execute_date=$1
        shift
        ;;
      --plane)
        shift
        plane="$1"
        shift
        ;;
      -d|--directory)
        shift
        check_arg "--directory" "$1"
        if [[ "$1" = /* ]]; then
          # Absoluter Pfad, also nicht an PROJECT_ROOT anhängen
          CHECK_DIR="$1"
        else
          # Relativer Pfad, an PROJECT_ROOT anhängen
          CHECK_DIR="${LOCATIONS[root]}/$1"
        fi
        if [ ! -d "$CHECK_DIR" ]; then
          error "\"$CHECK_DIR\" is not a valid directory."
        fi
        folder="$CHECK_DIR"
        shift
        ;;

      *)
        logger "[Error]" red "Unknown option: $1"
        usage "$flag_color"
        exit 1
        ;;
    esac
  done

  if [[ -z "$folder" ]]; then
    set_paths "$mode" initialConditionPath
    folder="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "$(basename $initialConditionPath .h5)")"
    warn "No output directory given. Falling back to: $folder"
  else
    folder="$folder"
  fi

  # Main logic to process based on the mode
  contain_files --only "h5"

  # --- Count .h5 Files (like Steps Count Phase) ---
  info "Checking number of timestep .h5 files in '$folder'"
  step_files_count=$(find "$folder" -type f -name 'ts*.h5' | wc -l)

  if (( step_files_count > 0 )); then
    info "Number of timestep .h5 files found: $step_files_count"
  else
    error "No timestep .h5 files found in $folder"
  fi


  pids=()             # Für Hintergrundprozesse
  pid_phase_map=()    # Optional: Phase pro PID für Logging

  for i in $(printf "%s\n" "${!PLOT_TYP[@]}" | grep -E '^[0-9]+$' | sort -n); do
    info "Start post-processing $i (${PLOT_TYP[$i]}) in the background..."
    cmd=("$scriptPath" "$mode" -d "$folder" -p "$i" -v "$flag_verbose")
    [[ "$flag_color" == true ]] && cmd+=( --color )
    [[ -n "${skip_phases[*]}" ]] && cmd+=( --skip "$(IFS="${SEPARATOR[list]}"; echo "${skip_phases[*]}")" )
    [[ -n "$plane" ]] && cmd+=( --plane "$plane" )

    (
      export POST_KEY="$i"
      execute "${cmd[@]}" --exe
    ) &

    pid=$!
    pids+=("$pid")
    pid_phase_map["$pid"]="$i"
  done


  # ---------------------- Warte auf Prozesse ----------------------
  for pid in "${pids[@]}"; do
    if wait "$pid"; then
      phase="${pid_phase_map[$pid]}"
      success "Phase $phase (PID $pid) finished successfully."
    else
      phase="${pid_phase_map[$pid]}"
      error "Phase $phase (PID $pid) failed!"
    fi
  done

  unset POST_KEY
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0