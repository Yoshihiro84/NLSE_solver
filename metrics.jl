module Metrics

using FFTW
using ..Plates
using ..Beam
using ..NLSESolver

export plate_index_at_z, classify_B, classify_I,
       analyze_plate_limits, compute_B,
       spectral_bandwidth_dB, pulse_fwhm_fs, compressed_fwhm_fs

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

"""
Aeff at z-grid index `idx` (1-based).
When Aeff_hist is provided (self-focusing), read from it;
otherwise fall back to static beam profile at z_mm[idx].
"""
function _get_Aeff_at(idx::Int, cfg::NLSESolver.NLSEConfig,
                      Aeff_hist::Union{Vector{Float64}, Nothing})
    if Aeff_hist !== nothing
        @assert 1 ≤ idx ≤ length(Aeff_hist) "Aeff_hist index out of bounds: idx=$idx, len=$(length(Aeff_hist))"
        return Aeff_hist[idx]
    else
        return Beam.A_eff(cfg.beam, cfg.z_mm[idx])
    end
end

"""
Aeff at midpoint between z-grid indices `iz` and `iz+1`.
When Aeff_hist is provided, linearly interpolate between iz and iz+1;
otherwise use beam profile at the midpoint z.
"""
function _get_Aeff_mid(iz::Int, cfg::NLSESolver.NLSEConfig,
                       Aeff_hist::Union{Vector{Float64}, Nothing})
    if Aeff_hist !== nothing
        @assert 1 ≤ iz && iz+1 ≤ length(Aeff_hist) "Aeff_hist index out of bounds: iz=$iz, len=$(length(Aeff_hist))"
        return 0.5 * (Aeff_hist[iz] + Aeff_hist[iz+1])
    else
        z_mid_mm = 0.5 * (cfg.z_mm[iz] + cfg.z_mm[iz+1])
        return Beam.A_eff(cfg.beam, z_mid_mm)
    end
end

function analyze_plate_limits(Itz::Array{Float64,2}, cfg::NLSESolver.NLSEConfig;
                              B_warn_rad::Float64,
                              B_limit_rad::Float64,
                              safety_factor::Float64,
                              Aeff_hist::Union{Vector{Float64}, Nothing}=nothing)
    nplates = length(cfg.plates)
    I_damage_Wcm2_per_plate = [p.I_damage_Wcm2 for p in cfg.plates]
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
        Aeff_end = _get_Aeff_at(iz + 1, cfg, Aeff_hist)
        if n2_here == 0.0 || Aeff_end <= 0.0 || !isfinite(Aeff_end)
            continue
        end

        gamma = n2_here * cfg.ω0 / (NLSESolver.c0 * Aeff_end)
        Ppeak = maximum(Itz[:, iz+1])
        if !isfinite(gamma) || !isfinite(Ppeak)
            continue
        end

        B_per_plate[pidx] += gamma * Ppeak * cfg.dz

        Ipk_Wcm2 = (2.0 * Ppeak / Aeff_end) / 1e4
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

function compute_B(Itz::Array{Float64,2}, cfg::NLSESolver.NLSEConfig;
                   Aeff_hist::Union{Vector{Float64}, Nothing}=nothing)
    Nz = length(cfg.z_mm) - 1
    B_total = 0.0
    for iz in 1:Nz
        z_mid_mm = 0.5 * (cfg.z_mm[iz] + cfg.z_mm[iz+1])
        _, _, n2_here = Plates.coeffs_at_z(z_mid_mm, cfg.plates, cfg.beam, cfg.λ0)
        if n2_here == 0.0
            continue
        end
        Aeff_mid = _get_Aeff_mid(iz, cfg, Aeff_hist)
        if Aeff_mid < 1e-20 || !isfinite(Aeff_mid)
            @warn "compute_B: skipping step $iz — Aeff dangerously small or non-finite" Aeff_mid
            continue
        end
        gamma = n2_here * cfg.ω0 / (NLSESolver.c0 * Aeff_mid)
        Ppeak = maximum(Itz[:, iz+1])
        if !isfinite(Ppeak) || !isfinite(gamma)
            @warn "compute_B: skipping step $iz — non-finite gamma or Ppeak" gamma Ppeak
            continue
        end
        B_total += gamma * Ppeak * cfg.dz
    end
    return B_total
end

# ===============================
# New metric functions
# ===============================

"""
    spectral_bandwidth_dB(A_end, ω; threshold_dB=-20.0) -> Float64

Compute the spectral bandwidth [rad/s] at `threshold_dB` below the peak.
Returns 0.0 if no points are above the threshold.
"""
function spectral_bandwidth_dB(A_end::Vector{ComplexF64}, ω::Vector{Float64};
                                threshold_dB::Float64=-20.0)
    Aω = fft(A_end)
    S = abs2.(Aω)
    S_max = maximum(S)
    if S_max <= 0.0
        return 0.0
    end
    S_norm = S ./ S_max
    threshold_lin = 10.0^(threshold_dB / 10.0)

    # Find frequency indices above threshold
    ω_sorted_idx = sortperm(ω)
    ω_sorted = ω[ω_sorted_idx]
    S_sorted = S_norm[ω_sorted_idx]

    above = findall(x -> x >= threshold_lin, S_sorted)
    if isempty(above)
        return 0.0
    end
    ω_min = ω_sorted[first(above)]
    ω_max = ω_sorted[last(above)]
    return ω_max - ω_min
end

"""
    pulse_fwhm_fs(A_end, t) -> Float64

Compute the temporal FWHM [fs] of |A|^2.
Returns 0.0 if the pulse is zero.
"""
function pulse_fwhm_fs(A_end::Vector{ComplexF64}, t::Vector{Float64})
    I = abs2.(A_end)
    I_max = maximum(I)
    if I_max <= 0.0
        return 0.0
    end
    half_max = 0.5 * I_max
    above = findall(x -> x >= half_max, I)
    if isempty(above)
        return 0.0
    end
    dt_range = t[last(above)] - t[first(above)]
    return dt_range * 1e15  # convert s -> fs
end

"""
    compressed_fwhm_fs(A_end, t) -> Float64

Fourier-transform-limited (FTL) pulse duration [fs].
Computed by phase-flattening the spectrum (setting all spectral phases to zero)
and measuring the FWHM of the resulting compressed-pulse intensity.
This is the minimum achievable pulse duration given the current spectral bandwidth.
"""
function compressed_fwhm_fs(A_end::Vector{ComplexF64}, t::Vector{Float64})
    Aω = fft(A_end)
    # Phase-flat spectrum: keep amplitudes, discard phases
    Aω_flat = complex.(abs.(Aω))
    A_compressed = ifft(Aω_flat)
    # ifft of a real positive spectrum produces a pulse centered at index 1 (t[1]).
    # ifftshift re-centers it to the middle of the time window.
    return pulse_fwhm_fs(ifftshift(A_compressed), t)
end

end # module
