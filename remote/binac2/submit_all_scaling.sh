#!/bin/bash

usage() {
  local use_color="${1:-false}"
  declare -A ACTIVE_COLORS=()

  # Farbprofil aktivieren/deaktivieren
  if [[ "$use_color" == true ]]; then
    for key in "${!COLORS[@]}"; do
      ACTIVE_COLORS[$key]="${COLORS[$key]}"
    done
  else
    for key in "${!COLORLESS[@]}"; do
      ACTIVE_COLORS[$key]="${COLORLESS[$key]}"
    done
  fi

  # Arrays in Strings umwandeln
  VALID_MODES_LIST=""
  for mode in "${VALID_MODES[@]}"; do
    VALID_MODES_LIST+="${ACTIVE_COLORS[CYAN]}$mode${ACTIVE_COLORS[RESET]},"
  done

  PHASES_LIST=""
  for i in "${!PHASES[@]}"; do
    PHASES_LIST+="  $i - ${PHASES[$i]}\n"
  done

  cat <<EOF
${ACTIVE_COLORS[BOLD]}Usage:${ACTIVE_COLORS[RESET]}
  ${ACTIVE_COLORS[CYAN]}$(basename "$0")${ACTIVE_COLORS[RESET]} [options]

${ACTIVE_COLORS[BOLD]}Options:${ACTIVE_COLORS[RESET]}
  ${ACTIVE_COLORS[GREEN]}--steps <NUM>${ACTIVE_COLORS[RESET]}        Number of steps to pass (default: ${ACTIVE_COLORS[YELLOW]}10${ACTIVE_COLORS[RESET]})
  ${ACTIVE_COLORS[GREEN]}-v, --verbose <LVL>${ACTIVE_COLORS[RESET]}  Verbosity level (0–3)
  ${ACTIVE_COLORS[GREEN]}-c, --color${ACTIVE_COLORS[RESET]}          Enable colored output
  ${ACTIVE_COLORS[GREEN]}--select <LIST>${ACTIVE_COLORS[RESET]}      Run only selected test modes
  ${ACTIVE_COLORS[GREEN]}--skip <PHASES>${ACTIVE_COLORS[RESET]}      Skip selected test phases
  ${ACTIVE_COLORS[GREEN]}-h, --help${ACTIVE_COLORS[RESET]}           Show this help message
EOF
  # Optional: Liste der verfügbaren Testmodes
  if [[ ${#VALID_MODES[@]} -gt 0 ]]; then
    printf "${ACTIVE_COLORS[BOLD]}Available <LIST>:${ACTIVE_COLORS[RESET]} $VALID_MODES_LIST\n"
  fi

  if [[ ${#PHASES[@]} -gt 0 ]]; then
    printf "${ACTIVE_COLORS[BOLD]}Available <PHASES>:${ACTIVE_COLORS[RESET]}\n$PHASES_LIST"
  fi
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

main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"
  source "${LOCATIONS[script]}/execute_total_scaling.sh"

  layer=2
  scriptPath="${LOCATIONS[script]}/all_scaling.sh"

  # Parse command-line arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--color)
        flag_color=true
        shift
        ;;
      -n|--steps)
        shift
        check_arg "--steps" "$1"
        check_natural_numbers "--steps" "$1" "$(get_range_min steps)" "$(get_range_max steps)"
        steps="$1"
        shift
        ;;
      -np|--process)
        shift
        check_arg "--process" "$1"
        check_natural_numbers "--process" "$1" "$(get_range_min process)" "$(get_range_max process)"
        process="$1"
        shift
        ;;
      -v|--verbose)
        shift
        check_arg "--verbose" "$1"
        check_natural_numbers "--verbose" "$1" "$(get_range_min verbose)" "$(get_range_max verbose)"
        flag_verbose="$1"
        shift
        ;;
      --select)
        shift
        check_arg "--select" "$1"
        check_select selected_modes "$1" "${VALID_MODES[@]}"
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
      *)
        logger "[Error]" red "Unknown option: $1"
        usage "$flag_color"
        exit 1
        ;;
    esac
  done
  # --- Timer starten ---
  overall_start=$(start_timer)

  outputDir="$(get_path_outputRootDir "$PREFIX_OUTPUT" "$layer" "-" "-")"
  mkdir -p "$outputDir/log/"

  submitScript="$(get_name_submitFile "submit_scale" $layer "-" "-" "slurm")"


  completed_modes=()
  acronym=""
  for mode in "${selected_modes[@]}"; do
      mode=$(get_name_completeMode "$mode")
      completed_modes+=("$mode")
      acronym+="$(get_acronym "$mode")"
  done
  jobName="$(get_name_job "s" "3" "${git_branch}_${acronym}" "-")"

  cat > "$submitScript" << EOF
#!/bin/bash
#SBATCH --job-name=${jobName}
#SBATCH --output="${outputDir}/log/%x${SEPARATOR[extension]}%j.out"
#SBATCH --error="${outputDir}/log/%x${SEPARATOR[extension]}%j.err"
#SBATCH --time=${SLURM_OPTS[time]}
#SBATCH --nodes=${SLURM_OPTS[nodes]}
#SBATCH --ntasks=${SLURM_OPTS[ntasks]}
#SBATCH --cpus-per-task=${SLURM_OPTS[cpus_per_task]}
#SBATCH --mem=${SLURM_OPTS[mem]}
#SBATCH --partition=${SLURM_OPTS[partition]}

source ~/.bashrc
source "$( dirname "${SOURCE}" )/load_setup_shell.sh"

cd "\$SLURM_SUBMIT_DIR" || exit 1
info "Working directory: \$SLURM_SUBMIT_DIR"

module purge

EOF

  # module.info zeilenweise einlesen und in echo-Befehle umwandeln
  while IFS= read -r line; do
    # Leere oder kommentierte Zeilen überspringen
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    for entry in $line; do
      module=$(echo "$entry" | sed -E 's/^[0-9]+\)//')
      [[ -n "$module" ]] && echo "module load $module" >> "$submitScript"
    done
  done < "${LOCATIONS[script]}/module.info"

  cat >> "$submitScript" << EOF
module list

export LD_LIBRARY_PATH="\${HOME}/local/lib:\${LD_LIBRARY_PATH}"

export OMPI_MCA_btl="^ofi,openib"
export OMPI_MCA_mtl="^ofi"

info "Checking availability of mpic++:"
which mpic++ || { echo "[Error] mpic++ not found"; exit 1; }
EOF

  cmd=("$scriptPath" --steps "${steps}" --process "${process}" -v "${flag_verbose}" --layer "$((layer + 2))")
  [[ "$flag_color" == true ]] && cmd+=( --color )
  (( ${#completed_modes[@]} > 0 )) && cmd+=( --select "$(IFS="${SEPARATOR[list]}"; echo "${completed_modes[*]}")" )
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
    exit 0
fi
return 0