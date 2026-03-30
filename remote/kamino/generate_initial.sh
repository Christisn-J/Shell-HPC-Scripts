#!/bin/bash
# ===================================================================
# Generate alloy testcases (2D or 3D) with specified velocity
# Automatically generate all empirical particle numbers if --all
# is set.
#
# Improvements in this version:
#   • Strict bash mode enabled for safer execution
#   • Python virtual environment existence is validated
#   • Mode directory & initial_alloy.py are validated before run
#   • Centralized Δ selection logic (no duplicated logic)
# ===================================================================
#
# This script generates testcases for alloy simulations using the
# `initial_alloy.py` Python script. It supports:
#   - 2D and 3D modes
#   - Specifying impactor velocity
#   - Generating multiple empirical particle numbers automatically
#   - Selecting which particle attributes to plot/output
#
# Example:
#   ./scripts/remote/kamino/generate_initial.sh --mode alloy_disc_colliding_plate --velocity -7e-3 -v 3 -k "v rho" --all
#   ./scripts/remote/kamino/generate_initial.sh --mode alloy_sphere_colliding_cube --velocity -7e-3 -v 3 -k "v rho" --all
# ===================================================================

# --- Strict bash mode (important for robustness) ---
#set -euo pipefail

# --- Help / usage ---
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script generates initial testcases for alloy simulations using Python scripts.
Supports 2D and 3D cases, specific velocities, and automated generation for multiple
empirical particle numbers.

Options:
  --mode MODE[,MODE2,...]   Testcase mode(s) (folder(s) in ./testcases). Required.
  -d, --dim DIM             Dimension (2 or 3). Optional if mode has default.
  --velocity VELOCITY       Impactor velocity (float, e.g., -7000.0). Default: -7000.0
  --delta DELTA             Specific Δ value (float). Use this or --all.
  --all                     Generate all empirical particle numbers from DELTA_MODES table
  -o, --output DIR          Output directory. Default: ./output/YYYYMMDD/
  -k, --keys "KEYS"         Keys to plot/output (comma-separated string). Default: "x,v,m,matId,rho,e"
  -v, --verbose LEVEL       Verbosity level (0-4). Default: 3
  -c, --color               Enable colored output
  -h, --help                Show this help message

Notes:
  * Either --delta or --all must be specified.
  * When using --all, N_tot and SML values are read from DELTA_MODES.
  * SML_opt is used if available; otherwise SML_est is used.
  * Generates initial_alloy.py cases, material files, and optionally copies config.info.
EOF
}


header_index_for() {
    local mode="$1"
    local column="$2"

    IFS=',' read -ra headers <<< "${HEADER_MODES[$mode]}"

    for i in "${!headers[@]}"; do
        if [[ "${headers[$i]}" == "$column" ]]; then
            echo "$i"
            return 0
        fi
    done

    error "Column '$column' not found for mode '$mode'"
}

values_for_column() {
    local mode="$1"
    local column="$2"

    local idx
    idx=$(header_index_for "$mode" "$column")

    while read -r line; do
        [[ -z "$line" ]] && continue

        IFS=',' read -ra fields <<< "$line"
        echo "${fields[$idx]}"

    done <<< "${DELTA_MODES[$mode]}"
}


# --- Run generator ---
generate_case() {
  local N="$1"
  local DELTA="$2"
  local OUTPUT_DIR="$3"
  local SLICE_FLAG=""
  [[ "$DIM" -eq 3 ]] && SLICE_FLAG="--slice"

  verbose 1 "============================================================"
  info "Running initial_alloy.py with Δ=$DELTA N=$N DIM=$DIM velocity=$VELOCITY"

  read -r -a keys_array <<< "$PLOT_KEYS"
  execute python3 "$PY_SCRIPT" \
      -d "$DIM" \
      --velocity="$VELOCITY" \
      --delta="$DELTA" \
      -o "$OUTPUT_DIR" \
      --verbose "$flag_verbose" \
      -k "${keys_array[@]}" \
      --optimize \
      --scale x=centi\
      $SLICE_FLAG --exe
}


main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
   DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
   SOURCE="$(readlink "$SOURCE")"
   [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"

  # --- Runtime variables ---
  DIM=
  MODE=
  VELOCITY=-7000.0
  OUTPUT_DIR=
  ALL_N=false
  PLOT_KEYS="x v m matId rho e"
  BASE_TIME_MIN=30  # 30 Minuten für 1 Prozess

  # --- Argument parsing ---
  while [[ $# -gt 0 ]]; do
      case "$1" in
          --mode)
              shift
              check_arg "--mode" "$1"
              # selected_modes wird mit allen gültigen Modi gefüllt (Array)
              check_select selected_modes "$1" "${VALID_MODES[@]}"
              shift
              ;;
          -d|--dim)
              shift
              check_arg "--dim" "$1"
              validate_natural_numbers "dimension" "$1" 1 3
              DIM="$1"
              shift
              ;;
          -n|--steps)
            shift
            check_arg "--steps" "$1"
            check_natural_numbers "--steps" "$1" "$(get_range_min steps)" "$(get_range_max steps)"
            steps="$1"
            shift
            ;;
          --velocity)
              shift
              check_arg "--velocity" "$1"
              validate_float "$1"
              VELOCITY="$1"
              shift
              ;;
          --delta)
              shift
              check_arg "--delta" "$1"
              validate_float "$1"
              DELTA="$1"
              shift
              ;;
          -o|--output)
              shift
              check_arg "--output" "$1"
              OUTPUT_DIR="$1"
              shift
              ;;
          -c|--color)
              flag_color=true
              shift
              ;;
          -v|--verbose)
              shift
              check_arg "--verbose" "$1"
              validate_natural_numbers "verbosity level" "$1" 0 4
              flag_verbose="$1"
              shift
              ;;
          -k|--keys)
              shift
              check_arg "--keys" "$1"
              PLOT_KEYS="$1"
              # Kommas in Leerzeichen umwandeln
              PLOT_KEYS="${PLOT_KEYS//,/ }"
              shift
              ;;
          --all)
              ALL_N=true
              shift
              ;;
          -h|--help)
              usage
              exit 0
              ;;
          *)
              echo "Unknown option: $1"
              usage
              exit 1
              ;;
      esac
  done
  # --- Default output directory ---
  if [[ -z "$OUTPUT_DIR" ]]; then
      DATE_TAG="$(date +%Y%m%d)"
      OUTPUT_DIR="${LOCATIONS[output]}/${DATE_TAG}/${git_branch}"
  fi
  mkdir -p "${OUTPUT_DIR}"

  if [[ ${#selected_modes[@]} -eq 0 ]]; then
      error "No modes specified. Available modes: ${VALID_MODES[*]}"
  fi

  # --- Activate Python venv safely ---
  VENV_PATH="${LOCATIONS[root]}/.venv/bin/activate"
  if [[ ! -f "$VENV_PATH" ]]; then
    error "Python virtual environment not found (.venv missing)"
  fi
  info "Activated Python environment: $VENV_PATH"
  source "$VENV_PATH"

  for MODE in "${selected_modes[@]}"; do
    if ! check_valid_mode "$MODE" VALID_MODES; then
      error "Invalid mode '$MODE'. Available modes: ${VALID_MODES[*]}"
    fi

    MODE_PATH="${LOCATIONS[testcases]}/$MODE"
    # Finde das erste Python-Skript, das initial_*.py entspricht
    PY_SCRIPTS=( "$MODE_PATH"/initial_*.py )

    # Prüfe, ob mindestens eins gefunden wurde
    if [[ ${#PY_SCRIPTS[@]} -eq 0 ]]; then
        error "No Python scripts matching initial_*.py found in $MODE_PATH"
    fi

    if [[ -z "$DIM" ]]; then
        if [[ -n "${MODE_DEFAULT_DIM[$MODE]}" ]]; then
            DIM="${MODE_DEFAULT_DIM[$MODE]}"
            info "Dimension for mode '$MODE' not specified, using default DIM=$DIM"
        else
            error "No dimension specified for mode '$MODE' and no default available"
        fi
    fi

    # Optional: nimm das erste gefundene Script (falls mehrere)
    PY_SCRIPT="${PY_SCRIPTS[0]}"

    # --- Default output directory ---
    MODE_OUTPUT_DIR="${OUTPUT_DIR}/${MODE}"
    mkdir -p "${MODE_OUTPUT_DIR}"

    info "Generating $MODE testcases in ${DIM}D with velocity=${VELOCITY}..."

    if [[ -n "${DELTA-}" ]]; then
        # Wenn --delta explizit gesetzt, N aus Delta ableiten
        generate_case "nan" "$DELTA" "$MODE_OUTPUT_DIR"
    elif [ "$ALL_N" = true ]; then
      idx=0
      # Indexe der Spalten aus HEADER_MODES bestimmen
      idx_delta=$(header_index_for "$MODE" "delta_particles")
      idx_Ntot=$(header_index_for "$MODE" "N_tot")
      idx_SMLest=$(header_index_for "$MODE" "SML_estimate")
      idx_SMLopt=$(header_index_for "$MODE" "SML_optimize")

      # Jede Zeile aus DELTA_MODES direkt verarbeite
      while read -r line; do
          [[ -z "$line" ]] && continue

          IFS=',' read -ra fields <<< "$line"
          DELTA="${fields[$idx_delta]}"
          N_tot="${fields[$idx_Ntot]}"
          SML_est="${fields[$idx_SMLest]}"
          SML_opt="${fields[$idx_SMLopt]}"

          # Prüfen, ob N_tot eine Zahl ist, sonst als "nan" belassen
          if [[ "$N_tot" =~ ^[0-9.]+([eE][-+]?[0-9]+)?$ ]]; then
              # Mantisse & Exponent berechnen
              exponent=$(awk "BEGIN{printf \"%+02d\", int(log($N_tot)/log(10))}")
              mantisse=$(awk "BEGIN{printf \"%.6f\", $N_tot / (10^$exponent)}")

              OUTPUT_SUBDIR="$MODE_OUTPUT_DIR/Ne${exponent}m${mantisse}"
          else
              OUTPUT_SUBDIR="$MODE_OUTPUT_DIR/Nnan"
          fi

          mkdir -p "$OUTPUT_SUBDIR"

          # Wenn SML_opt nan ist → SML_est verwenden
          if [[ "$SML_opt" =~ ^nan$ ]]; then
              SML="$SML_est"
          else
              SML="$SML_opt"
          fi

          info "Generating case for Δ=$DELTA, N_tot=$N_tot, SML=$SML"

          # Generate the case
          generate_case "$N_tot" "$DELTA" "$OUTPUT_SUBDIR"

          scriptPath="${LOCATIONS[script]}/generate_material.sh"
          cmd=("$scriptPath" -d "$DIM" --delta "$DELTA" --sml "$SML" --verbose "$flag_verbose" --output "$OUTPUT_SUBDIR")
          execute "${cmd[@]}" --exe


          if (( idx <= 6 )); then
              NPROCs=$(( 2**idx ))
              TOTAL_MIN=$(( BASE_TIME_MIN * NPROCs ))
          else
              NPROCs=""
              TOTAL_MIN=$(( BASE_TIME_MIN * 1 ))
          fi

          HOURS=$(( TOTAL_MIN / 60 ))
          MINUTES=$(( TOTAL_MIN % 60 ))
          SECONDS=0
          TIME=$(printf "%03d:%02d:%02d" "$HOURS" "$MINUTES" "$SECONDS")

          # Generate resource file ONLY if NPROCs gesetzt
          if [[ -n "$NPROCs" ]]; then
              scriptPath="${LOCATIONS[script]}/generate_resource.sh"
              cmd=("$scriptPath" --gpu-type "a30" --mem "64G" --steps "$steps" --time "$TIME"  --procs "$NPROCs" --verbose "$flag_verbose" --output "$OUTPUT_SUBDIR" --strict)
              execute "${cmd[@]}" --exe
              info "Resource file generated for NPROCs=$NPROCs"
          fi

          # Datei kopieren, falls sie existiert
          if [[ -f "$MODE_PATH/config.info" ]]; then
              cp "$MODE_PATH/config.info" "$OUTPUT_SUBDIR/"
              info "Copied config.info to $OUTPUT_SUBDIR"
          else
              warn "No config.info found in $MODE_PATH"
          fi

          ((idx++))
      done <<< "${DELTA_MODES[$MODE]}"
    else
     error "Either --delta or --all must be specified for mode '$MODE'"
    fi

    info "Testcase generation complete. Outputs in $MODE_OUTPUT_DIR"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
return 0
