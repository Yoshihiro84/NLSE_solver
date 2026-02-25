# `Beam_focus.jl` の1行ずつ解説（圧倒的に丁寧版）
このファイルは **ビーム（空間モード）を表す型と、`wx/wy/A_eff` という共通API**を定義します。
NLSE側は時間方向の1D伝播を解きますが、非線形係数 `γ(z)` や損傷判定に **有効面積 `A_eff(z)`** が必要なので、ここが “空間情報の供給口” になります。

## 対象ファイル（そのまま）
```julia

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
```

---
## 1行ずつ解説
### L1 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L2 `module Beam`
- ここから `Beam` モジュール（名前空間）を定義開始します。ビーム関連の型・関数を他ファイルから `Beam.xxx` としてまとめて参照できるようにするための枠です。

### L3 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L4 `export AbstractBeam, BeamProfile, KnifeEdgeGaussian, constant_beam,`
- このモジュールを `using .Beam` したとき、ここに列挙した名前を `Beam.` なしで呼べるようにします。外部に公開する“APIの表面”をここで決めています。

### L5 `       knifeedge_beam, A_eff, wx, wy, initial_q`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L6 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L7 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L8 `Abstract beam interface.`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L9 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L10 `We mainly need:`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L11 `- wx(beam, z_mm) [m]`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L12 `- wy(beam, z_mm) [m]`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L13 `- A_eff(beam, z_mm) [m^2]  (elliptic Gaussian: π*wx*wy)`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L14 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L15 `abstract type AbstractBeam end`
- ビームの“共通インターフェース”を表す抽象型です。具体実装（`BeamProfile` や `KnifeEdgeGaussian`）はこれを継承して、`wx/wy/A_eff` が呼べることを保証する設計になります。

### L16 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L17 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L18 `Generic beam profile defined by functions wx(z_mm), wy(z_mm) returning radii [m].`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L19 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L20 `struct BeamProfile <: AbstractBeam`
- 任意の `wx(z_mm)` / `wy(z_mm)` を関数として渡せる汎用ビーム型を定義します。ナイフエッジfit以外（測定値補間、独自モデル等）も同じ枠で扱えるようにするための器です。

### L21 `    wx_func::Function`
- x方向のビーム半径（1/e^2半径）を返す関数スロットです。引数は `z_mm`、返り値は **m単位**の半径、という規約をこの型で固定します。

### L22 `    wy_func::Function`
- y方向のビーム半径を返す関数スロットです。楕円ビーム（x≠y）を自然に扱えるように分けています。

### L23 `end`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L24 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L25 `wx(b::BeamProfile, z_mm::Float64) = b.wx_func(z_mm)`
- `BeamProfile` に対する `wx` を定義（多重ディスパッチ）。`b.wx_func(z_mm)` をそのまま返す薄いラッパで、以後のコードは `wx(beam,z)` と統一した書き方ができます。

### L26 `wy(b::BeamProfile, z_mm::Float64) = b.wy_func(z_mm)`
- `BeamProfile` に対する `wy` を定義。xと同様に関数を呼ぶだけのラッパで、後段（A_eff計算など）を共通化します。

### L27 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L28 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L29 `Knife-edge fitted Gaussian beam (possibly elliptical), parameterized by:`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L30 `- w0x, w0y : 1/e^2 radius at waist [m]`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L31 `- z0x_mm, z0y_mm : waist position [mm] in your solver's z-coordinate`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L32 `- zRx_mm, zRy_mm : Rayleigh length [mm] (in the same coordinate/medium you fitted)`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L33 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L34 `struct KnifeEdgeGaussian <: AbstractBeam`
- ナイフエッジ測定をガウシアンビームの理論式 `w(z)=w0*sqrt(1+((z-z0)/zR)^2)` でフィットした結果を保持する型です。x/y別パラメータを持てるので楕円にも対応します。

### L35 `    w0x::Float64`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L36 `    w0y::Float64`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L37 `    z0x_mm::Float64`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L38 `    z0y_mm::Float64`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L39 `    zRx_mm::Float64`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L40 `    zRy_mm::Float64`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L41 `end`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L42 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L43 `@inline function gaussian_w(z_mm::Float64, w0::Float64, z0_mm::Float64, zR_mm::Float64)`
- `w(z)` 計算の中核関数。`@inline` は“インライン展開しても良い”という最適化ヒントで、頻繁に呼ぶ小関数なのでオーバーヘッドを減らす意図です。入力はmmとmが混じるので、ここでは **zはmm、w0はm** という約束になっています。

### L44 `    ξ = (z_mm - z0_mm) / zR_mm`
- 無次元化した距離 `ξ` を作ります。`z` と `z0` と `zR` が同じ単位（mm）なので、比を取って無次元になります。

### L45 `    return w0 * sqrt(1 + ξ*ξ)`
- ガウシアンビームの標準式で半径を返します。ここで返る半径は **m単位**（`w0` がmだから）になります。

### L46 `end`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L47 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L48 `wx(b::KnifeEdgeGaussian, z_mm::Float64) = gaussian_w(z_mm, b.w0x, b.z0x_mm, b.zRx_mm)`
- `KnifeEdgeGaussian` の x半径を `gaussian_w` で計算する実装。パラメータは構造体に保持している値を使います。

### L49 `wy(b::KnifeEdgeGaussian, z_mm::Float64) = gaussian_w(z_mm, b.w0y, b.z0y_mm, b.zRy_mm)`
- y方向も同様。x/yで別々の `w0, z0, zR` を使うので、非対称集光（楕円）を表現できます。

### L50 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L51 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L52 `Elliptic Gaussian effective area: A_eff(z) = π wx(z) wy(z)`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L53 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L54 `function A_eff(beam::AbstractBeam, z_mm::Float64)`
- 有効断面積 `A_eff` を、抽象型 `AbstractBeam` に対して定義します。具体型が何でも `wx/wy` が定義されていれば使える、という“インターフェース設計”の肝です。

### L55 `    return π * wx(beam, z_mm) * wy(beam, z_mm)`
- 楕円ガウシアンの有効面積を `π wx wy` で定義しています（1/e^2半径ならこの形）。この `A_eff` が NLSE の `γ(z) ∝ 1/A_eff(z)` に直結します。

### L56 `end`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L57 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L58 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L59 `Convenience: constant beam radii.`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L60 `Arguments are radii [m].`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L61 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L62 `function constant_beam(wx_m::Float64, wy_m::Float64=wx_m)`
- 半径一定のビームを作る便利関数。引数は **m単位の半径**。`wy_m=wx_m` のデフォルトで円形ビームを簡単に作れます。

### L63 `    return BeamProfile(_ -> wx_m, _ -> wy_m)`
- `BeamProfile` を、zに依存しない定数関数で埋めて返します。`_ -> wx_m` の `_` は“使わない引数”の慣用表現で、`z_mm` を無視するという意味です。

### L64 `end`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L65 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L66 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L67 `Convenience: build a knife-edge Gaussian beam.`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L68 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L69 `You can specify waist either as radius or diameter:`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L70 `- If you measured *diameter* D0 at waist (common in knife-edge reports), set \`waist_is_diameter=true\`.`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L71 `- Otherwise, provide waist radius directly.`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L72 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L73 `All length inputs are in mm except w0 which you may pass in mm too via keywords.`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L74 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L75 `Examples`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L76 `--------`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L77 `# If knife-edge gave waist *diameters* (mm):`
- コメント行です。実行には影響しませんが、設計意図・単位・使い方の注意を残すために重要です。

### L78 `beam = knifeedge_beam(;`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L79 `    w0x_mm = 0.125, z0x_mm = 6.6, zRx_mm = 0.9,`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L80 `    w0y_mm = 0.057, z0y_mm = 6.5, zRy_mm = 0.5,`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L81 `    waist_is_diameter = true`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L82 `)`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L83 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L84 `# If knife-edge gave waist *radii* (mm):`
- コメント行です。実行には影響しませんが、設計意図・単位・使い方の注意を残すために重要です。

### L85 `beam = knifeedge_beam(; w0x_mm=0.0625, z0x_mm=..., zRx_mm=..., waist_is_diameter=false)`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L86 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L87 `function knifeedge_beam(; `
- ナイフエッジフィット結果を与えて `KnifeEdgeGaussian` を生成するためのキーワード引数関数です。引数の単位は **mm** で受け取り、内部で **m** に変換します。

### L88 `    w0x_mm::Float64,`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L89 `    z0x_mm::Float64,`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L90 `    zRx_mm::Float64,`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L91 `    w0y_mm::Float64 = w0x_mm,`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L92 `    z0y_mm::Float64 = z0x_mm,`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L93 `    zRy_mm::Float64 = zRx_mm,`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L94 `    waist_is_diameter::Bool = true`
- ウエスト `w0` を“直径で入力したか”のフラグです。knife-edge結果が直径で報告されることが多いので、ここで半径に変換する事故防止をしています。

### L95 `)`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L96 `    w0x = (waist_is_diameter ? 0.5*w0x_mm : w0x_mm) * 1e-3`
- w0xを mm入力から m半径に変換します。`waist_is_diameter=true` なら 0.5 を掛けて直径→半径にし、さらに `1e-3` で mm→m にします。ここがズレると `A_eff` が4倍ズレて γも4倍ズレます。

### L97 `    w0y = (waist_is_diameter ? 0.5*w0y_mm : w0y_mm) * 1e-3`
- y方向も同様に直径→半径（必要なら）→mm→m 変換します。

### L98 `    return KnifeEdgeGaussian(w0x, w0y, z0x_mm, z0y_mm, zRx_mm, zRy_mm)`
- 変換済みパラメータで `KnifeEdgeGaussian` を生成して返します。z関連（z0, zR）は mm のまま保持して、`gaussian_w` で mm 系で扱う設計です（無次元化により整合）。

### L99 `end`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L100 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L101 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L102 `Compute initial q-parameters from a KnifeEdgeGaussian beam at position z_mm.`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L103 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L104 `    q(z) = (z - z0) + i*zR   (all in metres)`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L105 `"""`
- ドキュメント文字列（docstring）の区切り行です。ここから次の `"""` までの内容は、実行動作ではなく説明としてJuliaのヘルプに表示されます。

### L106 `function initial_q(beam::KnifeEdgeGaussian, z_mm::Float64)`
- Kerr self-focusing モードで使う初期 q パラメータを作ります。`KnifeEdgeGaussian` の `z0` と `zR` を用いて、指定位置 zでの `q=(z-z0)+i zR` を **m単位**で返します。

### L107 `    z_m = z_mm * 1e-3`
- 入力の z（mm）を m に変換します。q の実部・虚部はmで扱うので、ここで単位を揃えます。

### L108 `    qx = ComplexF64(z_m - beam.z0x_mm * 1e-3, beam.zRx_mm * 1e-3)`
- x方向の q を複素数で作ります。実部は `(z - z0)`、虚部は `zR`。`ComplexF64(re, im)` は `re + i im` の意味。ここで `z0x_mm` と `zRx_mm` も mm→m に変換しています。

### L109 `    qy = ComplexF64(z_m - beam.z0y_mm * 1e-3, beam.zRy_mm * 1e-3)`
- y方向も同様。楕円ビームの場合は x/y で異なる q を持てるので、自己収束を異方的に扱う土台になります。

### L110 `    return qx, qy`
- xとyの初期qをタプルで返します。呼び出し側は `qx,qy = initial_q(...)` の形で受け取ります。

### L111 `end`
- Juliaの通常のコード行です。上位の意図（ビームAPIを統一する）に沿って、型・関数・メソッドを定義しています。

### L112 （空行）
- 見やすさのための空行です。実行の挙動は変わりません。
### L113 `end # module`
- `Beam` モジュールの終わり。ここまでの定義が `Beam` 名前空間に閉じ込められます。

---
## 設計の要点（このファイルを読むときの地図）
1. **抽象型 `AbstractBeam`**：`wx/wy/A_eff` が呼べる“ビーム”の共通口。
2. **`BeamProfile`**：`wx(z), wy(z)` を関数として差し替え可能な汎用型（補間・実測・任意モデル向け）。
3. **`KnifeEdgeGaussian`**：ナイフエッジフィット（w0, z0, zR）に基づくガウシアンビーム。
4. **`A_eff`**：NLSEの `γ(z)` や損傷判定へ直結する “面積” を統一的に提供。
5. **`initial_q`**：self-focusingモードで使う初期条件（qパラメータ）を生成。
