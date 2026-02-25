# ========== パルス条件 ==========
λ0       = 4.8e-6        # 中心波長 [m]
Ep       = 50e-6        # パルスエネルギー [J]
τ_fwhm   = 100e-15       # パルス幅 FWHM [s]

# ========== 時間グリッド ==========
T_window = 2e-12         # 時間窓 [s]
N        = 2^14          # グリッド点数

# ========== 空間グリッド ==========
z_min_mm = 0.0           # [mm]
z_max_mm = 50.0          # [mm]
Nz       = 4000

# ========== ビーム設定 ==========
BEAM_MODE = :focus    # :constant or :focus

# constant beam
const_diam_x_mm = 2      # [mm]
const_diam_y_mm = 2      # [mm]

# focused beam (knife-edge)
focus_w0x_mm = 0.125
focus_z0x_mm = 25.0
focus_zRx_mm = 0.9
focus_w0y_mm = 0.057
focus_z0y_mm = 24.9
focus_zRy_mm = 0.5
focus_waist_is_diameter = true

# ========== 非線形トグル ==========
ENABLE_SPM             = true
ENABLE_SELF_STEEPENING = true
ENABLE_SELF_FOCUSING   = true

# ========== プレート定義 ==========
# main用: Plate(z_start, z_end, material, β2, β3, I_damage)
plate_defs = [
    (z_start=8.0, z_end=13.0, material=Material.Si_48um, β2=0.0, β3=0.0, I_damage=4.0e11),
]

# optimize用: PlateSpec(material, thick, β2, β3, I_damage, z_init, fixed, z_range)
plate_specs_defs = [
    (mat=Material.Si_48um, thick=2.0, β2=316, β3=0.0, I_damage=4.0e11, z_init=3.0,  fixed=false,  z_range=(0.0, 10.0)),
    (mat=Material.NaCl_48um, thick=2.0, β2=-112, β3=0.0, I_damage=1.0e13, z_init=8.0,  fixed=false, z_range=(25.0, 29.0)),
    (mat=Material.Si_48um, thick=2.0, β2=316, β3=0.0, I_damage=4.0e11, z_init=14.0, fixed=false, z_range=(35.0, 45.0)),
    (mat=Material.CaF2_48um, thick=1.0, β2=-500, β3=0.0, I_damage=1.0e13, z_init=49.0, fixed=true, z_range=(15.0, 25.0)),
]

# ========== 制約・安全設定 ==========
B_WARN_PER_PLATE_RAD  = π
B_LIMIT_PER_PLATE_RAD = 2.0π
I_SAFETY_FACTOR       = 1.5
LIMIT_ACTION          = :warn   # :warn or :error

# ========== Aeff ガード設定 ==========
# 0.0 = 無効; Kerr薄レンズ近似の破綻を早期に検出するためのAeff下限 [m²]
# 典型例: 10 × 回折限界 = 10 × λ0²/π ≈ 7.3e-11 m² (@λ0=4.8μm)
AEFF_MIN_GUARD_M2 = 0.0

# ========== 最適化設定 ==========
OPT_MAX_EVALS   = 300
OPT_N_RESTARTS  = 3
OPT_λ_OVERLAP   = 1e4
OPT_λ_B         = 1e2
