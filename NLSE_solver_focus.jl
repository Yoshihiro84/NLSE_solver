module NLSESolver

using FFTW
using ..Plates
using ..Beam

export NLSEConfig, propagate!

const ε0  = 8.8541878128e-12
const c0  = 2.99792458e8

"NLSE の設定一式"
struct NLSEConfig
    λ0::Float64             # 中心波長 [m]
    ω0::Float64             # 中心角周波数 [rad/s]
    t::Vector{Float64}      # 時間軸 [s]
    ω::Vector{Float64}      # 周波数軸 [rad/s]
    z_mm::Vector{Float64}   # 伝搬位置 [mm]
    dz::Float64             # z ステップ [m]
    plates::Vector{Plates.Plate}
    beam::Beam.AbstractBeam
    apply_beam_scaling::Bool  # if true, rescale A by sqrt(A_eff) to include focusing
    enable_dispersion::Bool
    enable_spm::Bool
    enable_self_steepening::Bool
end

"Convenience constructor"
NLSEConfig(λ0, ω0, t, ω, z_mm, dz, plates, beam;
           apply_beam_scaling=false,
           enable_dispersion=true,
           enable_spm=true,
           enable_self_steepening=true) =
    NLSEConfig(λ0, ω0, t, ω, z_mm, dz, plates, beam,
               apply_beam_scaling, enable_dispersion, enable_spm, enable_self_steepening)


"線形ステップ: GVD + TOD を周波数領域で進める"
function linear_step(A::Vector{ComplexF64},
                     dz::Float64,
                     β2_here::Float64,
                     β3_here::Float64,
                     ω::Vector{Float64},
                     enable_dispersion::Bool)
    if !enable_dispersion
        return A
    end
    if β2_here == 0.0 && β3_here == 0.0
        return A
    end
    Aω = fft(A)
    phaseL = exp.(1im .* ((β2_here/2) .* (ω.^2) .+ (β3_here/6) .* (ω.^3)) .* dz)
    Aω .*= phaseL
    return ifft(Aω)
end

"非線形演算子（self-steepening 含む）"
function N_op(A::Vector{ComplexF64},
              γ_here::Float64,
              ω0::Float64,
              ω::Vector{Float64},
              enable_spm::Bool,
              enable_self_steepening::Bool)
    if γ_here == 0.0
        return zeros(ComplexF64, length(A))
    end
    I  = abs2.(A)
    S  = I .* A
    term_spm = enable_spm ? S : zero.(S)
    if enable_self_steepening
        Sω = fft(S)
        dSdt = ifft(1im .* ω .* Sω)
        term_ss = (1im/ω0) .* dSdt
    else
        term_ss = zero.(S)
    end
    return 1im * γ_here .* (term_spm .+ term_ss)
end

"非線形ステップを z 方向に RK4 で進める"
function nonlinear_step_rk4(A::Vector{ComplexF64},
                            dz::Float64,
                            γ_here::Float64,
                            ω0::Float64,
                            ω::Vector{Float64},
                            enable_spm::Bool,
                            enable_self_steepening::Bool)
    if γ_here == 0.0
        return A
    end
    if !enable_spm && !enable_self_steepening
        return A
    end
    k1 = N_op(A, γ_here, ω0, ω, enable_spm, enable_self_steepening)
    k2 = N_op(A .+ 0.5 * dz .* k1, γ_here, ω0, ω, enable_spm, enable_self_steepening)
    k3 = N_op(A .+ 0.5 * dz .* k2, γ_here, ω0, ω, enable_spm, enable_self_steepening)
    k4 = N_op(A .+ dz .* k3,      γ_here, ω0, ω, enable_spm, enable_self_steepening)
    return A .+ (dz/6.0) .* (k1 .+ 2k2 .+ 2k3 .+ k4)
end

"""
伝搬本体
- A0: z = z_min での初期包絡（電場）
- cfg: NLSEConfig
返り値:
- A_end: 出口の包絡
- Itz: 時間強度 vs z（nt × nz_frames）
- Ifz: スペクトル強度 vs z（nt × nz_frames）
"""
function propagate!(A0::Vector{ComplexF64}, cfg::NLSEConfig)
    A = copy(A0)
    nt = length(cfg.t)
    Nz = length(cfg.z_mm) - 1

    nz_frames = Nz + 1
    Itz = zeros(Float64, nt, nz_frames)
    Ifz = zeros(Float64, nt, nz_frames)

    # z = z_min
    Itz[:, 1] .= abs2.(A)
    S0 = fft(A)
    Ifz[:, 1] .= fftshift(abs2.(S0))

    for iz in 1:Nz
        z_here_mm = cfg.z_mm[iz]
        z_next_mm = cfg.z_mm[iz+1]
        z_mid_mm  = 0.5 * (z_here_mm + z_next_mm)

        # Dispersion/nonlinearity coefficients (use midpoint for better coupling)
        β2_here, β3_here, n2_here =
            Plates.coeffs_at_z(z_mid_mm, cfg.plates, cfg.beam, cfg.λ0)

        # --- Include focusing (knife-edge / optics) via area scaling ---
        # Keep pulse energy Ep = ∫ I(t) dt * A_eff(z) conserved when A_eff changes with z.
        # This approximates linear focusing in a 1D (time-only) NLSE.
        if cfg.apply_beam_scaling
            Aeff_here = Beam.A_eff(cfg.beam, z_here_mm)
            Aeff_mid  = Beam.A_eff(cfg.beam, z_mid_mm)
            A .*= sqrt(Aeff_here / Aeff_mid)
        end

        # gamma from current Aeff (power-envelope form)
        Aeff_mid = Beam.A_eff(cfg.beam, z_mid_mm)
        γ_here = (n2_here == 0.0) ? 0.0 : (n2_here * cfg.ω0 / (c0 * Aeff_mid))

        # Inner NLSE: symmetric split-step (L/2 -> N -> L/2)
        A = linear_step(A, cfg.dz/2, β2_here, β3_here, cfg.ω, cfg.enable_dispersion)
        A = nonlinear_step_rk4(A, cfg.dz,  γ_here, cfg.ω0, cfg.ω,
                               cfg.enable_spm, cfg.enable_self_steepening)
        A = linear_step(A, cfg.dz/2, β2_here, β3_here, cfg.ω, cfg.enable_dispersion)

        if cfg.apply_beam_scaling
            Aeff_mid  = Beam.A_eff(cfg.beam, z_mid_mm)
            Aeff_next = Beam.A_eff(cfg.beam, z_next_mm)
            A .*= sqrt(Aeff_mid / Aeff_next)
        end
        Itz[:, iz+1] .= abs2.(A)
        S = fft(A)
        Ifz[:, iz+1] .= fftshift(abs2.(S))
    end

    return A, Itz, Ifz
end

end # module
