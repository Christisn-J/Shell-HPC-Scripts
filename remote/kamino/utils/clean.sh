#!/bin/bash

#clean() {
#  # --- Tidy Up Phase ---
#  if check_skip_phase 6; then
#    info "Skipping tidy-up step (Phase 6)."
#    return
#  fi
#
#  info "Running final tidy-up ..."
#  t0=$(start_timer)
#  cmd=( "$PREFIX/execute_tidy_up.sh" "$mode" --layer "$layer" -v "$flag_verbose")
#  [[ "$flag_color" == true ]] && cmd+=( --color )
#  execute "${cmd[@]}" --exe || error "Failed to tidy up."
#  t1=$(end_timer "$t0")
#  trace "⏱ Tidy Up-Phase duration: $(format_timer "$t1")"
#}