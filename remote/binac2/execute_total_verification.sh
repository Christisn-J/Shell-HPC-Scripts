#!/bin/bash

# This script merges selected "Weak" and "Strong" data folders from multiple date-based sources
# into a single consolidated folder. It generates a detailed README.md describing the structure
# and optionally removes "validation" and "evaluation" folders.
#
# Phases:
#   0: Copy Weak/Strong folders while preserving relative structure
#   1: Generate README.md documenting the merged dataset
#   2: Remove any "validation" or "evaluation" folders
#   3: Perform validation scripts on selected datasets
#   4: Perform performance analysis scripts on selected datasets
#
# Logging functions (info, warn, error, verbose, etc.) are assumed to be defined.
# Each phase can be skipped using the --skip option.

set -e

# -----------------------
# Phase definitions
# -----------------------
declare -a PHASES=(
  [0]="copy-weak-strong"
  [1]="generate-readme"
  [2]="remove-validation-evaluation"
  [3]="perform-validation"
  [4]="perform-performance-analysis"
)

# -----------------------
# Usage function
# -----------------------
usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -d, --directory <folder>       Target folder (default: output/overall)"
  echo "  -v, --verbose <N>              Verbosity level (default: 3)"
  echo "  -c, --color                    Enable color output"
  echo "  --skip <PHASES>                Comma-separated phases to skip (e.g., 2)"
  echo "  -h, --help                     Show this help"
}

# -----------------------
# Main function
# -----------------------
main() {
  # -----------------------
  # Resolve script source path
  # -----------------------
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  SCRIPT_DIR="$(dirname "$SOURCE")"

  # Optional: load setup (if available)
  [[ -f "$SCRIPT_DIR/load_setup_shell.sh" ]] && source "$SCRIPT_DIR/load_setup_shell.sh"

  # -----------------------
  # Default settings
  # -----------------------
  TARGET_FOLDER="output/${execute_date}/overall"
  local skip_phases=()

  # -----------------------
  # Parse command-line arguments
  # -----------------------
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--directory) check_arg "directory" "$2"; TARGET_FOLDER="$2"; shift 2 ;;
      -v|--verbose) check_arg "verbose" "$2"; flag_verbose="$2"; shift 2 ;;
      -c|--color) flag_color=true; shift ;;
      --skip) check_skip skip_phases "$2" 0 4; shift 2 ;;
      --dry) flag_dry=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) error "Unknown option: $1" ;;
    esac
  done

  # --------------------------------------------------
  # Directory fallback
  # --------------------------------------------------
  if [[ -z "$outputDir" ]]; then
      outputDir="${LOCATIONS[root]}/output/${execute_date}/overall"
  fi

  mkdir -p "$TARGET_FOLDER"

  # -----------------------
  # Phase 0: Copy selected Weak/Strong folders
  # -----------------------
  if check_skip_phase 0; then
      info "Skipping Phase 0 (copy Weak/Strong)"
  else
      verbose 2 "==================== Phase 0: ${PHASES[0]} ===================="

      # === Start folder relative to which we preserve structure ===
      RELATIVE_START="alluminium-alloy"   # <-- configurable

      # Format: <source-directory>:<pattern-to-match>
      declare -a SOURCES=(
         "${LOCATIONS[root]}/output/20260225/alluminium-alloy/alloy_disc_colliding_plate/scale/weak:*/P0[1-8]*"
         "${LOCATIONS[root]}/output/20260225/alluminium-alloy/alloy_disc_colliding_plate/scale/strong/Ne+6m1.047770:/P0[1-8]*"
         "${LOCATIONS[root]}/output/20260225/alluminium-alloy/alloy_sphere_colliding_cube/scale/weak/:*/P0[1-8]*"
         "${LOCATIONS[root]}/output/20260226/alluminium-alloy/alloy_sphere_colliding_cube/scale/strong/Ne+7m1.021964:/P0[1-8]*"
         "${LOCATIONS[root]}/output/20260302/alluminium-alloy/alloy_disc_colliding_plate/scale/weak:*/P16*"
         "${LOCATIONS[root]}/output/20260302/alluminium-alloy/alloy_disc_colliding_plate/scale/strong/Ne+6m1.047770:/P16*"
         "${LOCATIONS[root]}/output/20260303/alluminium-alloy/alloy_sphere_colliding_cube/scale/weak:*/P16*"
         "${LOCATIONS[root]}/output/20260303/alluminium-alloy/alloy_sphere_colliding_cube/scale/strong/Ne+7m1.021964:/P16*"
      )

      SOURCES+=(
        "${LOCATIONS[root]}/output/20260226/alluminium-alloy/alloy_sphere_colliding_cube/scale/strong/Ne+6m1.030437:/P0[1-8]*"
      )

      for src_rule in "${SOURCES[@]}"; do
          SRC_DIR="${src_rule%%:*}"
          PATTERN="${src_rule##*:}"

          for folder in $SRC_DIR/$PATTERN; do

              if [[ "$(basename "$folder")" == "$(basename "$(dirname "$folder")")" ]]; then
                  warn "Skipping nested duplicate folder: $folder"
                  continue
              fi

              if [[ -d "$folder" ]]; then
                  REL_PATH="${folder#*/$RELATIVE_START/}"
                  DEST_PATH="$TARGET_FOLDER/$RELATIVE_START/$REL_PATH"

                  mkdir -p  "$DEST_PATH"

                  cmd=(cp -r "$folder/"* "$DEST_PATH")
#                  cmd=(rsync -a "$folder/" "$DEST_PATH/")
                  [[ "$flag_dry" == false ]] && execute "${cmd[@]}" --exe

                  [[ "$flag_dry" == true ]] && debug 2 "Copied $folder → $DEST_PATH (structure preserved under $RELATIVE_START)"
              else
                  warn "Folder not found, skipping: $folder"
              fi
          done
      done
  fi

  # -----------------------
  # Phase 1: Generate README.md
  # -----------------------
  if check_skip_phase 1; then
     info "Skipping Phase 1 (generate README)"
  else
     verbose 2 "==================== Phase 1: ${PHASES[1]} ===================="
     cat > "$TARGET_FOLDER/README.md" << EOF
# Merged Data Overview: $TARGET_FOLDER

## Purpose

This folder consolidates "Weak" and "Strong" datasets from multiple date-based sources
while preserving the original folder structure. It is intended for analysis or visualization.

---

## Folder Structure Example

output/overall/
├── alluminium-alloy/
│   ├── alloy_disc_colliding_plate/
│   │   ├── scale/
│   │   │   ├── weak/
│   │   │   │   └── N/
│   │   │   │   │   └── P01
│   │   │   │   └── .
│   │   │   │   └── .
│   │   │   │   └── .
│   │   │   │   └── N/
│   │   │   │   │   └── P16
│   │   │   └── strong/
│   │   │   │   └── N
│   │   │   │   │   └── P01 … P16
│   ├── alloy_sphere_colliding_cube/
│   │   ├── scale/
│   │   │   ├── weak/
│   │   │   │   └── N/
│   │   │   │   │   └── P01
│   │   │   │   └── .
│   │   │   │   └── .
│   │   │   │   └── .
│   │   │   │   └── N/
│   │   │   │   │   └── P16
│   │   │   └── strong/
│   │   │   │   └── N/
│   │   │   │   │   └── P01 … P16

---

## Copied Data Summary

| Date       | Source | Copied Folders |
|------------|--------|----------------|
| 20260225   | alloy_disc_colliding_plate/scale | weak , strong (P01–P08) |
| 20260225   | alloy_sphere_colliding_cube/scale | weak (P01–P08) |
| 20260226   | alloy_sphere_colliding_cube/scale | strong (P01–P08) |
| 20260302   | alloy_disc_colliding_plate/scale | weak , strong (P16) |
| 20260303   | alloy_sphere_colliding_cube/scale | weak , strong (P16) |

---

## Notes

1. Original folder hierarchy is preserved.
2. Weak datasets include all subfolders.
3. Strong datasets include only selected P-folders for consistency.
4. Copies are performed with "cp -r" to maintain folder structure.
5. Phase 2 removes any "validation" or "evaluation" folders if they exist.
6. Use this folder directly for analysis or visualization.

EOF
  fi

  # -----------------------
  # Phase 2: Remove Validation/Evaluation folders
  # -----------------------
  if check_skip_phase 2; then
    info "Skipping Phase 2 (remove)"
  else
    verbose 2 "==================== Phase 2: ${PHASES[2]} ===================="
    cmd=(find "$TARGET_FOLDER" -type d \( -name "validation" -o -name "evaluation" \) -exec rm -rf {} +)
    execute "${cmd[@]}" --exe
  fi

  info "Merge completed."

  # -----------------------
  # Phase 3: Run Validation
  # -----------------------
  if check_skip_phase 3; then
      info "Skipping Phase 3 (validation)"
  else
      verbose 2 "==================== Phase 3: ${PHASES[3]} ===================="

      declare -a VALIDATION_PATHS=(
          "${TARGET_FOLDER}/alluminium-alloy/alloy_disc_colliding_plate/scale/strong/Ne+6m1.047770/P08_N04x2GPUa30_T001-00-00:2"
          "${TARGET_FOLDER}/alluminium-alloy/alloy_sphere_colliding_cube/scale/strong/Ne+7m1.021964/P08_N04x2GPUa30_T004-00-00:3"
      )
      source "${LOCATIONS[root]}/.venv/bin/activate"

      for item in "${VALIDATION_PATHS[@]}"; do
          dir="${item%%:*}"
          dim="${item##*:}"
          if [[ -d "$dir" ]]; then
              info "Running validation at $dir"
              cmd=("${LOCATIONS[root]}/postprocessing/validationAlloy.py" --path "$dir" --dim "$dim" -v "$flag_verbose")
              execute "${cmd[@]}" --exe
          else
              warn "Validation path not found, skipping: $dir"
          fi
      done
  fi

  # -----------------------
  # Phase 4: Run Performance Analysis
  # -----------------------
  if check_skip_phase 4; then
      info "Skipping Phase 4 (performance analysis)"
  else
      verbose 2 "==================== Phase 4: ${PHASES[4]} ===================="

      declare -a ANALYSIS_PATHS=(
          "${TARGET_FOLDER}/alluminium-alloy/alloy_disc_colliding_plate/scale/strong/Ne+6m1.047770:2"
          "${TARGET_FOLDER}/alluminium-alloy/alloy_disc_colliding_plate/scale/weak/:2"
          "${TARGET_FOLDER}/alluminium-alloy/alloy_sphere_colliding_cube/scale/strong/Ne+7m1.021964:3"
          "${TARGET_FOLDER}/alluminium-alloy/alloy_sphere_colliding_cube/scale/weak/:3"
      )

      ANALYSIS_PATHS+=(
        "${TARGET_FOLDER}/alluminium-alloy/alloy_sphere_colliding_cube/scale/strong/Ne+6m1.030437:3"
      )

      for item in "${ANALYSIS_PATHS[@]}"; do
          dir="${item%%:*}"
          dim="${item##*:}"
          if [[ -d "$dir" ]]; then
              info "Running performance analysis at $dir..."
              cmd=("${LOCATIONS[script]}/execute_total_analysis_performance.sh" -d "$dir" -v "$flag_verbose" --dim "$dim" -c)
              [[ "$flag_color" == true ]] && cmd+=( --color )
              execute "${cmd[@]}" --exe
          else
              warn "Analysis path not found, skipping: $dir"
          fi
      done
  fi
}

# -----------------------
# Execute main
# -----------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi