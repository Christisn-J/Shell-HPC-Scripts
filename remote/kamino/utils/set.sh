#!/bin/bash
set_paths() {
  local mode="$1"
  local prefix="$2"
  shift 2

  declare -A fallback_suffix=(
    [initialConditionPath]=".h5"
    [resourcePath]=".res"
    [configPath]=".info"
    [materialPath]=".cfg"
    [parameterPath]=".h"
  )

  declare -A fallback_path=(
    [initialConditionPath]="$prefix/testcases/$mode/"
    [resourcePath]="$prefix/testcases/"
    [configPath]="$prefix/testcases/$mode/"
    [materialPath]="$prefix/testcases/$mode/"
    [parameterPath]="$prefix/testcases/$mode/"
  )

  declare -A fallback_message
  for key in "${!fallback_path[@]}"; do
    fallback_message[$key]="falling back to auto-detect ${fallback_suffix[$key]} file in ${fallback_path[$key]}"
  done

  local varname value fallback

  for varname in "$@"; do
    if [[ -z "$varname" ]]; then
      warn "Empty variable name passed to set_paths, skipping..."
      continue
    fi

    declare -n ref_var="$varname"
    value="${ref_var:-}"

    if [[ -n "$value" ]]; then
      check_valid_path "$value" "--$varname"
      fallback="$(get_filePath "--$varname" "$value" "${fallback_suffix[$varname]}")"

    else
      warn "--$varname not provided, ${fallback_message[$varname]}"
      fallback="$(get_filePath "--$varname" "${fallback_path[$varname]}" "${fallback_suffix[$varname]}")"
    fi

    ref_var="$fallback"
    check_valid_path "${ref_var}" "--$varname"
  done
}