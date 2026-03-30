#!/bin/bash
usage() {
  echo ""
  echo "Usage: $0 <mode> [OPTIONS] --cmd <command>"
  echo ""
  echo "Generate a SLURM submission script for the specified simulation mode."
  echo ""
  echo "Arguments:"
  echo "  mode                    Simulation mode to run. Available modes:"
  for m in "${VALID_MODES[@]}"; do
    echo "                          - $m"
  done
  echo "  cmd                     Command to execute (if not given, will be auto-generated)"
  echo ""
  echo "Options:"
  echo "  -c, --color             Enable colored output (if supported)"
  echo "  -v, --verbose <LEVEL>   Verbosity level (integer, default: 3)"
  echo "      --steps <N>         Number of simulation steps to run (default: 10)"
  echo "      --date <YYYYMMDD>   Set build or execution date (default: today)"
  echo "      --layer <N>         Layer depth (for naming, default: 3)"
  echo "      --separator <SYM>   Separator symbol for naming (default: .)"
  echo "      --paths <KEY=VAL>   Comma-separated input file paths:"
  echo "                             initial=<FILE>      Initial condition file"
  echo "                             resource=<FILE>     Resource configuration"
  echo "                             config=<FILE>       Config file"
  echo "                             material=<FILE>     Material file"
  echo "                             parameter=<FILE>    Parameter file"
  echo "      --names <JOBNAME>   Set custom SLURM job name"
  echo "      --submitScript <F>  Output filename for the SLURM script"
  echo "  -o, --output <DIR>      Output directory (for logs, binaries, etc.)"
  echo "      --cmd <COMMAND>     Command to execute (can include arguments)"
  echo "  -h, --help              Show this help message and exit"
  echo ""
  echo "Examples:"
  echo "  $0 sedov --steps 100 --cmd './main_sim'"
  echo "  $0 colliding_rings -v 4 --output ./out --cmd './run_me'"
  echo "  $0 kelvin-helmholtz --paths initial=init.h5,config=cfg.json --cmd './main'"
  echo ""
}

# Shows queue overview for SLURM
show_SLURM_mode_overview() {
  debug 4 "Partition Overview (BinAC2 - SLURM):"
  debug 4
  debug 4 "  Choose a partition based on walltime, GPU, and interactive/development needs:"
  debug 4
  debug 4 "  +---------------+----------------+------------------------------------------+----------------------------+"
  debug 4 "  |  Partition    | Max Walltime   | Purpose                                  | Limits                     |"
  debug 4 "  +---------------+----------------+------------------------------------------+----------------------------+"
  debug 4 "  | compute       | 14 days        | Standard CPU jobs                        | Max 2 nodes                |"
  debug 4 "  | gpu           | 14 days        | GPU workloads (A100, A30, H200)          | Check GPU type availability|"
  debug 4 "  | interactive   | 10 hours       | Interactive jobs via salloc              | 1 job per user             |"
  debug 4 "  | development   | 30 minutes     | Short test/development jobs              | Max 1 node                 |"
  debug 4 "  +---------------+----------------+------------------------------------------+----------------------------+"
  debug 4
  debug 4 "  Note:"
  debug 4 "   - Use '--partition' in your SLURM script or let the tool auto-select."
  debug 4 "   - For interactive jobs: use 'salloc --partition=interactive ...'"
  debug 4 "   - Always check actual availability with 'sinfo' or 'scontrol show partition'."
  debug 4
}

show_summary() {
  debug 4 "========== Debug Info =========="
  debug 4 "Generated Script:     $submitScript"
  debug 4 "Simulation Mode:      $mode"
  debug 4 "Git Branch:           $git_branch"
  debug 4 "Execution Date:       $execute_date"
  debug 4 "Command:              $cmd"
  debug 4 "Binary:               $binaryPath"
  debug 4 "Init File:            ${initialConditionPath:-<none>}"
  debug 4 "Resource Config:      ${resourcePath:-default/fallback}"
  debug 4 "Output Directory:     $outputDir"
  debug 4 "Steps:                $steps"
  debug 4 "Verbosity Level:      $flag_verbose"
  debug 4 "Force Enabled:        $flag_force"
  debug 4 "Color Output:         $flag_color"
  verbose 3 "--- Resource Requests ---"
  verbose 3 "Queue Selected:       $JOB_MODE"
  verbose 3 "Nodes:                $NODEs"
  verbose 3 "CPUs:                 $CPUs"
  verbose 3 "GPUs:                 $GPUs"
  verbose 3 "Walltime:             $TIME"
  debug 4 "================================"
}

# Function: Normalize time string to HH:MM:SS format (adds leading zeros if needed)
normalize_time() {
  local parts normalized_time
  IFS=':' read -ra parts <<< "$1"
  case "${#parts[@]}" in
    3)
      # HH:MM:SS, formatiere mit führenden Nullen
      printf -v normalized_time "%02d:%02d:%02d" "${parts[0]}" "${parts[1]}" "${parts[2]}"
      ;;
    2)
      # MM:SS → 00:MM:SS
      printf -v normalized_time "00:%02d:%02d" "${parts[0]}" "${parts[1]}"
      ;;
    1)
      # SS → 00:00:SS
      printf -v normalized_time "00:00:%02d" "${parts[0]}"
      ;;
    *)
      # Fallback-Wert, falls kein gültiges Format
      normalized_time="00:12:00"
      ;;
  esac
  echo "$normalized_time"
}

select_SLURM_jop_mode() {
  local normalized_time h m s total_seconds
  normalized_time=$(normalize_time "$TIME")
  IFS=':' read -r h m s <<< "$normalized_time"

  # Konvertiere sicher in Sekunden
  h=$((10#$h))
  m=$((10#$m))
  s=$((10#$s))
  total_seconds=$((h * 3600 + m * 60 + s))

  # -------- [Interaktive Jobs] --------
#  # interactive: max 1 Job/User, max 10h
#  if (( NODEs <= 1 && total_seconds <= 36000 )); then
#    JOB_MODE="interactive"
#    info "Auto-selected queue: $JOB_MODE (interactive mode)"
#    return
#  else
#    warn "Interactive mode requested, but limits exceeded. Falling back to 'compute'."
#  fi

  # -------- [GPU-Jobs] --------
  if [[ $GPUs -ne 0 && "$GPU_TYPE" =~ ^(a100|a30|h200)$ ]]; then
    # gpu: max 14 Tage Laufzeit, GPU-Typ + Menge müssen passen
    if (( total_seconds <= 1209600 )); then
      JOB_MODE="gpu"
      info "Auto-selected queue: $JOB_MODE (GPU=$GPUs:$GPU_TYPE)"
      return
    else
      warn "Requested GPU job exceeds 14-day limit. Falling back to 'compute'."
    fi
  fi

  # -------- [Entwicklung / Test] --------
  if (( NODEs <= 1 && total_seconds <= 1800 )); then
    # development: <30min, max 1 Node
    JOB_MODE="development"
    info "Auto-selected queue: $JOB_MODE (short development job)"
    return
  fi

  # -------- [Default: CPU-Compute] --------
  # compute: max 2 Nodes, max 14 Tage
  if (( NODEs <= 2 && total_seconds <= 1209600 )); then
    JOB_MODE="compute"
    info "Auto-selected queue: $JOB_MODE (standard CPU job)"
    return
  else
    warn "Request exceeds limits of all known partitions. Please check config. Defaulting to 'compute'."
    JOB_MODE="compute"
  fi
}

# ---------------------------------------------------------------------------
# Function: Check that required variables are set
# ---------------------------------------------------------------------------
check_required_vars() {
  local missing=0
  local var_list=(
    execute_date
    jobName
    outputDir
    NODEs
    NTASKs
    CPUs
    GPU_TYPE
    GPUs
    MEM
    TIME
    JOB_MODE
    SLURM_OPTS[mail_type]
    SLURM_OPTS[mail_user]
    SOURCE
    SLURM_SUBMIT_DIR
  )

  for var in "${var_list[@]}"; do
    # Handle associative array entries
    if [[ "$var" == SLURM_OPTS* ]]; then
      key="${var#SLURM_OPTS[}"
      key="${key%]}"
      [[ -z "${SLURM_OPTS[$key]}" ]] && {
        warn "Required variable SLURM_OPTS[$key] is not set!"
        missing=1
      }
    else
      [[ -z "${!var}" ]] && {
        warn "Required variable '$var' is not set!"
        missing=1
      }
    fi
  done

  if (( missing )); then
    error "One or more required variables are missing. Aborting script generation."
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

  layer=3

  mode="$(get_name_completeMode "$1")"
  check_valid_mode "$mode" "${VALID_MODES[@]}"
  shift

  # Parse command line options
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
      --layer)
        shift
        check_arg "--layer" "$1"
        check_natural_numbers "--layer" "$1" "$(get_range_min layer)" "$(get_range_max layer)"
        layer="$1"
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
      --date)
        shift
        check_arg "--date" "$1"
        if [[ "$1" =~ ^[0-9]{8}$ ]]; then
          execute_date="$1"
        else
          error "Invalid date format: '$1'. Use YYYYMMDD."
        fi
        shift
        ;;
      --cmd)
        shift
        cmd=$1
        shift
        ;;

      *)
        logger "[Error]" red "Unknown option: $1"
        usage "$flag_color"
        exit 1
        ;;
    esac
  done

  set_paths "$mode" initialConditionPath resourcePath configPath materialPath

  if [[ -z "$submitScript" ]]; then
    submitScript="$(get_name_submitFile "submit" $layer "$mode" "$(basename $initialConditionPath .h5)" "slurm")"
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
    jobName="$(get_name_job "test" "$layer" "$mode" "$(basename $initialConditionPath .h5)")"
    warn "No job name given. Falling back to: $jobName"
  else
    jobName="$jobName"
  fi

  binaryPath="$outputDir/compiled/$(get_name_binary "$mode")"

  # Check if binary is executable; exit on failure
  if [[ -x "$binaryPath" ]]; then
    info "Using binary: $binaryPath"
  else
    error "Binary '$binaryPath' not found or not executable! Aborting."
  fi

  # Versuche zuerst benutzerdefinierte Ressourcenkonfiguration zu laden
  verbose 1 "$resourcePath"
  if [[ -n "$resourcePath" ]]; then
    if [[ -f "$resourcePath" ]]; then
      source "$resourcePath"
      info "Loaded custom resource config: '$resourcePath' (NODEs=$NODEs, CPUs=$CPUs, GPUs=$GPUs, NPROCs=$NPROCs, NTASKs=$NTASKs)"
    else
      warn "Custom resource config '$resourcePath' not found."
      set_paths resourcePath
      source "$resourcePath"
      warn "Using fallback '$resourcePath' (NODEs=$NODEs, CPUs=$CPUs, GPUs=$GPUs)"
    fi
  fi

  if [[ -n "$NPROCs" && -n "$NTASKs" && "$NPROCs" -ne "$NTASKs" ]]; then
    warn "NTASKs ($NTASKs) and NPROCs ($NPROCs) differ. Using NTASKs=$NPROCs."
    NTASKs="$NPROCs"
  fi


  # If no command given, generate the default MPI command
  if [[ -z "$cmd" ]]; then
      warn "No command provided. Generating default MPI command..."

      # --- Process count handling (NPROCs vs. --process) ---
      if [[ -n "$NPROCs" ]]; then
        if [[ -n "$process" && "$process" -ne "$NPROCs" ]]; then
          warn "NPROCs is defined in the resource file ($NPROCs) and overrides the --process value ($process)."
        else
          warn "NPROCs is defined in the resource file ($NPROCs) and overrides the default process count."
        fi
        process="$NPROCs"
      fi

      # --- Steps handling (NSTEPs vs. --steps) ---
      if [[ -n "$NSTEPs" ]]; then
        if [[ -n "$steps" && "$steps" -ne "$NSTEPs" ]]; then
          warn "NSTEPs is defined in the resource file ($NSTEPs) and overrides the --steps value ($steps)."
        else
          warn "NSTEPs is defined in the resource file ($NSTEPs) and overrides the default number of steps."
        fi
        steps="$NSTEPs"
      fi

      IFS=${SEPARATOR[cmd]} read -r -a mpi_cmd <<< "$(get_cmd_mpirun "$mode" "$outputDir" "$initialConditionPath" "$configPath" "$materialPath" "$process" "$steps" "$flag_verbose" "$GPUs")"
      cmd="${mpi_cmd[@]}"
      verbose 1 "Fallback to: $cmd"
  else
    info "Using user-provided command: $cmd"
  fi

  info "Time limit is $TIME"
  info "Max memory is $MEM"

  # Select SLURM queue based on requested resources and walltime
  select_SLURM_jop_mode

  check_required_vars

  cat > "$submitScript" << EOF
#!/bin/bash

###############################################################################
## SLURM submission script (auto-generated)
##
## Cluster:        BinAC2 (bwForCluster) 'https://wiki.bwhpc.de/e/BinAC2/Slurm'
## Scheduler:      SLURM
## Generated on:   ${execute_date}
##
## Important Notes:
##  - GPUs are allocated per node via --gres=gpu:<type>:<count>
##  - CUDA_VISIBLE_DEVICES is automatically configured by SLURM
##    → Do not manually set or override it
##  - Use 'srun' to launch parallel MPI jobs. It integrates with SLURM's resource allocation and ensures proper GPU/CPU binding
##  - Avoid using 'mpirun' directly in SLURM jobs unless explicitly required, as it may bypass SLURM's task distribution
##  - OpenMPI process count is controlled by SLURM (avoid manual --np)
###############################################################################

## ------------------------- Job Identification ------------------------------
#SBATCH --job-name=${jobName}                    ## Logical job name
#SBATCH --output="${outputDir}/log/%x${SEPARATOR[extension]}%j.out"  ## STDOUT file
#SBATCH --error="${outputDir}/log/%x${SEPARATOR[extension]}%j.err"   ## STDERR file

## ------------------------- Resource Allocation -----------------------------
#SBATCH --nodes=${NODEs}                         ## Number of physical nodes
#SBATCH --ntasks=${NTASKs}                       ## Total MPI tasks across all nodes
##SBATCH --ntasks-per-node=$(( (NTASKs + NODEs - 1) / NODEs ))  ## Tasks per node (optional)
##SBATCH --cpus-per-task=${CPUs}                 ## Logical CPUs per MPI task (important for HT)

#SBATCH --gres=gpu:${GPU_TYPE}:${GPUs}           ## GPUs per node (e.g. a30:2)
## Total GPUs = nodes × GPUs-per-node

#SBATCH --mem=${MEM}                             ## Memory per node
#SBATCH --time=${TIME}                           ## Walltime limit (HH:MM:SS)

## ------------------------- Partition Selection -----------------------------
#SBATCH --partition=${JOB_MODE}                  ## Selected SLURM partition
## Typical partitions on BinAC2:
##   compute      → Standard CPU jobs (max 2 nodes)
##   gpu          → GPU workloads (A30/A100/H200)
##   interactive  → Interactive sessions (max 10h, 1 job/user)
##   development  → Short test jobs (<30 min)

## ------------------------- Notifications -----------------------------------
#SBATCH --mail-type=${SLURM_OPTS[mail_type]}     ## Email notifications
#SBATCH --mail-user=${SLURM_OPTS[mail_user]}     ## Email address

###############################################################################
## Runtime Environment Setup
###############################################################################

source ~/.bashrc
source "$( dirname "${SOURCE}" )/load_setup_shell.sh"

cd "\$SLURM_SUBMIT_DIR" || exit 1
info "Working directory: \$SLURM_SUBMIT_DIR"

## Clear existing module environment to avoid conflicts
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

###############################################################################
## MPI / CUDA Runtime Configuration
###############################################################################

## Extend local library path
export LD_LIBRARY_PATH="\${HOME}/local/lib:\${LD_LIBRARY_PATH}"

## ---- OpenMPI transport configuration --------------------------------------
## Disable legacy OFI/OpenIB BTL layers to avoid conflicts on BinAC2.
## Communication will be handled via UCX.
export OMPI_MCA_btl="^ofi,openib"
export OMPI_MCA_mtl="^ofi"

## ---- UCX / CUDA communication setup ---------------------------------------
## Disable UCX memory type cache (avoids cuMemHostRegister issues)
export UCX_MEMTYPE_CACHE=n

## Fast node-local GPU communication (recommended for production)
##   sm          → shared memory (CPU↔CPU)
##   cuda_copy   → GPU↔GPU via host memory
##   cuda_ipc    → direct GPU↔GPU on same node
## Uncomment for optimized runs:
## export UCX_TLS=sm,cuda_copy,cuda_ipc

## Fallback mode (robust but slower):
##   tcp   → TCP/IP communication
##   self  → loopback
export UCX_TLS=tcp,self

###############################################################################
## GPU Information
###############################################################################

info "Allocated GPUs:"
EOF
  # List GPUs on all allocated nodes
  if (( flag_verbose <= 3 )); then
    # Führe nvidia-smi -L aus, um GPUs auf allen Knoten anzuzeigen
    echo "mpirun nvidia-smi -L" >> "$submitScript"
  else
    # Führe nvidia-smi aus, wenn detailliertere Ausgabe gewünscht ist
    echo "mpirun nvidia-smi" >> "$submitScript"
  fi

  cat >> "$submitScript" << EOF

###############################################################################
## GPU Monitoring Setup
###############################################################################

## Start background GPU monitoring using nvidia-smi.
## Metrics:
##   p  → power usage
##   u  → GPU utilization
##   c  → compute mode
##   v  → memory usage
##   m  → memory total
##   t  → temperature
## Sampling interval: 5 seconds

info "Start GPU monitoring"

mpirun nvidia-smi dmon -s pucvmt -d 5 > ${outputDir}/log/gpu_usage_\$SLURM_JOB_ID.log &

## Store background process ID
GPU_MON_PID=\$!

## Ensure monitoring process is terminated on job exit or cancellation
trap "kill \$GPU_MON_PID 2>/dev/null || true" EXIT INT TERM

EOF
# ---------------------------------------------------------------------------
# Dump binary metadata and shared library dependencies
# ---------------------------------------------------------------------------
  if [[ -n "$binaryPath" ]]; then
    {
      echo ""
      echo "###############################################################################"
      echo "## Binary Diagnostics"
      echo "###############################################################################"
      echo ""
      echo "info \"Dump library dependencies of binary\""
      echo "ldd ${binaryPath} > ${outputDir}/log/$(basename ${binaryPath})${SEPARATOR[extension]}ldd.log"
      echo "file ${binaryPath} > ${outputDir}/log/$(basename ${binaryPath})${SEPARATOR[extension]}file.log"
      echo ""
    } >> "$submitScript"
  fi


  cat >> "$submitScript" << EOF

###############################################################################
## Simulation Execution
###############################################################################

## Display selected simulation mode
info "Starting simulation with mode: ${mode}"

## Execute main command
execute ${cmd[@]} --exe

###############################################################################
## Cleanup
###############################################################################

info "GPU monitoring stopped"

EOF

  chmod +x "$submitScript"
  show_summary
  info "Generated SLURM script: $submitScript"

  show_SLURM_mode_overview
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0