#!/bin/bash
declare -A PHASES=(
  [0]="Build/Compile Phase"
  [1]="Initial Conditions Phase"
  [2]="Weak Scaling Phase"
  [3]="Strong Scaling Phase"
  [4]="Tidy-Up Phase"
)

declare -A SCALE_TYP=(
  [1]="initial"
  [2]="weak"
  [3]="strong"
)

declare -A SCALE_VARIANTS=(
  [1]="initial:0,2,3"
  [2]="weak:0,1,3"
  [3]="strong:0,1,2"
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  usage() {
    echo -e "\nUsage: $0 <mode> [options]"
    echo ""
    echo "This script builds and submits a SLURM job based on a given simulation mode."
    echo ""
    echo "Available testcases (auto-detected):"
    echo "  ${VALID_MODES[*]}"
    echo ""
    echo "Options:"
    echo "  -c, --color               Enable colored output (if supported)"
    echo "  --layer <NUMBER>          Specify layer (integer)"
    echo "  --steps <NUMBER>          Number of steps to build/run (positive integer, default: 10)"
    echo "  -v, --verbose <LEVEL>     Verbosity level (non-negative integer, default: 3)"
    echo "  --paths <KEY=VALUE,...>   Specify paths (comma-separated list). Keys can be:"
    echo "                             initial, resource, config, material, parameter"
    echo "  --skip <PHASES>           Skip specific phases (comma-separated list of integers):"
    for i in "${!PHASES[@]}"; do
      printf "                             %d - %s\n" "$i" "${PHASES[$i]}"
    done
    echo "  -h, --help               Show this help message and exit"
    exit 0
  }

  cleanup() {
    # --- Tidy Up Phase ---
    if check_skip_phase 4; then
      info "Skipping tidy-up step (Phase 4)."
    else
      info "Running final tidy-up ..."
      t0=$(start_timer)
      cmd=( "${LOCATIONS[script]}/execute_tidy_up.sh" "$mode" --output "$outputDir" --layer "$layer" -v "$flag_verbose" --skip 0,3)
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

###############################################################################
# scaling_phase
#
# Executes scaling runs (initial / weak / strong) in a unified way.
#
# Behaviour:
#   • Runs folders in parallel
#   • Runs resource files inside folders in parallel
#   • Waits for all child jobs correctly
#   • Produces consistent logging output
#
# Parameters:
#   $1 : scaling type (initial | weak | strong)
#   $2 : phase id used for skip checking
#
# Environment:
#   Uses globally configured paths, job parameters and helpers.
#
# Logging:
#   Each execution logs folder + file combination.
###############################################################################
scaling_phase() {
    local typ="$1"
    local phase_id="$2"

    # ------------------------------------------------------------
    # Phase skip check
    # ------------------------------------------------------------
    if check_skip_phase "$phase_id"; then
        warn "Skipping $typ Scaling Phase (Phase $phase_id)."
        return
    fi

    # Base directory for this scaling type
    local dir="${LOCATIONS[setup]}/${mode}/${typ}"

    if [[ ! -d "$dir" ]]; then
        warn "$typ directory not found: $dir"
        return
    fi

    # Track folder background jobs
    folder_pids=()
    declare -A pid_folder_map

    # ------------------------------------------------------------
    # Iterate folders (parallel level 1)
    # ------------------------------------------------------------
    shopt -s nullglob  # ensure empty globs expand to nothing
    for folder_path in "$dir"/*/; do
        folder="$(basename "$folder_path")"
        files=("$folder_path"/*${SUFFIX[resourcePath]})
        if [ ${#files[@]} -eq 0 ]; then
            warn "No resource files (*${SUFFIX[resourcePath]}) found in folder '$folder', skipping folder."
            continue
        fi
        {

        info "[Folder] Launching '$folder'"

        file_pids=()
        declare -A pid_file_map

        # --------------------------------------------------------
        # Iterate resource files (parallel level 2)
        # --------------------------------------------------------
        for file_path in "$folder_path"/*${SUFFIX[resourcePath]}; do
            file="$(basename "$file_path")"
            filename="${file%${SUFFIX[resourcePath]}}"

            # Prüfen, bevor man in &-Subshell geht
            if [ ! -f "$file_path" ]; then
              warn "File $file_path does not exist, skipping."
              continue
            fi

            {

            info "[File] Processing '$file' in '$folder'"

            # Export variant identifier for downstream scripts
            export SCALE_KEY="${folder},${filename}"

            # Setup required paths
            initialConditionPath="$folder_path"
            materialPath="$folder_path"
            configPath="$folder_path"
            resourcePath="$file_path"

            if ! set_paths "$mode" "${LOCATIONS[setup]}" initialConditionPath materialPath configPath resourcePath; then
              error "set_paths failed for $folder/$filename"
            fi

            # Output directory per run
            outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "scale/$typ/$folder/$filename/")"

            mkdir -p "$outputDir/log"

            logfile="$outputDir/log/$(get_name_logFile "$typ" "$layer" "$mode" "${folder}_$filename" "log")"

            # ----------------------------------------------------
            # Build dynamic path argument string
            # ----------------------------------------------------
            paths_arg=""
            [[ -n "$initialConditionPath" ]] && paths_arg+="initial=$initialConditionPath,"
            [[ -n "$resourcePath" ]]         && paths_arg+="resource=$resourcePath,"
            [[ -n "$configPath" ]]           && paths_arg+="config=$configPath,"
            [[ -n "$materialPath" ]]         && paths_arg+="material=$materialPath,"
            [[ -n "$parameterPath" ]]        && paths_arg+="parameter=$parameterPath,"
            paths_arg="${paths_arg%,}"

            baseName="${filename:0:3}${folder}"

            # Submit and job naming
            submitScript="$(get_name_submitFile "submit" $layer "$mode" "${typ}_${baseName}_${SLURM_JOB_ID:-local}" "slurm")"

#            jobName="$(get_name_job "${typ:0:1}" "$layer" "$mode" "${filename:0:3}${folder:0:1}${folder:3:4}${folder:6:}")"
            jobName="$(get_name_job "${typ:0:1}" "$layer" "$mode" "$baseName")"

            # Construct execution command
            cmd=("$scriptPath" "$mode"
                 --steps "$steps"
                 --process "$process"
                 -v "$flag_verbose"
                 --output "$outputDir"
                 --names "$jobName"
                 --submitScript "$submitScript"
                 --skip 0)

            [[ -n "$paths_arg" ]] && cmd+=(--paths "$paths_arg")
            [[ "$flag_color" == true ]] && cmd+=(--color)

            # Execution banner
            info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
            info "Executing $typ, testcase: $mode, folder: $folder, file: $filename"
            info "$(head -c 95 < <(printf '=%.0s' {1..100}))"

            # Run job and capture logs
            if ! ( execute "${cmd[@]}" --exe ) 2>&1 | tee "$logfile"; then
                error "Execution failed for $mode $folder/$filename. Log saved in: $logfile"
                exit 1
            fi

        } &

        pid=$!
        file_pids+=("$pid")
        pid_file_map["$pid"]="$filename"
        done

        # --------------------------------------------------------
        # Wait for all file jobs in this folder
        # --------------------------------------------------------
        for pid in "${file_pids[@]}"; do
            if wait "$pid"; then
                info "[PID $pid] File '${pid_file_map[$pid]}' finished successfully."
            else
                warn "[PID $pid] File '${pid_file_map[$pid]}' failed!"
            fi
        done

#        TODO: evaluation: sacling einabuen
#submit script erstellen
#./scripts/remote/binac2/execute_total_analysis_performanc.sh -d output/20260225/alluminium-alloy/alloy_disc_colliding_plate/scale/strong -v 1

        info "Folder $folder finished."

    } &

    pid=$!
    folder_pids+=("$pid")
    pid_folder_map["$pid"]="$folder"
    done
    shopt -u nullglob  # optional wieder ausschalten

    # ------------------------------------------------------------
    # Wait for all folders
    # ------------------------------------------------------------
    for pid in "${folder_pids[@]}"; do
        if wait "$pid"; then
            info "[PID $pid] Folder '${pid_folder_map[$pid]}' finished successfully."
        else
            warn "[PID $pid] Folder '${pid_folder_map[$pid]}' failed!"
        fi
    done

    unset SCALE_KEY
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

  SLEEP_INTERVAL=1
  layer=4
  scriptPath="${LOCATIONS[script]}/execute_total_testcase.sh"

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

        IFS="${SEPARATOR[list]}" read -ra path_args <<< "$1"  # Zerlege den String bei Kommas

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

      *)
        logger "[Error]" red "Unknown option: $1"
        usage "$flag_color"
        exit 1
        ;;
    esac
  done
  # --- Timer starten ---
  overall_start=$(start_timer)

  # --- Configuration ---
  set_paths "$mode" "${LOCATIONS[testcases]}" parameterPath

  if [[ -z "$submitScript" ]]; then
    submitScript="$(get_name_submitFile "submit" $layer "$mode" "scale_$(basename $initialConditionPath .h5)" "slurm")"
    warn "No submit name given. Falling back to: $submitScript"
  else
    submitScript="$submitScript"
  fi

  if [[ -z "$outputDir" ]]; then
    outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "scale")"
    warn "No output directory given. Falling back to: $outputDir"
  else
    outputDir="$outputDir"
  fi
  mkdir -p "${outputDir}/log"
  logfile="$outputDir/log/$(get_name_logFile "${SLURM_JOB_ID:-local}" "$layer" $mode "scale" "log")"

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
  debug 4 "$(module list 2>&1)"
  t1=$(end_timer "$t0")
  trace "⏱ Setup-Module-Phase duration: $(format_timer "$t1")"


  # --- Build / Compile Phase ---
  t0=$(start_timer)
  cmd=("${LOCATIONS[script]}/build_binary.sh" "$mode" -v "$flag_verbose" --output "$outputDir" )
  if check_skip_phase 0; then
    warn "Simplified build (Phase 0)"
    cmd+=( --skip 0,1 )
  else
    info "Building and running local test for mode: $mode"
  fi
  [[ -n "$paths_arg" ]] && cmd+=( --paths "$paths_arg" )
  [[ "$flag_color" == true ]] && cmd+=( --color )
  [[ -n $execute_date ]] && cmd+=( --date "$execute_date")
  execute "${cmd[@]}" --exe || error "Failed to build binary."
  t1=$(end_timer "$t0")
  trace "⏱ Build-Phase duration: $(format_timer "$t1")"

  # --- Scaling Phases ---
  for i in "${!SCALE_VARIANTS[@]}"; do
      name="${SCALE_VARIANTS[$i]%%:*}"
      scaling_phase "$name" "$i"
  done
  }


#  # --- Initial Conditions Phase ---
#  scaling_phase "${SCALE_TYP[1]}" 1
#  # --- Weak Scaling Phase ---
#  scaling_phase "${SCALE_TYP[2]}" 2
#  # --- Strong Scaling Phase ---
#  scaling_phase "${SCALE_TYP[3]}" 3
#  }

#  # --- Initial Conditions Phase---
#  if check_skip_phase 1; then
#    warn "Skipping initial Conditions Phase (Phase 1)."
#  else
#    typ="init"
#    dir="${LOCATIONS[setup]}/${mode}/${typ}Condition"
#    if [[ -d "$dir" ]]; then
#      # ===== Parallel Scaling =====
#      pids=()
#      declare -A pid_typ_map
#      for folder_path in "$dir"/*/; do
#        {
#          folder="$(basename "$folder_path")"
#          info "Start $typ $folder in the background..."
#          outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "scale/$typ/$folder/")"
#          mkdir -p "$outputDir/log"
#          logfile="$outputDir/log/$(get_name_logFile "$typ" "$layer" $mode "$folder" "log")"
#
#          initialConditionPath="$dir/$folder/"
#          materialPath="$dir/$folder/"
#          configPath="$dir/$folder/"
#          set_paths "$mode" "${LOCATIONS[setup]}" configPath
#  #          resourcePath="$dir/$folder/"
#          for file_path in "$dir/$folder"/*${SUFFIX[resourcePath]}; do
#            {
#              file="$(basename "$file_path")"
#              filename="${file%${SUFFIX[resourcePath]}}"
#              resourcePath="$dir/$folder/$file"
#
#              info "Start $typ $file in the background..."
#              outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "scale/$typ/$folder/$filename/")"
#              mkdir -p "$outputDir/log"
#
#              set_paths "$mode" "${LOCATIONS[setup]}" initialConditionPath materialPath resourcePath|| {
#                  error "set_paths failed for $folder"
#              }
#
#              # Dynamisch Pfade sammeln
#              paths_arg=""
#              [[ -n "$initialConditionPath" ]] && paths_arg+="initial=$initialConditionPath,"
#              [[ -n "$resourcePath" ]]         && paths_arg+="resource=$resourcePath,"
#              [[ -n "$configPath" ]]           && paths_arg+="config=$configPath,"
#              [[ -n "$materialPath" ]]         && paths_arg+="material=$materialPath,"
#              [[ -n "$parameterPath" ]]        && paths_arg+="parameter=$parameterPath,"
#              paths_arg="${paths_arg%,}"  # letztes Komma entfernen
#
#              submitScript="$(get_name_submitFile "submit" $layer "$mode" "${typ}_${folder}" "slurm")"
#              jobName="$(get_name_job "${typ:0:1}" "$layer" "$mode" "$folder")"
#
#              # Variante exportieren
#              export SCALE_KEY="$folder"
#
#              cmd=("$scriptPath" "$mode" --steps "$steps" --process "$process" -v "$flag_verbose" --output "$outputDir" --names "$jobName" --submitScript "$submitScript" --skip 0)
#              [[ -n "$paths_arg" ]] && cmd+=( --paths "$paths_arg" )
#              [[ "$flag_color" == true ]] && cmd+=( --color )
#
#              info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
#              info "Executing $typ, testcase: $mode, folder: $folder"
#              info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
#
#              if ! ( execute "${cmd[@]}" --exe ) 2>&1 | tee "$logfile"; then
#                error "Execution failed for $mode $folder. Log saved in: $logfile"
#              fi
#            }
#        done
#        } &  # Hintergrundprozess starten
#
#        pid=$!
#        pids+=("$pid")
#        pid_typ_map["$pid"]="$folder"
#      done
#
#      # Auf alle Hintergrundprozesse warten
#      for pid in "${pids[@]}"; do
#        if wait "$pid"; then
#            info "[PID $pid] Folder '${pid_typ_map[$pid]}' finished successfully."
#        else
#            warn "[PID $pid] Folder '${pid_typ_map[$pid]}' failed!"
#        fi
#      done
#
#      unset SCALE_KEY
#    else
#      warn "$typ directory not found: $dir"
#    fi
#  fi
#
#  # --- Weak Scaling Phase ---
#  if check_skip_phase 2; then
#      warn "Skipping weak Scaling Phase (Phase 2)."
#  else
#    typ="weak"
#    dir="${LOCATIONS[setup]}/${mode}/${typ}Scaling"
#    if [[ -d "$dir" ]]; then
##      resourcePath="$dir"
##      configPath="$dir"
##      set_paths "$mode" "${LOCATIONS[setup]}" configPath resourcePath
##       set_paths "$mode" "${LOCATIONS[setup]}" configPath
#      # ===== Parallel Scaling =====
#      pids=()
#      declare -A pid_typ_map
#      for folder_path in "$dir"/*/; do
#        {
#          folder="$(basename "$folder_path")"
#          info "Start $typ $folder in the background..."
#          outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "scale/$typ/$folder/")"
#          mkdir -p "$outputDir/log"
#          logfile="$outputDir/log/$(get_name_logFile "$typ" "$layer" $mode "$folder" "log")"
#
#          initialConditionPath="$dir/$folder/"
#          materialPath="$dir/$folder/"
#          configPath="$dir/$folder/"
#          set_paths "$mode" "${LOCATIONS[setup]}" configPath
##          resourcePath="$dir/$folder/"
#          for file_path in "$dir/$folder"/*${SUFFIX[resourcePath]}; do
#            {
#              file="$(basename "$file_path")"
#              filename="${file%${SUFFIX[resourcePath]}}"
#              resourcePath="$dir/$folder/$file"
#
#              info "Start $typ $file in the background..."
#              outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "scale/$typ/$folder/$filename/")"
#              mkdir -p "$outputDir/log"
#
#              set_paths "$mode" "${LOCATIONS[setup]}" initialConditionPath materialPath resourcePath|| {
#                  error "set_paths failed for $folder"
#              }
#
#              # Dynamisch Pfade sammeln
#              paths_arg=""
#              [[ -n "$initialConditionPath" ]] && paths_arg+="initial=$initialConditionPath,"
#              [[ -n "$resourcePath" ]]         && paths_arg+="resource=$resourcePath,"
#              [[ -n "$configPath" ]]           && paths_arg+="config=$configPath,"
#              [[ -n "$materialPath" ]]         && paths_arg+="material=$materialPath,"
#              [[ -n "$parameterPath" ]]        && paths_arg+="parameter=$parameterPath,"
#              paths_arg="${paths_arg%,}"  # letztes Komma entfernen
#
#              submitScript="$(get_name_submitFile "submit" $layer "$mode" "${typ}_${folder}" "slurm")"
#              jobName="$(get_name_job "${typ:0:1}" "$layer" "$mode" "$folder")"
#
#              # Variante exportieren
#              export SCALE_KEY="$folder"
#
#              cmd=("$scriptPath" "$mode" --steps "$steps" --process "$process" -v "$flag_verbose" --output "$outputDir" --names "$jobName" --submitScript "$submitScript" --skip 0)
#              [[ -n "$paths_arg" ]] && cmd+=( --paths "$paths_arg" )
#              [[ "$flag_color" == true ]] && cmd+=( --color )
#
#              info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
#              info "Executing $typ, testcase: $mode, folder: $folder"
#              info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
#
#              if ! ( execute "${cmd[@]}" --exe ) 2>&1 | tee "$logfile"; then
#                error "Execution failed for $mode $folder. Log saved in: $logfile"
#              fi
#            }
#        done
#        } &  # Hintergrundprozess starten
#
#        pid=$!
#        pids+=("$pid")
#        pid_typ_map["$pid"]="$folder"
#      done
#
#      # Auf alle Hintergrundprozesse warten
#      for pid in "${pids[@]}"; do
#        if wait "$pid"; then
#            info "[PID $pid] Folder '${pid_typ_map[$pid]}' finished successfully."
#        else
#            warn "[PID $pid] Folder '${pid_typ_map[$pid]}' failed!"
#        fi
#      done
#
#      unset SCALE_KEY
#
#    else
#        warn "$typ directory not found: $dir"
#    fi
#  fi
#
#  # --- Strong Scaling Phase ---
#  if check_skip_phase 3; then
#    warn "Skipping strong Scaling Phase (Phase 3)."
#  else
#    typ="strong"
#    dir="${LOCATIONS[setup]}/${mode}/${typ}Scaling"
#    if [[ -d "$dir" ]]; then
##      configPath="$dir"
##      set_paths "$mode" "${LOCATIONS[setup]}" configPath
#      for folder_path in "$dir"/*/; do
#        folder="$(basename "$folder_path")"
#        info "Start $typ $folder in the background..."
##        outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "scale/$typ/$folder/")"
##        mkdir -p "$outputDir/log"
##        logfile="$outputDir/log/$(get_name_logFile "$typ" "$layer" $mode "$folder" "log")"
#
#        configFiles=( "$dir/$folder/"*${SUFFIX[configPath]} )
#        if [ ${#configFiles[@]} -eq 0 ]; then
#            error "No config file found in $dir/$folder/"
#        fi
#        configPath="${configFiles[0]}"
#
#        set_paths "$mode" "${LOCATIONS[setup]}" configPath
#
#        materialPath="$dir/$folder/"
#        initialConditionPath="$dir/$folder/"
#        set_paths "$mode" "${LOCATIONS[setup]}" initialConditionPath materialPath|| {
#            error "set_paths failed for $folder"
#        }
#
#        # ===== Parallel Scaling =====
#        pids=()
#        declare -A pid_typ_map
#
#        for file_path in "$dir/$folder"/*${SUFFIX[resourcePath]}; do
#          {
#
#            file="$(basename "$file_path")"
#            filename="${file%${SUFFIX[resourcePath]}}"
#            resourcePath="$dir/$folder/$file"
#
#            info "Start $typ $file in the background..."
#            outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "scale/$typ/$folder/$filename/")"
#            mkdir -p "$outputDir/log"
#
#            set_paths "$mode" "${LOCATIONS[setup]}" resourcePath || {
#               log "[ERROR]" "red" "set_paths failed for $resourcePath"
#               continue
#             }
#
#            # Dynamisch Pfade sammeln
#            paths_arg=""
#
#            [[ -n "$initialConditionPath" ]] && paths_arg+="initial=$initialConditionPath,"
#            [[ -n "$resourcePath" ]]         && paths_arg+="resource=$resourcePath,"
#            [[ -n "$configPath" ]]           && paths_arg+="config=$configPath,"
#            [[ -n "$materialPath" ]]         && paths_arg+="material=$materialPath,"
#            [[ -n "$parameterPath" ]]        && paths_arg+="parameter=$parameterPath,"
#
#            # Letztes Komma entfernen (sauberer)
#            paths_arg="${paths_arg%,}"
#
#            submitScript="$(get_name_submitFile "submit" $layer "$mode" "${typ}_${filename}" "slurm")"
#            jobName="$(get_name_job "${typ:0:1}" "$layer" "$mode" "$filename")"
#
#            # Variante exportieren
#            export SCALE_KEY="$filename"
#
#            cmd=("$scriptPath" "$mode" --steps "$steps" --process "$process" -v "$flag_verbose" --output "$outputDir" --names "$jobName" --submitScript "$submitScript" --skip 0)
#            [[ -n "$paths_arg" ]] && cmd+=( --paths "$paths_arg" )
#            [[ "$flag_color" == true ]] && cmd+=( --color )
#
#            info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
#            info "Executing $typ, testcase: $mode, file: $file"
#            info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
#            if ! ( execute "${cmd[@]}" --exe ) 2>&1 | tee "$logfile"; then
#              error "Execution failed for $mode $folder. Log saved in: $logfile"
#            fi
#
#          } &  # Hintergrundprozess starten
#
#          pid=$!
#          pids+=("$pid")
#          pid_typ_map["$pid"]="$filename"
#        done
#
#        # Auf alle Hintergrundprozesse warten
#        for pid in "${pids[@]}"; do
#            if wait "$pid"; then
#                info "[PID $pid] File '${pid_typ_map[$pid]}' finished successfully."
#            else
#                warn "[PID $pid] File '${pid_typ_map[$pid]}' failed!"
#            fi
#        done
#
#        unset SCALE_KEY
#      done
#    else
#      warn "$typ directory not found: $dir"
#    fi
#  fi
#}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0
