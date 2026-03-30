#!/bin/bash
# ===================================================================
# Generate material input for alloy simulations
# ===================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -d               Dimension (2 or 3)
  --delta          Δ value
  --sml            Smoothing length
  -o, --output     Output directory
  -v, --verbose    Verbosity level (default: 3)
  -h, --help       Show this help
EOF
}

main(){
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
   DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
   SOURCE="$(readlink "$SOURCE")"
   [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  source "$( dirname "$SOURCE" )/load_setup_shell.sh"

  # --- Default values ---
  DIM=
  DELTA=
  SML=
  OUTPUT_DIR=
  # --- Argument parsing ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
         shift
         check_arg "--mode" "$1"
         # Fill selected_modes array with valid modes
         check_select selected_modes "$1" "${VALID_MODES[@]}"
         shift
         ;;
      -d|--dim)
         shift
         check_arg "--dim" "$1"
         validate_natural_numbers "dimension" "$1" 1 3
         DIM="$1"
         shift
         ;;
      --delta)
         shift
         check_arg "--delta" "$1"
         validate_float "$1"
         DELTA="$1"
         shift
         ;;
      --sml)
         shift
         check_arg "--sml" "$1"
         validate_float "$1"
         SML="$1"
         shift
         ;;
      -o|--output)
         shift
         check_arg "--output" "$1"
         OUTPUT_DIR="$1"
         shift
         ;;
      -c|--color)
         flag_color=true
         shift
         ;;
      -v|--verbose)
         shift
         check_arg "--verbose" "$1"
         validate_natural_numbers "verbosity level" "$1" 0 4
         flag_verbose="$1"
         shift
         ;;
      -h|--help)
          usage
          exit 0
          ;;
      *)
          echo "Unknown option: $1"
          usage
          exit 1
          ;;
    esac
  done

  # --- Validate mandatory arguments ---
  if [[ -z "$DIM" || -z "$DELTA" || -z "$SML" ]]; then
      echo "Error: -d, --delta and --sml are required."
      usage
      exit 1
  fi

   if [[ -z "$OUTPUT_DIR" ]]; then
     OUTPUT_DIR="${LOCATIONS[output]}"
   fi

  mkdir -p "$OUTPUT_DIR"
  MATERIAL_FILE="${OUTPUT_DIR}/materials${SUFFIX[materialPath]}"

  cat > "$MATERIAL_FILE" <<EOF
materials = (
    {
        ID = 0;
        name = "Al6061 (Target)";
        sml = $SML;
        interactions = 50;  # Number of neighbor particles
        artificial_viscosity = { alpha = 1.0; beta = 2.0; };
        artificial_stress = {exponent_tensor = 4.; epsilon_stress = 0.3; mean_particle_distance = $DELTA; };
        plasticity = { yield_stress = 2.4e7; };
        eos = {
            type = 2;  # Tillotson EOS
            n = 1.0;
            polytropic_K = 7.6e10;
            polytropic_gamma = 1.4;
            rho_0 = 2.7e3;
            bulk_modulus = 7.6e10;
            shear_modulus = 2.6e10;
            young_modulus = 6.9e10;
            till_A = 7.52e10;
            till_B = 6.5e10;
            E_0 = 5.0e6;
            E_iv = 3.0e6;
            E_cv = 1.39e7;
            till_a = 0.5;
            till_b = 1.63;
            till_alpha = 5.0;
            till_beta = 5.0;
            rho_limit = 0.9;
            cs_limit = 50.0;
        };
    },

    {
        ID = 1;
        name = "Al6061 (Projectile)";
        sml = $SML;
        interactions = 50;
        artificial_viscosity = { alpha = 1.0; beta = 2.0; };
        artificial_stress = {exponent_tensor = 4.; epsilon_stress = 0.3; mean_particle_distance = $DELTA; };
        plasticity = { yield_stress = 2.4e7; };
        eos = {
            type = 2;  # Tillotson EOS
            rho_0 = 2.7e3;
            n = 1.0;
            polytropic_K = 7.6e10;
            polytropic_gamma = 1.4;
            bulk_modulus = 7.6e10;
            shear_modulus = 2.6e10;
            young_modulus = 6.9e10;
            till_A = 7.52e10;
            till_B = 6.5e10;
            E_0 = 5.0e6;
            E_iv = 3.0e6;
            E_cv = 1.39e7;
            till_a = 0.5;
            till_b = 1.63;
            till_alpha = 5.0;
            till_beta = 5.0;
            rho_limit = 0.9;
            cs_limit = 50.0;
        };
    }
);
EOF

  info "Material file generated: $MATERIAL_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
return 0