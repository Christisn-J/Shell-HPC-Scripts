#!/usr/bin/env bash

# ===============================================================
# Post-processing script for simulation performance analysis
# ===============================================================

# Associative array describing processing phases
declare -A PHASES=(
  [0]="Find performance.h5 files"
  [1]="Generate CSVs from performance.h5"
  [2]="Create evaluation plots from CSVs"
  [3]="Create scaling plots"
)


# ===============================================================
# Helper Functions
# ===============================================================

usage() {
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Postprocess simulation results (generate CSVs and summary)."
    echo ""
    echo "Options:"
    echo "  -d, --directory <folder>   Root result directory (required)"
    echo "  -k, --key <metric>         Performance key from time.csv (default: rhs)"
    echo "  -v, --verbose <N>          Verbosity level (default: 3)"
    echo "  -c, --color                Force colored output"
    echo "  -s, --scaling <strong|weak>  Scaling type (required)"
    echo "  -h, --help                 Show this help message"
    echo ""
}

# ---------------------------------------------------------------
# Create or activate Python virtual environment
# ---------------------------------------------------------------
create_or_activate_env() {
    if [[ ! -d ".venv" ]]; then
        warn "Virtual environment '.venv' not found. Creating..."
        command -v python3 >/dev/null 2>&1 || error "python3 not installed."
        python3 -m venv .venv || error "Failed to create virtual environment."
        source .venv/bin/activate
        pip install --upgrade pip
        pip install numpy matplotlib h5py scipy || error "Failed to install dependencies."
    else
        info "Activating existing virtual environment '.venv'"
        source .venv/bin/activate
    fi
}

# ---------------------------------------------------------------
# Compute median of numeric values
# ---------------------------------------------------------------
median() {
    printf '%s\n' "$@" | sort -n | awk '
    {
        a[NR]=$1
    }
    END {
        if (NR == 0) {
            print "NaN"
        } else if (NR % 2) {
            print a[(NR+1)/2]
        } else {
            print (a[NR/2] + a[NR/2+1]) / 2
        }
    }'
}

# ===============================================================
# Main
# ===============================================================
main() {

    SOURCE="${BASH_SOURCE[0]}"
    while [[ -h "$SOURCE" ]]; do
        DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
    done

    source "$( dirname "$SOURCE" )/load_setup_shell.sh"

    local ROOT_FOLDER=
    local KEY=
    local SCALING_TYPE=
    local SIM_TYPE=2
    local dim
    local skip_phases=()

    # -----------------------------------------------------------
    # Argument parsing
    # -----------------------------------------------------------
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dim)
              shift
              dim=$1
              shift
              ;;
            --skip)
              shift
              check_skip skip_phases "$1" 0 3
              shift
              ;;
            -d|--directory)
                shift
                ROOT_FOLDER="$1"
                [[ ! -d "$ROOT_FOLDER" ]] && error "Directory $ROOT_FOLDER not found."
                shift
                ;;
            -k|--key)
                shift
                KEY="$1"
                shift
                ;;
            -v|--verbose)
                shift
                flag_verbose="$1"
                shift
                ;;
            -c|--color)
                flag_color=true
                shift
                ;;
            -s|--scaling)
                shift
                SCALING_TYPE="$1"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    [[ -z "$ROOT_FOLDER" ]] && error "No root folder specified. Use -d <folder>."
    [[ -z "$KEY" ]] && KEY="rhsElapsed"

    # -----------------------------------------------------------
    # Determine scaling type automatically from folder path
    # -----------------------------------------------------------
    if [[ -z "$SCALING_TYPE" ]]; then
        if [[ "$ROOT_FOLDER" =~ weak ]]; then
            SCALING_TYPE="weak"
            info "Detected weak scaling from path."
        elif [[ "$ROOT_FOLDER" =~ strong ]]; then
            SCALING_TYPE="strong"
            info "Detected strong scaling from path."
        else
            error "Cannot detect scaling type from directory path. Please include 'strong' or 'weak' in the folder name, or use -s option."
        fi
    fi

    create_or_activate_env

    # ---------------------------------------------------------------
    # Find all performance.h5 files
    # ---------------------------------------------------------------
    if check_skip_phase 0; then
        info "Skipping Phase 0: (${PHASES[0]})"
        local perf_files=()
    else
      verbose 2 "==================== Phase 0 : ${PHASES[0]} ===================="
      info "Searching for performance.h5 files in $ROOT_FOLDER ..."
      mapfile -t perf_files < <(find "$ROOT_FOLDER" -type f -name "performance.h5")
      info "Found ${#perf_files[@]} performance files."
    fi

    # ---------------------------------------------------------------
    # Generate evaluation CSV files
    # ---------------------------------------------------------------
    if check_skip_phase 1; then
        info "Skipping Phase 1: (${PHASES[1]})"
    else
      verbose 2 "==================== Phase 1: ${PHASES[1]} ===================="
      for perf_file in "${perf_files[@]}"; do
          local folder
          folder=$(dirname "$perf_file")
          local eval_folder="$folder/../evaluation"
          mkdir -p "$eval_folder"

          verbose 2 "Generated CSVs for $perf_file"
          cmd=("${LOCATIONS[root]}/postprocessing/Performance.py"  --sim_type "$SIM_TYPE" --details --file "$perf_file" --output "$eval_folder" --scaling "$SCALING_TYPE" -v "$flag_verbose")
          execute "${cmd[@]}" --exe
      done
    fi

    value="t"
    local log_evaluation="$ROOT_FOLDER/evaluation"
    mkdir -p "$log_evaluation"
    local summary_file="$log_evaluation/performance_summary_$SCALING_TYPE.csv"
    # ---------------------------------------------------------------
    # Create performance summary CSV
    # ---------------------------------------------------------------
    if check_skip_phase 2; then
        info "Skipping Phase 2: (${PHASES[2]})"
    else
      verbose 2 "==================== Phase 2: ${PHASES[2]} ===================="

      echo "case,N_process,N_gpu,N_particle_median,N_loss_median,${value}_total,${value}_real" > "$summary_file"

      for perf_file in "${perf_files[@]}"; do
         verbose 2 "Processing performance file: $perf_file"

         local folder
         folder=$(dirname "$perf_file")

         # -----------------------------
         # Parse .res file for N_process & N_gpu
         # -----------------------------
         local res_file
         res_file=$(find "$folder/../configured" -maxdepth 1 -name "*.res" 2>/dev/null | head -n1)

         local N_process=0
         local N_gpu=0
         local N_node=0

         if [[ -f "$res_file" ]]; then
             N_process=$(grep "^NPROCs=" "$res_file" | cut -d'=' -f2)
             N_gpu=$(grep "^GPUs=" "$res_file" | cut -d'=' -f2)
             N_node=$(grep "^NODEs=" "$res_file" | cut -d'=' -f2)

             [[ -z "$N_process" ]] && N_process=0
             [[ -z "$N_gpu" ]] && N_gpu=0
             [[ -z "$N_node" ]] && N_node=1

             N_gpu=$((N_node * N_gpu))
         fi

         # -----------------------------
         # Compute median from particle CSV
         # -----------------------------
         local particle_csv="$folder/../evaluation/particle_${SCALING_TYPE}_P${N_process}_N*_sim${SIM_TYPE}.csv"
         particle_csv=$(printf "%s\n" $particle_csv 2>/dev/null | head -n1)

         [[ ! -f "$particle_csv" ]] && { warn "Particle CSV not found for N_process=$N_process"; continue; }

         # Header und Daten
         header_line=$(head -n1 "$particle_csv")
         mapfile -t particle_lines < <(tail -n +2 "$particle_csv")

         # -----------------------------
         # Spalten für numParticles und loss dynamisch bestimmen
         # -----------------------------
         # numParticles ist immer die erste Spalte
         num_field=1

         # Suche die Spalte 'loss' anhand des Headers
         loss_field=$(awk -F';' -v col="loss" '{
             for (i=1;i<=NF;i++) if($i==col) print i
         }' <<< "$header_line")

         # -----------------------------
         # Werte sammeln
         # -----------------------------
         local N_values=() Loss_values=()
         for line in "${particle_lines[@]}"; do
             N_values+=($(echo "$line" | cut -d';' -f"$num_field"))
             if [[ -n "$loss_field" ]]; then
                 Loss_values+=($(echo "$line" | cut -d';' -f"$loss_field"))
             fi
         done

         # -----------------------------
         # Mediane berechnen
         # -----------------------------
         local N_particle_median
         local N_loss_median

         N_particle_median=$(median "${N_values[@]}")

         if [[ -n "$loss_field" ]]; then
             N_loss_median=$(median "${Loss_values[@]}")
         else
             warn "Cannot determine loss column in $particle_csv"
             N_loss_median="NaN"
         fi

         # -----------------------------
         # Construct exact time CSV path (_reference_)
         # -----------------------------
         N_particle=${N_particle_median%.*}
         time_csv="$folder/../evaluation/time_${SCALING_TYPE}_P${N_process}_N${N_particle}_reference_sim${SIM_TYPE}.csv"

         if [[ ! -f "$time_csv" ]]; then
             warn "Reference time CSV not found: $time_csv"
             continue
         fi

#         debug 3 "Using time CSV: $time_csv"
#         debug 3 "Using particle CSV: $particle_csv"

         # -----------------------------
         # Extract performance key
         # -----------------------------
         local key_total key_real
         read key_total key_real < <(
             awk -F';' -v k="$KEY" 'NR>2 { gsub(/\r/,"",$1); if($1==k) print $3, $4 }' "$time_csv"
         )

         if [[ -z "$key_total" || -z "$key_real" ]]; then
             warn "Key '$KEY' not found in CSV: $time_csv"
             key_total="NaN"
             key_real="NaN"
         fi

         # -----------------------------
         # Append to summary CSV
         # -----------------------------
         local case_name
         case_name=$(head -n1 "$time_csv" | cut -d';' -f1)

         echo "$case_name,$N_process,$N_gpu,$N_particle_median,$N_loss_median,$key_total,$key_real" >> "$summary_file"
      done

      info "Summary CSV created at $summary_file"
    fi

    # ---------------------------------------------------------------
    # Phase 3: Create scaling plots from summary CSV
    # ---------------------------------------------------------------
    if check_skip_phase 3; then
        info "Skipping Phase 3: (${PHASES[3]})"
    else
      verbose 2 "==================== Phase 3: ${PHASES[3]} ===================="
      info "Creating scaling plots from summary CSV..."

      cmd=("${LOCATIONS[root]}/postprocessing/plotScalingPerformance.py" -i "$summary_file" -V "$value" -s "$SCALING_TYPE" -m all -v "$flag_verbose" -d "$dim")
      execute "${cmd[@]}" --exe

      info "Postprocessing completed successfully."
    fi
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi