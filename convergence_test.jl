# convergence_test.jl — 数値収束試験
# Codex推奨: Nz×2 / N×2(dt半減) / T_window×2(窓拡大) で波形変化を確認
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using FFTW, Printf, Plots, Plots.PlotMeasures
include("material.jl"); include("Beam_focus.jl"); include("Plate_focus.jl")
include("NLSE_solver_focus.jl"); include("metrics.jl")
using .Material, .Beam, .Plates, .NLSESolver, .Metrics
include("config.jl")

const c0 = 2.99792458e8

# ベスト解プレート（replot.jl と同じ）
best_plates = [
    Plates.Plate(0.38, 2.38,   plate_specs_defs[1].mat, plate_specs_defs[1].β2, 0.0, plate_specs_defs[1].I_damage),
    Plates.Plate(25.35, 27.35, plate_specs_defs[2].mat, plate_specs_defs[2].β2, 0.0, plate_specs_defs[2].I_damage),
    Plates.Plate(36.29, 38.29, plate_specs_defs[3].mat, plate_specs_defs[3].β2, 0.0, plate_specs_defs[3].I_damage),
]

# -------------------------------------------------------
# ヘルパー: 任意グリッドで伝搬してA_endを返す
# -------------------------------------------------------
function run_with_params(; N_pts, T_win, Nz_pts)
    ω0 = 2π * c0 / λ0
    dt = T_win / N_pts
    t  = collect((0:N_pts-1) .* dt .- T_win/2)
    dω = 2π / T_win
    ω  = [(k < N_pts÷2) ? k*dω : (k-N_pts)*dω for k in 0:N_pts-1]
    z_mm = collect(range(z_min_mm, z_max_mm, length=Nz_pts+1))
    dz   = (z_max_mm - z_min_mm) * 1e-3 / Nz_pts

    beam = Beam.knifeedge_beam(
        w0x_mm=focus_w0x_mm, z0x_mm=focus_z0x_mm, zRx_mm=focus_zRx_mm,
        w0y_mm=focus_w0y_mm, z0y_mm=focus_z0y_mm, zRy_mm=focus_zRy_mm,
        waist_is_diameter=focus_waist_is_diameter)

    τ0 = τ_fwhm / (2sqrt(log(2)))
    P0 = Ep / (0.94 * τ_fwhm)
    A0 = complex.(sqrt(P0) .* exp.(-(t.^2) ./ (2τ0^2)))
    qx0, qy0 = Beam.initial_q(beam, z_min_mm)

    cfg = NLSESolver.NLSEConfig(λ0, ω0, t, ω, z_mm, dz, best_plates, beam;
        apply_beam_scaling=false, enable_dispersion=true,
        enable_spm=true, enable_self_steepening=true,
        enable_self_focusing=true, qx0=qx0, qy0=qy0)

    A_end, Itz, _, _ = NLSESolver.propagate!(A0, cfg)

    # 共通時間軸に補間するためベースライン時間軸で評価: 強度プロファイルを返す
    I_out = abs2.(A_end)
    E_in  = sum(abs2.(A0)) * dt
    E_out = sum(I_out) * dt

    return (t=t, I=I_out, E_in=E_in, E_out=E_out, A_end=A_end, A0=A0, dt=dt)
end

# -------------------------------------------------------
# 共通: L2 相対誤差を計算（両結果を共通軸に補間）
# -------------------------------------------------------
function l2_rel(ref, tgt)
    # 単純に共通時間軸のデータ点だけ使って比較
    # 時間軸が同じ場合はそのまま、違う場合は小さいほうを使う
    n = min(length(ref.I), length(tgt.I))
    # 中央周辺を切り出す
    c_ref = length(ref.I) ÷ 2
    c_tgt = length(tgt.I) ÷ 2
    half = n ÷ 4   # 対称的に ±n/4 を使う
    r = ref.I[c_ref-half : c_ref+half]
    t = tgt.I[c_tgt-half : c_tgt+half]
    # tを長さ合わせ（小さいほうに）
    n2 = min(length(r), length(t))
    r = r[1:n2]; t = t[1:n2]
    denom = sqrt(sum(r.^2))
    return denom > 0 ? sqrt(sum((r .- t).^2)) / denom : NaN
end

# -------------------------------------------------------
# ケース1 (Baseline): N=2^14, T_window=2ps, Nz=2000
# -------------------------------------------------------
println("=== Baseline: N=2^14, T=2ps, Nz=2000 ===")
r0 = run_with_params(N_pts=2^14, T_win=2e-12, Nz_pts=2000)
@printf("  Energy conservation: %.8f\n", r0.E_out / r0.E_in)
@printf("  Peak intensity: %.4f (normalized)\n", maximum(r0.I) / maximum(abs2.(r0.A0)))

# -------------------------------------------------------
# ケース2: Nz×2 (dz 半減)
# -------------------------------------------------------
println("\n=== Test dz/2: N=2^14, T=2ps, Nz=4000 ===")
r1 = run_with_params(N_pts=2^14, T_win=2e-12, Nz_pts=4000)
@printf("  Energy conservation: %.8f\n", r1.E_out / r1.E_in)
@printf("  Peak intensity: %.4f (normalized)\n", maximum(r1.I) / maximum(abs2.(r1.A0)))
err_dz = l2_rel(r0, r1)
@printf("  L2 relative error vs baseline: %.4e\n", err_dz)

# -------------------------------------------------------
# ケース3: N×2, T_window 固定 (dt 半減)
# -------------------------------------------------------
println("\n=== Test dt/2: N=2^15, T=2ps, Nz=2000 ===")
r2 = nothing
err_dt = NaN
try
    r2 = run_with_params(N_pts=2^15, T_win=2e-12, Nz_pts=2000)
    @printf("  Energy conservation: %.8f\n", r2.E_out / r2.E_in)
    @printf("  Peak intensity: %.4f (normalized)\n", maximum(r2.I) / maximum(abs2.(r2.A0)))
    err_dt = l2_rel(r0, r2)
    @printf("  L2 relative error vs baseline: %.4e\n", err_dt)
catch e
    println("  FAILED: ", e.msg)
    println("  → q-パラメータ崩壊: N増加時の高周波ノイズがthin-lens近似を不安定化した可能性")
end

# -------------------------------------------------------
# ケース3b: N×2 + Nz×2 (dt/2 + dz/2 同時)
# -------------------------------------------------------
println("\n=== Test dt/2 + dz/2: N=2^15, T=2ps, Nz=4000 ===")
r2b = nothing
err_dt_dz = NaN
try
    r2b = run_with_params(N_pts=2^15, T_win=2e-12, Nz_pts=4000)
    @printf("  Energy conservation: %.8f\n", r2b.E_out / r2b.E_in)
    @printf("  Peak intensity: %.4f (normalized)\n", maximum(r2b.I) / maximum(abs2.(r2b.A0)))
    err_dt_dz = l2_rel(r0, r2b)
    @printf("  L2 relative error vs baseline: %.4e\n", err_dt_dz)
catch e
    println("  FAILED: ", e.msg)
end

# -------------------------------------------------------
# ケース4: T_window×2, N×2 (dt 固定、窓拡大)
# -------------------------------------------------------
println("\n=== Test T_win×2: N=2^15, T=4ps, Nz=2000 ===")
r3 = nothing
err_twin = NaN
try
    r3 = run_with_params(N_pts=2^15, T_win=4e-12, Nz_pts=2000)
    @printf("  Energy conservation: %.8f\n", r3.E_out / r3.E_in)
    @printf("  Peak intensity: %.4f (normalized)\n", maximum(r3.I) / maximum(abs2.(r3.A0)))
    err_twin = l2_rel(r0, r3)
    @printf("  L2 relative error vs baseline: %.4e\n", err_twin)
catch e
    println("  FAILED: ", e.msg)
end

# -------------------------------------------------------
# プロット: 全ケースの出力波形を重ね描き
# -------------------------------------------------------
output_dir = joinpath(@__DIR__, "output_focus")
mkpath(output_dir)

xlim = (-500.0, 500.0)
I0_n = r0.I ./ maximum(abs2.(r0.A0))
I1_n = r1.I ./ maximum(abs2.(r1.A0))

p = plot(r0.t .* 1e15, I0_n;
    label="Baseline (N=2¹⁴, Nz=2000)", lw=2, ls=:solid,
    xlabel="Time [fs]", ylabel="Normalized intensity",
    title="Convergence test: output waveform",
    xlims=xlim, legend=:topright)
plot!(p, r1.t .* 1e15, I1_n; label="dz/2  (Nz=4000)", lw=1.5, ls=:dash)
if !isnothing(r2)
    plot!(p, r2.t .* 1e15, r2.I ./ maximum(abs2.(r2.A0));
        label="dt/2  (N=2¹⁵, T=2ps)", lw=1.5, ls=:dot)
end
if !isnothing(r2b)
    plot!(p, r2b.t .* 1e15, r2b.I ./ maximum(abs2.(r2b.A0));
        label="dt/2+dz/2 (N=2¹⁵, Nz=4000)", lw=1.5, ls=:dot)
end
if !isnothing(r3)
    plot!(p, r3.t .* 1e15, r3.I ./ maximum(abs2.(r3.A0));
        label="T×2 (N=2¹⁵, T=4ps)", lw=1.5, ls=:dashdot)
end

savefig(p, joinpath(output_dir, "convergence_waveform.png"))
println("\nSaved: convergence_waveform.png")

# -------------------------------------------------------
# 判定サマリー
# -------------------------------------------------------
println("\n=== 収束判定サマリー ===")
label_judge(e) = isnan(e) ? "FAILED" : (e < 1e-2 ? "収束OK (< 1%)" : "要注意 (> 1%)")
@printf("  dz/2          L2 error: %s  → %s\n", isnan(err_dz)    ? "  N/A   " : @sprintf("%.4e", err_dz),    label_judge(err_dz))
@printf("  dt/2          L2 error: %s  → %s\n", isnan(err_dt)    ? "  N/A   " : @sprintf("%.4e", err_dt),    label_judge(err_dt))
@printf("  dt/2+dz/2     L2 error: %s  → %s\n", isnan(err_dt_dz) ? "  N/A   " : @sprintf("%.4e", err_dt_dz), label_judge(err_dt_dz))
@printf("  T_win×2       L2 error: %s  → %s\n", isnan(err_twin)  ? "  N/A   " : @sprintf("%.4e", err_twin),  label_judge(err_twin))
println()
println("判定: L2 < 1e-2 なら数値アーティファクトは小さく二山は物理的")
println("      L2 > 1e-2 ならグリッド改善を推奨")
