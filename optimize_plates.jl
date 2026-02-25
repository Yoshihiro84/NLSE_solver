import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using FFTW
using Printf
using BlackBoxOptim

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
include("metrics.jl")

using .Material
using .Beam
using .Plates
using .NLSESolver
using .Metrics

# ===============================
# PlateSpec: template for one plate
# ===============================

"""
1枚のプレートテンプレート。
- fixed=true のプレートは最適化対象外（z_start_init が固定される）
- z_range: 最適化時の z_start 探索範囲 [mm]
"""
struct PlateSpec
    material::Material.MaterialModel
    thick_mm::Float64           # 固定厚み [mm]
    β2::Float64
    β3::Float64
    I_damage_Wcm2::Float64
    z_start_init::Float64       # 初期位置 (固定時はこの値を使用) [mm]
    fixed::Bool                 # true=位置固定, false=最適化対象
    z_range::Tuple{Float64,Float64}  # 探索範囲 [mm] (fixed=trueなら無視)
end

# ===============================
# OptConfig: optimization settings
# ===============================

struct OptConfig
    safety_factor::Float64       # default 1.5
    B_limit_rad::Float64         # default 2π
    λ_overlap::Float64           # ペナルティ重み (default 1e4)
    λ_B::Float64                 # ペナルティ重み (default 1e2)
    max_evals::Int               # 総評価回数 (default 300)
    n_restarts::Int              # マルチスタート回数 (default 1)
end

OptConfig(; safety_factor=1.5, B_limit_rad=2π, λ_overlap=1e4, λ_B=1e2, max_evals=300, n_restarts=1) =
    OptConfig(safety_factor, B_limit_rad, λ_overlap, λ_B, max_evals, n_restarts)

# ===============================
# Base simulation parameters
# ===============================

struct BaseParams
    λ0::Float64
    ω0::Float64
    t::Vector{Float64}
    ω::Vector{Float64}
    z_mm::Vector{Float64}
    dz::Float64
    beam::Beam.AbstractBeam
    A0::Vector{ComplexF64}
    enable_spm::Bool
    enable_self_steepening::Bool
    enable_self_focusing::Bool
    apply_beam_scaling::Bool
    qx0::ComplexF64
    qy0::ComplexF64
    B_warn_rad::Float64
    B_limit_rad::Float64
    aeff_min_m2::Float64        # Aeff 下限ガード [m²] (0 = 無効)
end

# ===============================
# Core functions
# ===============================

"""
Build Vector{Plate} from optimization variable x_opt and PlateSpec[].
fixed=true plates use z_start_init; variable plates get positions from x_opt.
All plates are sorted by z_start.
"""
function build_plates(x_opt::Vector{Float64}, specs::Vector{PlateSpec})
    plates = Plates.Plate[]
    opt_idx = 0
    for spec in specs
        if spec.fixed
            z_start = spec.z_start_init
        else
            opt_idx += 1
            z_start = x_opt[opt_idx]
        end
        z_end = z_start + spec.thick_mm
        push!(plates, Plates.Plate(z_start, z_end, spec.material,
                                   spec.β2, spec.β3, spec.I_damage_Wcm2))
    end
    sort!(plates, by=p -> p.z_start_mm)
    return plates
end

"""
Run NLSE simulation with given plates and return metrics.
Returns a NamedTuple with all analysis results.
"""
function run_sim(plates::Vector{Plates.Plate}, bp::BaseParams, opt::OptConfig;
                 save_history::Bool=false)
    cfg = NLSESolver.NLSEConfig(
        bp.λ0, bp.ω0, bp.t, bp.ω, bp.z_mm, bp.dz, plates, bp.beam;
        apply_beam_scaling = bp.apply_beam_scaling,
        enable_dispersion = true,
        enable_spm = bp.enable_spm,
        enable_self_steepening = bp.enable_self_steepening,
        enable_self_focusing = bp.enable_self_focusing,
        qx0 = bp.qx0,
        qy0 = bp.qy0,
        aeff_min_m2 = bp.aeff_min_m2,
    )

    A_end, Itz, Ifz, beam_hist = NLSESolver.propagate!(bp.A0, cfg)
    sf_Aeff = bp.enable_self_focusing ? beam_hist.Aeff : nothing

    limit_report = Metrics.analyze_plate_limits(
        Itz, cfg;
        B_warn_rad = bp.B_warn_rad,
        B_limit_rad = bp.B_limit_rad,
        safety_factor = opt.safety_factor,
        Aeff_hist = sf_Aeff
    )

    bandwidth_radps = Metrics.spectral_bandwidth_dB(A_end, bp.ω; threshold_dB=-10.0)
    bandwidth_THz = bandwidth_radps / (2π * 1e12)
    fwhm_fs = Metrics.pulse_fwhm_fs(A_end, bp.t)
    compressed_fs = Metrics.compressed_fwhm_fs(A_end, bp.t)
    tbp = fwhm_fs * 1e-15 * bandwidth_THz * 1e12  # dimensionless TBP

    result = (
        A_end = A_end,
        Itz = Itz,
        bandwidth_THz = bandwidth_THz,
        fwhm_fs = fwhm_fs,
        compressed_fwhm_fs = compressed_fs,
        tbp = tbp,
        Ipk_per_plate = limit_report.Ipk_per_plate,
        I_allow_per_plate = limit_report.I_allow_Wcm2_per_plate,
        B_per_plate = limit_report.B_per_plate,
        B_total = limit_report.B_total,
        B_status = limit_report.B_status,
        I_status = limit_report.I_status,
        has_violation = limit_report.has_violation,
    )
    if save_history
        return merge(result, (Ifz=Ifz, beam_hist=beam_hist))
    else
        return result
    end
end

"""
Compute penalty for overlap and B-integral excess (excluding damage, which is a hard 0).
"""
function penalty(x_opt::Vector{Float64}, specs::Vector{PlateSpec},
                 metrics::NamedTuple, opt::OptConfig)
    plates = build_plates(x_opt, specs)
    pen = 0.0

    # Overlap penalty (sorted plates)
    for i in 1:(length(plates)-1)
        gap = plates[i+1].z_start_mm - plates[i].z_end_mm
        if gap < 0.0
            pen += opt.λ_overlap * gap^2
        end
    end

    # B-integral penalty
    for Bi in metrics.B_per_plate
        excess = Bi / opt.B_limit_rad - 1.0
        if excess > 0.0
            pen += opt.λ_B * excess^2
        end
    end

    return pen
end

const _INFEASIBLE = 1e10  # sentinel for infeasible configurations (damage, out-of-bounds, sim failure)

"""
Objective function for BlackBoxOptim (minimization).
- Damage threshold exceeded / infeasible → return _INFEASIBLE (large positive, always worse than any valid solution)
- Otherwise → return -bandwidth + penalty
"""
function objective(x_opt::Vector{Float64}, specs::Vector{PlateSpec},
                   bp::BaseParams, opt::OptConfig,
                   n_collapsed::Ref{Int}=Ref(0),
                   n_other_fail::Ref{Int}=Ref(0))
    plates = build_plates(x_opt, specs)

    # Check z-domain validity: plates must fit within z_mm range
    z_max = bp.z_mm[end]
    for p in plates
        if p.z_end_mm > z_max || p.z_start_mm < bp.z_mm[1]
            return _INFEASIBLE
        end
    end

    local metrics
    try
        metrics = run_sim(plates, bp, opt)
    catch e
        if e isa ErrorException && (occursin("non-physical q-parameter", e.msg) ||
                                    occursin("Aeff dropped below minimum guard", e.msg))
            # Kerr thin-lens近似の破綻 or 物理的ビーム崩壊 → 想定内
            n_collapsed[] += 1
            return _INFEASIBLE
        end
        # 予期しない失敗
        n_other_fail[] += 1
        @warn "Simulation failed (unexpected)" exception=e
        return _INFEASIBLE
    end

    # Damage check: any plate with Ipk > I_allow → objective = 0 (plate destroyed)
    for i in eachindex(metrics.Ipk_per_plate)
        if metrics.Ipk_per_plate[i] > metrics.I_allow_per_plate[i]
            return _INFEASIBLE
        end
    end

    # No damage → maximize bandwidth (minimize -bandwidth + penalty)
    raw = metrics.bandwidth_THz
    pen = penalty(x_opt, specs, metrics, opt)
    return -raw + pen
end

"""
Run plate position optimization.
Returns (best_x, best_metrics, result) where result is the BlackBoxOptim result object.
"""
function optimize_plates!(specs::Vector{PlateSpec}, bp::BaseParams, opt::OptConfig;
                          verbose::Bool=true)
    # Determine variable plate indices and search ranges
    var_indices = findall(s -> !s.fixed, specs)
    n_var = length(var_indices)

    if n_var == 0
        @info "No variable plates to optimize. Running simulation with fixed positions."
        x_fixed = Float64[]
        plates = build_plates(x_fixed, specs)
        metrics = run_sim(plates, bp, opt)
        return x_fixed, metrics, nothing
    end

    lower = [specs[i].z_range[1] for i in var_indices]
    upper = [specs[i].z_range[2] for i in var_indices]

    if verbose
        println("=== Plate Position Optimization ===")
        println("Variable plates: $n_var")
        for (k, vi) in enumerate(var_indices)
            @printf("  Var %d (spec %d): range [%.2f, %.2f] mm, init=%.2f mm\n",
                    k, vi, lower[k], upper[k], specs[vi].z_start_init)
        end
        println("Fixed plates:")
        for (i, s) in enumerate(specs)
            if s.fixed
                @printf("  Spec %d: z_start=%.2f mm (fixed)\n", i, s.z_start_init)
            end
        end
        println("Max evaluations: $(opt.max_evals)")
    end

    # Initial guess from z_start_init of variable plates
    x0 = [specs[i].z_start_init for i in var_indices]

    n_collapsed  = Ref(0)
    n_other_fail = Ref(0)
    obj_fn = x -> objective(collect(x), specs, bp, opt, n_collapsed, n_other_fail)

    evals_per_restart = max(opt.max_evals ÷ opt.n_restarts, 10)
    best_result = nothing
    best_fit    = Inf

    for restart_i in 1:opt.n_restarts
        if verbose && opt.n_restarts > 1
            @printf("\n--- Restart %d / %d (max_evals=%d) ---\n",
                    restart_i, opt.n_restarts, evals_per_restart)
        end
        r = bboptimize(obj_fn;
            SearchRange = collect(zip(lower, upper)),
            NumDimensions = n_var,
            MaxFuncEvals = evals_per_restart,
            TraceMode = verbose ? :compact : :silent,
            Method = :adaptive_de_rand_1_bin_radiuslimited,
            RngSeed = restart_i * 1234,
        )
        if best_fitness(r) < best_fit
            best_fit    = best_fitness(r)
            best_result = r
        end
    end
    result = best_result

    best_x = collect(best_candidate(result))
    best_plates = build_plates(best_x, specs)
    best_metrics = run_sim(best_plates, bp, opt; save_history=true)

    if verbose
        println("\n=== Optimization Result ===")
        @printf("Best objective: %.6f\n", best_fitness(result))
        @printf("Bandwidth (-10dB): %.3f THz\n", best_metrics.bandwidth_THz)
        @printf("FWHM (actual):     %.1f fs\n", best_metrics.fwhm_fs)
        @printf("FWHM (FTL):        %.1f fs\n", best_metrics.compressed_fwhm_fs)
        @printf("TBP (actual):      %.3f  (Gaussian FTL = 0.441)\n", best_metrics.tbp)

        println("\nPlate layout:")
        opt_idx = 0
        for (i, spec) in enumerate(specs)
            if spec.fixed
                z_start = spec.z_start_init
                label = "FIXED"
            else
                opt_idx += 1
                z_start = best_x[opt_idx]
                label = @sprintf("optimized, range=[%.1f,%.1f]", spec.z_range[1], spec.z_range[2])
            end
            z_end = z_start + spec.thick_mm

            # Find plate in sorted plates to get the right metrics index
            plate_idx = findfirst(p -> abs(p.z_start_mm - z_start) < 1e-10, best_plates)
            if plate_idx !== nothing
                Ipk = best_metrics.Ipk_per_plate[plate_idx]
                Iallow = best_metrics.I_allow_per_plate[plate_idx]
                i_status = Ipk > Iallow ? "DAMAGE" : "OK"
                @printf("  Plate %d: z=%.2f-%.2f mm (%s), Ipk=%.3e W/cm² %s\n",
                        i, z_start, z_end, label, Ipk, i_status)
            else
                @printf("  Plate %d: z=%.2f-%.2f mm (%s)\n", i, z_start, z_end, label)
            end
        end

        if best_metrics.has_violation
            println("\nWARNING: Best solution has violations!")
        else
            println("\nAll plates within safe limits.")
        end

        @printf("\nCollapse events : %d (beam/thin-lens), %d (unexpected)\n",
                n_collapsed[], n_other_fail[])
    end

    return best_x, best_metrics, result
end

# ===============================
# CLI: Example usage
# ===============================

if abspath(PROGRAM_FILE) == @__FILE__
    # Load shared config
    include("config.jl")

    # Derived quantities
    ω0 = 2π * 2.99792458e8 / λ0

    dt = T_window / N
    t  = (0:N-1) .* dt .- T_window/2

    dω = 2π / T_window
    ω  = similar(t)
    for j in eachindex(ω)
        k = j - 1
        ω[j] = (k < N ÷ 2) ? (k * dω) : ((k - N) * dω)
    end

    z_mm = collect(range(z_min_mm, z_max_mm, length=Nz+1))
    dz = (z_max_mm - z_min_mm) * 1e-3 / Nz

    # Beam (from config)
    beam = if BEAM_MODE == :focus
        Beam.knifeedge_beam(
            w0x_mm = focus_w0x_mm,
            z0x_mm = focus_z0x_mm,
            zRx_mm = focus_zRx_mm,
            w0y_mm = focus_w0y_mm,
            z0y_mm = focus_z0y_mm,
            zRy_mm = focus_zRy_mm,
            waist_is_diameter = focus_waist_is_diameter,
        )
    elseif BEAM_MODE == :constant
        Beam.constant_beam(0.5 * const_diam_x_mm * 1e-3, 0.5 * const_diam_y_mm * 1e-3)
    else
        error("Unsupported BEAM_MODE=$(BEAM_MODE). Use :focus or :constant.")
    end

    # Input pulse
    τ0 = τ_fwhm / (2sqrt(log(2)))
    G  = exp.(-(t.^2) ./ (2τ0^2))
    P0 = Ep / (0.94 * τ_fwhm)
    A0 = complex.(sqrt(P0) .* G)

    if ENABLE_SELF_FOCUSING && !hasmethod(Beam.initial_q, Tuple{typeof(beam), Float64})
        error("ENABLE_SELF_FOCUSING=true requires a beam type that implements Beam.initial_q(). " *
              "Got $(typeof(beam)), which does not support q-parameter computation.")
    end

    sf_qx0, sf_qy0 = if ENABLE_SELF_FOCUSING
        Beam.initial_q(beam, z_min_mm)
    else
        (ComplexF64(0, 1), ComplexF64(0, 1))
    end

    bp = BaseParams(
        λ0, ω0, t, ω, z_mm, dz, beam, A0,
        ENABLE_SPM,
        ENABLE_SELF_STEEPENING,
        ENABLE_SELF_FOCUSING,
        (BEAM_MODE == :focus && !ENABLE_SELF_FOCUSING),  # apply_beam_scaling
        sf_qx0,
        sf_qy0,
        B_WARN_PER_PLATE_RAD,
        B_LIMIT_PER_PLATE_RAD,
        AEFF_MIN_GUARD_M2,
    )

    # Plate specs (from config)
    specs = [
        PlateSpec(ps.mat, ps.thick, ps.β2, ps.β3, ps.I_damage, ps.z_init, ps.fixed, ps.z_range)
        for ps in plate_specs_defs
    ]

    opt = OptConfig(
        safety_factor = I_SAFETY_FACTOR,
        B_limit_rad   = B_LIMIT_PER_PLATE_RAD,
        λ_overlap     = OPT_λ_OVERLAP,
        λ_B           = OPT_λ_B,
        max_evals     = OPT_MAX_EVALS,
        n_restarts    = OPT_N_RESTARTS,
    )

    best_x, best_metrics, result = optimize_plates!(specs, bp, opt)

    if ENABLE_PLOTS
        include(joinpath(@__DIR__, "plot_best_run.jl"))
        best_plates_plot = build_plates(best_x, specs)
        output_dir = joinpath(@__DIR__, "output_focus")
        println("\nGenerating plots...")
        plot_best_run(best_metrics, bp, best_plates_plot; output_dir=output_dir)
    end
end
