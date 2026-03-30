#!/bin/bash
declare -A SCALE_VARIANTS=(
  [1]="initial:0,2,3"
  [2]="weak:0,1,3"
  [3]="strong:0,1,2"
)

# --- Hilfsfunktionen ---
usage() {
  echo -e "\nUsage: $0 [OPTIONS]\n"
  echo "Run all valid simulation scaling testcases."
  echo ""
  echo "Options:"
  echo "  -v, --verbose <LEVEL>    Verbosity level (default: 3)"
  echo "  --steps <N>              Number of steps to run (positive integer, default: 10)"
  echo "  --skip <INDICES>         Comma-separated list of testcase indices to skip (starting at 0)"

  echo "  --select <NAMES>         Comma-separated list of testcase names to run exclusively"
  echo "  -c, --color              Enable colored output if supported"
  echo "  --layer <N>              Layer level for output directory structure (default: 4)"
  echo "  -h, --help               Show this help message and exit"
  echo ""
  echo "Available testcases (auto-detected):"
  for i in "${!VALID_MODES[@]}"; do
    echo "  [$i] ${VALID_MODES[$i]}"
  done
  echo ""
  echo "Examples:"
  echo "  $0 --steps 50 --skip 0,2"
  echo "  $0 --select sedov,shocktube -v 4"
  echo "  $0 -c --layer 3"
  echo ""
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

  layer=4
  scriptPath="${LOCATIONS[script]}/execute_total_scaling.sh"

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
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          flag_verbose="$1"
        else
          error "Invalid value for --verbose: must be a positive integer."
        fi
        shift
        ;;
      --skip)
        shift
        check_arg "--skip" "$1"
        check_skip skip_phases "$1" "$(get_range_min skip)" $(( ${#PHASES[@]} - 1 ))
        shift
        ;;
      --select)
        shift
        check_arg "--select" "$1"
        IFS=',' read -ra selected_modes <<< "$1"
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

  if (( ${#selected_modes[@]} > 0 )); then
    testcases_to_run=()
    for sel in "${selected_modes[@]}"; do
      if [[ -d "${LOCATIONS[testcases]}/$sel" ]]; then
        testcases_to_run+=("${LOCATIONS[testcases]}/$sel")
      else
        warn "Selected testcase '$sel' does not exist in ${LOCATIONS[testcases]} – skipping."
      fi
    done
  else
    testcases_to_run=( "${LOCATIONS[testcases]}"/* )
  fi

  # --- Main loop ---
  for dir in "${testcases_to_run[@]}"; do
    if [[ -d "$dir" ]]; then
      mode=$(basename "$dir")
      mode_index=-1

      for i in "${!VALID_MODES[@]}"; do
        if [[ "${VALID_MODES[$i]}" == "$mode" ]]; then
          mode_index=$i
          break
        fi
      done

      if [[ $mode_index -lt 0 ]]; then
        warn "Skipping unknown testcase: $mode"
        continue
      fi

      outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "scale")"
      mkdir -p "$outputDir/log/"
      logfile="$outputDir/log/$(get_name_logFile "${SLURM_JOB_ID:-local}" "$layer" $mode "scale" "log")"

      info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
      info "Starting scaling: $outputDir"
      info "$(head -c 95 < <(printf '=%.0s' {1..100}))"


      # Haupt-Build ausführen
      cmd=( "$scriptPath" "$mode" --steps "$steps" -v "$flag_verbose" -o $outputDir)
      if ! check_skip_phase 0; then
         cmd+=( --skip 1,2,3)
      else
        info "Skipping main build phase (Phase 0)"
         cmd+=( --skip 0,1,2,3)
      fi
      [[ "$flag_color" == true ]] && cmd+=( --color )
      if ! ( execute "${cmd[@]}" --exe ) 2>&1 | tee "$logfile"; then
        error "Main build '$mode' at '$git_branch' failed. Log saved in: $logfile"
      fi

      #--- Wenn Phase 4 (Tidy-Up) geskippt wird → an alle Varianten ,4 anhängen ---
      if check_skip_phase 4; then
          info "Tidy-Up (Phase 4) is skipped → appending ',4' to all variants"
          for i in "${!SCALE_VARIANTS[@]}"; do
              name="${SCALE_VARIANTS[$i]%%:*}"
              phases="${SCALE_VARIANTS[$i]#*:}"
              # nur anhängen, wenn noch nicht enthalten
              [[ "$phases" != *",4"* ]] && phases="$phases,4"
              SCALE_VARIANTS[$i]="$name:$phases"
          done
      fi

      # ===== Parallel Scaling =====
      pids=()
      declare -A pid_variant_map

      # Sortiere numerische Keys (1,2,3) nach Name
      mapfile -t sorted_keys < <(for k in "${!SCALE_VARIANTS[@]}"; do
          echo "$k"
      done | sort)

      for i in "${sorted_keys[@]}"; do
          name="${SCALE_VARIANTS[$i]%%:*}"
          phases="${SCALE_VARIANTS[$i]#*:}"

          info "Start $name in the background..."
          export VARIANT_KEY="$name"  # Damit logger den Variantennamen kennt

          # Finde numerische Phase-ID (1–3)
          phase_id=""
          for id in "${!PHASES[@]}"; do
              if [[ "${PHASES[$id]}" == *"${name^}"* ]]; then
                  phase_id="$id"
                  break
              fi
          done

          # Prüfen, ob diese Phase geskippt werden soll
          if check_skip_phase "$phase_id"; then
              info "Skipping variant '$name' (${PHASES[$phase_id]}) via --skip (Phase $phase_id)"
              continue
          fi

          (
              outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "scale/$name")"
              mkdir -p "$outputDir/log/"
              logfile="$outputDir/log/$(get_name_logFile "${SLURM_JOB_ID:-local}" "$layer" $mode "$name" "log")"

              info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
              info "Starting scaling: $outputDir"
              info "$(head -c 95 < <(printf '=%.0s' {1..100}))"

              cmd=( "$scriptPath" "$mode" --steps "$steps" --process "$process" -o "$outputDir" -v "$flag_verbose" --skip "$phases" )
              [[ "$flag_color" == true ]] && cmd+=( --color )

              if ! ( execute "${cmd[@]}" --exe ) 2>&1 | tee "$logfile"; then
                  warn "Testcase '$name' failed. Log saved in: $logfile"
                  exit 1
              fi
          ) &

          pid=$!
          pids+=("$pid")
          pid_variant_map["$pid"]="$name"
      done

      for pid in "${pids[@]}"; do
          if wait "$pid"; then
              info "[PID $pid] Variant '${pid_variant_map[$pid]}' finished successfully."
          else
              warn "[PID $pid] Variant '${pid_variant_map[$pid]}' failed!"
          fi
      done
      unset VARIANT_KEY
    fi
  done


  total_duration=$(end_timer "$overall_start")
  trace "Scaling completed at $git_branch in $(format_timer "$total_duration")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0
