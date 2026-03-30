#!/usr/bin/env bash
declare -A MODE_CONFIG=(
  ["alloy_sphere_colliding_cube"]="dim=3 slice=false extrema=false projection=false dynamicRender=true scale=x=centi,t=micro script=plotScatter.py"
  ["alloy_disc_colliding_plate"]="dim=2 slice=false extrema=false projection=false dynamicRender=true scale=x=centi,t=micro script=plotScatter.py"
  ["colliding_cylinders"]="dim=3 slice=true extrema=false projection=false dynamicRender=false scale=x=none,t=none script=plotScatter.py"
  ["colliding_rings"]="dim=2 slice=false extrema=true projection=false dynamicRender=false scale=x=none,t=none script=plotScatter.py"
  ["sedov"]="dim=3 slice=true extrema=false projection=false dynamicRender=false scale=x=none,t=none script=plotScatter.py"
  ["plummer"]="dim=3 slice=true extrema=false projection=false dynamicRender=false scale=x=none,t=none script=plotScatter.py"
  ["kelvin-helmholtz"]="dim=2 slice=false extrema=false projection=false dynamicRender=false scale=x=none,t=none script=plotScatter.py"
)

declare -A PLOT_TYP=(
  [0]="mechanics"
  [1]="change_rates"
  [2]="hydro"
  [3]="process"
  [4]="stress"
  [5]="velocity"
  [6]="matId"
  [7]="rho"
  [8]="proc"
  [9]="noi"
  [10]="p"
  [11]="e"
  [12]="cs"
)

declare -A PHASES=(
  [0]=".h5 file check          (checks and counts ts*.h5 files)"
  [1]=".png generation         (create images using postprocessing script)"
  [2]=".mp4 creation           (create a video from PNG images)"
  [3]=".gif creation           (convert video into a GIF sequence)"
)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  usage() {
    echo ""
    echo "Usage: $0 <mode> [OPTIONS]"
    echo ""
    echo "Run postprocessing for simulation data (e.g. create plots, videos, gifs)."
    echo ""
    echo "Available modes:"
    for m in "${VALID_MODES[@]}"; do
      echo "  - $m"
    done
    echo ""
    echo "Options:"
    echo "  -d, --directory <folder>   Path to result folder (relative or absolute)"
    echo "  -p, --plot_type <N>        Plot type ID (default: 0)"
    for i in "${!PLOT_TYP[@]}"; do
        printf "                                %d = %s\n" "$i" "${PLOT_TYP[$i]}"
    done
    echo "      --plane <PLANE>        (Optional) Specify slicing plane"
    echo "  -v, --verbose <N>          Verbosity level (default: 3)"
    echo "  -c, --color                Force colored output"
    echo "      --skip <N>             Skip one or more processing phases"
    for i in "${!PHASES[@]}"; do
        printf "                                %d - %s\n" "$i" "${PHASES[$i]}"
    done
    echo "  -h, --help                 Show this help message and exit"
  }
fi

contain_files() {
  local mode="${1:---all}"    # either --all or --only
  local ext="$2"

  info "Contained files in folder: $folder"

  shopt -s nullglob
  for file in "$folder"/*; do
    if [ -f "$file" ]; then
      filename=$(basename "$file")
      name_without_extension="${filename%.*}"
      extension="${filename##*.}"

      if [[ "$mode" == "--only" && "$extension" != "$ext" ]]; then
        continue
      fi

      verbose 4 "File: $name_without_extension (.$extension)"
    fi
  done
  shopt -u nullglob
}

create_or_activate_env(){
  if [ ! -d ".venv" ]; then
    warn "Virtual environment '.venv' not found. Creating now..."

    if ! command -v python3 &>/dev/null; then
      error "python3 is not installed. Please install python3."
    fi

    python3 -m venv .venv || error "Failed to create virtual environment."

    info "Upgrading pip..."
    source .venv/bin/activate
    pip install --upgrade pip || warn "Could not upgrade pip."

    info "Installing required Python packages..."
    pip install numpy matplotlib h5py scipy || error "Failed to install required Python packages."

  else
    info "Activating existing virtual environment '.venv'"
    source .venv/bin/activate
  fi
}

main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"

  layer=3

  VALID_MODES=("${!MODE_CONFIG[@]}")
  mode="$(get_name_completeMode "$1")"
  check_valid_mode "$mode" "${VALID_MODES[@]}"
  shift

  # Parse flags
  while [[ $# -gt 0 && "$1" == -* ]]; do
    case "$1" in
      -c|--color)
         flag_color=true
         shift
         ;;
       -v|--verbose)
         shift
         check_arg "--verbose" "$1"
         check_natural_numbers "--verbose" "$1" "$(get_range_min verbose)" "$(get_range_max verbose)"
         flag_verbose="$1"
         shift
         ;;
       --skip)
         shift
         check_arg "--skip" "$1"
         check_skip skip_phases "$1" "$(get_range_min skip)" $(( ${#PHASES[@]} - 1 ))
         shift
         ;;
       --layer)
         shift
         check_arg "--layer" "$1"
         check_natural_numbers "--layer" "$1" "$(get_range_min layer)" "$(get_range_max layer)"
         layer="$1"
         shift
         ;;
       -h|--help)
         usage "$flag_color"
         exit 0
         ;;

      --plane)
        shift
        check_arg "--plane" "$1"
        plane="$1"
        shift
        ;;
      -d|--directory)
        shift
        check_arg "--directory" "$1"
        if [[ "$1" = /* ]]; then
          # Absoluter Pfad, also nicht an PROJECT_ROOT anhängen
          CHECK_DIR="$1"
        else
          # Relativer Pfad, an PROJECT_ROOT anhängen
          CHECK_DIR="$PROJECT_ROOT/$1"
        fi
        if [ ! -d "$CHECK_DIR" ]; then
          error "\"$CHECK_DIR\" is not a valid directory."
        fi
        folder="$CHECK_DIR"
        shift
        ;;
      -p|--plot_type)
        shift
        check_arg "--plot_type" "$1"
        plot_type=$1
        shift
        ;;

      *)
        logger "[Error]" red "Unknown option: $1"
        usage "$flag_color"
        exit 1
        ;;
    esac
  done



  if ! check_skip_phase 0; then
    # Main logic to process based on the mode
    contain_files --only "h5"

    # --- Count .h5 Files (like Steps Count Phase) ---
    info "Checking number of timestep .h5 files in '$folder'"
    step_files_count=$(find "$folder" -type f -name 'ts*.h5' | wc -l)

    if (( step_files_count > 0 )); then
      info "Number of timestep .h5 files found: $step_files_count"
    else
      error "No timestep .h5 files found in $folder"
    fi
  else
    info "Skipping Phase 0 (.h5 file check)"
  fi

  create_or_activate_env

  plot_type_slug=""
  if [[ -v PLOT_TYP[$plot_type] ]]; then
    plot_type_slug="${PLOT_TYP[$plot_type]}"
  else
    error "Unknown plot_type: $plot_type"
  fi


  # Stelle sicher, dass der Modus existiert
    config="${MODE_CONFIG[$mode]}"
    [[ -z "$config" ]] && error "Unknown mode: $mode"

  if ! check_skip_phase 1; then
    info "Create .png out of ts*.h5"
    if [[ ! " ${VALID_MODES[*]} " =~ " $mode " ]]; then
      error "Invalid mode '$mode'\nAvailable modes: ${VALID_MODES[*]}"
    fi

    # Parse die Konfig in Variablen
    IFS=' ' read -ra properties <<< "$config"
    for prop in "${properties[@]}"; do
      eval "$prop"
    done

    mkdir -p "$folder/visualized/"
    args=(-p "$folder" -o "$folder/visualized/" -pT "$plot_type" --dim "$dim" -v 2)
#    args=(-p "$folder" -o "$folder/visualized/" -pT "$plot_type" --dim "$dim" -v "$(( flag_verbose <= 1 ? 1 : (flag_verbose == 2 ? 2 : 3) ))")
    [[ "$slice" == "true" ]] && args+=(--slice)
    [[ "$extrema" == "true" ]] && args+=(--extrema)
    [[ "$projection" == "true" ]] && args+=(--projection)
    [[ "$dynamicRender" == "true" ]] && args+=(--dynamicRender)
    if [[ -n "$scale" ]]; then
      IFS=',' read -r -a scale_args <<< "$scale"
      args+=(--scale "${scale_args[@]}")
    fi

    info_file=$(compgen -G "$folder/configured"/*.info | head -n 1)
    [[ -n "$info_file" ]] && args+=(-c "$info_file")
    res_file=$(compgen -G "$folder/configured"/*.res | head -n 1)
    [[ -n "$res_file"  ]] && args+=(-r "$res_file")
    mat_file=$(compgen -G "$folder/configured"/*.cfg | head -n 1)
    [[ -n "$mat_file"  ]] && args+=(-m "$mat_file")

    cmd=(python "./postprocessing/$script" "${args[@]}")
    debug 0 $config
    debug 0 $scale
    execute "${cmd[@]}" --exe #2> /dev/null || warn "Failed to create .png video for '${plot_type}'"
#    execute "${cmd[@]}" --exe --silence 2> /dev/null || error "Failed to create .png video for '${plot_type}'"
  fi

  if ! check_skip_phase 2; then
    [ -n "$plane" ] && kind="slice"

    pattern=""
    [ -n "$plot_type_slug" ] && pattern+="_$plot_type_slug"
    [ -n "$kind" ]           && pattern+="_$kind"
    [ -n "$plane" ]          && pattern+="_$plane"

    if check_ffmpeg; then
      info "Creating .mp4 video from snapshots for plot type: \"$plot_type_slug\""
      cmd=(ffmpeg -y -framerate 30 \
                  -pattern_type glob \
                  -i "$folder/visualized/ts*$pattern.png" \
                  -vf "scale=1770:1778"\
                  -c:v libx264 \
                  -pix_fmt yuv420p "$folder/visualized/${plot_type}${pattern}.mp4")
        execute "${cmd[@]}" --exe #2> /dev/null || warn "Failed to create .mp4 video for '${plot_type}${pattern}'"
    else
      warn "ffmpeg is not installed or not in PATH."
    fi
  else
    info "Skipping Phase 2 (.mp4 creation)"
  fi

  if ! check_skip_phase 3; then
    info "Create .gif out of .mp4"
    if check_ffmpeg; then
      info "Creating .gif sequence from video for plot type: \"$plot_type_slug\""
      cmd=(ffmpeg -i "$folder/visualized/${plot_type}${pattern}.mp4" -vf "fps=10,scale=480:-1:flags=lanczos" -loop 0 "$folder/visualized/${plot_type}${pattern}.gif")
      execute "${cmd[@]}" --exe #2> /dev/null || warn "Failed to create .gif for '${plot_type}${pattern}'"
    else
      warn "ffmpeg is not installed or not in PATH."
    fi
  else
    info "Skipping Phase 3 (.gif creation)"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
return 0
