
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using FFTW
using DelimitedFiles
using Printf

const ENABLE_PLOTS = get(ENV, "ENABLE_PLOTS", "1") != "0"
if ENABLE_PLOTS
    using Plots
    using Plots.PlotMeasures
end

# ---- Use focus-enabled modules ----
include("material.jl")
include("Beam_focus.jl")
include("Plate_focus.jl")
include("NLSE_solver_focus.jl")

using .Material
using .Beam
using .Plates
using .NLSESolver

# ===============================
# User parameters (edit here)
# ===============================

λ0 = 4.8e-6              # [m]
ω0 = 2π * 2.99792458e8 / λ0

f0_THz = 2.99792458e8 / λ0 / 1e12  # optical carrier frequency [THz]

output_dir = joinpath(@__DIR__, "output_focus")
mkpath(output_dir)
# Time grid (example)
T_window = 2e-12         # [s]
N = 2^14
dt = T_window / N
t  = (0:N-1) .* dt .- T_window/2

dω = 2π / T_window
ω  = similar(t)
for j in eachindex(ω)
    k = j - 1
    ω[j] = (k < N ÷ 2) ? (k * dω) : ((k - N) * dω)
end

# z grid (example, in mm)
z_min_mm = 0.0
z_max_mm = 20.0
Nz = 2000
z_mm = collect(range(z_min_mm, z_max_mm, length=Nz+1))
dz = (z_max_mm - z_min_mm) * 1e-3 / Nz   # [m]

# ===============================
# Manual toggles
# ===============================
# Beam mode: :focus (knife-edge focusing) or :constant (fixed beam diameter)
const BEAM_MODE = :constant
# Nonlinear terms
const ENABLE_SPM = true
const ENABLE_SELF_STEEPENING = true

# ===============================
# Beam settings
# ===============================
# Focused beam (knife-edge fit)
focus_w0x_mm = 0.125   # waist diameter [mm]
focus_z0x_mm = 6.6     # waist position [mm]
focus_zRx_mm = 0.9     # Rayleigh length [mm]
focus_w0y_mm = 0.057
focus_z0y_mm = 6.5
focus_zRy_mm = 0.5
focus_waist_is_diameter = true

# Constant beam (diameter at all z)
const_diam_x_mm = 2
const_diam_y_mm = 2

beam, beam_label = if BEAM_MODE == :focus
    (
        Beam.knifeedge_beam(
            w0x_mm = focus_w0x_mm,
            z0x_mm = focus_z0x_mm,
            zRx_mm = focus_zRx_mm,
            w0y_mm = focus_w0y_mm,
            z0y_mm = focus_z0y_mm,
            zRy_mm = focus_zRy_mm,
            waist_is_diameter = focus_waist_is_diameter,
        ),
        "focus",
    )
elseif BEAM_MODE == :constant
    (
        Beam.constant_beam(0.5 * const_diam_x_mm * 1e-3, 0.5 * const_diam_y_mm * 1e-3),
        "constant",
    )
else
    error("Unsupported BEAM_MODE=$(BEAM_MODE). Use :focus or :constant.")
end

# ===============================
# Plates (example)
# ===============================
plates = Plates.Plate[]
push!(plates, Plates.Plate(8.0, 13.0, Material.Si_48um, 0.0, 0.0))  # z in mm

# ===============================
# Input pulse (example, power-envelope: |A|^2 = P)
# ===============================
τ_fwhm = 100e-15
τ0 = τ_fwhm / (2sqrt(log(2)))
G  = exp.(-(t.^2) ./ (2τ0^2))

Ep = 100e-6  # [J] total pulse energy (example)
P0 = Ep / (0.94 * τ_fwhm)   # Gaussian power pulse

A0 = complex.(sqrt(P0) .* G)

# ===============================
# Operation limits (production checks)
# ===============================

const B_WARN_PER_PLATE_RAD  = 1.5π
const B_LIMIT_PER_PLATE_RAD = 2.0π

# Replace by your measured threshold.
const I_DAMAGE_WCM2_PER_PLATE = [
    2.0e11,  # plate 1
]
const I_SAFETY_FACTOR = 1.5

# :warn -> print warnings only, :error -> throw when any plate violates limits
const LIMIT_ACTION = :warn

function plate_index_at_z(z_mm::Float64, plates::Vector{Plates.Plate})
    for (i, p) in enumerate(plates)
        if p.z_start_mm <= z_mm <= p.z_end_mm
            return i
        end
    end
    return nothing
end

function classify_B(Bi::Float64, warn_rad::Float64, limit_rad::Float64)
    if Bi > limit_rad
        return "VIOLATION"
    elseif Bi > warn_rad
        return "CAUTION"
    else
        return "OK"
    end
end

function classify_I(Ipk_Wcm2::Float64, Iallow_Wcm2::Float64)
    return (Ipk_Wcm2 > Iallow_Wcm2) ? "VIOLATION" : "OK"
end

function analyze_plate_limits(Itz::Array{Float64,2}, cfg::NLSESolver.NLSEConfig;
                              B_warn_rad::Float64,
                              B_limit_rad::Float64,
                              I_damage_Wcm2_per_plate::Vector{Float64},
                              safety_factor::Float64)
    nplates = length(cfg.plates)
    if length(I_damage_Wcm2_per_plate) != nplates
        error("Length mismatch: I_DAMAGE_WCM2_PER_PLATE has $(length(I_damage_Wcm2_per_plate)) values, but plates has $(nplates).")
    end
    B_per_plate = zeros(Float64, nplates)
    Ipk_per_plate = zeros(Float64, nplates)
    z_Ipk_mm = fill(NaN, nplates)
    I_allow_Wcm2_per_plate = I_damage_Wcm2_per_plate ./ safety_factor

    for iz in 1:(length(cfg.z_mm)-1)
        z_mid_mm = 0.5 * (cfg.z_mm[iz] + cfg.z_mm[iz+1])
        pidx = plate_index_at_z(z_mid_mm, cfg.plates)
        if pidx === nothing
            continue
        end

        _, _, n2_here = Plates.coeffs_at_z(z_mid_mm, cfg.plates, cfg.beam, cfg.λ0)
        Aeff_mid = Beam.A_eff(cfg.beam, z_mid_mm)
        if n2_here == 0.0 || Aeff_mid <= 0.0 || !isfinite(Aeff_mid)
            continue
        end

        gamma = n2_here * cfg.ω0 / (NLSESolver.c0 * Aeff_mid)
        Ppeak = maximum(Itz[:, iz+1]) # |A|^2 = power [W]
        if !isfinite(gamma) || !isfinite(Ppeak)
            continue
        end

        B_per_plate[pidx] += gamma * Ppeak * cfg.dz

        Ipk_Wcm2 = (2.0 * Ppeak / Aeff_mid) / 1e4
        if Ipk_Wcm2 > Ipk_per_plate[pidx]
            Ipk_per_plate[pidx] = Ipk_Wcm2
            z_Ipk_mm[pidx] = z_mid_mm
        end
    end

    B_total = sum(B_per_plate)
    B_status = [classify_B(Bi, B_warn_rad, B_limit_rad) for Bi in B_per_plate]
    I_status = [classify_I(Ipk_per_plate[i], I_allow_Wcm2_per_plate[i]) for i in 1:nplates]
    has_violation = any(s -> s == "VIOLATION", B_status) || any(s -> s == "VIOLATION", I_status)

    return (
        B_per_plate = B_per_plate,
        Ipk_per_plate = Ipk_per_plate,
        z_Ipk_mm = z_Ipk_mm,
        B_total = B_total,
        B_status = B_status,
        I_status = I_status,
        I_allow_Wcm2_per_plate = I_allow_Wcm2_per_plate,
        has_violation = has_violation
    )
end

function compute_B(Itz::Array{Float64,2}, cfg::NLSESolver.NLSEConfig)
    c0_local = 2.99792458e8
    Nz = length(cfg.z_mm) - 1
    B_total = 0.0
    for iz in 1:Nz
        z_mid_mm = 0.5 * (cfg.z_mm[iz] + cfg.z_mm[iz+1])
        _, _, n2_here = Plates.coeffs_at_z(z_mid_mm, cfg.plates, cfg.beam, cfg.λ0)
        if n2_here == 0.0
            continue
        end
        Aeff_mid = Beam.A_eff(cfg.beam, z_mid_mm)
        gamma = n2_here * cfg.ω0 / (c0_local * Aeff_mid)
        Ppeak = maximum(Itz[:, iz+1])
        if !isfinite(Ppeak) || !isfinite(gamma)
            continue
        end
        B_total += gamma * Ppeak * cfg.dz
    end
    return B_total
end

# ===============================
# Solve
# ===============================
cfg = NLSESolver.NLSEConfig(
    λ0, ω0, t, ω, z_mm, dz, plates, beam;
    apply_beam_scaling = (BEAM_MODE == :focus),
    enable_dispersion = true,
    enable_spm = ENABLE_SPM,
    enable_self_steepening = ENABLE_SELF_STEEPENING,
)

println("BEAM_MODE = ", BEAM_MODE, " (", beam_label, ")")
println("ENABLE_SELF_STEEPENING = ", ENABLE_SELF_STEEPENING)
println("ENABLE_SPM = ", ENABLE_SPM)

A_end, Itz, Ifz = NLSESolver.propagate!(A0, cfg)

println("Done. |A_end|^2 peak = ", maximum(abs2.(A_end)))
B_total = compute_B(Itz, cfg)
@printf("Computed B-integral (total): %.6f rad\n", B_total)

limit_report = analyze_plate_limits(
    Itz, cfg;
    B_warn_rad = B_WARN_PER_PLATE_RAD,
    B_limit_rad = B_LIMIT_PER_PLATE_RAD,
    I_damage_Wcm2_per_plate = I_DAMAGE_WCM2_PER_PLATE,
    safety_factor = I_SAFETY_FACTOR
)

println("\n=== Plate Limit Report ===")
@printf("SF = %.3f\n", I_SAFETY_FACTOR)
@printf("B thresholds: warn = %.3f rad, limit = %.3f rad\n",
        B_WARN_PER_PLATE_RAD, B_LIMIT_PER_PLATE_RAD)
@printf("Total ΣB = %.6f rad\n", limit_report.B_total)
for (i, p) in enumerate(plates)
    @printf("Plate %d [%.3f, %.3f] mm | B_i=%.6f (%s) | I_peak=%.3e W/cm^2 @ z=%.3f mm (%s) | I_damage=%.3e | I_allow=%.3e\n",
            i, p.z_start_mm, p.z_end_mm,
            limit_report.B_per_plate[i], limit_report.B_status[i],
            limit_report.Ipk_per_plate[i], limit_report.z_Ipk_mm[i], limit_report.I_status[i],
            I_DAMAGE_WCM2_PER_PLATE[i], limit_report.I_allow_Wcm2_per_plate[i])
end

plate_report_csv = joinpath(output_dir, "plate_limit_report.csv")
open(plate_report_csv, "w") do io
    println(io, "plate_idx,z_start_mm,z_end_mm,B_i_rad,B_status,I_peak_Wcm2,z_at_I_peak_mm,I_status,B_warn_rad,B_limit_rad,I_damage_Wcm2,safety_factor,I_allow_Wcm2")
    for (i, p) in enumerate(plates)
        println(io,
            join((
                i,
                p.z_start_mm,
                p.z_end_mm,
                limit_report.B_per_plate[i],
                limit_report.B_status[i],
                limit_report.Ipk_per_plate[i],
                limit_report.z_Ipk_mm[i],
                limit_report.I_status[i],
                B_WARN_PER_PLATE_RAD,
                B_LIMIT_PER_PLATE_RAD,
                I_DAMAGE_WCM2_PER_PLATE[i],
                I_SAFETY_FACTOR,
                limit_report.I_allow_Wcm2_per_plate[i]
            ), ",")
        )
    end
end

summary_csv = joinpath(output_dir, "run_limit_summary.csv")
open(summary_csv, "w") do io
    println(io, "key,value")
    println(io, "beam_mode,$(BEAM_MODE)")
    println(io, "enable_spm,$(ENABLE_SPM)")
    println(io, "enable_self_steepening,$(ENABLE_SELF_STEEPENING)")
    println(io, "B_total_rad,$(limit_report.B_total)")
    println(io, "B_total_from_compute_B_rad,$(B_total)")
    println(io, "B_warn_per_plate_rad,$(B_WARN_PER_PLATE_RAD)")
    println(io, "B_limit_per_plate_rad,$(B_LIMIT_PER_PLATE_RAD)")
    println(io, "I_damage_Wcm2_per_plate,\"$(join(I_DAMAGE_WCM2_PER_PLATE, ';'))\"")
    println(io, "safety_factor,$(I_SAFETY_FACTOR)")
    println(io, "I_allow_Wcm2_per_plate,\"$(join(limit_report.I_allow_Wcm2_per_plate, ';'))\"")
    println(io, "has_violation,$(limit_report.has_violation)")
end

println("Saved limit reports to: ", output_dir)

if limit_report.has_violation
    msg = "Plate limit violation detected. See $(plate_report_csv)"
    if LIMIT_ACTION == :error
        error(msg)
    else
        @warn msg
    end
end

if ENABLE_PLOTS
    # ===============================
    # 1D プロット（入力 vs 出力）
    # ===============================

    I0 = abs2.(A0)
    If = abs2.(A_end)

    p1 = plot(t .* 1e15, I0,
              label = "z = $(z_min_mm) mm",
              xlabel="Time [fs]",
              ylabel="|A|^2 (arb.)",
              title="Temporal |A|^2 (input vs output)",
              xlims=(-300,300))
    plot!(p1, t .* 1e15, If, label="z = $(z_max_mm) mm")
    savefig(p1, joinpath(output_dir, "intensity_zdep_multi_plate.png"))

    # スペクトル
    Aω0 = fft(A0)
    Aωf = fft(A_end)
    Δf_THz_base = fftshift(ω) ./ (2π) ./ 1e12
    freq_THz    = Δf_THz_base .+ f0_THz

    S0_1D = fftshift(abs2.(Aω0))
    Sf_1D = fftshift(abs2.(Aωf))

    p2 = plot(freq_THz, S0_1D,
              label="input",
              xlabel="Frequency [THz]",
              ylabel="Spectral power (arb.)",
              title="Spectrum (input vs output)",
              xlims=(f0_THz-30, f0_THz+30))
    plot!(p2, freq_THz, Sf_1D, label="output")
    savefig(p2, joinpath(output_dir, "spectrum_zdep_multi_plate.png"))

    # ===============================
    # 2D マップ: z–スペクトル / z–時間
    # ===============================

    t_fs   = t .* 1e15
    max_Itz = maximum(Itz)
    max_Ifz = maximum(Ifz)
    Itz_norm = (max_Itz == 0.0) ? Itz : (Itz ./ max_Itz)
    Ifz_norm = (max_Ifz == 0.0) ? Ifz : (Ifz ./ max_Ifz)

    p_spec = heatmap(
        z_mm,
        freq_THz,
        log10.(max.(Ifz_norm, 1e-4)),
        xlabel = "Propagation length z [mm]",
        ylabel = "Frequency [THz]",
        title  = "Spectral evolution along z (log10)",
        colorbar_title = "\nLog10 Norm. |Aω|^2",
        ylims = (40, 90),
        xlims = (9, 15),
        clims = (-2, 0),
        right_margin = 10mm,
    )
    savefig(p_spec, joinpath(output_dir, "spec_vs_z.png"))

    p_time = heatmap(
        z_mm,
        t_fs,
        log10.(max.(Itz_norm, 1e-4)),
        xlabel = "Propagation length z [mm]",
        ylabel = "Time [fs]",
        title  = "Temporal evolution along z (log10)",
        colorbar_title = "\nLog10 Norm. |A|^2",
        ylims = (-150,150),
        xlims = (8,15),
        clims = (-2, 0),
        right_margin = 10mm,
    )
    savefig(p_time, joinpath(output_dir, "time_vs_z.png"))

    # ===============================
    # Beam diameter vs z
    # ===============================
    z_m = z_mm .* 1e-3
    diam_x_m = [2.0 * Beam.wx(beam, z_here_mm) for z_here_mm in z_mm]
    diam_y_m = [2.0 * Beam.wy(beam, z_here_mm) for z_here_mm in z_mm]

    p_beam = plot(
        z_m,
        diam_x_m,
        xlabel = "Propagation length z [m]",
        ylabel = "Beam diameter [m]",
        title  = "Beam diameter along z",
        label  = "2wx",
    )
    plot!(p_beam, z_m, diam_y_m, label = "2wy")
    savefig(p_beam, joinpath(output_dir, "beam_diameter_vs_z.png"))

    println("Saved plots to: ", output_dir)
else
    println("ENABLE_PLOTS=0: skipped plot generation.")
end
