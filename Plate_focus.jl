module Plates

using ..Material
using ..Beam

export Plate, plate_at_z, coeffs_at_z, check_plate_overlaps

"""
1枚のプレート
- z_start_mm, z_end_mm: 配置範囲 [mm]
- material: MaterialModel
- β2_fs2_per_mm, β3_fs3_per_mm: 4.6 µm での GVD, TOD
- I_damage_Wcm2: 実験的損傷閾値 [W/cm^2] (Inf = 未設定)
"""
struct Plate
    z_start_mm::Float64
    z_end_mm::Float64
    material::Material.MaterialModel
    β2_fs2_per_mm::Float64
    β3_fs3_per_mm::Float64
    I_damage_Wcm2::Float64

    function Plate(z_start_mm, z_end_mm, material, β2, β3, I_damage_Wcm2)
        if isnan(I_damage_Wcm2) || I_damage_Wcm2 < 0.0
            error("Plate: I_damage_Wcm2 must be ≥ 0 or Inf, got $I_damage_Wcm2")
        end
        if I_damage_Wcm2 == 0.0
            @warn "Plate: I_damage_Wcm2 = 0 means any intensity is a violation"
        end
        if z_start_mm > z_end_mm
            error("Plate: z_start_mm ($z_start_mm) > z_end_mm ($z_end_mm)")
        end
        if z_start_mm == z_end_mm
            @warn "Plate: zero-thickness plate (z_start_mm == z_end_mm == $z_start_mm)"
        end
        new(z_start_mm, z_end_mm, material, β2, β3, I_damage_Wcm2)
    end
end

"Convenience constructor: I_damage_Wcm2 はオプション (デフォルト Inf = 制限なし)"
Plate(z_start_mm, z_end_mm, material, β2, β3) =
    Plate(z_start_mm, z_end_mm, material, β2, β3, Inf)

# 単位変換
β2_fs2mm_to_SI(β2_fs2_per_mm) = β2_fs2_per_mm * 1e-30 / 1e-3
β3_fs3mm_to_SI(β3_fs3_per_mm) = β3_fs3_per_mm * 1e-45 / 1e-3

"z_mm が含まれるプレートを返す（なければ nothing）。複数マッチ時は先頭優先。"
function plate_at_z(z_mm::Float64, plates::Vector{Plate})
    for p in plates
        if p.z_start_mm ≤ z_mm ≤ p.z_end_mm
            return p
        end
    end
    return nothing
end

"""
Check for overlapping plate ranges and warn.
Call once at setup time.
"""
function check_plate_overlaps(plates::Vector{Plate})
    for i in 1:length(plates)
        for j in (i+1):length(plates)
            a, b = plates[i], plates[j]
            if a.z_start_mm ≤ b.z_end_mm && b.z_start_mm ≤ a.z_end_mm
                @warn "Plates $i and $j overlap or share boundary: [$(a.z_start_mm), $(a.z_end_mm)] ∩ [$(b.z_start_mm), $(b.z_end_mm)]. plate_at_z returns first-listed plate at shared points."
            end
        end
    end
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
