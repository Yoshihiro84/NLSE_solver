#=
plot_best_run.jl — 最適化ベスト解の可視化
==============================================
optimize_plates.jl の CLI セクションから include して使う。

呼び出し方:
    include("plot_best_run.jl")
    plot_best_run(best_metrics, bp, best_plates; output_dir=joinpath(@__DIR__, "output_focus"))

前提:
    best_metrics は run_sim(...; save_history=true) の戻り値（Ifz, beam_hist を含む）
    bp は BaseParams
    best_plates は Vector{Plates.Plate}（ソート済み）
=#

using Plots
using Plots.PlotMeasures
using FFTW
using Printf

# -------------------------------------------------------
# ヘルパー: プレート領域を vspan! で重ね描き
# -------------------------------------------------------
function _add_plate_spans!(plt, plates)
    for (i, p) in enumerate(plates)
        vspan!(plt, [p.z_start_mm, p.z_end_mm];
               alpha=0.18, color=:gray,
               label=(i == 1 ? "Plate" : ""))
    end
    return plt
end

# -------------------------------------------------------
# メイン関数
# -------------------------------------------------------
"""
    plot_best_run(best_metrics, bp, best_plates; output_dir)

最適化ベスト解の 5 種類のプロットを output_dir に保存する。

プロット一覧:
  1. opt_spec_vs_z.png     — z vs スペクトル ヒートマップ (log10)
  2. opt_time_vs_z.png     — z vs 時間波形 ヒートマップ (log10)
  3. opt_spectrum_io.png   — 入力 vs 出力 スペクトル (dB, 1D)
  4. opt_waveform_io.png   — 入力 vs 出力 時間波形 (正規化, 1D)
  5. opt_beam_vs_z.png     — ビーム径 (wx, wy) vs z
"""
function plot_best_run(best_metrics, bp, best_plates;
                       output_dir::String=joinpath(@__DIR__, "output_focus"))
    mkpath(output_dir)

    c0    = 2.99792458e8
    f0_THz = c0 / bp.λ0 / 1e12

    t_fs  = bp.t .* 1e15
    z_mm  = bp.z_mm

    # 周波数軸 (fftshift済み、絶対周波数 [THz])
    freq_THz = fftshift(bp.ω) ./ (2π) ./ 1e12 .+ f0_THz

    # 正規化
    Itz      = best_metrics.Itz
    Ifz      = best_metrics.Ifz
    max_Itz  = maximum(Itz)
    max_Ifz  = maximum(Ifz)
    Itz_norm = max_Itz > 0 ? Itz ./ max_Itz : Itz
    Ifz_norm = max_Ifz > 0 ? Ifz ./ max_Ifz : Ifz

    # ylims の自動決定: 出力スペクトルを自己ピーク正規化して -10 dB 帯域を取る
    # (Ifz_norm はグローバル最大で割ったもので出力ピークが << 1 になる場合があるため、
    #  出力フレームだけを自己正規化してマスクを作る)
    S_out_raw = Ifz[:, end]
    S_out_self = S_out_raw ./ max(maximum(S_out_raw), 1e-30)
    mask_f = S_out_self .>= 0.1   # -10 dB relative to output peak
    valid_f = freq_THz[mask_f]
    if isempty(valid_f)
        f_lo, f_hi = f0_THz - 20.0, f0_THz + 20.0
    else
        pad = 5.0  # THz
        f_lo = minimum(valid_f) - pad
        f_hi = maximum(valid_f) + pad
    end

    mask_t = vec(any(Itz_norm .>= 1e-4, dims=2))
    valid_t = t_fs[mask_t]
    if isempty(valid_t)
        t_lo, t_hi = -500.0, 500.0
    else
        pad = 50.0  # fs
        t_lo = minimum(valid_t) - pad
        t_hi = maximum(valid_t) + pad
    end

    # =====================================================
    # 1. z vs スペクトル ヒートマップ
    # =====================================================
    # freq_THz は -4000〜4000 THz 超の広範囲なので、表示域だけ事前クリップ
    fmask = (freq_THz .>= f_lo) .& (freq_THz .<= f_hi)
    freq_THz_clip = freq_THz[fmask]
    Ifz_norm_clip = Ifz_norm[fmask, :]

    p_spec = heatmap(
        z_mm,
        freq_THz_clip,
        log10.(max.(Ifz_norm_clip, 1e-4));
        xlabel          = "Propagation length z [mm]",
        ylabel          = "Frequency [THz]",
        title           = "Spectral evolution along z  (log₁₀, normalized)",
        colorbar_title  = "\nLog₁₀ |Aω|²",
        clims           = (-4, 0),
        right_margin    = 10mm,
    )
    _add_plate_spans!(p_spec, best_plates)
    savefig(p_spec, joinpath(output_dir, "opt_spec_vs_z.png"))
    println("  Saved opt_spec_vs_z.png")

    # =====================================================
    # 2. z vs 時間 ヒートマップ
    # =====================================================
    # t_fs も広範囲なので表示域だけ事前クリップ
    tmask = (t_fs .>= t_lo) .& (t_fs .<= t_hi)
    t_fs_clip   = t_fs[tmask]
    Itz_norm_clip = Itz_norm[tmask, :]

    p_time = heatmap(
        z_mm,
        t_fs_clip,
        log10.(max.(Itz_norm_clip, 1e-4));
        xlabel          = "Propagation length z [mm]",
        ylabel          = "Time [fs]",
        title           = "Temporal evolution along z  (log₁₀, normalized)",
        colorbar_title  = "\nLog₁₀ |A|²",
        clims           = (-4, 0),
        right_margin    = 10mm,
    )
    _add_plate_spans!(p_time, best_plates)
    savefig(p_time, joinpath(output_dir, "opt_time_vs_z.png"))
    println("  Saved opt_time_vs_z.png")

    # =====================================================
    # 3. 入力 vs 出力 スペクトル (線形, 自己正規化)
    # =====================================================
    S_in  = fftshift(abs2.(fft(bp.A0)))
    S_out = fftshift(abs2.(fft(best_metrics.A_end)))
    S_in_n  = S_in  ./ max(maximum(S_in),  1e-30)
    S_out_n = S_out ./ max(maximum(S_out), 1e-30)

    # 横軸: -10 dB 帯域の約 2 倍幅
    f_center = (f_lo + f_hi) / 2
    bw_half  = (f_hi - f_lo) / 2
    f_lo_wide = f_center - bw_half * 2
    f_hi_wide = f_center + bw_half * 2

    p_spec_io = plot(
        freq_THz, S_in_n;
        label   = "Input",
        lw      = 1.5,
        xlabel  = "Frequency [THz]",
        ylabel  = "Spectral power (normalized)",
        title   = "Spectrum: input vs output",
        xlims   = (f_lo_wide, f_hi_wide),
    )
    plot!(p_spec_io, freq_THz, S_out_n; label="Output", lw=1.5, ls=:dash)
    savefig(p_spec_io, joinpath(output_dir, "opt_spectrum_io.png"))
    println("  Saved opt_spectrum_io.png")

    # =====================================================
    # 4. 入力 vs 出力 時間波形 (正規化強度)
    # =====================================================
    I_in  = abs2.(bp.A0)
    I_out = abs2.(best_metrics.A_end)
    I_peak = max(maximum(I_in), maximum(I_out))

    p_wave_io = plot(
        t_fs, I_in  ./ I_peak;
        label   = "Input",
        lw      = 1.5,
        xlabel  = "Time [fs]",
        ylabel  = "Normalized intensity",
        title   = "Waveform: input vs output",
        xlims   = (t_lo, t_hi),
    )
    plot!(p_wave_io, t_fs, I_out ./ I_peak; label="Output", lw=1.5, ls=:dash)
    savefig(p_wave_io, joinpath(output_dir, "opt_waveform_io.png"))
    println("  Saved opt_waveform_io.png")

    # =====================================================
    # 5. ビーム径 vs z
    # =====================================================
    bh = best_metrics.beam_hist
    p_beam = plot(
        z_mm, bh.wx .* 1e3;
        label   = "wx  (1/e² radius) [mm]",
        lw      = 1.5,
        xlabel  = "z [mm]",
        ylabel  = "Beam radius [mm]",
        title   = "Beam radii along z",
    )
    plot!(p_beam, z_mm, bh.wy .* 1e3; label="wy  (1/e² radius) [mm]", lw=1.5, ls=:dash)
    _add_plate_spans!(p_beam, best_plates)
    savefig(p_beam, joinpath(output_dir, "opt_beam_vs_z.png"))
    println("  Saved opt_beam_vs_z.png")

    println("All plots saved to: ", output_dir)
end
