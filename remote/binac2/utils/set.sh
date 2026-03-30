#!/bin/bash
set_paths() {
  local mode="$1"
  local prefix="$2"
  shift 2

  declare -A fallback_path=(
    [initialConditionPath]="$prefix/$mode/"
    [resourcePath]="$prefix/"
    [configPath]="$prefix/"
    [materialPath]="$prefix/$mode/"
    [parameterPath]="$prefix/$mode/"
  )

  declare -A fallback_message
  for key in "${!fallback_path[@]}"; do
    fallback_message[$key]="falling back to auto-detect ${SUFFIX[$key]} file in ${fallback_path[$key]}"
  done

  local varname value fallback

  local skip_list=(${SKIP_PATHS_MAP[$mode]})

  for varname in "$@"; do
    if [[ -z "$varname" ]]; then
      warn "Empty variable name passed to set_paths, skipping..."
      continue
    fi

    if [[ " ${skip_list[*]} " == *" $varname "* ]]; then
      info "Skipping $varname for mode=$mode"
      continue
    fi

    declare -n ref_var="$varname"
    value="${ref_var:-}"

    if [[ -n "$value" ]]; then
      check_valid_path "--$varname" "$value"
      fallback="$(get_filePath "--$varname" "$value" "${SUFFIX[$varname]}")"

    else
      warn "--$varname not provided, ${fallback_message[$varname]}"
      fallback="$(get_filePath "--$varname" "${fallback_path[$varname]}" "${SUFFIX[$varname]}")"
    fi

    ref_var="$fallback"
    check_valid_path "--$varname" "${ref_var}"
  done
}

reset_paths() {
  for varname in "$@"; do
    if [[ -z "$varname" ]]; then
      warn "Empty variable name passed to reset_paths, skipping..."
      continue
    fi
    unset "$varname"
  done
}
