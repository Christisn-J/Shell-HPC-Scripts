#!/bin/bash
start_timer() {
  date +%s.%N
}

end_timer() {
  local start="$1"
  local end=$(date +%s.%N)
  echo "$end - $start" | bc
}

format_timer() {
  local total_seconds=$1
  # Prüfen, ob total_seconds kleiner als 0.01 ist
  local hundredths=$(( $(echo "$total_seconds * 100" | bc -l | cut -d. -f1) ))

  if (( $hundredths <= 0 )); then
    echo "< 0.01s"
    return
  fi
  local hours=$(printf "%02d" $(echo "$total_seconds/3600" | bc))
  local minutes=$(printf "%02d" $(echo "($total_seconds%3600)/60" | bc))
  # Sekunden mit 2 Nachkommastellen, vorangestellt mit 0 falls <10
  local seconds=$(printf "%05.2f" $(echo "$total_seconds%60" | bc -l))
  echo "${hours}:${minutes}:${seconds}"
}







