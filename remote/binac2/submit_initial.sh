#!/bin/bash
declare -A slurm_opts=(
  [partition]="compute"
  [time]="00:30:00"
  [mem]="512G"
  [cpus_per_task]="1"
  [ntasks]="1"
  [nodes]="1"
  [mail_type]="ALL"
  [mail_user]="christian.jetter@student.uni-tuebingen.de"
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

This script generates and submits a SLURM job to run alloy testcases.

Options:
  --partition <name>  SLURM partition to use (default: compute)
  --time <hh:mm:ss>   Time limit for the job (default: 02:00:00)
  -v, --verbose       Increase verbosity
  -h, --help          Show this help and exit
  "Available testcases (auto-detected):"
  "  ${VALID_MODES[*]}"
EOF
}

cleanup() {
  # --- Tidy Up Phase ---
  info "Running final tidy-up ..."
  t0=$(start_timer)
  cmd=( "${LOCATIONS[script]}/execute_tidy_up.sh" "$mode" --output "$outputDir" --submitScript "$submitScript" -v "$flag_verbose" --skip 0,1,3)
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

  mode="$(get_name_completeMode "$1")"
  check_valid_mode "$mode" "${VALID_MODES[@]}"
  shift

  layer=1

  # === Parse arguments ===
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--verbose)
        shift
        flag_verbose=$1
        shift
        ;;
      -o|--output)
        shift
        check_arg "--output" "$1"
        outputDir="$1"
        shift
        ;;
      -c|--color)
        flag_color=true
        shift
        ;;
      --opts)
        IFS=' ' read -r -a opt_array <<< "$2"
        for opt in "${opt_array[@]}"; do
          key="${opt%%=*}"
          value="${opt#*=}"
          if [[ -v slurm_opts[$key] ]]; then
            slurm_opts[$key]="$value"
          else
            warn "Unknown SLURM option: $key"
          fi
        done
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log "[Error]" "red" "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
  overall_start=$(start_timer)

  if [[ -z "$outputDir" ]]; then
    outputDir="$(get_path_outputRootDir 1 "-" "-" "-")"
    warn "No output directory given. Falling back to: $outputDir"
  else
    outputDir="$outputDir"
  fi
  mkdir -p "${outputDir}/log"

  jobName="$(get_name_job $layer "initial_${mode}" "-")"
  submitScript="$(get_name_submitFile $layer "initial_${mode}" "-" "${separator}slurm")"

  case "$mode" in
    alloy_disc_colliding_plate)
      dim=2
      delta_main="1.0e-3"
      delta_strong="1.0e-3"
      ;;
    alloy_sphere_colliding_cube)
      dim=3
      delta_main="0.4e-2"
      delta_strong="0.4e-2"
      ;;
    *)
      error "Mode '$mode' is not implemented yet."
      ;;
  esac

  # === Generate SLURM script ===
  cat > "$submitScript" <<EOF
  #!/bin/bash
  #SBATCH --job-name=${jobName}
  #SBATCH --output=${outputDir}/log/%x.%j.out
  #SBATCH --error=${outputDir}/log/%x.%j.err
  #SBATCH --time=${slurm_opts[time]}
  #SBATCH --nodes=${slurm_opts[nodes]}
  #SBATCH --ntasks=${slurm_opts[ntasks]}
  #SBATCH --cpus-per-task=${slurm_opts[cpus_per_task]}
  #SBATCH --mem=${slurm_opts[mem]}
  #SBATCH --partition=${slurm_opts[partition]}
  #SBATCH --mail-type=${slurm_opts[mail_type]}
  #SBATCH --mail-user=${slurm_opts[mail_user]}

  source ~/.bashrc

  cd "\$SLURM_SUBMIT_DIR" || exit 1
  echo "[INFO] Working directory: \$SLURM_SUBMIT_DIR"

  module purge
EOF

  # === Load modules from module.info ===
  if [[ -f "$SCRIPT_DIR/module.info" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      for entry in $line; do
        module=$(echo "$entry" | sed -E 's/^[0-9]+\)//')
        [[ -n "$module" ]] && echo "module load $module" >> "$submitScript"
      done
    done < "$SCRIPT_DIR/module.info"
  fi

  # === SLURM command section ===
  cat >> "$submitScript" <<EOF
  module list

  echo "[INFO] Activate python env..."
  source .venv/bin/activate

  echo "[INFO] Running alloy testcases..."
  rm ${SCRIPT_DIR}/testcases/${mode}/*.{h5,png}
  ./testcases/${mode}/initial_alloy.py -d ${dim} -v ${flag_verbose} -o ${SCRIPT_DIR}/testcases/${mode}/ --delta ${delta_main} --constant 5

  find "${SCRIPT_DIR}/testcases/${mode}/initialCondition/" -type f \( -name "*.h5" -o -name "*.png" \) -delete
  ./testcases/${mode}/initial_alloy.py -d ${dim} -v ${flag_verbose} --set v -o ${SCRIPT_DIR}/testcases/${mode}/initialCondition/

  find "${SCRIPT_DIR}/testcases/${mode}/weakScaling/" -type f \( -name "*.h5" -o -name "*.png" \) -delete
  ./testcases/${mode}/initial_alloy.py -d ${dim} -v ${flag_verbose} --set N -o ${SCRIPT_DIR}/testcases/${mode}/weakScaling/ --constant 5

  rm ${SCRIPT_DIR}/testcases/${mode}/strongScaling/*.{h5,png}
  ./testcases/${mode}/initial_alloy.py -d ${dim} -v ${flag_verbose} -o ${SCRIPT_DIR}/testcases/${mode}/strongScaling --delta ${delta_strong} --constant 5

EOF

  # === Submit SLURM script ===
  chmod +x "$submitScript"

  info "Submitting SLURM job..."
  sbatch "$submitScript"

  trap cleanup EXIT

  total_duration=$(end_timer "$overall_start")
  trace "Submit SLURM-Job in $(format_timer "$total_duration")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0
