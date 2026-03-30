# --- Default dimension per mode ---
declare -Ag MODE_DEFAULT_DIM=(
  [alloy_disc_colliding_plate]=2
  [alloy_sphere_colliding_cube]=3
  [colliding_cylinders]=3
  [colliding_rings]=2
  [sedov]=3
  [plummer]=3
)

declare -Ag SUFFIX=(
  [initialConditionPath]=".h5"
  [resourcePath]=".res"
  [configPath]=".info"
  [materialPath]=".cfg"
  [parameterPath]=".h"
)

# --- Header per mode ---
declare -Ag HEADER_MODES=(
  [alloy_disc_colliding_plate]="delta_particles,N_tot,N_target,N_projectile,SML_estimate,SML_optimize,avg_distance_particles,avg_neighbors_optimized,delta_gap"
  [alloy_sphere_colliding_cube]="delta_particles,N_tot,N_target,N_projectile,SML_estimate,SML_optimize,avg_distance_particles,avg_neighbors_optimized,delta_gap"
  [colliding_rings]="delta_particles,N_tot,N_ring,SML_estimate,SML_optimize,avg_distance_particles,avg_neighbors_optimized,delta_gap"
  [colliding_cylinders]="delta_particles,N_tot,N_ring,SML_estimate,SML_optimize,avg_distance_particles,avg_neighbors_optimized,delta_gap"
)

# --- Δ values per mode (N can be exponential) ---
declare -Ag DELTA_MODES
# ./scripts/remote/kamino/generate_delta_to_amount.sh --mode alloy_disc_colliding_plate --delta mantissa 3.18e-04 3.00e-05 0.002 --output ./output/20260208
DELTA_MODES[alloy_disc_colliding_plate]="
3.180000e-04,1.001630e+05,9.985600e+04,3.070000e+02,4.134000e-04,1.111012e-03,3.180000e-04,3.565590e+01,1.590000e-03
2.225000e-04,2.040390e+05,2.034010e+05,6.380000e+02,2.892500e-04,7.773594e-04,2.225000e-04,3.575870e+01,1.112500e-03
1.575000e-04,4.057710e+05,4.044960e+05,1.275000e+03,2.047500e-04,5.502656e-04,1.575000e-04,3.582879e+01,7.875000e-04
1.120000e-04,8.017540e+05,7.992360e+05,2.518000e+03,1.456000e-04,3.913000e-04,1.120000e-04,3.587817e+01,5.600000e-04
7.925000e-05,1.600206e+06,1.595169e+06,5.037000e+03,1.030250e-04,2.768797e-04,7.925000e-05,3.591375e+01,3.962500e-04
5.600000e-05,3.203457e+06,3.193369e+06,1.008800e+04,7.280000e-05,1.956500e-04,5.600000e-05,3.593903e+01,2.800000e-04
3.950000e-05,6.436377e+06,6.416089e+06,2.028800e+04,5.135000e-05,1.380031e-04,3.950000e-05,3.595698e+01,1.975000e-04

9.800000e-05,1.047770e+06,1.044484e+06,3.286000e+03,1.274000e-04,3.423875e-04,9.800000e-05,3.589343e+01,4.900000e-04
3.150000e-05,1.011889e+07,1.008698e+07,3.191100e+04,4.095000e-05,1.100531e-04,3.150000e-05,3.596569e+01,1.575000e-04
"

# ./scripts/remote/kamino/generate_delta_to_amount.sh --mode alloy_sphere_colliding_cube --delta mantissa 2.30e-03 4.625e-04 0.002 --output ./output/20260208
DELTA_MODES[alloy_sphere_colliding_cube]="
2.200000e-03,1.038310e+05,1.038230e+05,8.000000e+00,2.860000e-03,5.005000e-03,2.200000e-03,5.309823e+01,5.500000e-03
1.750000e-03,2.054020e+05,2.053790e+05,2.300000e+01,2.275000e-03,3.981250e-03,1.750000e-03,5.368101e+01,4.375000e-03
1.375000e-03,4.052750e+05,4.052240e+05,5.100000e+01,1.787500e-03,3.128125e-03,1.375000e-03,5.414676e+01,3.437500e-03
1.090000e-03,8.044500e+05,8.043570e+05,9.300000e+01,1.417000e-03,2.479750e-03,1.090000e-03,5.452299e+01,2.725000e-03
8.650000e-04,1.601818e+06,1.601613e+06,2.050000e+02,1.124500e-03,1.967875e-03,8.650000e-04,5.482417e+01,2.162500e-03
6.825000e-04,3.242212e+06,3.241792e+06,4.200000e+02,8.872500e-04,1.552688e-03,6.825000e-04,5.506941e+01,1.706250e-03
5.425000e-04,6.435682e+06,6.434856e+06,8.260000e+02,7.052500e-04,1.234188e-03,5.425000e-04,5.525892e+01,1.356250e-03

1.000000e-03,1.030437e+06,1.030301e+06,1.360000e+02,1.300000e-03,2.275000e-03,1.000000e-03,5.463900e+01,2.500000e-03
4.650000e-04,1.021964e+07,1.021831e+07,1.322000e+03,6.045000e-04,1.057875e-03,4.650000e-04,5.536448e+01,1.162500e-03
"

DELTA_MODES[colliding_rings]="
0.1,4.392,2.196,1.300000e-01,nan,nan,nan,1.000000e+01
"


DELTA_MODES[colliding_cylinders]="
"

DELTA_MODES[sedov]="
"

DELTA_MODES[plummer]="
"



