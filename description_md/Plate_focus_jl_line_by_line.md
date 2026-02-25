# `Plate_focus.jl` の1行ずつ解説（圧倒的に丁寧版）

このファイルは **「プレート（媒質区間）のデータ構造」と「z位置→係数（β2/β3/n2）のルーティング」**を担当します。
NLSE solver は毎ステップでその場所の係数が欲しいので、ここが **“係数辞書の窓口”**になります。

## 対象ファイル（そのまま）

```julia
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
```

---

## 1行ずつ解説

### L1 `module Plates`
- ここから `Plates` モジュール（名前空間）を定義開始します。プレート（媒質区間）の表現と、z位置に応じた係数（β2/β3/n2）の取り出しをこのモジュールに集約します。

### L2 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L3 `using ..Material`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L4 `using ..Beam`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L5 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L6 `export Plate, plate_at_z, coeffs_at_z, check_plate_overlaps`
- 外部に公開するAPI（型や関数）を列挙します。`using .Plates` したときに `Plates.` を付けずに呼べるようになります。

### L7 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L8 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L9 `1枚のプレート`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L10 `- z_start_mm, z_end_mm: 配置範囲 [mm]`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L11 `- material: MaterialModel`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L12 `- β2_fs2_per_mm, β3_fs3_per_mm: 4.6 µm での GVD, TOD`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L13 `- I_damage_Wcm2: 実験的損傷閾値 [W/cm^2] (Inf = 未設定)`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L14 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L15 `struct Plate`
- 1枚（1区間）のプレートを表す `Plate` 構造体の定義開始です。`z_start_mm`〜`z_end_mm` の範囲にいるときだけ、このプレートの係数を使う、という設計のコアになります。

### L16 `    z_start_mm::Float64`
- プレート開始位置（mm単位）。外部インターフェースとして z を mm で統一する設計なので、ここも mm で保持します。

### L17 `    z_end_mm::Float64`
- プレート終了位置（mm単位）。`z_start_mm < z_end_mm` が期待され、逆だとバリデーションで止めます。

### L18 `    material::Material.MaterialModel`
- プレートの材料（MaterialModel）を保持します。ここから `n2`（非線形屈折率）を取り出して γ(z) を作るため、プレートは“材料参照”を持ちます。

### L19 `    β2_fs2_per_mm::Float64`
- GVD係数 β2 を **fs²/mm** で保持します。solver側では s²/m が欲しいので、係数取り出し時に単位変換します。

### L20 `    β3_fs3_per_mm::Float64`
- TOD係数 β3 を **fs³/mm** で保持します。β2と同様、取り出し時に s³/m へ変換します。

### L21 `    I_damage_Wcm2::Float64`
- 損傷閾値（W/cm²）を保持します。`metrics.jl` 側で `I_peak` と比較して、安全係数込みで違反判定に使う想定です。

### L22 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L23 `    function Plate(z_start_mm, z_end_mm, material, β2, β3, I_damage_Wcm2)`
- ユーザーがプレートを作るときの“コンストラクタ（生成関数）”です。入力の整合性チェック（負の損傷閾値、開始＞終了など）をここでまとめて行い、壊れた設定を早期に止めます。

### L24 `        if isnan(I_damage_Wcm2) || I_damage_Wcm2 < 0.0`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L25 `            error("Plate: I_damage_Wcm2 must be ≥ 0 or Inf, got $I_damage_Wcm2")`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L26 `        end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L27 `        if I_damage_Wcm2 == 0.0`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L28 `            @warn "Plate: I_damage_Wcm2 = 0 means any intensity is a violation"`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L29 `        end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L30 `        if z_start_mm > z_end_mm`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L31 `            error("Plate: z_start_mm ($z_start_mm) > z_end_mm ($z_end_mm)")`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L32 `        end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L33 `        if z_start_mm == z_end_mm`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L34 `            @warn "Plate: zero-thickness plate (z_start_mm == z_end_mm == $z_start_mm)"`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L35 `        end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L36 `        new(z_start_mm, z_end_mm, material, β2, β3, I_damage_Wcm2)`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L37 `    end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L38 `end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L39 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L40 `"Convenience constructor: I_damage_Wcm2 はオプション (デフォルト Inf = 制限なし)"`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L41 `Plate(z_start_mm, z_end_mm, material, β2, β3) =`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L42 `    Plate(z_start_mm, z_end_mm, material, β2, β3, Inf)`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L43 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L44 `# 単位変換`
- コメント行です。実行には影響しませんが、設計意図・単位・使い方の注意を残すために重要です。

### L45 `β2_fs2mm_to_SI(β2_fs2_per_mm) = β2_fs2_per_mm * 1e-30 / 1e-3`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L46 `β3_fs3mm_to_SI(β3_fs3_per_mm) = β3_fs3_per_mm * 1e-45 / 1e-3`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L47 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L48 `"z_mm が含まれるプレートを返す（なければ nothing）。複数マッチ時は先頭優先。"`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L49 `function plate_at_z(z_mm::Float64, plates::Vector{Plate})`
- 与えられた位置 `z_mm` に「どのプレートが存在するか」を返す関数です。solverが毎ステップで係数を引くためのルーティング機能になります。

### L50 `    for p in plates`
- プレート配列を先頭から走査し、`z_start_mm ≤ z ≤ z_end_mm` を満たす最初のプレートを返します（重なりがあると“先に出た方が勝つ”仕様になります）。

### L51 `        if p.z_start_mm ≤ z_mm ≤ p.z_end_mm`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L52 `            return p`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L53 `        end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L54 `    end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L55 `    return nothing`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L56 `end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L57 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L58 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L59 `Check for overlapping plate ranges and warn.`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L60 `Call once at setup time.`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L61 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L62 `function check_plate_overlaps(plates::Vector{Plate})`
- プレート同士が重なっていないかをチェックする補助関数です。重なりがあると `plate_at_z` がどちらを返すか曖昧になり、物理・数値ともに危険なので、警告（または将来エラー）で気づけるようにします。

### L63 `    for i in 1:length(plates)`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L64 `        for j in (i+1):length(plates)`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L65 `            a, b = plates[i], plates[j]`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L66 `            if a.z_start_mm ≤ b.z_end_mm && b.z_start_mm ≤ a.z_end_mm`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L67 `                @warn "Plates $i and $j overlap or share boundary: [$(a.z_start_mm), $(a.z_end_mm)] ∩ [$(b.z_start_mm), $(b.z_end_mm)]. plate_at_z returns first-listed plate at shared points."`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L68 `            end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L69 `        end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L70 `    end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L71 `end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L72 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L73 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L74 `ある z_mm における β2, β3, n2 を返す`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L75 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L76 `function coeffs_at_z(z_mm::Float64,`
- z位置における **β2, β3, n2** をまとめて返す“窓口関数”です。NLSE solverはここだけを呼べば、その場所の材料・分散・非線形が分かるようになります。

### L77 `                     plates::Vector{Plate},`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L78 `                     beam::Beam.AbstractBeam,`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L79 `                     λ0::Float64)`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L80 `    p = plate_at_z(z_mm, plates)`
- `z_mm` に存在するプレートを探します。プレートが無ければ、係数はゼロとして“真空（線形・非線形なし）”を表現します。

### L81 `    if p === nothing`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L82 `        # 空気中（ゼロ近似）`
- コメント行です。実行には影響しませんが、設計意図・単位・使い方の注意を残すために重要です。

### L83 `        return (0.0, 0.0, 0.0)`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L84 `    else`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L85 `        β2_here = β2_fs2mm_to_SI(p.β2_fs2_per_mm)`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L86 `        β3_here = β3_fs3mm_to_SI(p.β3_fs3_per_mm)`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L87 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L88 `        n2_here = p.material.n2`
- 材料モデルから非線形屈折率 n2 を取り出します。ここが `material.jl` の値と直結していて、γ(z) を通じてスペクトル広がりやB積分に影響します。

### L89 `        return (β2_here, β3_here, n2_here)`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L90 `    end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L91 `end`
- Juliaの通常のコード行です。プレートの表現・検索・単位変換・係数返却のいずれかを構成しています。

### L92 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。

### L93 `end # module`
- `Plates` モジュール定義の終わりです。ここで定義した型・関数が `Plates` 名前空間に閉じます。

---
## 設計上の“肝”（このモジュールが守っている約束）
- zは外部では **mm** で扱い、solverが必要とする係数は **SI（s²/m, s³/m）**に変換して返す。
- プレートが無い領域は係数ゼロ（真空扱い）で自然に連結できる。
- 重なりは危険なので、別途チェック関数で早期に気づけるようにする。
