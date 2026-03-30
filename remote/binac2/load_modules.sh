#!/bin/bash
main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
   DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
   SOURCE="$(readlink "$SOURCE")"
   [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  flag_empty=false
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"
  flag_empty=true

  module_file="${LOCATIONS[script]}/module.info"

  # Überprüfen, ob die Datei existiert
  if [[ ! -f "$module_file" ]]; then
      error "Fehler: Datei '$module_file' nicht gefunden."
  fi

  if [[ ! -f "$module_file" ]]; then
    warn "Module info file '$module_file' not found. Skipping module loading."
    return 1
  fi

  info "Lade Module aus $module_file ..."

  while IFS= read -r line; do
    # Leere oder kommentierte Zeilen überspringen
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Einzelne Module aus der Zeile extrahieren (z.B. '1) compiler/gnu/14.2')
    for entry in $line; do
      # Modulpfad extrahieren (alles nach '1)')
      cleaned_module=$(echo "$entry" | sed -E 's/^[0-9]+\)//')
      if [[ -n "$cleaned_module" ]]; then
        verbose 1 "-> module load $cleaned_module"
        module load "$cleaned_module"
      fi
    done
  done < "$module_file"
}

main "$@"
# Prüfen, ob dieses Skript direkt ausgeführt wird
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    verbose 1 "$(module list)"
    exit 0
fi
return 0