module NLSESolver

using FFTW
using ..Plates
using ..Beam

export NLSEConfig, propagate!, w_from_q, Aeff_from_q, beam_half_step

const ε0  = 8.8541878128e-12
const c0  = 2.99792458e8
const _W_FROM_Q_TOL = 1e-30  # tolerance for imag(1/q) physical-beam check

# =============================================
# q-parameter helpers (ported from NLSE_step5)
# =============================================

"Beam radius from q-parameter (air approximation), with numerical guard"
@inline function w_from_q(q::ComplexF64, λ0::Float64)
    if q == 0.0 + 0.0im
        error("w_from_q: q = 0 (singular). Beam has collapsed.")
    end
    invq = 1.0 / q
    if !isfinite(real(invq)) || !isfinite(imag(invq))
        error("w_from_q: 1/q is not finite (1/q = $invq, q = $q).")
    end
    imag_invq = imag(invq)
    # imag(1/q) must be negative for a physical beam.
    # Use tolerance to avoid false trigger from floating-point rounding
    # (e.g. wide/collimated beams where imag(1/q) ≈ -0).
    if imag_invq > -_W_FROM_Q_TOL
        error("w_from_q: non-physical q-parameter (imag(1/q) = $imag_invq ≥ -tol). " *
              "Beam has collapsed or q has become unphysical. " *
              "q = $q")
    end
    return sqrt(-λ0 / (π * imag_invq))
end

"Effective area and beam radii from q-parameters"
@inline function Aeff_from_q(qx::ComplexF64, qy::ComplexF64, λ0::Float64)
    wx = w_from_q(qx, λ0)
    wy = w_from_q(qy, λ0)
    return π * wx * wy, wx, wy
end

"ABCD linear free-space propagation for half-step (dz/2)"
@inline function beam_linear_half_step(qx::ComplexF64, qy::ComplexF64, dz_half::Float64)
    return qx + dz_half, qy + dz_half
end

"""
Kerr thin-lens update at a single z-plane (nonlinear full-step coupling point).
This is intentionally separated from linear free-space propagation so that
Kerr update can be applied in the same nonlinear sub-step as SPM/SS.
"""
function beam_kerr_step(qx::ComplexF64, qy::ComplexF64;
                        dz_nl::Float64,
                        n2_here::Float64,
                        Ppeak::Float64,
                        λ0::Float64,
                        enable_self_focusing::Bool)
    if !(enable_self_focusing && n2_here != 0.0 && Ppeak > 0.0)
        return qx, qy
    end

    _Aeff_here, wx_here, wy_here = Aeff_from_q(qx, qy, λ0)

    # On-axis intensity of an elliptic Gaussian beam: I0 = 2P / (pi wx wy)
    I0 = 2.0 * Ppeak / (π * wx_here * wy_here)

    # Thin-lens strengths from 2nd-order Kerr phase expansion.
    invfx = 4.0 * n2_here * I0 * dz_nl / (wx_here^2)
    invfy = 4.0 * n2_here * I0 * dz_nl / (wy_here^2)

    qx_next = 1.0 / (1.0 / qx - invfx)
    qy_next = 1.0 / (1.0 / qy - invfy)
    return qx_next, qy_next
end

"""
Beam half-step: free-propagate dz_half/2, apply Kerr thin-lens, free-propagate dz_half/2.
When enable_self_focusing=false or n2_here==0, only free propagation is applied.
"""
function beam_half_step(qx::ComplexF64, qy::ComplexF64;
                        dz_half::Float64,
                        n2_here::Float64,
                        Ppeak::Float64,
                        λ0::Float64,
                        enable_self_focusing::Bool)
    # free propagate to mid-plane
    qx_mid = qx + dz_half / 2
    qy_mid = qy + dz_half / 2

    # Kerr lens at mid-plane
    if enable_self_focusing && n2_here != 0.0 && Ppeak > 0.0
        _Aeff_mid, wx_mid, wy_mid = Aeff_from_q(qx_mid, qy_mid, λ0)

        # on-axis intensity (elliptic Gaussian): I0 = 2P / (π wx wy)
        I0 = 2.0 * Ppeak / (π * wx_mid * wy_mid)

        # thin-lens strengths from 2nd-order expansion
        invfx = 4.0 * n2_here * I0 * dz_half / (wx_mid^2)
        invfy = 4.0 * n2_here * I0 * dz_half / (wy_mid^2)

        qx_mid = 1.0 / (1.0 / qx_mid - invfx)
        qy_mid = 1.0 / (1.0 / qy_mid - invfy)
    end

    # free propagate to end of half-step
    qx_next = qx_mid + dz_half / 2
    qy_next = qy_mid + dz_half / 2
    return qx_next, qy_next
end

# =============================================
# Config
# =============================================

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
    enable_self_focusing::Bool  # Kerr self-focusing via q-parameter
    qx0::ComplexF64             # 初期 q-parameter (x)
    qy0::ComplexF64             # 初期 q-parameter (y)
    aeff_min_m2::Float64        # Aeff 下限ガード [m²] (0 = 無効)
end

"Convenience constructor with validation"
function NLSEConfig(λ0, ω0, t, ω, z_mm, dz, plates, beam;
           apply_beam_scaling=false,
           enable_dispersion=true,
           enable_spm=true,
           enable_self_steepening=true,
           enable_self_focusing=false,
           qx0=ComplexF64(0, 1),
           qy0=ComplexF64(0, 1),
           aeff_min_m2=0.0)
    if enable_self_focusing && apply_beam_scaling
        error("enable_self_focusing and apply_beam_scaling are mutually exclusive. " *
              "Use one or the other.")
    end
    if enable_self_focusing && qx0 == ComplexF64(0, 1) && qy0 == ComplexF64(0, 1)
        @warn "enable_self_focusing=true but qx0/qy0 are default dummy values. " *
              "Set qx0/qy0 from Beam.initial_q() for physically meaningful results."
    end
    return NLSEConfig(λ0, ω0, t, ω, z_mm, dz, plates, beam,
               apply_beam_scaling, enable_dispersion, enable_spm, enable_self_steepening,
               enable_self_focusing, qx0, qy0, aeff_min_m2)
end


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
- beam_hist: (wx=..., wy=..., Aeff=...) NamedTuple of beam history arrays
"""
function propagate!(A0::Vector{ComplexF64}, cfg::NLSEConfig)
    A = copy(A0)
    nt = length(cfg.t)
    Nz = length(cfg.z_mm) - 1

    nz_frames = Nz + 1
    Itz = zeros(Float64, nt, nz_frames)
    Ifz = zeros(Float64, nt, nz_frames)

    # beam history arrays
    wx_hist   = zeros(Float64, nz_frames)
    wy_hist   = zeros(Float64, nz_frames)
    Aeff_hist = zeros(Float64, nz_frames)

    # z = z_min
    Itz[:, 1] .= abs2.(A)
    S0 = fft(A)
    Ifz[:, 1] .= fftshift(abs2.(S0))

    # initialise q-parameters and beam history at z_min
    qx = cfg.qx0
    qy = cfg.qy0
    if cfg.enable_self_focusing
        Aeff_0, wx_0, wy_0 = Aeff_from_q(qx, qy, cfg.λ0)
        wx_hist[1]   = wx_0
        wy_hist[1]   = wy_0
        Aeff_hist[1] = Aeff_0
    else
        z_min_mm = cfg.z_mm[1]
        wx_hist[1]   = Beam.wx(cfg.beam, z_min_mm)
        wy_hist[1]   = Beam.wy(cfg.beam, z_min_mm)
        Aeff_hist[1] = Beam.A_eff(cfg.beam, z_min_mm)
    end

    for iz in 1:Nz
        z_here_mm = cfg.z_mm[iz]
        z_next_mm = cfg.z_mm[iz+1]
        z_mid_mm  = 0.5 * (z_here_mm + z_next_mm)

        # Dispersion/nonlinearity coefficients (use midpoint for better coupling)
        β2_here, β3_here, n2_here =
            Plates.coeffs_at_z(z_mid_mm, cfg.plates, cfg.beam, cfg.λ0)

        # Strang (coupled) scheme:
        # time-linear(dz/2) -> spatial-linear(dz/2) -> nonlinear(dz, with Kerr)
        # -> spatial-linear(dz/2) -> time-linear(dz/2)
        A = linear_step(A, cfg.dz/2, β2_here, β3_here, cfg.ω, cfg.enable_dispersion)

        if cfg.enable_self_focusing
            # Spatial linear half-step (ABCD free-space only).
            qx, qy = beam_linear_half_step(qx, qy, cfg.dz/2)
            Aeff_mid, _wx_mid, _wy_mid = Aeff_from_q(qx, qy, cfg.λ0)
            if cfg.aeff_min_m2 > 0.0 && Aeff_mid < cfg.aeff_min_m2
                error("propagate!: Aeff dropped below minimum guard " *
                      "(Aeff_mid=$(Aeff_mid) m² < aeff_min=$(cfg.aeff_min_m2) m²). " *
                      "Beam has collapsed (thin-lens approximation breakdown).")
            end

            # Use the same field/intensity snapshot for both temporal nonlinearity
            # (SPM+SS) and Kerr thin-lens update.
            Ppeak_nl = maximum(abs2.(A))
            γ_here = (n2_here == 0.0) ? 0.0 : (n2_here * cfg.ω0 / (c0 * Aeff_mid))
            A = nonlinear_step_rk4(A, cfg.dz, γ_here, cfg.ω0, cfg.ω,
                                   cfg.enable_spm, cfg.enable_self_steepening)
            qx, qy = beam_kerr_step(qx, qy;
                dz_nl=cfg.dz, n2_here=n2_here, Ppeak=Ppeak_nl,
                λ0=cfg.λ0, enable_self_focusing=true)

            # Spatial linear half-step.
            qx, qy = beam_linear_half_step(qx, qy, cfg.dz/2)
            Aeff_now, wx_now, wy_now = Aeff_from_q(qx, qy, cfg.λ0)
            if cfg.aeff_min_m2 > 0.0 && Aeff_now < cfg.aeff_min_m2
                error("propagate!: Aeff dropped below minimum guard " *
                      "(Aeff_now=$(Aeff_now) m² < aeff_min=$(cfg.aeff_min_m2) m²). " *
                      "Beam has collapsed (thin-lens approximation breakdown).")
            end
        else
            # Existing static-beam scaling path, aligned with the same split order.
            if cfg.apply_beam_scaling
                Aeff_here = Beam.A_eff(cfg.beam, z_here_mm)
                Aeff_mid  = Beam.A_eff(cfg.beam, z_mid_mm)
                A .*= sqrt(Aeff_here / Aeff_mid)
            end
            Aeff_mid = Beam.A_eff(cfg.beam, z_mid_mm)
            γ_here = (n2_here == 0.0) ? 0.0 : (n2_here * cfg.ω0 / (c0 * Aeff_mid))
            A = nonlinear_step_rk4(A, cfg.dz, γ_here, cfg.ω0, cfg.ω,
                                   cfg.enable_spm, cfg.enable_self_steepening)
            if cfg.apply_beam_scaling
                Aeff_next = Beam.A_eff(cfg.beam, z_next_mm)
                A .*= sqrt(Aeff_mid / Aeff_next)
            end
            wx_now   = Beam.wx(cfg.beam, z_next_mm)
            wy_now   = Beam.wy(cfg.beam, z_next_mm)
            Aeff_now = Beam.A_eff(cfg.beam, z_next_mm)
        end

        A = linear_step(A, cfg.dz/2, β2_here, β3_here, cfg.ω, cfg.enable_dispersion)

        Itz[:, iz+1] .= abs2.(A)
        S = fft(A)
        Ifz[:, iz+1] .= fftshift(abs2.(S))

        wx_hist[iz+1]   = wx_now
        wy_hist[iz+1]   = wy_now
        Aeff_hist[iz+1] = Aeff_now
    end

    beam_hist = (wx=wx_hist, wy=wy_hist, Aeff=Aeff_hist)
    return A, Itz, Ifz, beam_hist
end

end # module
