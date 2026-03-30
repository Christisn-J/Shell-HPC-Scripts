#!/bin/bash

usage() {
cat <<EOF
Usage: $(basename "$0") [options]

This script generates and submits a SLURM job that runs
execute_total_verification.sh.

Options:
  -v, --verbose <N>       Verbosity level
  -c, --color             Enable colored output
  --skip <LIST>           Skip phases (comma-separated)
  -d, --directory <DIR>   Target directory
  --dry                   Dry run (do not submit)
  -h, --help              Show this help
EOF
}

cleanup() {
  # --- Tidy Up Phase ---
  info "Running final tidy-up ..."
  t0=$(start_timer)
  cmd=( "${LOCATIONS[script]}/execute_tidy_up.sh" "scale" --output "$outputDir" --submitScript "$submitScript" -v "$flag_verbose" --skip 0,1,3)
  [[ "$flag_color" == true ]] && cmd+=( --color )
  execute "${cmd[@]}" --exe || error "Failed to tidy up."
  t1=$(end_timer "$t0")
  trace "⏱ Tidy Up-Phase duration: $(format_timer "$t1")"
}

main() {

  # --------------------------------------------------
  # Resolve script path
  # --------------------------------------------------
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  SCRIPT_DIR="$(dirname "$SOURCE")"

  source "$SCRIPT_DIR/load_setup_shell.sh"

  scriptPath="${LOCATIONS[script]}/execute_total_verification.sh"

  # --------------------------------------------------
  # Default values
  # --------------------------------------------------
  skip_phases=()
  outputDir=""

  layer=3

  # --------------------------------------------------
  # Argument parsing
  # --------------------------------------------------
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--verbose)
        check_arg "--verbose" "$2"
        flag_verbose="$2"
        shift 2
        ;;
      -c|--color)
        flag_color=true
        shift
        ;;
      --skip)
        check_arg "--skip" "$2"
        skip_phases="$2"
        shift 2
        ;;
      -d|--directory)
        check_arg "--directory" "$2"
        outputDir="$2"
        shift 2
        ;;
      --dry)
        flag_dry=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        ;;
    esac
  done
  overall_start=$(start_timer)

  # --------------------------------------------------
  # Directory fallback
  # --------------------------------------------------
  if [[ -z "$outputDir" ]]; then
      outputDir="${LOCATIONS[root]}/output/${execute_date}/overall"
  fi

  mkdir -p "$outputDir/log"

  submitScript="submit_verification.slurm"
  jobName="$(get_name_job "v" "$layer" "verification" "-")"

  # --------------------------------------------------
  # Create SLURM script
  # --------------------------------------------------
  cat > "$submitScript" <<EOF
#!/bin/bash
#SBATCH --job-name=${jobName}
#SBATCH --output=${outputDir}/log/%x.%j.out
#SBATCH --error=${outputDir}/log/%x.%j.err
#SBATCH --time=${SLURM_OPTS[time]}
#SBATCH --nodes=${SLURM_OPTS[nodes]}
#SBATCH --ntasks=${SLURM_OPTS[ntasks]}
#SBATCH --cpus-per-task=${SLURM_OPTS[cpus_per_task]}
#SBATCH --mem=${SLURM_OPTS[mem]}
#SBATCH --partition=${SLURM_OPTS[partition]}

source ~/.bashrc
source "${SCRIPT_DIR}/load_setup_shell.sh"

cd "\$SLURM_SUBMIT_DIR" || exit 1

module purge
EOF

  # --------------------------------------------------
  # module.info laden (wie bei deinen anderen Skripten)
  # --------------------------------------------------
  if [[ -f "${LOCATIONS[script]}/module.info" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      for entry in $line; do
        module=$(echo "$entry" | sed -E 's/^[0-9]+\)//')
        [[ -n "$module" ]] && echo "module load $module" >> "$submitScript"
      done
    done < "${LOCATIONS[script]}/module.info"
  fi

  # --------------------------------------------------
  # Command construction
  # --------------------------------------------------
  cat >> "$submitScript" <<EOF

module list
EOF


  cmd=("$scriptPath" --directory "$outputDir" -v "${flag_verbose}")
  [[ "$flag_color" == true ]] && cmd+=( --color )
  [[ "$flag_dry" == true ]] && cmd+=( --dry )
  [[ -n "${skip_phases[*]}" ]] && cmd+=( --skip "$(IFS="${SEPARATOR[list]}"; echo "${skip_phases[*]}")" )
  echo "execute ${cmd[@]} --exe" >> "$submitScript"

  # Mache das SLURM-Skript ausführbar
  chmod +x "$submitScript"
  info "Sende Job-Skript an SLURM: $submitScript"

  # Sende das Job-Skript an SLURM
  sbatch "$submitScript"

  trap cleanup EXIT

  # --- Dauer ausgeben ---
  total_duration=$(end_timer "$overall_start")
  trace "Submit SLURM-Job in $(format_timer "$total_duration")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi