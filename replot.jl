# replot.jl — ベスト解でプロットだけ再生成（最適化不要）
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using FFTW, Printf, Plots, Plots.PlotMeasures
include("material.jl"); include("Beam_focus.jl"); include("Plate_focus.jl")
include("NLSE_solver_focus.jl"); include("metrics.jl")
using .Material, .Beam, .Plates, .NLSESolver, .Metrics
include("config.jl")

c0 = 2.99792458e8; ω0 = 2π * c0 / λ0
dt = T_window / N; t = collect((0:N-1) .* dt .- T_window/2)
dω = 2π / T_window; ω = [(k < N÷2) ? k*dω : (k-N)*dω for k in 0:N-1]
z_mm = collect(range(z_min_mm, z_max_mm, length=Nz+1))
dz = (z_max_mm - z_min_mm) * 1e-3 / Nz
beam = Beam.knifeedge_beam(w0x_mm=focus_w0x_mm, z0x_mm=focus_z0x_mm, zRx_mm=focus_zRx_mm,
    w0y_mm=focus_w0y_mm, z0y_mm=focus_z0y_mm, zRy_mm=focus_zRy_mm,
    waist_is_diameter=focus_waist_is_diameter)
τ0 = τ_fwhm / (2sqrt(log(2))); P0 = Ep / (0.94 * τ_fwhm)
A0 = complex.(sqrt(P0) .* exp.(-(t.^2) ./ (2τ0^2)))
qx0, qy0 = Beam.initial_q(beam, z_min_mm)

# ベスト解プレート
best_plates = [
    Plates.Plate(0.35, 2.35,   plate_specs_defs[1].mat, plate_specs_defs[1].β2, 0.0, plate_specs_defs[1].I_damage),
    Plates.Plate(25.65, 27.65, plate_specs_defs[2].mat, plate_specs_defs[2].β2, 0.0, plate_specs_defs[2].I_damage),
    Plates.Plate(36.23, 38.23, plate_specs_defs[3].mat, plate_specs_defs[3].β2, 0.0, plate_specs_defs[3].I_damage),
    Plates.Plate(48.0, 50.0, plate_specs_defs[4].mat, plate_specs_defs[4].β2, 0.0, plate_specs_defs[4].I_damage),
]

cfg = NLSESolver.NLSEConfig(λ0, ω0, t, ω, z_mm, dz, best_plates, beam;
    apply_beam_scaling=false, enable_dispersion=true,
    enable_spm=true, enable_self_steepening=true,
    enable_self_focusing=true, qx0=qx0, qy0=qy0)

A_end, Itz, Ifz, bh = NLSESolver.propagate!(A0, cfg)

best_metrics = (A_end=A_end, Itz=Itz, Ifz=Ifz, beam_hist=bh)

struct FakeBP
    λ0::Float64; t::Vector{Float64}; ω::Vector{Float64}; z_mm::Vector{Float64}
    A0::Vector{ComplexF64}
end
bp = FakeBP(λ0, collect(t), collect(ω), z_mm, A0)

include("plot_best_run.jl")
plot_best_run(best_metrics, bp, best_plates; output_dir=joinpath(@__DIR__, "output_focus"))
