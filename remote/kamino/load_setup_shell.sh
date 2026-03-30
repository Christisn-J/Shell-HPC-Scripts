#!/bin/bash
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

    cat <<EOF
${ACTIVE_COLORS[BOLD]}Usage:${ACTIVE_COLORS[RESET]}
  ${ACTIVE_COLORS[CYAN]}$(basename "$0")${ACTIVE_COLORS[RESET]} [options]

${ACTIVE_COLORS[BOLD]}Options:${ACTIVE_COLORS[RESET]}
  ${ACTIVE_COLORS[GREEN]}-h${ACTIVE_COLORS[RESET]}, ${ACTIVE_COLORS[GREEN]}--help${ACTIVE_COLORS[RESET]} Show this help message and exit.
  ${ACTIVE_COLORS[GREEN]}-c${ACTIVE_COLORS[RESET]}, ${ACTIVE_COLORS[GREEN]}--color${ACTIVE_COLORS[RESET]} Enable colored output (if the terminal supports it).
  ${ACTIVE_COLORS[GREEN]}--steps <NUM>${ACTIVE_COLORS[RESET]} Set the number of steps (default: ${ACTIVE_COLORS[YELLOW]}10${ACTIVE_COLORS[RESET]}).
  ${ACTIVE_COLORS[GREEN]}--add <NAME>${ACTIVE_COLORS[RESET]} Add an extra mode to VALID_MODES.
  ${ACTIVE_COLORS[GREEN]}-v${ACTIVE_COLORS[RESET]}, ${ACTIVE_COLORS[GREEN]}--verbose <LVL>${ACTIVE_COLORS[RESET]} Set verbosity level (default ${ACTIVE_COLORS[YELLOW]}3${ACTIVE_COLORS[RESET]})
${ACTIVE_COLORS[BOLD]}Available verbosity level:${ACTIVE_COLORS[RESET]}
  ${ACTIVE_COLORS[YELLOW]}0${ACTIVE_COLORS[RESET]} = No output
  ${ACTIVE_COLORS[YELLOW]}1${ACTIVE_COLORS[RESET]} = Basic info only
  ${ACTIVE_COLORS[YELLOW]}2${ACTIVE_COLORS[RESET]} = Extended runtime details
  ${ACTIVE_COLORS[YELLOW]}3${ACTIVE_COLORS[RESET]} = Full debug info (default)
${ACTIVE_COLORS[BOLD]}Current configuration:${ACTIVE_COLORS[RESET]}
  Script path: ${ACTIVE_COLORS[YELLOW]}${LOCATIONS[script]:-<not set>}${ACTIVE_COLORS[RESET]}
  Root directory: ${ACTIVE_COLORS[YELLOW]}${LOCATIONS[root]:-<not set>}${ACTIVE_COLORS[RESET]}
EOF

    # Optional: Liste der verfügbaren Testmodes nachträglich ausgeben
    if [[ ${#VALID_MODES[@]} -gt 0 ]]; then
      echo -e "${ACTIVE_COLORS[BOLD]}Current available modes:${ACTIVE_COLORS[RESET]}"
      for mode in "${VALID_MODES[@]}"; do
        echo -e "  ${ACTIVE_COLORS[CYAN]}- $mode${ACTIVE_COLORS[RESET]}"
      done
      echo
    fi

  }

  show() {
    debug 1 "=== Variablenübersicht (Level: $flag_verbose) ==="

    # --- Level 1: Basisinformationen ---
    debug 1 "VALID_MODES:         ${VALID_MODES[*]}"
    debug 1 "execute_date:        $execute_date"
    debug 1 "git_branch:          $git_branch"

    # --- Level 2: erweiterte Laufzeitdetails ---
    debug 2 "flag_color:          $flag_color"
    debug 2 "flag_verbose:        $flag_verbose"
    debug 2 "steps:               $steps"

    # --- Level 3: technische & Pfad-Details ---
    debug 3 "SOURCE:              $SOURCE"
    debug 3 "SHELL:               ${LOCATIONS[shell]}"
    debug 3 "ROOT:                ${LOCATIONS[root]}"
    debug 3 "TESTCASES:           ${LOCATIONS[testcases]}"
    debug 3 "SETUP:               ${LOCATIONS[setup]}"

    # --- Falls spezielle Kontextvariablen gesetzt sind ---
    if [[ -n "${VARIANT_KEY:-}" || -n "${PHASE_ID:-}" ]]; then
      debug 3 "VARIANT_KEY:         ${VARIANT_KEY:-<unset>}"
      debug 3 "PHASE_ID:            ${PHASE_ID:-<unset>}"
    fi

    debug 1 "======================================================"
  }
fi

normalize_locations() {
  local kind="${1:-absolute}"
  local key val

  for key in "${!LOCATIONS[@]}"; do
    val="${LOCATIONS[$key]}"
    case "$kind" in
      absolute)
        LOCATIONS[$key]="$(realpath "$val")"
        ;;
      relative)
        LOCATIONS[$key]="$(realpath --relative-to="${LOCATIONS[root]}" "$val")"
        ;;
      *)
        echo "Unknown path: $kind" >&2
        return 1
        ;;
    esac
  done
}

main(){
  # --- Resolve Skript-Verzeichnis ---
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done

  # Default path kind
  : ${path_kind:="absolute"}
  : ${execute_date:=$(date +%Y%m%d)}
  : ${git_branch:=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "local")}
  : ${flag_color:=false}
  : ${flag_empty:=true}
  : ${flag_verbose:=3}
  : ${process:=1}
  : ${steps:=10}

  # --- Assoziatives Array für alle relevanten Verzeichnisse ---
  declare -Ag LOCATIONS

  LOCATIONS[root]="$(pwd)"
  LOCATIONS[script]="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
  LOCATIONS[testcases]="${LOCATIONS[root]}/testcases"
  LOCATIONS[utils]="${LOCATIONS[script]}/utils"
  LOCATIONS[output]="${LOCATIONS[root]}/output"
#  LOCATIONS[setup]="${LOCATIONS[root]}/setup/${execute_date}"

  # Alle .sh Dateien rekursiv aus utils/ laden (sortiert)
  if [ -d "${LOCATIONS[utils]}" ]; then
    while IFS= read -r libfile; do
      [ -r "$libfile" ] && source "$libfile"
    done < <(find "${LOCATIONS[utils]}" -type f -name '*.sh' | sort)
  fi

#  # Check if the folder exists
#  if [[ ! -d "${LOCATIONS[setup]}" ]]; then
#    warn "Setup directory '${LOCATIONS[setup]}' does not exist! Falling back to 'default'."
#    LOCATIONS[setup]="${LOCATIONS[root]}/setup/default"
#  fi

  shopt -s nullglob
  VALID_MODES=()
  for dir in "${LOCATIONS[testcases]}"/*; do
    [[ -d "$dir" ]] && VALID_MODES+=( "$(basename "$dir")" )
  done
  shopt -u nullglob

  if git rev-parse --git-dir > /dev/null 2>&1; then
      # Git-Repo vorhanden, alle Branches einlesen
      mapfile -t VALID_BRANCHES < <(git for-each-ref --format='%(refname:short)' refs/heads/)
  else
      # Kein Git-Repo, Default Branch setzen
      VALID_BRANCHES=("local")
  fi

  # --- Argumente parsen ---
  while [[ $# -gt 0 && "$1" == -* ]]; do
    case "$1" in
      -c|--color)
        shift
        if check_color_support; then
          flag_color=true
        else
          flag_color=false
        fi
        ;;
       --steps)
         shift
         check_arg "--steps" "$1"
         check_natural_numbers "--steps" "$1" "$(get_range_min steps)" "$(get_range_max steps)"
         steps="$2"
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

      --empty)
        shift
        flag_empty=false
        ;;
      --add)
        shift
        VALID_MODES+=( "$1" )
        shift
        ;;
      --path-kind)
        shift
        check_arg "--path-kind" "$1"
        if [[ "$1" =~ ^(absolute|relative)$ ]]; then
          path_kind="$1"
        else
          error "--path-kind must be 'absolute' or 'relative'"
        fi
        shift
        ;;
      *)
        logger "[Error]" red "Unknown option: $1"
        usage "$flag_color"
        exit 1
        ;;
    esac
  done

  # --- Pfade anpassen ---
  normalize_locations "$path_kind"

  # --- Apply empty flag ---
  if [[ "$flag_empty" == true ]]; then
    outputDir=""
    scriptPath=""
    initialConditionPath=""
    resourcePath=""
    configPath=""
    parameterPath=""
    skip_phases=()
    selected_modes=()
    layer=0
    plot_type=0
  fi

  SLEEP_INTERVAL=10
  SLEEP_DELAY=5
}

# Prüfen, ob dieses Skript direkt ausgeführt wird
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  show
  exit 0
fi

main
return 0
