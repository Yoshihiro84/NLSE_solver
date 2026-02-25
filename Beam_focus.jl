
module Beam

export AbstractBeam, BeamProfile, KnifeEdgeGaussian, constant_beam,
       knifeedge_beam, A_eff, wx, wy, initial_q

"""
Abstract beam interface.

We mainly need:
- wx(beam, z_mm) [m]
- wy(beam, z_mm) [m]
- A_eff(beam, z_mm) [m^2]  (elliptic Gaussian: π*wx*wy)
"""
abstract type AbstractBeam end

"""
Generic beam profile defined by functions wx(z_mm), wy(z_mm) returning radii [m].
"""
struct BeamProfile <: AbstractBeam
    wx_func::Function
    wy_func::Function
end

wx(b::BeamProfile, z_mm::Float64) = b.wx_func(z_mm)
wy(b::BeamProfile, z_mm::Float64) = b.wy_func(z_mm)

"""
Knife-edge fitted Gaussian beam (possibly elliptical), parameterized by:
- w0x, w0y : 1/e^2 radius at waist [m]
- z0x_mm, z0y_mm : waist position [mm] in your solver's z-coordinate
- zRx_mm, zRy_mm : Rayleigh length [mm] (in the same coordinate/medium you fitted)
"""
struct KnifeEdgeGaussian <: AbstractBeam
    w0x::Float64
    w0y::Float64
    z0x_mm::Float64
    z0y_mm::Float64
    zRx_mm::Float64
    zRy_mm::Float64
end

@inline function gaussian_w(z_mm::Float64, w0::Float64, z0_mm::Float64, zR_mm::Float64)
    ξ = (z_mm - z0_mm) / zR_mm
    return w0 * sqrt(1 + ξ*ξ)
end

wx(b::KnifeEdgeGaussian, z_mm::Float64) = gaussian_w(z_mm, b.w0x, b.z0x_mm, b.zRx_mm)
wy(b::KnifeEdgeGaussian, z_mm::Float64) = gaussian_w(z_mm, b.w0y, b.z0y_mm, b.zRy_mm)

"""
Elliptic Gaussian effective area: A_eff(z) = π wx(z) wy(z)
"""
function A_eff(beam::AbstractBeam, z_mm::Float64)
    return π * wx(beam, z_mm) * wy(beam, z_mm)
end

"""
Convenience: constant beam radii.
Arguments are radii [m].
"""
function constant_beam(wx_m::Float64, wy_m::Float64=wx_m)
    return BeamProfile(_ -> wx_m, _ -> wy_m)
end

"""
Convenience: build a knife-edge Gaussian beam.

You can specify waist either as radius or diameter:
- If you measured *diameter* D0 at waist (common in knife-edge reports), set `waist_is_diameter=true`.
- Otherwise, provide waist radius directly.

All length inputs are in mm except w0 which you may pass in mm too via keywords.

Examples
--------
# If knife-edge gave waist *diameters* (mm):
beam = knifeedge_beam(;
    w0x_mm = 0.125, z0x_mm = 6.6, zRx_mm = 0.9,
    w0y_mm = 0.057, z0y_mm = 6.5, zRy_mm = 0.5,
    waist_is_diameter = true
)

# If knife-edge gave waist *radii* (mm):
beam = knifeedge_beam(; w0x_mm=0.0625, z0x_mm=..., zRx_mm=..., waist_is_diameter=false)
"""
function knifeedge_beam(; 
    w0x_mm::Float64,
    z0x_mm::Float64,
    zRx_mm::Float64,
    w0y_mm::Float64 = w0x_mm,
    z0y_mm::Float64 = z0x_mm,
    zRy_mm::Float64 = zRx_mm,
    waist_is_diameter::Bool = true
)
    w0x = (waist_is_diameter ? 0.5*w0x_mm : w0x_mm) * 1e-3
    w0y = (waist_is_diameter ? 0.5*w0y_mm : w0y_mm) * 1e-3
    return KnifeEdgeGaussian(w0x, w0y, z0x_mm, z0y_mm, zRx_mm, zRy_mm)
end

"""
Compute initial q-parameters from a KnifeEdgeGaussian beam at position z_mm.

    q(z) = (z - z0) + i*zR   (all in metres)
"""
function initial_q(beam::KnifeEdgeGaussian, z_mm::Float64)
    z_m = z_mm * 1e-3
    qx = ComplexF64(z_m - beam.z0x_mm * 1e-3, beam.zRx_mm * 1e-3)
    qy = ComplexF64(z_m - beam.z0y_mm * 1e-3, beam.zRy_mm * 1e-3)
    return qx, qy
end

end # module
