#!/bin/bash
declare -Ag SEPARATOR=(
  ["path"]="/"
  ["name"]="_"
  ["extension"]="."
  ["list"]=","
  ["cmd"]=" "
)

declare -Ag SLURM_OPTS=(
  [partition]="compute"
  [time]="168:00:00"
  [mem]="64G"
  [cpus_per_task]="1"
  [ntasks]="4"
  [nodes]="1"
  [mail_type]="ALL"
  [mail_user]="christian.jetter@student.uni-tuebingen.de"
)

# --- Farbprofile global definieren ---
declare -Ag COLORS=(
  [BOLD]=$'\033[1m'
  [CYAN]=$'\033[0;36m'
  [GREEN]=$'\033[0;32m'
  [YELLOW]=$'\033[0;33m'
  [RED]=$'\033[0;31m'
  [RESET]=$'\033[0m'
)

# --- COLORLESS dynamisch erzeugen ---
declare -Ag COLORLESS=()
for key in "${!COLORS[@]}"; do
  COLORLESS["$key"]=""
done

declare -Ag RANGES=(
  [steps]="min=0 max="
  [layer]="min=0 max=4"
  [skip]="min=0 max="
  [verbose]="min=0 max="
  [process]="min=1 max="
)

declare -Ag SUFFIX=(
  [initialConditionPath]=".h5"
  [resourcePath]=".res"
  [configPath]=".info"
  [materialPath]=".cfg"
  [parameterPath]=".h"
)

declare -Ag SKIP_PATHS_MAP=(
  [plummer]="materialPath"
)



