#!/bin/bash
set -eEuo pipefail
trap 'log "FATAL" red "Command failed at line $LINENO: $BASH_COMMAND"; exit 1' ERR

declare -A PHASES=(
  [0]="Move executable to output directory"
  [1]="Copy parameter.h from include/ directory"
  [2]="Move PBS/SLURM submit script"
  [3]="Copy configuration and input files"
  [4]="Remove temporary files"
  [5]="Archive logs and job files"
  [6]="Reset path-related variables"
)

usage() {
  echo "Usage: $0 MODE -o <outputDir> [options]"
  echo ""
  echo "Moves executables, log files, and PBS scripts into the output directory."
  echo ""
  echo "Arguments:"
  echo "  MODE                   Simulation mode to run. Available modes:"
  for mode in "${VALID_MODES[@]}"; do
    echo "    - $mode"
  done
  echo ""
  echo "Options:"
  echo "  -o, --output DIR       Output directory (required)"
  echo "  -v, --verbose LEVEL    Verbosity level (default: 3)"
  echo "      --date YYYYMMDD    Execution date (default: today)"
  echo "      --script FILE      Submit script to move"
  echo "      --color            Force colored output"
  echo "      --paths key=VALUE  Pass custom paths (comma-separated):"
  echo "                         initial=FILE,resource=FILE,config=FILE,material=FILE,parameter=FILE"
  echo "      --skip <PHASES>   Skip one or more phases (by index, see below)"
  for i in "${!PHASES[@]}"; do
    printf "                                %d - %s\n" "$i" "${PHASES[$i]}"
  done
  echo "  -h, --help             Show this help message and exit"
}

main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
   DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
   SOURCE="$(readlink "$SOURCE")"
   [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"

  VALID_MODES+=( "$1" )
  mode="$(get_name_completeMode "$1")"
  check_valid_mode "$mode" "${VALID_MODES[@]}"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--color)
        flag_color=true
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

      -o|--output)
        shift
        check_arg "--output" "$1"
        outputDir="$1"
        shift
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
      --submitScript)
        shift
        check_arg "--submitScript" "$1"
        submitScript="$1"
        shift
        ;;
      *)
        logger "[Error]" red "Unknown option: $1"
        usage "$flag_color"
        exit 1
        ;;
    esac
  done

  if [[ -z "$outputDir" ]]; then
    outputDir="$(get_path_outputRootDir "$layer" "$mode" "scale")"
  fi

  # --- Main logic ---
  info "Tidying up for mode: $mode"
  info "Target output directory: $outputDir"

  # --- Move executable ---
  if check_skip_phase 0; then
    warn "Skipping binary copy to output directory (Phase 0)"
  else
    verbose 3 "Copy executable (Phase 0)"
    exe_path="$outputDir/compiled/$(get_name_binary "$mode")"
    exe_basename=$(basename "$exe_path")

    mkdir -p "$outputDir/compiled/"
    if [[ -f "$exe_path" ]]; then
      if [[ -e "$exe_path" ]]; then
        warn "Overwriting existing file: '$(basename $exe_path)'"
      else
        info "Moving $exe_path → $outputDir/compiled/"
      fi
      cp -f "$exe_path" "$outputDir/compiled/"
    else
      warn "Expected binary '$exe_path' not found."
    fi
  fi
  # --- copy parameter.h from include/ directory ---
  if check_skip_phase 1; then
    warn "Skipping copy parameter.h from include (Phase 1)"
  else
    verbose 3 "Copy parameter.h (Phase 1)"
    mkdir -p "$outputDir/compiled/include/"
    if [[ -f "${LOCATIONS[root]}/include/parameter.h" ]]; then
      info "Copying parameter.h from ${LOCATIONS[root]}/include/ to $outputDir/compiled/"
      cp "${LOCATIONS[root]}/include/parameter.h" "$outputDir/compiled/include/parameter.h"
    else
      warn "parameter.h not found in include/ directory"
    fi
  fi
  # --- Move PBS submit script ---
  if check_skip_phase 2; then
    warn "Skipping move submit script (Phase 2)"
  else
    verbose 3 "Move submit script (Phase 2)"
    if [[ -z "${submitScript:-}" ]]; then
      submitScript="$(get_name_submitFile "submit" $layer "$mode" "$(basename $initialConditionPath .h5)" "slurm")"
    else
      submitScript="$submitScript"
    fi

    if [[ -n "$submitScript" && -f "$submitScript" ]]; then
      if [[ -f "$submitScript" ]]; then
        if [[ -e "$submitScript" ]]; then
          warn "Overwriting existing file: '$(basename $submitScript)'"
        else
          info "Moving $submitScript → $outputDir/"
        fi
        mv -f "$submitScript" "$outputDir/"
      fi
    fi
  fi

  # --- Copy configuration files ---
  if check_skip_phase 3; then
    warn "Skipping copy config data (Phase 3)"
  else
    verbose 3 "Copy configuration files (Phase 3)"
    mkdir -p  "$outputDir/configured/"
    if [[ -n "${resourcePath:-}" ]]; then
      if [[ -f "$resourcePath" ]]; then
        info "Copying $(basename "$resourcePath") → $outputDir/configured/$(basename "$resourcePath")"
        cp "$resourcePath" "$outputDir/configured/$(basename "$resourcePath")"
      else
        warn "Resource file not found: $resourcePath"
      fi
    fi

    if [[ -n "${materialPath:-}" ]]; then
      if [[ -f "$materialPath" ]]; then
          info "Copying $(basename "$materialPath") → $outputDir/configured/$(basename "$materialPath")"
          cp "$materialPath" "$outputDir/configured/$(basename "$materialPath")"
        else
          warn "Config file not found: $materialPath"
        fi
    fi

    if [[ -n "${configPath:-}" ]]; then
      if [[ -f "$configPath" ]]; then
        info "Copying $(basename "$configPath") → $outputDir/configured/$(basename "$configPath")"
        cp "$configPath" "$outputDir/configured/$(basename "$configPath")"
      else
        warn "Config file not found: $configPath"
      fi
    fi

    if [[ -n "${parameterPath:-}" ]]; then
      if [[ -f "$parameterPath" ]]; then
        info "Copying $(basename "$parameterPath") → $outputDir/configured/$(basename "$parameterPath")"
        cp "$parameterPath" "$outputDir/configured/$(basename "$parameterPath")"
      else
        warn "Parameter file not found: $parameterPath"
      fi
    fi

    if [[ -n "${initialConditionPath:-}" ]]; then
      if [[ -f "$initialConditionPath" ]]; then
        info "Copying $(basename "$initialConditionPath") → $outputDir/configured/$(basename "$initialConditionPath")"
        cp "$initialConditionPath" "$outputDir/configured/$(basename "$initialConditionPath")"

        info "Copying initial condition files matching $(basename "$initialConditionPath" .h5)* from $(dirname "$initialConditionPath") to $outputDir/configured/"

        # Kopiere alle Dateien, die mit dem Basisnamen beginnen (zb .png)
        for file in "$(dirname "$initialConditionPath")"/"$(basename "$initialConditionPath" .h5)"*; do
          [[ -e "$file" ]] || continue  # Skip if no matching files
          if [[ -f "$file" ]]; then
            info "Copying $(basename "$file") → $outputDir/configured/$(basename "$file")"
            cp "$file" "$outputDir/configured/"
          fi
        done
      else
        warn "Initial condition file not found: $initialConditionPath"
      fi
    fi
  fi

  # --- Remove temporary files ---
  if check_skip_phase 4; then
    warn "Skipping temporary file cleanup (Phase 4)"
  else
    verbose 3 "Remove temporary files (Phase 4)"
    shopt -s nullglob
    for temp in ./*.tmp ./*.bak ./*~ ./*.swp ./CMakeCache.txt; do
      if [[ -f "$temp" ]]; then
        if (( flag_verbose >= 3 )); then
          debug 3 "Removing temporary file: $temp"
        fi
        rm -f "$temp"
      fi
    done
    shopt -u nullglob
  fi

  # --- Archive files ---
  if check_skip_phase 5; then
    warn "Skipping archive step (Phase 5)"
  else
    verbose 3 "Archive logs and scripts (Phase 5)"
    mkdir -p "$outputDir/archiv"

    shopt -s nullglob
    archive_patterns=("*.pbs" "core.*" "*.o*" "*.e*")

    for pattern in "${archive_patterns[@]}"; do
      for file in $pattern; do
        if [[ -f "$file" ]]; then
          if (( flag_verbose >= 3 )); then
            debug 3 "Archiving: $file → $outputDir/archiv"
          fi
          mv -f "$file" "$outputDir/archiv"
        fi
      done
    done
    shopt -u nullglob
  fi

  if check_skip_phase 6; then
    warn "Skipping reset (Phase 6)"
  else
    verbose 3 "Resetting path-related variables to initial state (Phase 6)"
    reset_paths outputDir submitScript parameterPath initialConditionPath resourcePath configPath materialPath
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0