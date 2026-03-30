#!/bin/bash
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

This script generates and submits a SLURM job script to run all test cases.
It resolves paths, loads required modules from 'module.info',
and builds a SLURM-compatible submission script.

Options:
  --steps <n>        Number of steps to pass to submit_testcases_all.sh (default: 10)
  -v, --verbose      Enable verbose output (increases verbosity level)
  --color            Enable colored output (if terminal supports it)
  -h, --help         Show this help message and exit
EOF
}
# === Default SLURM flags ===
declare -A slurm_opts=(
  [partition]="compute"
  [time]="00:30:00"
  [mem]="512G"
  [mail_user]="christian.jetter@student.uni-tuebingen.de"
)

main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"
  PREFIX="$(realpath "$SCRIPT_DIR")"

  SCRIPT="$SCRIPT_DIR/submit_initial.sh"
  layer=1

  # Parse command-line arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--color)
        flag_color=true
        shift
        ;;
      --layer)
        shift
        layer="$1"
        shift
        ;;
      --steps)
        shift
        check_arg "--steps" "$1"
        if [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
          steps="$1"
        else
          error "Invalid value for --steps: must be a positive integer."
        fi
        shift
        ;;
      -v|--verbose)
        shift
        check_arg "--verbose" "$1"
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          flag_verbose="$1"
        else
          error "Invalid value for --verbose: must be a positive integer."
        fi
        shift
        ;;
      -h|--help)
        usage "$flag_color"
        exit 0
        ;;
      *)
        logger "[Error]" red "Unknown option: $1"
        usage "$flag_color"
        exit 1
        ;;
    esac
  done
  # --- Timer starten ---
  overall_start=$(start_timer)

  outputDir="$(get_path_outputRootDir "$layer" "-" "-")"
  mkdir -p "$outputDir/log/"

  for mode in "${VALID_MODES[@]}"; do
    # Build SLURM options string
    opts_string=""
    for key in "${!slurm_opts[@]}"; do
      opts_string+="${key}=${slurm_opts[$key]} "
    done
    opts_string="${opts_string%" "}"

    cmd=("$SCRIPT" "$mode" -v "${flag_verbose}" --output "$outputDir" --opts "$opts_string")
    [[ "$flag_color" == true ]] && cmd+=( --color )
    execute "${cmd[@]}" --exe
  done

  # --- Dauer ausgeben ---
  total_duration=$(end_timer "$overall_start")
  trace "SLURM-Job-Skript zu submit_all_branches.sh erstellt und abgeschickt in $(format_timer "$total_duration")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0
