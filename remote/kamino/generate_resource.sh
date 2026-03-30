#!/bin/bash

# -----------------------------
# Usage function
# -----------------------------
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Generates SLURM configuration files for BinAC2.

Options:
  -h, --help            Show this help message
  -o, --output DIR      Output directory for config files
      --gpu-type TYPE   GPU type: a30, a100, h200 (default: a30)
      --nodes N         Minimum number of nodes to consider (default: 1)
      --mem MEM         Memory per node (default: 64G)
      --steps N         Number of simulation output steps
      --procs N         Generate configs only for this MPI process count
      --time HH:MM:SS   Generate configs only for this walltime
  -v, --verbose LEVEL   Verbosity level 0-4
  -c, --color           Enable colored output
EOF
}

# -----------------------------
# Main function
# -----------------------------
main() {
    # Resolve script path even when called via symlink
    SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SOURCE" ]; do
        DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
    done

    # Load environment setup
    source "$( dirname "$SOURCE" )/load_setup_shell.sh"

    # -----------------------------
    # Default configuration
    # -----------------------------
    OUTPUT_DIR=
    GPU_TYPE="a30"
    BASE_NODEs=1
    MEM="64G"

    # Number of simulation output snapshots written
    NSTEPs=10

    # Optional overrides
    CUSTOM_TIME=""
    CUSTOM_PROCS=""
    STRICT_COMBO=false


    # -----------------------------
    # Parse command line options
    # -----------------------------
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -o|--output) shift; OUTPUT_DIR="$1"; shift ;;
            --gpu-type) shift; GPU_TYPE="$1"; shift ;;
            --nodes) shift; BASE_NODEs="$1"; shift ;;
            --mem) shift; MEM="$1"; shift ;;
            --steps) shift; NSTEPs="$1"; shift ;;
            --time) shift; CUSTOM_TIME="$1"; shift ;;
            --procs) shift; CUSTOM_PROCS="$1"; shift ;;
            -v|--verbose) shift; flag_verbose="$1"; shift ;;
            -c|--color) flag_color=true; shift ;;
            --strict) STRICT_COMBO=true; shift ;;
            *) echo "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    if [[ -n "$OUTPUT_DIR" ]]; then
        # Output explizit angegeben → alles direkt dort ablegen
        FINAL_OUTPUT_DIR="$OUTPUT_DIR"
        mkdir -p "$FINAL_OUTPUT_DIR"
        USE_TIME_SUBDIR=false
    else
        FINAL_OUTPUT_DIR="${LOCATIONS[output]}/download/${execute_date}"
        mkdir -p "$FINAL_OUTPUT_DIR"
        USE_TIME_SUBDIR=true
    fi

    # Maximum GPUs available per node for each GPU type
    declare -A MAX_GPUS_PER_NODE=( ["a30"]=2 ["a100"]=4 ["h200"]=4 )

    # Default MPI process counts for scaling studies
    NPROCs_LIST=(1 2 4 8 16 32 64)

    # Override process list if requested
    if [[ -n "$CUSTOM_PROCS" ]]; then
        NPROCs_LIST=("$CUSTOM_PROCS")
    fi

    # Default walltime configurations
    TIME_LIST=("000:05:00" "000:20:00" "000:30:00" "001:00:00" "006:00:00" "025:00:00" "168:00:00")

    # Override time list if requested
    if [[ -n "$CUSTOM_TIME" ]]; then
        TIME_LIST=("$CUSTOM_TIME")
    fi

    MAX_PER_NODE=${MAX_GPUS_PER_NODE[$GPU_TYPE]}

    # -------------------------------------------------------
    # Generate configuration files for all combinations
    # -------------------------------------------------------
    for TIME in "${TIME_LIST[@]}"; do
        SAFE_TIME="${TIME//:/-}"
        if $USE_TIME_SUBDIR; then
            TIME_DIR="$FINAL_OUTPUT_DIR/T${SAFE_TIME}"
            mkdir -p "$TIME_DIR"
        else
            TIME_DIR="$FINAL_OUTPUT_DIR"
        fi


        # Loop over total MPI ranks
        for NPROCs in "${NPROCs_LIST[@]}"; do
            NTASKs=$NPROCs   # one MPI task per process

            # Try all node counts up to NPROCs
            for ((NODEs=BASE_NODEs; NODEs<=NPROCs; NODEs++)); do
                # Try all possible GPU counts per node
                for ((GPUs=1; GPUs<=MAX_PER_NODE; GPUs++)); do
                    # Nur gültige Kombinationen behalten
                    if $STRICT_COMBO && (( NODEs * GPUs != NPROCs )); then
                        continue
                    fi

                    if $USE_TIME_SUBDIR; then
                        GPU_DIR="$TIME_DIR/$GPU_TYPE"
                        mkdir -p "$GPU_DIR"
                    else
                        GPU_DIR="$FINAL_OUTPUT_DIR"
                    fi

                    # Construct filename with padded numbering
                    FILENAME="$GPU_DIR/P$(printf "%02d" "$NPROCs")_N$(printf "%02d" "$NODEs")x${GPUs}GPU${GPU_TYPE}_T${SAFE_TIME}${SUFFIX[resourcePath]}"

                    # -------------------------------------------------------
                    # Write resource configuration file
                    # -------------------------------------------------------
                    cat <<EOL > "$FILENAME"
# ==========================================================
# SLURM job configuration (auto-generated)
# ==========================================================

# Number of compute nodes requested
NODEs=$NODEs

# CPU cores per task
CPUs=1

# GPUs per node
GPUs=$GPUs

# GPU hardware type
GPU_TYPE=$GPU_TYPE

# Total MPI tasks / ranks
NTASKs=$NTASKs

# Walltime limit
TIME=$TIME

# Memory per node
MEM=$MEM


# ==========================================================
# Simulation parameters
# ==========================================================

# Total number of MPI processes
NPROCs=$NPROCs

# Number of output snapshots written
NSTEPs=$NSTEPs

EOL

                done
            done
        done
    done

    info "All configuration files have been created in $FINAL_OUTPUT_DIR"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0
