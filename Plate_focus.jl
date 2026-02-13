module Plates

using ..Material
using ..Beam

export Plate, plate_at_z, coeffs_at_z

"""
1枚のプレート
- z_start_mm, z_end_mm: 配置範囲 [mm]
- material: MaterialModel
- β2_fs2_per_mm, β3_fs3_per_mm: 4.6 µm での GVD, TOD
"""
struct Plate
    z_start_mm::Float64
    z_end_mm::Float64
    material::Material.MaterialModel
    β2_fs2_per_mm::Float64
    β3_fs3_per_mm::Float64
end

# 単位変換
β2_fs2mm_to_SI(β2_fs2_per_mm) = β2_fs2_per_mm * 1e-30 / 1e-3
β3_fs3mm_to_SI(β3_fs3_per_mm) = β3_fs3_per_mm * 1e-45 / 1e-3

"z_mm が含まれるプレートを返す（なければ nothing）"
function plate_at_z(z_mm::Float64, plates::Vector{Plate})
    for p in plates
        if p.z_start_mm ≤ z_mm ≤ p.z_end_mm
            return p
        end
    end
    return nothing
end

"""
ある z_mm における β2, β3, n2 を返す
"""
function coeffs_at_z(z_mm::Float64,
                     plates::Vector{Plate},
                     beam::Beam.AbstractBeam,
                     λ0::Float64)
    p = plate_at_z(z_mm, plates)
    if p === nothing
        # 空気中（ゼロ近似）
        return (0.0, 0.0, 0.0)
    else
        β2_here = β2_fs2mm_to_SI(p.β2_fs2_per_mm)
        β3_here = β3_fs3mm_to_SI(p.β3_fs3_per_mm)

        n2_here = p.material.n2
        return (β2_here, β3_here, n2_here)
    end
end

end # module
