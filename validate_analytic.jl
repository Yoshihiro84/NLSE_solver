#=
validate_analytic.jl — SPM / Self-steepening 解析解との整合性検証
==========================================================
Script_sf のモジュールをそのまま使い、1 ファイルで
  1. シミュレーション実行
  2. 解析解の計算
  3. 残差の定量評価（RMS / max）
  4. 比較プロット生成
を行う。

Usage:
    julia Script_sf/validate_analytic.jl

環境変数:
    ENABLE_PLOTS  "0" でプロット生成を無効化（デフォルト: "1"）
=#

import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using FFTW
using Printf

const ENABLE_PLOTS = get(ENV, "ENABLE_PLOTS", "1") != "0"
if ENABLE_PLOTS
    using Plots
end

# ---- Script_sf モジュール読み込み ----
include(joinpath(@__DIR__, "material.jl"))
include(joinpath(@__DIR__, "Beam_focus.jl"))
include(joinpath(@__DIR__, "Plate_focus.jl"))
include(joinpath(@__DIR__, "NLSE_solver_focus.jl"))

using .Material
using .Beam
using .Plates
using .NLSESolver

# =====================
# 共通パラメータ
# =====================
const c0          = 2.99792458e8
const lambda0_um  = 4.6
const lambda0     = lambda0_um * 1e-6
const omega0      = 2π * c0 / lambda0
const f0_THz      = c0 / lambda0 / 1e12

const Ep_uJ       = 50.0
const Ep          = Ep_uJ * 1e-6
const tau_fwhm_fs = 100.0
const tau_fwhm    = tau_fwhm_fs * 1e-15
const tau0        = tau_fwhm / (2sqrt(log(2)))

const T_window_fs = 4000.0
const T_window    = T_window_fs * 1e-15
const N           = 2^14

const dt = T_window / N
const t  = collect((0:N-1) .* dt .- T_window / 2)

const domega = 2π / T_window
const omega_axis = [(k < div(N, 2)) ? (k * domega) : ((k - N) * domega) for k in 0:N-1]

# z-range (short propagation, purely nonlinear)
const z_min_mm = 0.0
const z_max_mm = 2.0
const Nz       = 800
const Lz       = (z_max_mm - z_min_mm) * 1e-3
const dz       = Lz / Nz
const z_mm     = collect(range(z_min_mm, z_max_mm, length=Nz+1))

# Beam (constant, 1 mm radius)
const beam = Beam.constant_beam(1.0e-3, 1.0e-3)
const Aeff = Beam.A_eff(beam, z_min_mm)

# Plate (uniform Si, no dispersion)
const plates = [Plates.Plate(z_min_mm, z_max_mm, Material.Si_48um, 0.0, 0.0)]

# Input pulse (power-envelope)
const P0 = Ep / (0.94 * tau_fwhm)
const A0 = complex.(sqrt(P0) .* exp.(-(t .^ 2) ./ (2tau0^2)))

# Analytic B-integral
const n2   = Material.Si_48um.n2
const gamma = n2 * omega0 / (c0 * Aeff)
const B_val = gamma * P0 * Lz

# Output directory
const output_dir = joinpath(@__DIR__, "output_focus")
mkpath(output_dir)

# =====================
# Helper functions
# =====================
function rms(x::AbstractVector)
    return sqrt(mean_sq(x))
end
function mean_sq(x::AbstractVector)
    return sum(abs2, x) / length(x)
end

function safe_normalize(v::AbstractVector)
    mx = maximum(abs.(v))
    return mx == 0.0 ? v : v ./ mx
end

# ========================================================
# Self-steepening 解析解
# ========================================================
"""
Self-steepening analytic waveform via implicit Newton iteration.
Returns I_out_norm (peak-normalized).
"""
function analytic_ss_waveform(t_vec::Vector{Float64}, B::Float64, tau_fwhm_s::Float64, lambda0_m::Float64)
    a = 4 * log(2) / (tau_fwhm_s^2)
    I0(τ)   = exp(-a * τ^2)
    dI0dt(τ) = -2a * τ * I0(τ)

    tau_s = lambda0_m / (2π * c0)   # [s]
    K = 3.0 * tau_s * B

    t0 = copy(t_vec)
    for _ in 1:40
        f  = t0 .+ K .* I0.(t0) .- t_vec
        fp = 1.0 .+ K .* dI0dt.(t0)
        fp = map(x -> abs(x) < 1e-8 ? 1e-8 : x, fp)
        delta = f ./ fp
        t0 .-= delta
        maximum(abs.(delta)) < 1e-12 && break
    end

    I_out = I0.(t0)
    return safe_normalize(I_out)
end

# ========================================================
# Run simulation helper
# ========================================================
function run_sim(; enable_spm::Bool, enable_ss::Bool)
    cfg = NLSESolver.NLSEConfig(
        lambda0, omega0, t, omega_axis, z_mm, dz, plates, beam;
        apply_beam_scaling=false,
        enable_dispersion=false,
        enable_spm=enable_spm,
        enable_self_steepening=enable_ss,
        enable_self_focusing=false
    )
    A_end, _, _, _ = NLSESolver.propagate!(A0, cfg)
    return A_end
end

# ========================================================
# 1. SPM 検証
# ========================================================
println("="^60)
println("  SPM Validation")
println("="^60)

A_end_spm = run_sim(enable_spm=true, enable_ss=false)

# Simulation spectrum
freq_THz_sim = fftshift(omega_axis) ./ (2π) ./ 1e12 .+ f0_THz
S_sim_spm = fftshift(abs2.(fft(A_end_spm)))
S_sim_spm_norm = safe_normalize(S_sim_spm)

# Analytic SPM spectrum (same FFT convention as simulation: fft then fftshift)
# NLSE: dA/dz = +iγ|A|²A → exact solution: A(L) = A(0)·exp(+iγ|A|²L)
S_ana_direct = let
    I_t = abs2.(A0)
    I0  = maximum(I_t)
    I0  = I0 > 0 ? I0 : 1.0
    phi = B_val .* (I_t ./ I0)
    E_out = A0 .* exp.(1im .* phi)
    fftshift(abs2.(fft(E_out)))
end
S_ana_direct_norm = safe_normalize(S_ana_direct)

# Residual (on normalized spectra)
resid_spm = S_sim_spm_norm .- S_ana_direct_norm
rms_spm   = rms(resid_spm)
max_spm   = maximum(abs.(resid_spm))

@printf("  B-integral         = %.6f rad\n", B_val)
@printf("  gamma              = %.6e 1/(W·m)\n", gamma)
@printf("  P0                 = %.6e W\n", P0)
@printf("  Spectrum RMS resid = %.6e\n", rms_spm)
@printf("  Spectrum max resid = %.6e\n", max_spm)

spm_pass = rms_spm < 1e-3
println("  Result: ", spm_pass ? "PASS" : "FAIL",
        " (threshold: RMS < 1e-3)")

# ========================================================
# 2. Self-steepening 検証
# ========================================================
println()
println("="^60)
println("  Self-Steepening Validation")
println("="^60)

A_end_ss = run_sim(enable_spm=false, enable_ss=true)

# Simulation waveform (normalized intensity)
I_sim_ss = abs2.(A_end_ss)
I_sim_ss_norm = safe_normalize(I_sim_ss)

# Analytic waveform
I_ana_ss_norm = analytic_ss_waveform(t, B_val, tau_fwhm, lambda0)

# Residual
resid_ss = I_sim_ss_norm .- I_ana_ss_norm
rms_ss   = rms(resid_ss)
max_ss   = maximum(abs.(resid_ss))

@printf("  B-integral         = %.6f rad\n", B_val)
@printf("  tau_s              = %.6e s\n", lambda0 / (2π * c0))
@printf("  Waveform RMS resid = %.6e\n", rms_ss)
@printf("  Waveform max resid = %.6e\n", max_ss)

ss_pass = rms_ss < 1e-2
println("  Result: ", ss_pass ? "PASS" : "FAIL",
        " (threshold: RMS < 1e-2)")

# ========================================================
# 3. GVD-only 検証
# ========================================================
println()
println("="^60)
println("  GVD-only Validation")
println("="^60)

β2_gvd_fs2mm = 316.0                         # [fs²/mm]  (Si ~4.8 µm)
β2_gvd_SI    = β2_gvd_fs2mm * 1e-30 / 1e-3   # [s²/m]
plates_gvd   = [Plates.Plate(z_min_mm, z_max_mm, Material.Si_48um, β2_gvd_fs2mm, 0.0)]

cfg_gvd = NLSESolver.NLSEConfig(
    lambda0, omega0, t, omega_axis, z_mm, dz, plates_gvd, beam;
    apply_beam_scaling=false,
    enable_dispersion=true,
    enable_spm=false,
    enable_self_steepening=false,
    enable_self_focusing=false)
A_end_gvd, _, _, _ = NLSESolver.propagate!(A0, cfg_gvd)

# 解析解: A(z,t) = A₀_peak/√(1−iD) · exp(−t²/[2T₀²(1−iD)])
# D = β₂z/T₀²  (規格化分散長)
# GVDは線形なのでピーク振幅 sqrt(P0) をそのままスケール
D_gvd     = β2_gvd_SI * Lz / tau0^2
A_ana_gvd = @. (sqrt(P0) / sqrt(1 - 1im * D_gvd)) * exp(-t^2 / (2 * tau0^2 * (1 - 1im * D_gvd)))

resid_gvd   = A_end_gvd .- A_ana_gvd
rms_gvd     = sqrt(sum(abs2.(resid_gvd))) / sqrt(sum(abs2.(A_ana_gvd)))
max_gvd     = maximum(abs.(resid_gvd)) / maximum(abs.(A_ana_gvd))

@printf("  β₂         = %.1f fs²/mm\n", β2_gvd_fs2mm)
@printf("  D          = %.6f  (= β₂·z / T₀²)\n", D_gvd)
@printf("  FWHM broadening (expected) : ×%.4f\n", sqrt(1 + D_gvd^2))
@printf("  Relative L2 error          : %.3e\n", rms_gvd)
@printf("  Max field error            : %.3e\n", max_gvd)

gvd_pass = rms_gvd < 1e-3
println("  Result: ", gvd_pass ? "PASS" : "FAIL",
        " (threshold: rel-L2 < 1e-3)")

# ========================================================
# 4. dz 収束テスト（GVD+SPM、高精度参照解との比較）
# ========================================================
# 備考: GVD-only は SSFM で厳密解のため dz 依存性がない（誤差 ~機械精度）。
#       演算子分割誤差は GVD+SPM 同時有効時に O(dz²) で現れる。
println()
println("="^60)
println("  dz Convergence Test (GVD+SPM, reference=8×Nz)")
println("="^60)

# 参照解: 8×Nz で GVD+SPM
Nz_ref   = 8 * Nz
dz_ref   = Lz / Nz_ref
z_mm_ref = collect(range(z_min_mm, z_max_mm, length=Nz_ref+1))
cfg_ref  = NLSESolver.NLSEConfig(
    lambda0, omega0, t, omega_axis, z_mm_ref, dz_ref, plates_gvd, beam;
    apply_beam_scaling=false,
    enable_dispersion=true,
    enable_spm=true,
    enable_self_steepening=false,
    enable_self_focusing=false)
A_ref, _, _, _ = NLSESolver.propagate!(A0, cfg_ref)

err_list = Float64[]

for (k, Nz_k) in enumerate([Nz, 2*Nz, 4*Nz])
    dz_k   = Lz / Nz_k
    z_mm_k = collect(range(z_min_mm, z_max_mm, length=Nz_k+1))
    cfg_k  = NLSESolver.NLSEConfig(
        lambda0, omega0, t, omega_axis, z_mm_k, dz_k, plates_gvd, beam;
        apply_beam_scaling=false,
        enable_dispersion=true,
        enable_spm=true,
        enable_self_steepening=false,
        enable_self_focusing=false)
    A_k, _, _, _ = NLSESolver.propagate!(A0, cfg_k)

    err = sqrt(sum(abs2.(A_k .- A_ref))) / sqrt(sum(abs2.(A_ref)))
    push!(err_list, err)

    ord_str = k > 1 && err_list[k-1] > 0 ?
              @sprintf("  order≈%.2f", log2(err_list[k-1] / err)) : ""
    @printf("  Nz=%5d  dz=%.4e mm  rel-L2=%.3e%s\n",
            Nz_k, dz_k * 1e3, err, ord_str)
end

conv_pass = length(err_list) >= 2 && all(diff(err_list) .< 0)
println("  Result: ", conv_pass ? "PASS" : "FAIL",
        " (error must decrease as dz is halved)")

# ========================================================
# Summary
# ========================================================
println()
println("="^60)
println("  Summary")
println("="^60)
println("  SPM spectrum  : ", spm_pass  ? "PASS" : "FAIL")
println("  SS waveform   : ", ss_pass   ? "PASS" : "FAIL")
println("  GVD field     : ", gvd_pass  ? "PASS" : "FAIL")
println("  dz convergence: ", conv_pass ? "PASS" : "FAIL")
all_pass = spm_pass && ss_pass && gvd_pass && conv_pass
println("  Overall       : ", all_pass ? "ALL PASS" : "SOME FAILED")
println("="^60)

# ========================================================
# Plots
# ========================================================
if ENABLE_PLOTS
    println("\nGenerating comparison plots...")

    t_fs = t .* 1e15

    # --- SPM spectrum comparison ---
    p_spm = plot(freq_THz_sim, 10 .* log10.(max.(S_sim_spm_norm, 1e-6)),
                 label="Simulation", lw=1.5,
                 xlabel="Frequency [THz]", ylabel="Spectral power [dB]",
                 title="SPM: Simulation vs Analytic (spectrum)")
    plot!(p_spm, freq_THz_sim, 10 .* log10.(max.(S_ana_direct_norm, 1e-6)),
          label="Analytic", ls=:dash, lw=1.5)
    # Focus around carrier
    xlims!(p_spm, f0_THz - 30, f0_THz + 30)
    ylims!(p_spm, -60, 2)
    savefig(p_spm, joinpath(output_dir, "validate_spm_spectrum.png"))

    # --- SPM spectrum residual ---
    p_spm_r = plot(freq_THz_sim, resid_spm,
                   label="Residual", lw=1.0,
                   xlabel="Frequency [THz]", ylabel="Residual (norm.)",
                   title=@sprintf("SPM spectrum residual (RMS=%.2e)", rms_spm))
    xlims!(p_spm_r, f0_THz - 30, f0_THz + 30)
    savefig(p_spm_r, joinpath(output_dir, "validate_spm_residual.png"))

    # --- SS waveform comparison ---
    I_in_norm = safe_normalize(abs2.(A0))
    p_ss = plot(t_fs, I_in_norm,
                label="Input", lw=1.0, ls=:dot,
                xlabel="Time [fs]", ylabel="Normalized intensity",
                title="Self-Steepening: Simulation vs Analytic (waveform)")
    plot!(p_ss, t_fs, I_sim_ss_norm, label="Simulation", lw=1.5)
    plot!(p_ss, t_fs, I_ana_ss_norm, label="Analytic", ls=:dash, lw=1.5)
    xlims!(p_ss, -300, 300)
    savefig(p_ss, joinpath(output_dir, "validate_ss_waveform.png"))

    # --- SS waveform residual ---
    p_ss_r = plot(t_fs, resid_ss,
                  label="Residual", lw=1.0,
                  xlabel="Time [fs]", ylabel="Residual (norm.)",
                  title=@sprintf("SS waveform residual (RMS=%.2e)", rms_ss))
    xlims!(p_ss_r, -300, 300)
    savefig(p_ss_r, joinpath(output_dir, "validate_ss_residual.png"))

    # --- GVD field comparison ---
    I_sim_gvd = abs2.(A_end_gvd)
    I_ana_gvd = abs2.(A_ana_gvd)
    p_gvd = plot(t_fs, safe_normalize(abs2.(A0)),
                 label="Input", lw=1.0, ls=:dot,
                 xlabel="Time [fs]", ylabel="Normalized intensity",
                 title=@sprintf("GVD-only: Simulation vs Analytic (D=%.4f)", D_gvd))
    plot!(p_gvd, t_fs, safe_normalize(I_sim_gvd), label="Simulation", lw=1.5)
    plot!(p_gvd, t_fs, safe_normalize(I_ana_gvd), label="Analytic",   ls=:dash, lw=1.5)
    xlims!(p_gvd, -300, 300)
    savefig(p_gvd, joinpath(output_dir, "validate_gvd_waveform.png"))

    # --- dz convergence plot ---
    Nz_list = [Nz, 2*Nz, 4*Nz]
    dz_list = Lz ./ Nz_list .* 1e3  # [mm]
    p_conv = plot(dz_list, err_list,
                  marker=:circle, lw=1.5, xscale=:log10, yscale=:log10,
                  xlabel="dz [mm]", ylabel="Relative L2 error",
                  title="dz Convergence (GVD-only, vs. analytic)",
                  label="SSFM error")
    savefig(p_conv, joinpath(output_dir, "validate_dz_convergence.png"))

    println("Saved plots to: ", output_dir)
else
    println("\nENABLE_PLOTS=0: skipped plot generation.")
end
