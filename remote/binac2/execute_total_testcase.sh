#!/bin/bash

declare -a PHASES=(
  [0]="build"
  [1]="submission"
  [2]="monitoring"
  [3]="observe-log"
  [4]="steps-count"
  [5]="postprocessing"
  [6]="tidy-up"
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
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
    VALID_MODES_LIST="${VALID_MODES_LIST%,}"

    PHASES_LIST=""
    NUM_LIST=""
    for i in "${!PHASES[@]}"; do
      PHASES_LIST+="  ${ACTIVE_COLORS[YELLOW]}$i${ACTIVE_COLORS[RESET]} - ${PHASES[$i]}\n"
      NUM_LIST+="${ACTIVE_COLORS[YELLOW]}$i${ACTIVE_COLORS[RESET]},"
    done
    NUM_LIST="${NUM_LIST%,}"
    PHASES_LIST="${PHASES_LIST%,}"

    cat <<EOF
${ACTIVE_COLORS[BOLD]}Usage:${ACTIVE_COLORS[RESET]}
  ${ACTIVE_COLORS[CYAN]}$(basename "$0")${ACTIVE_COLORS[RESET]} <mode> [options]
${ACTIVE_COLORS[BOLD]}Options:${ACTIVE_COLORS[RESET]}
  ${ACTIVE_COLORS[GREEN]}--steps <NUM>${ACTIVE_COLORS[RESET]}        Number of steps to pass (default: ${ACTIVE_COLORS[YELLOW]}10${ACTIVE_COLORS[RESET]})
  ${ACTIVE_COLORS[GREEN]}-v, --verbose <LVL>${ACTIVE_COLORS[RESET]}  Verbosity level (0–3)
  ${ACTIVE_COLORS[GREEN]}-c, --color${ACTIVE_COLORS[RESET]}          Enable colored output
  ${ACTIVE_COLORS[GREEN]}--select <LIST>${ACTIVE_COLORS[RESET]}      Run only selected test modes
  ${ACTIVE_COLORS[GREEN]}--skip <PHASES>${ACTIVE_COLORS[RESET]}      Skip selected test phases
  ${ACTIVE_COLORS[GREEN]}--layer <N>${ACTIVE_COLORS[RESET]}          Layer level for output directory structure (default: 2)"
  ${ACTIVE_COLORS[GREEN]}-h, --help${ACTIVE_COLORS[RESET]}           Show this help message
EOF
    # Optional: Liste der verfügbaren Testmodes
    if [[ ${#VALID_MODES[@]} -gt 0 ]]; then
      printf "${ACTIVE_COLORS[BOLD]}Available <LIST>:${ACTIVE_COLORS[RESET]} $VALID_MODES_LIST\n"
    fi

    if [[ ${#PHASES[@]} -gt 0 ]]; then
      printf "${ACTIVE_COLORS[BOLD]}Available <PHASES>:${ACTIVE_COLORS[RESET]} $NUM_LIST"
      printf "${ACTIVE_COLORS[RESET]}\n$PHASES_LIST"
    fi
  }

  cleanup() {
    # --- Tidy Up Phase ---
    if check_skip_phase 6; then
      info "Skipping tidy-up step (Phase 6)."
    else
      info "Running final tidy-up ..."
      t0=$(start_timer)
      cmd=( "${LOCATIONS[script]}/execute_tidy_up.sh" "$mode" --layer $layer --output "$outputDir" --submitScript "$submitScript_MPI" -v "$flag_verbose" --skip 0)
      [[ -n "$paths_arg" ]] && cmd+=( --paths "$paths_arg" )
      [[ "$flag_color" == true ]] && cmd+=( --color )
      execute "${cmd[@]}" --exe || error "Failed to tidy up."
      t1=$(end_timer "$t0")
      trace "⏱ Tidy Up-Phase duration: $(format_timer "$t1")"
    fi
    # --- Dauer ausgeben ---
    total_duration=$(end_timer "$overall_start")
    trace "⏱ Total duration: $(format_timer "$total_duration")"
    return
  }
fi

handle_SLURM_job_state() {
    local state="$1"
    local prev_state="$2"
    local jobNum="$3"

    # Nur reagieren, wenn sich der Status geändert hat
    [[ "$state" == "$prev_state" ]] && return 0

    PREV_STATE="$state"

    case "$state" in
        PENDING|PD)
            info "($state) Job $jobNum is queued and waiting for resources..."
            ;;
        CONFIGURING|CF)
            info "($state) Job $jobNum is configuring before start..."
            ;;
        RUNNING|R)
            info "($state) Job $jobNum is now running."
            ;;
        SUSPENDED|S)
            info "($state) Job $jobNum is suspended."
            ;;
        COMPLETING|CG)
            info "($state) Job $jobNum is completing."
            ;;
        COMPLETED|CD)
            info "($state) Job $jobNum completed."
            JOB_TERMINATED=true
            ;;
        CANCELLED|CA)
            warn "($state) Job $jobNum was cancelled."
            JOB_TERMINATED=true
            ;;
        FAILED|F)
            error "($state) Job $jobNum failed."
            JOB_TERMINATED=true
            ;;
        TIMEOUT|TO)
            warn "($state) Job $jobNum timed out."
            JOB_TERMINATED=true
            ;;
        NODE_FAIL|NF)
            error "($state) Job $jobNum failed due to node failure."
            JOB_TERMINATED=true
            ;;
        PREEMPTED|PR)
            warn "($state) Job $jobNum was preempted."
            JOB_TERMINATED=true
            ;;
        REQUEUED|RQ)
            info "($state) Job $jobNum was requeued."
            ;;
        RESIZING|RS)
            info "($state) Job $jobNum is resizing resources."
            ;;
        STAGE_OUT|SO)
            info "($state) Job $jobNum is staging out files."
            ;;
        "")
            # Leerer Status wird außerhalb (sacct-Fallback) behandelt
            ;;
        *)
            info "($state) Job $jobNum changed to unknown state."
            ;;
    esac
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

  layer=3
  SLEEP_INTERVAL=1
  SLEEP_DELAY=1

  # Argumente parsen
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

      -o|--output)
        shift
        check_arg "--output" "$1"
        check_valid_path "--output" "$1"
        outputDir="$1"
        shift
        ;;
      --paths)
        shift
        check_arg "--paths" "$1"

        IFS="${SEPARATOR[list]}" read -ra path_args <<< "$1"

        for key in "${path_args[@]}"; do
          case "$key" in
            initial=*)
              check_valid_path "initial" "${key#initial=}"
              initialConditionPath="${key#initial=}" ;;
            resource=*)
              check_valid_path "resourcePath" "${key#resource=}"
              resourcePath="${key#resource=}" ;;
            config=*)
              check_valid_path "config" "${key#config=}"
              configPath="${key#config=}" ;;
            material=*)
              check_valid_path "material" "${key#material=}"
              materialPath="${key#material=}" ;;
            parameter=*)
              check_valid_path "parameter" "${key#parameter=}"
              parameterPath="${key#parameter=}" ;;
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
        IFS="${SEPARATOR[list]}" read -r jobName<<< "$1"
        if [[ -z "$jobName" ]]; then
          error "--names requires exactly 1 comma-separated values: <jobName>"
        fi
        shift
        ;;
      --submitScript)
        shift
        check_arg "--submitScript" "$1"
        submitScript_MPI="$1"
        shift
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

  # --- Configuration ---x
  set_paths "$mode" "${LOCATIONS[root]}" parameterPath
  set_paths "$mode" "${LOCATIONS[setup]}" initialConditionPath resourcePath configPath materialPath

  if [[ -z "$submitScript_MPI" ]]; then
    submitScript_MPI="$(get_name_submitFile "submit" $layer "$mode" "$(basename $initialConditionPath .h5)" "slurm")"
    warn "No submit name given. Falling back to: $submitScript_MPI"
  else
    submitScript_MPI="$submitScript_MPI"
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

  # Dynamisch Pfade sammeln
  paths_arg=""

  [[ -n "$initialConditionPath" ]] && paths_arg+="initial=$initialConditionPath,"
  [[ -n "$resourcePath" ]]         && paths_arg+="resource=$resourcePath,"
  [[ -n "$configPath" ]]           && paths_arg+="config=$configPath,"
  [[ -n "$materialPath" ]]         && paths_arg+="material=$materialPath,"
  [[ -n "$parameterPath" ]]        && paths_arg+="parameter=$parameterPath,"

  # Letztes Komma entfernen (sauberer)
  paths_arg="${paths_arg%,}"

  trap cleanup EXIT

  t0=$(start_timer)
  module purge
  source "${LOCATIONS[script]}/load_modules.sh" || error "Failed to load modules."
  t1=$(end_timer "$t0")
  trace "⏱ Setup-Module-Phase duration: $(format_timer "$t1")"

  # --- Build / Compile Phase ---
  t0=$(start_timer)
  cmd=("${LOCATIONS[script]}/build_binary.sh" "$mode" -v "$flag_verbose" --output "$outputDir" )
  if check_skip_phase 0; then
    warn "Simplified build (Phase 0)"
    cmd+=( --skip 0,1)
  else
    info "Building and running local test for mode: $mode"
  fi
  [[ -n "$paths_arg" ]] && cmd+=( --paths "$paths_arg" )
  [[ "$flag_color" == true ]] && cmd+=( --color )
  [[ -n $execute_date ]] && cmd+=( --date "$execute_date")

  execute "${cmd[@]}" --exe || error "Failed to build binary."

  if [[ -z "${mpi_cmd[@]}" ]]; then
    warn "No command provided. Generating default MPI command..."
    # Versuche zuerst benutzerdefinierte Ressourcenkonfiguration zu laden
    verbose 1 "$resourcePath"
    if [[ -n "$resourcePath" ]]; then
      if [[ -f "$resourcePath" ]]; then
        source "$resourcePath"
        info "Loaded custom resource config: $resourcePath"
      else
        warn "Custom resource config '$resourcePath' not found."
        set_paths resourcePath
        source "$resourcePath"
        warn "Using fallback '$resourcePath' (NODEs=$NODEs, CPUs=$CPUs, GPUs=$GPUs)"
      fi
    fi

   # If no command given, generate the default MPI command
    if [[ -z "$cmd" ]]; then
      warn "No command provided. Generating default MPI command..."

      # --- Process count handling (NP vs. --process) ---
      if [[ -n "$NP" ]]; then
        if [[ -n "$process" && "$process" -ne "$NP" ]]; then
          warn "NP is defined in the resource file ($NP) and overrides the --process value ($process)."
        else
          warn "NP is defined in the resource file ($NP) and overrides the default process count."
        fi
        process="$NP"
      fi

      # --- Steps handling (N vs. --steps) ---
      if [[ -n "$N" ]]; then
        if [[ -n "$steps" && "$steps" -ne "$N" ]]; then
          warn "N is defined in the resource file ($N) and overrides the --steps value ($steps)."
        else
          warn "N is defined in the resource file ($N) and overrides the default number of steps."
        fi
        steps="$N"
      fi
    fi

    IFS=${SEPARATOR[cmd]} read -r -a mpi_cmd <<< "$(get_cmd_mpirun "$mode" "$outputDir" "$initialConditionPath" "$configPath" "$materialPath" "$process" "$steps" "$flag_verbose")"
    verbose 1 "Fallback to: "${mpi_cmd[@]}""
  fi
  t1=$(end_timer "$t0")
  trace "⏱ Build-Phase duration: $(format_timer "$t1")"

  # --- Generate Submit Phase ---
  if check_skip_phase 1; then
    warn "Skipping generate script (Phase 1)."
  else
    t0=$(start_timer)
    cmd=("${LOCATIONS[script]}/build_SLURM_script_MPI.sh" "$mode" --steps "$steps" --process "$process" -v "$flag_verbose" --output "$outputDir" --submitScript "$submitScript_MPI" --names "$jobName" --date "$execute_date")
    [[ -n "$paths_arg" ]] && cmd+=( --paths "$paths_arg" )
    [[ "$flag_color" == true ]] && cmd+=( --color )
  #  [[ -n "$mpi_cmd" ]] && cmd+=( --cmd "${mpi_cmd[*]}" )
    info "Generating SLURM submit script for mode: $mode"
    execute "${cmd[@]}" --exe || error "Failed to generate SLURM submit script (exit code: $?)."

    if [[ ! -f "$submitScript_MPI" ]]; then
      error "SLURM script not found: $submitScript_MPI"
    fi
    t1=$(end_timer "$t0")
    trace "⏱ Generate Submit-Phase duration: $(format_timer "$t1")"
  fi

  # --- Job Submit Phase ---
  if check_skip_phase 1; then
    warn "Skipping job submission (Phase 1)."
  else
    t0=$(start_timer)
    info "Submitting job to queue..."

    # Run sbatch and capture exit code
    SLURM_OUTPUT=$(sbatch "${LOCATIONS[root]}/${submitScript_MPI}" 2>&1)
    SLURM_EXIT_CODE=$?

    debug 0 $SLURM_OUTPUT

    t1=$(end_timer "$t0")
    trace "⏱ Job Submit-Phase duration: $(format_timer "$t1")"
    if [[ $SLURM_EXIT_CODE -eq 0 ]]; then
      SLURM_JOB_ID=$(echo "$SLURM_OUTPUT" | awk '/Submitted batch job/ {print $NF; exit}')

      if [[ ! "$SLURM_JOB_ID" =~ ^[0-9]+$ ]]; then
        error "Could not extract SLURM Job ID from sbatch output: $SLURM_OUTPUT"
      fi

      info "Job submitted successfully. Job ID: $SLURM_JOB_ID"
    else
      error "Job submission failed: $SLURM_OUTPUT"
    fi

    if [[ -z "$SLURM_JOB_ID" ]]; then
        error "Could not extract SLURM Job ID from output: $SLURM_OUTPUT"
    fi

    sleep $SLEEP_DELAY
  fi

  # --- Job Monitoring Phase ---
  if check_skip_phase 2; then
    warn "Skipping job monitoring (Phase 2)."
  else
    t0=$(start_timer)
    jobNum="${SLURM_JOB_ID%%.*}"

    if [[ -z "$jobName" ]]; then
      submitLogfile="${outputDir}/log/$(get_name_logFile "$layer" "${mode}" "scale" "${SEPARATOR[extension]}${jobNum}${SEPARATOR[extension]}out")"
      warn "No job name given. Falling back for logfile to: $submitLogfile"
    else
       submitLogfile="${jobName}${SEPARATOR[extension]}${jobNum}${SEPARATOR[extension]}out"
    fi
    submitErrfile="${submitLogfile%.out}.err"

    # Wait until the job status becomes 'C' (Completed) or disappears from qstat
    info "Waiting for job $jobNum to complete..."
    # Extract walltime from SLURM script
    SLURM_WALLTIME=$(grep "^#SBATCH --time=" "$submitScript_MPI" | cut -d= -f2)

    if [[ "$SLURM_WALLTIME" =~ ^[0-9]{3}:[0-9]{2}:[0-9]{2}$ ]]; then
      IFS=':' read -r hhh mm ss <<< "$SLURM_WALLTIME"
      TOTAL_SECONDS=$((10 + 60 * (mm + 60 * hhh)))  # buffer: 10s
      MAX_RETRIES=$((TOTAL_SECONDS / 5))
    else
      warn "Could not parse walltime from SLURM script. Falling back to default timeout."
      MAX_RETRIES=120  # fallback: 10 min
    fi

    PREV_STATE=""
    JOB_TERMINATED=false

    while true; do
      # 1) Aktuellen SLURM-State abfragen (kann leer sein!)
      SLURM_JOB_STATE=$(squeue -j "$jobNum" -h -o "%T" 2>/dev/null | head -n 1)

      # 2) Status-Handling (Logging + Termination über Funktion)
      handle_SLURM_job_state "$SLURM_JOB_STATE" "$PREV_STATE" "$jobNum"

      # Falls Job durch SLURM-State beendet wurde → raus
      if [[ "$JOB_TERMINATED" == true ]]; then
        break
      fi

      # 3) Job noch in der Queue?
      if [[ -n "$SLURM_JOB_STATE" ]]; then
        sleep "$SLEEP_INTERVAL"
        continue
      fi

      # 4) Job nicht mehr in squeue → sacct ist maßgeblich
      job_state=$(sacct -j "$jobNum" --format=State -n -P 2>/dev/null | head -n 1 | cut -d'|' -f1)

      # sacct kann leicht verzögert sein
      if [[ -z "$job_state" ]]; then
        sleep $SLEEP_DELAY
        job_state=$(sacct -j "$jobNum" --format=State -n -P 2>/dev/null | head -n 1 | cut -d'|' -f1)
      fi

      if [[ -n "$job_state" ]]; then
        case "$job_state" in
          COMPLETED*)
            success "(sacct:$job_state) Job $jobNum completed."
            JOB_TERMINATED=true
            ;;
          CANCELLED*|FAILED*|TIMEOUT*|OUT_OF_MEMORY*|NODE_FAIL*)
            warn "(sacct:$job_state) Job $jobNum failed."
            JOB_TERMINATED=true
            ;;
          *)
            verbose 1 "(sacct:$job_state) Job $jobNum finished."
            JOB_TERMINATED=true
            ;;
        esac
      fi

      [[ "$JOB_TERMINATED" == true ]] && break

      sleep "$SLEEP_INTERVAL"
    done

    if [[ "$JOB_TERMINATED" == true ]]; then
      verbose 2 "Job summary from sacct for JobID $jobNum:"

      # Sacct-Abfrage, mit Pipe zu while-read für schönere Ausgabe
      sacct -j "$jobNum" --format=JobID,State,exitcode,Elapsed,MaxRSS,AllocNodes -P -n | while IFS='|' read -r jobid state exitcode elapsed maxrss allocnodes; do
        verbose 2 "$(printf "JobID: %-12s | State: %-10s | exitcode: %-6s | Duration: %-8s | MaxRSS: %-6s | Nodes: %s" \
          "$jobid" "$state" "$exitcode" "$elapsed" "${maxrss:-N/A}" "${allocnodes:-N/A}")"
      done

      exitcode=$(sacct -j "$jobNum" --format=exitcode -n -P | awk -F'[:|]' 'NF > 0 && $1 ~ /^[0-9]+$/ { print $1; exit }')
      if [[ "$exitcode" -ne 0 ]]; then
#        log "FATAL" red "Job $jobNum exited with code $exitcode."
        error "Job $jobNum exited with code $exitcode."
      else
        success "Job $jobNum has finished successfully."
      fi
    fi

    t1=$(end_timer "$t0")
    trace "⏱ Job Monitoring-Phase duration: $(format_timer "$t1")"
    duration_run="$t1"
  fi

  sleep $SLEEP_DELAY
  #ls -l "${outputDir}/log/"

  # --- Log Phase ---
  if check_skip_phase 3; then
    warn "Skipping job log analysis (Phase 3)."
  else
    t0=$(start_timer)
    if [[ ! -f "$outputDir/log/$submitLogfile" ]]; then
      warn "Log file not found yet: $submitLogfile"
    fi

    if [[ ! -f "$outputDir/log/$submitErrfile" ]]; then
      warn "File not found yet: $submitErrfile"
    fi

    if [[ -f "$submitLogfile" && -f "$submitErrfile" ]]; then

      if (( flag_verbose > 3 )); then
        rows=8
        info "Showing full content of submit file:"
        execute cat "$submitScript_MPI" --exe
        echo -e "\n------\n"
        if [[ "$exitcode" -ne 0 ]]; then
          warn "Job exited with code $exitcode – showing full error log:"
          execute cat "$submitErrfile" --exe
        else
          info "Showing start ($rows lines) and end ($rows lines) of logfile:"
          execute head -n "$rows" "$submitLogfile" --exe
          echo -e "\n--- (middle omitted) ---\n"
          execute tail -n "$rows" "$submitLogfile" --exe
        fi
      elif (( flag_verbose == 3 )); then
        rows=3
        if [[ "$exitcode" -ne 0 ]]; then
          warn "Job exited with code $exitcode – showing full error log:"
          execute cat "$submitErrfile" --exe
        else
          info "Showing last $rows lines of log file:"
          execute tail -n "$rows" "$submitLogfile" --exe
        fi
      elif (( flag_verbose >= 1 )); then
        if [[ "$exitcode" -ne 0 ]]; then
          info "Showing full content of error log file:"
          execute cat "$submitErrfile" --exe
        fi
      else
        if execute tail -n 20 "$submitLogfile" | grep -q '[\-]\{15\}FINISHED[\-]\{15\}'; then
          success "$mode run completed successfully."
        else
          error "$mode run has crashed."
        fi
      fi
    else
      warn "You might want to check it later manually."
    fi

    t1=$(end_timer "$t0")
    trace "⏱ Log Phase duration: $(format_timer "$t1")"
  fi

  # --- Steps Count Phase ---
  if check_skip_phase 4; then
    warn "Skipping steps count phase (Phase 4)."
  else
    t0=$(start_timer)
    info "Counting number of timestep files (.h5) generated..."

    # Count .h5 files matching the pattern ts*.h5 recursively
    step_files_count=$(find "$outputDir" -type f -name 'ts*.h5' | wc -l)

    if (( step_files_count > 0 )); then
      info "Number of timestep .h5 files found: $step_files_count"
    else
      warn "No timestep .h5 files found in $outputDir"
    fi

    # Check if step count matches expected $steps
    if (( step_files_count != steps )); then
      warn "Mismatch: Expected $steps steps, but found $step_files_count timestep files."

      # Try to check steps inside log file
      if [[ -f "$submitLogfile" ]]; then
        # Count all lines matching "[TRACE] STEP:" ignoring Device number
        logged_steps_count=$(grep -cP '\(\d+\)\[TRACE\] STEP:' "$submitLogfile")

        if (( logged_steps_count > 0 )); then
          info "Log file analysis: Found $logged_steps_count steps logged in $submitLogfile"
          if (( logged_steps_count != steps )); then
            warn "Mismatch: Expected $steps steps, but log file shows $logged_steps_count steps."
          fi
        else
          warn "No steps found in log file ($submitLogfile)."
        fi
      else
        warn "Log file ($submitLogfile) not found to verify steps."
      fi
    fi

    t1=$(end_timer "$t0")
    trace "⏱ Steps Count Phase duration: $(format_timer "$t1")"
  fi

  #        TODO: validation einabeun
  #submit script erstellen
  #./post/analysis_AL.py


  # --- Postprocessing Phase ---
  if check_skip_phase 5; then
    info "Skipping postprocessing step (Phase 5)."
  else
    per_extra=${per_extra:-true}

    if $per_extra; then
      t0=$(start_timer)
      info "Submitting postprocessing job for mode: $mode"
      submitScript_POST="$(get_name_submitFile "submit_post" $layer "$mode" "$(basename $initialConditionPath .h5)" "slurm")"

      info "Generating SLURM submit script for postprocessing: $submitScript_POST"
      cmd=("${LOCATIONS[script]}/build_SLURM_script_POST.sh" "$mode" --steps "$steps" --process "$process" -v "$flag_verbose" -o "$outputDir" --submitScript "$submitScript_POST" --names "$(get_name_job "p" 4 "$mode" "$(basename $initialConditionPath .h5)")" --paths "$paths_arg")
      execute "${cmd[@]}" --exe || error "Failed generate SLURM submit script for postprocessing."
      # --- Job Submit Phase ---
      info "Submitting postprocessing job to SLURM queue..."
      SLURM_POST_ID=$(sbatch "${LOCATIONS[root]}/${submitScript_POST}" | awk '{print $4}')
      SLURM_EXIT_CODE=$?

      if [[ $SLURM_EXIT_CODE -eq 0 ]]; then
        SLURM_POST_ID=$(echo "$SLURM_OUTPUT" | awk '{print $4}')
        success "Postprocessing job submitted successfully. Job ID: $SLURM_POST_ID"

        mkdir -p "$outputDir"
        mv "${LOCATIONS[root]}/${submitScript_POST}" "$outputDir/"
        info "Submit script moved to output directory: $outputDir"
      else
        error "Failed to submit postprocessing job."
      fi

      t1=$(end_timer "$t0")
      trace "⏱ Postprocessing-Phase (submit) duration: $(format_timer "$t1")"
    else
      t0=$(start_timer)
      info "postprocessing for mode: $mode"
      cmd=("${LOCATIONS[script]}/execute_total_postprocessing.sh" "$mode" --directory "$outputDir" -v "$flag_verbose")
#      cmd=("${LOCATIONS[script]}/execute_snapshot2png.sh" "$mode" --directory "$outputDir" -v "$flag_verbose" --plot_type 2 --skip 2,3)
      [[ "$flag_color" == true ]] && cmd+=( --color )

      if ! execute "${cmd[@]}" --exe; then
        t1=$(end_timer "$t0")
        log "TRACE" red "⏱ Postprocessing-Phase duration: $(format_timer "$t1")"
        error "Failed to postprocess."
      else
        t1=$(end_timer "$t0")
        trace "⏱ Postprocessing-Phase duration: $(format_timer "$t1")"
      fi
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0
