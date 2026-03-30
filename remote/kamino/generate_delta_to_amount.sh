#!/bin/bash
# ===================================================================
# Generate Δ=N table using initial_alloy.py in --dry mode
# Automatically generates Δ values from start to end with a specified step
# The output is a CSV table containing particle statistics for each Δ
# ===================================================================

# ===================================================================
# Print usage/help for the Δ=N table generator script
# ===================================================================
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generate Δ=N tables using initial_alloy.py in --dry mode.
Automatically generates Δ values from start to end with a specified step.

Options:
  --mode MODE              Testcase mode (folder in ./testcases).
                           Multiple modes can be specified as comma-separated list.
  -d, --dim DIM            Simulation dimension (2 or 3).
  --delta START END STEP   Δ range: start, end, and step values.
                           Example: --delta 4.0e-4 1.0e-5 -5.0e-5
  -o, --output DIR         Output directory. Default: ./output/YYYYMMDD
  -c, --color              Enable colored output (if supported)
  -v, --verbose LEVEL      Verbosity level (0=quiet, 1=errors only, up to 4=debug)
  --optimize               Enable optimization mode (adds --optimize to Python script)
  -h, --help               Show this help message and exit

Examples:
  # Generate Δ=N table for mode 'alloy_disc_colliding_plate' in 3D
  $(basename "$0") --mode alloy_disc_colliding_plate -d 3 --delta 4.0e-4 1.0e-5 -5.0e-5

  # Generate for multiple modes and enable optimization
  $(basename "$0") --mode mode1,mode2 -d 2 --delta 5.0e-4 1.0e-5 -1.0e-5 --optimize
EOF
}


main() {
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
   DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
   SOURCE="$(readlink "$SOURCE")"
   [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"

  # --- Runtime variables ---
  DIM=                          # Dimension (2D or 3D)
  MODE=                         # Selected mode (testcase folder)
  VELOCITY="-7e3"               # Default impactor velocity
  OUTPUT_DIR=                    # Output directory for CSV
  flag_optimize=false            # Flag to enable optimization

  # --- Delta range variables ---
  DELTA_START=
  DELTA_END=
  DELTA_STEP=
  DELTA_MODE="linear"


  # --- Argument parsing ---
  while [[ $# -gt 0 ]]; do
      case "$1" in
          --mode)
              shift
              check_arg "--mode" "$1"
              # Fill selected_modes array with valid modes
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
          --delta)
              shift
              # Mode (optional, default linear)
              if [[ -n "$1" && "$1" =~ ^(linear|log|relative|mantissa)$ ]]; then
                  DELTA_MODE="$1"
                  shift
              else
                  DELTA_MODE="linear"
              fi

              # Falls keine weiteren Werte kommen → Defaults später
              if [[ -z "$1" || "$1" == -* ]]; then
                  continue
              fi
              # Start
              check_arg "--delta_start" "$1"; validate_float "$1"; DELTA_START="$1"; shift
              # End
              check_arg "--delta_end" "$1"; validate_float "$1"; DELTA_END="$1"; shift
              # Falls keine weiteren Werte kommen → Defaults später
              if [[ -z "$1" || "$1" == -* ]]; then
                  continue
              fi
              # Step
              check_arg "--delta_step" "$1"; validate_float "$1"; DELTA_STEP="$1"; shift
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
          --optimize)
              flag_optimize=true
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

  # --- Set default delta values if not provided ---
  if [[ -z "$DELTA_START" || -z "$DELTA_END" ]]; then
      info "Delta parameters not provided; using default values."
      DELTA_START=1.00e-03
      DELTA_END=1.00e-05
  fi
  if [[ -z "$DELTA_STEP" ]]; then
      case "$DELTA_MODE" in
          linear)
              # Einfacher linearer Schritt: 10 gleiche Schritte zwischen START und END
              DELTA_STEP=$(awk -v s="$DELTA_START" -v e="$DELTA_END" 'BEGIN {print (s - e)/10}')
              ;;
          log)
              DELTA_STEP=$(awk -v s="$DELTA_START" -v e="$DELTA_END" 'BEGIN {print 0.1 * (s - e) / e}')
              ;;
          relative)
              # Schritt = 10% des aktuellen Werts
              DELTA_STEP=$(awk 'BEGIN{print 0.1}')
              ;;
          mantissa)
              # Für Mantissa-Modus: Schritt = 1/10 des Startwertes
              DELTA_STEP=$(awk -v s="$DELTA_START" 'BEGIN{print s/10}')
              ;;
          *)
              # Fallback linear, 10 Schritte
              DELTA_STEP=$(awk -v s="$DELTA_START" -v e="$DELTA_END" 'BEGIN {print (s - e)/10}')
              ;;
      esac
      info "DELTA_STEP not provided, using default: $DELTA_STEP for mode $DELTA_MODE"
  fi


  verbose 2 "Delta start: $DELTA_START, Delta end: $DELTA_END, Delta step: $DELTA_STEP, Delta mode: $DELTA_MODE"

  # --- Set default output directory if not specified ---
  if [[ -z "$OUTPUT_DIR" ]]; then
      DATE_TAG="$(date +%Y%m%d)"
      OUTPUT_DIR="${LOCATIONS[output]}/${DATE_TAG}/${git_branch}"
  fi
  mkdir -p "${OUTPUT_DIR}"

  # --- Validate selected modes ---
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

  # --- Loop over selected modes ---
  for MODE in "${selected_modes[@]}"; do
    if ! check_valid_mode "$MODE" VALID_MODES; then
      error "Invalid mode '$MODE'. Available modes: ${VALID_MODES[*]}"
    fi

    MODE_PATH="${LOCATIONS[testcases]}/$MODE"
    # Find first Python script matching initial_*.py
    PY_SCRIPTS=( "$MODE_PATH"/initial_*.py )

    if [[ ${#PY_SCRIPTS[@]} -eq 0 ]]; then
        error "No Python scripts matching initial_*.py found in $MODE_PATH"
    fi

    # Use default dimension if not provided
    if [[ -z "$DIM" ]]; then
        if [[ -n "${MODE_DEFAULT_DIM[$MODE]}" ]]; then
            DIM="${MODE_DEFAULT_DIM[$MODE]}"
            warn "Dimension for mode '$MODE' not specified, using default DIM=$DIM"
        else
            error "No dimension specified for mode '$MODE' and no default available"
        fi
    fi

    # Select the first Python script if multiple exist
    PY_SCRIPT="${PY_SCRIPTS[0]}"

    MODE_OUTPUT_DIR="${OUTPUT_DIR}/${MODE}"
    mkdir -p "${MODE_OUTPUT_DIR}"

    # --- Prepare CSV output ---
    DATE_TAG="$(date +%Y%m%d)"
    OUTPUT_FILE="${MODE_OUTPUT_DIR}/${DATE_TAG}_${DIM}_${MODE}_${DELTA_MODE}_delta_to_amount.csv"
    > "$OUTPUT_FILE"  # Clear / create file

    # CSV header with creation timestamp
    DATE_TAG="$(date '+%Y-%m-%d %H:%M:%S')"
    HEADER="${HEADER_MODES[$MODE]}"
    echo "# Δ=N table generated on: $DATE_TAG" >> "$OUTPUT_FILE"
    echo "$HEADER" >> "$OUTPUT_FILE"

    # --- Loop through delta values ---
    DELTA=$DELTA_START
    while awk -v d="$DELTA" -v e="$DELTA_END" 'BEGIN {exit !(d >= e)}'; do

        # Build Python command as array
        cmd=(python3 "$PY_SCRIPT" -d "$DIM" --delta="$DELTA" --verbose "$flag_verbose" --dry --pipeline)
        $flag_optimize && cmd+=(--optimize)
        [[ -z "$VELOCITY" ]] && cmd+=( --velocity "$VELOCITY")

        # Execute Python script and capture JSON output
        verbose 1 "============================================================"
        FULL_OUTPUT=$(execute "${cmd[@]}" --exe)
        echo "$FULL_OUTPUT" | head -n 1
        verbose 1 "------------------------------------------------------------"

        # Extract JSON only (e.g., lines starting with { or [)
        DATA=$(echo "$FULL_OUTPUT" | grep -o '{.*}')

        # Then parse JSON safely
        CSV_LINE=$(echo "$DATA" | python3 -c "
import sys,json
d = json.load(sys.stdin)
line = [str(d['data'][h]) for h in d['header']]
print(','.join(line))
        ")

        # Write CSV line to file
        echo "$CSV_LINE" >> "$OUTPUT_FILE"

        # Optionally print to terminal
        info "$CSV_LINE"

        # Increment to next delta value
        if [[ "$DELTA_MODE" == "linear" ]]; then
            DELTA=$(awk -v d="$DELTA" -v s="$DELTA_STEP" 'BEGIN {
            print d - s}
            ')
        elif [[ "$DELTA_MODE" == "relative" ]]; then
            DELTA=$(awk -v d="$DELTA" -v s="$DELTA_STEP" 'BEGIN {
            printf "%.10e\n", d * (1 - s)
            }')
        elif [[ "$DELTA_MODE" == "log" ]]; then
            DELTA=$(awk -v d="$DELTA" -v s="$DELTA_STEP" 'BEGIN {
                d_next = d * (1 - s)
                if (d_next < 0) d_next = 0
                printf "%.10e\n", d_next
            }')
        elif [[ "$DELTA_MODE" == "mantissa" ]]; then
            # Berechne führende Exponent
            DELTA=$(awk -v d="$DELTA" -v s="$DELTA_STEP" 'BEGIN {
                if (d <= 0) {print 0; exit}
                e=int(log(d)/log(10))
                d_next = d - s*10^e
                printf "%.10e\n", d_next
            }')
        else
            error "Unknown --delta mode: '$DELTA_MODE'. Allowed modes: linear, relative, log, mantissa."
        fi
    done

    info "Δ-N table saved to $OUTPUT_FILE"

    PLOT_SCRIPT="${LOCATIONS[root]}/postprocessing/plotDeltaToAmount.py"
    execute python3 "$PLOT_SCRIPT" "$OUTPUT_FILE" --dim "$DIM" -o "$MODE_OUTPUT_DIR" --test_mode "$MODE" --delta_mode "$DELTA_MODE" --exe
  done
}

# --- Run main if script executed directly ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
return 0
