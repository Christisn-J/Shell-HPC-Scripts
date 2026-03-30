#!/bin/bash
# --- Hilfsfunktionen ---
usage() {
  echo -e "Usage: $0 [OPTIONS]\n"
  echo "Run simulation jobs on all local git branches."
  echo ""
  echo "Options:"
  echo "  -v, --verbos <LEVEL>     Verbosity level (default: 3)"
  echo "  --steps <N>              Number of steps to run (default: 10)"
  echo "  --skip <INDICES>         Comma-separated list of branch indices to skip"
  echo "  -c, --color              Enable colored output"
  echo "  -h, --help               Show this help message and exit"
  echo ""
  echo "Available branches:"
  for i in "${!VALID_BRANCHES[@]}"; do
    echo "  [$i] ${VALID_BRANCHES[$i]}"
  done
  echo ""
}

main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"

  layer=1
  SCRIPT="$SCRIPT_DIR/submit_all_testcases.sh"

  # --- Argumente parsen ---
  while [[ $# -gt 0 && "$1" == -* ]]; do
    case "$1" in
     -c|--color)
      flag_color=true
       shift
       ;;
     --layer)
       shift
       layer="$1"
       shift
       ;;
     --steps)
       shift
       check_arg "--steps" "$1"
       if [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
         steps="$1"
       else
         error "Invalid value for --steps: must be a positive integer."
       fi
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
        check_skip $(( ${#PHASES[@]} - 1 )) "$1" skip_phases
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

  # --- Main loop ---
  original_branch=$(git rev-parse --abbrev-ref HEAD)
  overall_start=$(start_timer)

  info "Starting branch loop at $(date +%F_%T)"

  for i in "${!VALID_BRANCHES[@]}"; do
    branch="${VALID_BRANCHES[$i]}"

    # Skip?
    skip=false
    for skip_idx in "${skip_branch_indices[@]}"; do
      [[ "$skip_idx" -eq "$i" ]] && skip=true && break
    done
    $skip && warn "Skipping branch $i ($branch)" && continue

    # Check for local changes
    has_local_changes=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
      has_local_changes=true
      info "Local changes detected. Stashing before switching branches..."
      git stash push -u -m "auto_stash_before_$branch"
    fi

    # Branch wechseln
    info "Switching to branch: $branch"
    git checkout "$branch" >/dev/null 2>&1 || {
      error "Could not checkout branch: $branch"
      continue
    }

    # Stash wieder anwenden, wenn vorhanden
    if $has_local_changes; then
      info "Applying local changes to branch '$branch'..."
      git stash pop || warn "Could not apply stash on $branch. Please resolve manually."
    fi

    # Falls Script nicht existiert, Branch überspringen
    if [[ ! -f "$SCRIPT" ]]; then
      warn "Script $SCRIPT not found in $branch. Skipping..."

      # Änderungen wieder stashen, um nächsten Branch wechseln zu können
      if $has_local_changes; then
        git stash push -u -m "auto_stash_before_next_branch"
      fi
      continue
    fi

    # Timer starten
    branch_start=$(start_timer)

    info "$(head -c 95 < <(printf '=%.0s' {1..100}))"
    info "Starting branch: $branch"
    info "$(head -c 95 < <(printf '=%.0s' {1..100}))"

    outputDir="$(get_path_outputRootDir "$layer" "" "")"
    mkdir -p "$outputDir/log/"
    logfile="$outputDir/log/$(get_name_logFile "$layer" "" "")"

    cmd=(bash "$SCRIPT" --steps "$steps" -v "$flag_verbose" --layer "$((layer + 1))")
    [[ "$flag_color" == true ]] && cmd+=(--color)
    if [[ -n "${skip_phases[*]}" ]]; then
      skip_arg=$(IFS=','; echo "${skip_phases[*]}")
      cmd+=( --skip "$skip_arg" )
    fi
    if [[ -n "${selected_modes[*]}" ]]; then
      select_arg=$(IFS=','; echo "${selected_modes[*]}")
      cmd+=( --select  "$select_arg" )
    fi

    job_output=$(execute "${cmd[@]}" --exe 2>&1 | tee "$logfile")
    echo "$job_output"

    job_id=$(echo "$job_output" | grep -oP 'Submitted batch job \K[0-9]+')
    if [[ -z "$job_id" ]]; then
      warn "No job ID found for branch $branch"

      # Änderungen wieder stashen für nächsten Branch
      if $has_local_changes; then
        git stash push -u -m "auto_stash_before_next_branch"
      fi
      continue
    fi

    info "Waiting for SLURM job $job_id to complete..."
    while squeue -j "$job_id" &> /dev/null; do
      sleep "$SLEEP_INTERVAL"
    done

    branch_duration=$(end_timer "$branch_start")
    trace "Job $job_id on branch '$branch' finished in $(format_timer "$branch_duration")"

    # Änderungen stashen, damit nächster Branch-Checkout funktioniert
    if $has_local_changes; then
      git stash push -u -m "auto_stash_before_next_branch"
    fi
  done


  git checkout "$original_branch" >/dev/null 2>&1
  info "Restored original branch: $original_branch"

  # Letzten Stash wiederherstellen (optional)
  if git stash list | grep -q 'auto_stash_before_next_branch'; then
    info "Restoring original working changes..."
    git stash pop || warn "Could not apply final stash. Please resolve manually."
  fi

  total_duration=$(end_timer "$overall_start")
  trace "All branches processed in $(format_timer "$total_duration")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0
