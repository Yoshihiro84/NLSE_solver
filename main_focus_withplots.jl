
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
# Load shared config
# ===============================
include("config.jl")

# ===============================
# Derived quantities
# ===============================
ω0 = 2π * 2.99792458e8 / λ0

f0_THz = 2.99792458e8 / λ0 / 1e12  # optical carrier frequency [THz]

output_dir = joinpath(@__DIR__, "output_focus")
mkpath(output_dir)

dt = T_window / N
t  = (0:N-1) .* dt .- T_window/2

dω = 2π / T_window
ω  = similar(t)
for j in eachindex(ω)
    k = j - 1
    ω[j] = (k < N ÷ 2) ? (k * dω) : ((k - N) * dω)
end

z_mm = collect(range(z_min_mm, z_max_mm, length=Nz+1))
dz = (z_max_mm - z_min_mm) * 1e-3 / Nz   # [m]

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
# Plates (from config)
# ===============================
plates = Plates.Plate[]
for pd in plate_defs
    push!(plates, Plates.Plate(pd.z_start, pd.z_end, pd.material, pd.β2, pd.β3, pd.I_damage))
end

# ===============================
# Input pulse (power-envelope: |A|^2 = P)
# ===============================
τ0 = τ_fwhm / (2sqrt(log(2)))
G  = exp.(-(t.^2) ./ (2τ0^2))

P0 = Ep / (0.94 * τ_fwhm)   # Gaussian power pulse

A0 = complex.(sqrt(P0) .* G)

include("metrics.jl")
using .Metrics

# ===============================
# Solve
# ===============================
# Compute initial q-parameters when self-focusing is enabled
if ENABLE_SELF_FOCUSING && !hasmethod(Beam.initial_q, Tuple{typeof(beam), Float64})
    error("ENABLE_SELF_FOCUSING=true requires a beam type that implements Beam.initial_q(). " *
          "Got $(typeof(beam)), which does not support q-parameter computation.")
end

sf_qx0, sf_qy0 = if ENABLE_SELF_FOCUSING
    Beam.initial_q(beam, z_min_mm)
else
    (ComplexF64(0, 1), ComplexF64(0, 1))
end

cfg = NLSESolver.NLSEConfig(
    λ0, ω0, t, ω, z_mm, dz, plates, beam;
    apply_beam_scaling = (BEAM_MODE == :focus && !ENABLE_SELF_FOCUSING),
    enable_dispersion = true,
    enable_spm = ENABLE_SPM,
    enable_self_steepening = ENABLE_SELF_STEEPENING,
    enable_self_focusing = ENABLE_SELF_FOCUSING,
    qx0 = sf_qx0,
    qy0 = sf_qy0,
)

println("BEAM_MODE = ", BEAM_MODE, " (", beam_label, ")")
println("ENABLE_SELF_STEEPENING = ", ENABLE_SELF_STEEPENING)
println("ENABLE_SPM = ", ENABLE_SPM)
println("ENABLE_SELF_FOCUSING = ", ENABLE_SELF_FOCUSING)

A_end, Itz, Ifz, beam_hist = NLSESolver.propagate!(A0, cfg)

println("Done. |A_end|^2 peak = ", maximum(abs2.(A_end)))
sf_Aeff = ENABLE_SELF_FOCUSING ? beam_hist.Aeff : nothing
B_total = compute_B(Itz, cfg; Aeff_hist=sf_Aeff)
@printf("Computed B-integral (total): %.6f rad\n", B_total)

limit_report = analyze_plate_limits(
    Itz, cfg;
    B_warn_rad = B_WARN_PER_PLATE_RAD,
    B_limit_rad = B_LIMIT_PER_PLATE_RAD,
    safety_factor = I_SAFETY_FACTOR,
    Aeff_hist = sf_Aeff
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
            p.I_damage_Wcm2, limit_report.I_allow_Wcm2_per_plate[i])
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
                p.I_damage_Wcm2,
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
    I_damage_vals = [p.I_damage_Wcm2 for p in plates]
    println(io, "I_damage_Wcm2_per_plate,\"$(join(I_damage_vals, ';'))\"")
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
    diam_x_m = 2.0 .* beam_hist.wx
    diam_y_m = 2.0 .* beam_hist.wy

    sf_label = ENABLE_SELF_FOCUSING ? " (self-focusing ON)" : ""
    p_beam = plot(
        z_m,
        diam_x_m,
        xlabel = "Propagation length z [m]",
        ylabel = "Beam diameter [m]",
        title  = "Beam diameter along z" * sf_label,
        label  = "2wx",
    )
    plot!(p_beam, z_m, diam_y_m, label = "2wy")
    savefig(p_beam, joinpath(output_dir, "beam_diameter_vs_z.png"))

    println("Saved plots to: ", output_dir)
else
    println("ENABLE_PLOTS=0: skipped plot generation.")
end
