import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using Printf, FFTW
include("material.jl")
include("Beam_focus.jl")
include("Plate_focus.jl")
include("NLSE_solver_focus.jl")
include("metrics.jl")
using .Material, .Beam, .Plates, .NLSESolver, .Metrics
include("config.jl")

c0 = 2.99792458e8
ω0 = 2π * c0 / λ0
dt = T_window / N
t  = collect((0:N-1) .* dt .- T_window/2)
dω = 2π / T_window
ω  = [(k < N÷2) ? k*dω : (k-N)*dω for k in 0:N-1]
z_mm = collect(range(z_min_mm, z_max_mm, length=Nz+1))
dz   = (z_max_mm - z_min_mm) * 1e-3 / Nz
beam = Beam.knifeedge_beam(
    w0x_mm=focus_w0x_mm, z0x_mm=focus_z0x_mm, zRx_mm=focus_zRx_mm,
    w0y_mm=focus_w0y_mm, z0y_mm=focus_z0y_mm, zRy_mm=focus_zRy_mm,
    waist_is_diameter=focus_waist_is_diameter)
tau0 = τ_fwhm / (2sqrt(log(2)))
P0 = Ep / (0.94 * τ_fwhm)
A0 = complex.(sqrt(P0) .* exp.(-(t.^2) ./ (2tau0^2)))
qx0, qy0 = Beam.initial_q(beam, z_min_mm)

# ベスト解のプレート位置 (最適化結果より)
plates = [
    Plates.Plate(0.38, 2.38,   plate_specs_defs[1].mat, plate_specs_defs[1].β2, 0.0, plate_specs_defs[1].I_damage),
    Plates.Plate(25.35, 27.35, plate_specs_defs[2].mat, plate_specs_defs[2].β2, 0.0, plate_specs_defs[2].I_damage),
    Plates.Plate(36.29, 38.29, plate_specs_defs[3].mat, plate_specs_defs[3].β2, 0.0, plate_specs_defs[3].I_damage),
]

cfg = NLSESolver.NLSEConfig(λ0, ω0, t, ω, z_mm, dz, plates, beam;
    apply_beam_scaling=false, enable_dispersion=true,
    enable_spm=true, enable_self_steepening=true,
    enable_self_focusing=true, qx0=qx0, qy0=qy0)

A_end, Itz, Ifz, bh = NLSESolver.propagate!(A0, cfg)

report = Metrics.analyze_plate_limits(Itz, cfg;
    B_warn_rad  = Float64(B_WARN_PER_PLATE_RAD),
    B_limit_rad = Float64(B_LIMIT_PER_PLATE_RAD),
    safety_factor = I_SAFETY_FACTOR,
    Aeff_hist = bh.Aeff)

B_warn  = Float64(B_WARN_PER_PLATE_RAD)
B_limit = Float64(B_LIMIT_PER_PLATE_RAD)
@printf("B_warn  = pi    = %.3f rad\n", B_warn)
@printf("B_limit = 2*pi  = %.3f rad\n", B_limit)
println()
names = ["Si  ", "NaCl", "Si  "]
println("Plate  Material  thick   z [mm]          B [rad]   /B_limit   status      Ipk [W/cm2]")
println(repeat("-", 88))
for i in 1:3
    p = plates[i]
    thick = p.z_end_mm - p.z_start_mm
    @printf("  %d    %s    %.1f mm  %5.2f--%5.2f mm  %6.3f    %5.1f%%     %-10s  %.3e\n",
        i, names[i], thick, p.z_start_mm, p.z_end_mm,
        report.B_per_plate[i],
        report.B_per_plate[i] / B_limit * 100,
        report.B_status[i],
        report.Ipk_per_plate[i])
end
println(repeat("-", 88))
@printf("Total                                     %6.3f    %5.1f%%     (limit=%.3f rad)\n",
    report.B_total, report.B_total / B_limit * 100, B_limit)
