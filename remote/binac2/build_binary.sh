#!/bin/bash
declare -a PHASES=(
  [0]="Copy parameter.h to ./include/parameter.h"
  [1]="Compile project with make remake"
  [2]="Rename binary to output directory"
)

usage() {
  echo ""
  echo "Usage: $0 MODE [OPTIONS]"
  echo ""
  echo "Run simulation setup and build pipeline for the given MODE."
  echo ""
  echo "Arguments:"
  echo "  MODE                     Simulation mode to run. Available modes:"
  for mode in "${VALID_MODES[@]}"; do
    echo "    - $mode"
  done
  echo ""
  echo "Options:"
  echo "  -c, --color              Enable colored output (if supported)"
  echo "  -v, --verbose <LEVEL>    Set verbosity level (integer, default: 3)"
  echo "      --steps <N>          Number of steps to run (positive integer, default: 10)"
  echo "      --date <YYYYMMDD>    Set build date (format: YYYYMMDD, default: today)"
  echo "  -o, --output <DIR>       Output directory"
  echo "      --paths <KEY=VAL>    Comma-separated list of custom paths:"
  echo "                              initial=<FILE>      Initial condition file"
  echo "                              resource=<FILE>     Resource configuration file"
  echo "                              config=<FILE>       Configuration file"
  echo "                              material=<FILE>     Material definition file"
  echo "                              parameter=<FILE>    Parameter header file"
  printf "      --skip <PHASES>      Comma-separated list of phases to skip (0–$(( ${#PHASES[@]} - 1 )))"
  for i in "${!PHASES[@]}"; do
      printf "                                %d - %s\n" "$i" "${PHASES[$i]}"
  done
  echo "  -h, --help               Show this help message and exit"
}

main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"

  debug 0 "$@"
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
       --layer)
         shift
         check_arg "--layer" "$1"
         check_natural_numbers "--layer" "$1" "$(get_range_min layer)" "$(get_range_max layer)"
         layer="$1"
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
      --paths)
        shift
        check_arg "--paths" "$1"
      #        check_paths "--paths" "$1"
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
      -o|--output)
        shift
        check_arg "--output" "$1"
        outputDir="$1"
        shift
        ;;

      *)
        logger "[Error]" red "Unknown option: $1\n"
        usage "$flag_color"
        exit 1
        ;;
    esac
  done

  if [[ -z "$outputDir" ]]; then
    set_paths "$mode" initialConditionPath
    outputDir="$(get_path_outputRootDir "${LOCATIONS[output]}" "$layer" "$mode" "$(basename $initialConditionPath .h)")"
    warn "No output directory given. Falling back to: $outputDir"
  else
    outputDir="$outputDir"
  fi
  mkdir -p "$outputDir/compiled/"

  # Prüfe parameter.h (Phase 0: Kopieren von parameter.h)
  if ! check_skip_phase 0; then
    set_paths "$mode" parameterPath
    [[ -f "$parameterPath" ]] || error "parameter.h not found: $parameterPath"
    info "Copying $parameterPath → ./include/parameter.h"
    cp "$parameterPath" "${LOCATIONS[root]}/include/parameter.h"
  else
    warn "Skipping copying parameter.h (phase 0)."
  fi

  # Kompilieren (Phase 1: make remake)
  if ! check_skip_phase 1; then
    info "Compiling project..."
    rm -r "${LOCATIONS[root]}/build/"
    make remake || error "Build failed."
#  else
#    warn "Running 'make' without cleanup... (phase 1)"
#    make || error "Build failed."
  fi

  # Binary umbennenen (Phase 2)
  if ! check_skip_phase 2; then
  #  cp ./bin/miluphpc "./bin/$(get_name_binary "$mode")" || error "Failed to rename binary."
    info "copy and rename binary"
    cp "${LOCATIONS[root]}/bin/miluphpc" "$outputDir/compiled/$(get_name_binary "$mode")" || error "Failed to rename binary."
  else
    warn "Skipping renaming binary (phase 2)."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0