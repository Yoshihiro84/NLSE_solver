module Material

export MaterialModel, CaF2_48um, Si_48um, NaCl_48um

"""
材料モデル
- name: 名前
- n_func(λ [m]) -> n(λ)
- n2: 非線形屈折率 [m^2/W]
"""
struct MaterialModel
    name::String
    n_func::Function
    n2::Float64
end

# ひとまず「λ=4.6 µm では n ≈ 1.43」として定数返す例
# 実際は Sellmeier 展開をここに書く or Python の ZnSe クラスと対応させる
n_NaCl_simple(λ::Float64) = 1.52
n_Si_simple(λ::Float64) = 3.43
n_CaF2_simple(λ::Float64) = 1.43

# 4.6 µm 付近の材料モデル
const CaF2_48um = MaterialModel("CaF2_4.8um", n_CaF2_simple, 0.0)
const Si_48um = MaterialModel("Si_4.8um", n_Si_simple, 3e-18)
const NaCl_48um = MaterialModel("NaCl_4.8um", n_NaCl_simple, 5e-20)

end # module