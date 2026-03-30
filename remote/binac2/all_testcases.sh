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
  ${ACTIVE_COLORS[CYAN]}$(basename "$0")${ACTIVE_COLORS[RESET]} [options]
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

main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done

  source "$( dirname "$SOURCE" )/load_setup_shell.sh"
  source "${LOCATIONS[script]}/execute_total_testcase.sh"

  layer=2
  scriptPath="${LOCATIONS[script]}/execute_total_testcase.sh"

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

      --layer)
        shift
        check_arg "--layer" "$1"
        check_natural_numbers "--layer" "$1" "$(get_range_min layer)" "$(get_range_max layer)"
        layer="$1"
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

      outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "-")"
      mkdir -p "$outputDir/log/"
      logfile="$outputDir/log/$(get_name_logFile "" "$layer" $mode "-" "log")"

      info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
      info "Starting testcases: $outputDir"
      info "$(head -c 95 < <(printf '=%.0s' {1..100}))"

      set_paths "$mode" "${LOCATIONS[testcases]}" parameterPath
      set_paths "$mode" "${LOCATIONS[setup]}" initialConditionPath resourcePath configPath materialPath
      outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$((layer + 2))" "$mode" "$(basename $initialConditionPath .h5)")"
      mkdir -p "$outputDir/log/"
      info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
      info "$outputDir"
      info "$(head -c 95 < <(printf '=%.0s' {1..100}))"


      # Dynamisch Pfade sammeln
      paths_arg=""
      [[ -n "$initialConditionPath" ]] && paths_arg+="initial=$initialConditionPath,"
      [[ -n "$resourcePath" ]]         && paths_arg+="resource=$resourcePath,"
      [[ -n "$configPath" ]]           && paths_arg+="config=$configPath,"
      [[ -n "$materialPath" ]]         && paths_arg+="material=$materialPath,"
      [[ -n "$parameterPath" ]]        && paths_arg+="parameter=$parameterPath,"

      # Letztes Komma entfernen
      paths_arg="${paths_arg%,}"

      cmd=( "$scriptPath" "$mode" --output "$outputDir" --steps "$steps" --process "$process" -v "$flag_verbose" --layer "$((layer + 1))")
      # Nur anhängen, wenn überhaupt Pfade vorhanden sind
      [[ -n "$paths_arg" ]] && cmd+=( --paths "$paths_arg" )
      [[ -n "${skip_phases[*]}" ]] && cmd+=(--skip "$(IFS=','; echo "${skip_phases[*]}")")
      [[ "$flag_color" == true ]] && cmd+=( --color )

      # Ausgabe umleiten in Logdatei
      if ! ( execute "${cmd[@]}" --exe ) 2>&1 | tee "$logfile"; then
        warn "Testcase '$mode' at '$git_branch' failed. Log saved in: $logfile"
        continue
      fi

      reset_paths outputDir parameterPath initialConditionPath resourcePath configPath materialPath
    fi
  done

  total_duration=$(end_timer "$overall_start")
  trace "All testcases completed at $git_branch in $(format_timer "$total_duration")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0