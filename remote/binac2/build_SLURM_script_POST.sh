#!/bin/bash
main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"

  layer=3

  mode="$(get_name_completeMode "$1")"
  check_valid_mode "$mode" "${VALID_MODES[@]}"
  shift

  while [[ $# -gt 0 && "$1" == -* ]]; do
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

      -h|--help)
         usage "$flag_color"
         exit 0
         ;;

      --paths)
        shift
        check_arg "--paths" "$1"

        IFS=',' read -ra path_args <<< "$1"  # Zerlege den String bei Kommas

        for key in "${path_args[@]}"; do
          case "$key" in
            initial=*)   initialConditionPath="${key#initial=}" ;;
            resource=*)  resourcePath="${key#resource=}" ;;
            config=*)    configPath="${key#config=}" ;;
            material=*)  materialPath="${key#material=}" ;;
            parameter=*) parameterPath="${key#parameter=}" ;;
            *)
              error "Unknown path keyword in --paths: $key"
              ;;
          esac
        done

        shift
        ;;
        --names)
        shift
        check_arg "--names" "$1"
        IFS=',' read -r jobName <<< "$1"
        if [[ -z "$jobName" ]]; then
          error "--names requires exactly 1 comma-separated values: <jobName>"
        fi
        shift
        ;;
      --submitScript)
        shift
        check_arg "--submitScript" "$1"
        submitScript="$1"
        shift
        ;;
      -o|--output)
        shift
        check_arg "--output" "$1"
        outputDir="$1"
        shift
        ;;

      *)
        logger "[Error]" red "Unknown option: $1"
        usage "$flag_color"
        exit 1
        ;;
    esac
  done

  # -----------------------------
  # Validation
  # -----------------------------
#  [[ -z "$mode" ]] && { error "Mode not specified"; usage; exit 1; }
#  [[ -z "$outputDir" ]] && { error "Output directory not specified"; usage; exit 1; }
#  [[ -z "$submitScript" ]] && submitScript="submit_post_${mode}.slurm"
#  [[ -z "$jobName" ]] && jobName="p_${mode}"

  set_paths "$mode" initialConditionPath resourcePath configPath materialPath

  if [[ -z "$submitScript" ]]; then
    submitScript="$(get_name_submitFile "submit_post" $layer "$mode" "$(basename $initialConditionPath .h5)" "slurm")"
    warn "No submit name given. Falling back to: $submitScript"
  else
    submitScript="$submitScript"
  fi

  if [[ -z "$outputDir" ]]; then
    outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "$(basename $initialConditionPath .h5)")"
    warn "No output directory given. Falling back to: $outputDir"
  else
    outputDir="$outputDir"
  fi
  mkdir -p "${outputDir}/log"

  if [[ -z "$jobName" ]]; then
    jobName="$(get_name_job "post" "$layer" "$mode" "$(basename $initialConditionPath .h5)")"
    warn "No job name given. Falling back to: $jobName"
  else
    jobName="$jobName"
  fi

  mkdir -p "$outputDir/log"

  # -----------------------------
  # SLURM script generation
  # -----------------------------
  cat > "$submitScript" << EOF
#!/bin/bash
#SBATCH --job-name=${jobName}
#SBATCH --output="${outputDir}/log/%x.%j.out"
#SBATCH --error="${outputDir}/log/%x.%j.err"
#SBATCH --partition=development
#SBATCH --time=24:00:00
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

# Environment
export LD_LIBRARY_PATH="\${HOME}/local/lib:\${LD_LIBRARY_PATH}"

info "Starting postprocessing for mode: ${mode}"
EOF

  cmd=("${LOCATIONS[script]}/execute_total_postprocessing.sh" "$mode" --directory "$outputDir" -v "$flag_verbose")
  [[ "$flag_color" == true ]] && cmd+=( --color )

  cat >> "$submitScript" << EOF
execute ${cmd[@]} --exe
EOF

  chmod +x "$submitScript"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
return 0