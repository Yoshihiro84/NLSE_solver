# `metrics.jl` 1行ずつ解説

- 対象: `metrics.jl`（223行）
- MD5: `8233a7284432697b9dcc48384ff8cbf5`
- 参照時刻（ローカルmtime）: `2026-02-24T13:39:05`

## このファイルの位置づけ（最初に全体像）

- ここは **NLSE 伝搬結果（`Itz` や `A_end`）から、設計・安全・性能の指標（metrics）を計算する層**。
- 具体的には：
  - **どの z がどのプレートか**（`plate_index_at_z`）
  - **B積分**（非線形位相の代表値）と **ピーク強度** のプレート別集計と制限判定（`analyze_plate_limits`）
  - **総B積分だけ**の軽量計算（`compute_B`）
  - **スペクトル帯域**（-XdB幅）、**パルス幅FWHM**、**FTL（位相ゼロ）幅**（`spectral_bandwidth_dB`, `pulse_fwhm_fs`, `compressed_fwhm_fs`）

### 重要な前提（単位と定義の“地雷”）

- solver 側では `Itz[:, iz] .= abs2.(A)` として出力されています。（`NLSE_solver_focus.jl` の該当行: L216）
- 同じく solver 側に `# gamma from current Aeff (power-envelope form)` という注記があり、`γ = n₂ ω₀ / (c A_eff)` を使っています。（該当行: L154）
- Beam 側の有効面積は `A_eff(z) = π wx(z) wy(z)` です。（`Beam_focus.jl` の該当行: L54）

> つまり、この `metrics.jl` の強度式 `I_peak = 2P/A_eff` は **ガウシアン定義に基づく中心強度** を仮定しています。

---

## L001

**スコープ**：(トップレベル)

**コード**：
```julia
module Metrics
```

**解説**：
- **何をしているか**：モジュール `Metrics` を定義開始。
- **なぜ**：関数名の衝突を避け、関連関数をひとまとまりにし、`export` で公開APIを制御するため。
- **注意**：`end` までがこのモジュールのスコープ。外部からは `Metrics.xxx` として参照される。

---

## L002

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L003

**スコープ**：module Metrics

**コード**：
```julia
using FFTW
```

**解説**：
- **何をしているか**：他モジュールを読み込み、識別子を使えるようにする。
- **なぜ**：ここでは FFT・プレート係数・ビーム幾何・NLSE設定を利用するので依存が必要。
- **注意**：`using ..X` は“親モジュールからの相対参照”。プロジェクト構成が変わると壊れるので、モジュール階層が重要。

---

## L004

**スコープ**：module Metrics

**コード**：
```julia
using ..Plates
```

**解説**：
- **何をしているか**：他モジュールを読み込み、識別子を使えるようにする。
- **なぜ**：ここでは FFT・プレート係数・ビーム幾何・NLSE設定を利用するので依存が必要。
- **注意**：`using ..X` は“親モジュールからの相対参照”。プロジェクト構成が変わると壊れるので、モジュール階層が重要。

---

## L005

**スコープ**：module Metrics

**コード**：
```julia
using ..Beam
```

**解説**：
- **何をしているか**：他モジュールを読み込み、識別子を使えるようにする。
- **なぜ**：ここでは FFT・プレート係数・ビーム幾何・NLSE設定を利用するので依存が必要。
- **注意**：`using ..X` は“親モジュールからの相対参照”。プロジェクト構成が変わると壊れるので、モジュール階層が重要。

---

## L006

**スコープ**：module Metrics

**コード**：
```julia
using ..NLSESolver
```

**解説**：
- **何をしているか**：他モジュールを読み込み、識別子を使えるようにする。
- **なぜ**：ここでは FFT・プレート係数・ビーム幾何・NLSE設定を利用するので依存が必要。
- **注意**：`using ..X` は“親モジュールからの相対参照”。プロジェクト構成が変わると壊れるので、モジュール階層が重要。

---

## L007

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L008

**スコープ**：module Metrics

**コード**：
```julia
export plate_index_at_z, classify_B, classify_I,
```

**解説**：
- **何をしているか**：このモジュールの“外向けAPI”を宣言。
- **なぜ**：利用側が `using Metrics` したときに、`Metrics.` を付けずに呼べる関数を限定したい。
- **注意**：`export` は“公開”であって“アクセス制限”ではない（`Metrics._get_Aeff_at` のように参照自体は可能）。

---

## L009

**スコープ**：module Metrics

**コード**：
```julia
       analyze_plate_limits, compute_B,
```

**解説**：
- **何をしているか**：実行行（具体処理）。
- **読み方のコツ**：この行が参照する変数が“どこで定義され、どんな単位/意味を持つか”を直前で確認する。
- **注意**：行単体では意味が薄い場合があるので、同じブロック（if/for/function）の範囲で因果関係を見る。

---

## L010

**スコープ**：module Metrics

**コード**：
```julia
       spectral_bandwidth_dB, pulse_fwhm_fs, compressed_fwhm_fs
```

**解説**：
- **何をしているか**：実行行（具体処理）。
- **読み方のコツ**：この行が参照する変数が“どこで定義され、どんな単位/意味を持つか”を直前で確認する。
- **注意**：行単体では意味が薄い場合があるので、同じブロック（if/for/function）の範囲で因果関係を見る。

---

## L011

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L012

**スコープ**：module Metrics

**コード**：
```julia
function plate_index_at_z(z_mm::Float64, plates::Vector{Plates.Plate})
```

**解説**：
- **何をしているか**：関数 `plate_index_at_z` の定義開始。
- **なぜ**：`metrics.jl` は“計測/評価ロジック”を solver から分離して、最適化や安全判定で再利用しやすくするため。
- **注意**：この行では引数型（例：`::Float64`）を付けている。型を固定することで（1）意図しない入力を弾ける、（2）JIT最適化が効きやすい。

---

## L013

**スコープ**：module Metrics > function plate_index_at_z

**コード**：
```julia
    for (i, p) in enumerate(plates)
```

**解説**：
- **何をしているか**：`for` ループ開始。
- **なぜ**：z ステップ（`iz`）やプレート配列（`enumerate`）を走査して集計するため。
- **注意**：このプロジェクトでは `cfg.z_mm` が mm、`cfg.dz` が m なので、ループ変数が扱う単位を常に意識する必要がある。

---

## L014

**スコープ**：module Metrics > function plate_index_at_z > for

**コード**：
```julia
        if p.z_start_mm <= z_mm <= p.z_end_mm
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L015

**スコープ**：module Metrics > function plate_index_at_z > for > if

**コード**：
```julia
            return i
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L016

**スコープ**：module Metrics > function plate_index_at_z > for > if

**コード**：
```julia
        end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L017

**スコープ**：module Metrics > function plate_index_at_z > for

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`for` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L018

**スコープ**：module Metrics > function plate_index_at_z

**コード**：
```julia
    return nothing
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L019

**スコープ**：module Metrics > function plate_index_at_z

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`function plate_index_at_z` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L020

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L021

**スコープ**：module Metrics

**コード**：
```julia
function classify_B(Bi::Float64, warn_rad::Float64, limit_rad::Float64)
```

**解説**：
- **何をしているか**：関数 `classify_B` の定義開始。
- **なぜ**：`metrics.jl` は“計測/評価ロジック”を solver から分離して、最適化や安全判定で再利用しやすくするため。
- **注意**：この行では引数型（例：`::Float64`）を付けている。型を固定することで（1）意図しない入力を弾ける、（2）JIT最適化が効きやすい。

---

## L022

**スコープ**：module Metrics > function classify_B

**コード**：
```julia
    if Bi > limit_rad
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L023

**スコープ**：module Metrics > function classify_B > if

**コード**：
```julia
        return "VIOLATION"
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L024

**スコープ**：module Metrics > function classify_B > if

**コード**：
```julia
    elseif Bi > warn_rad
```

**解説**：
- **何をしているか**：`elseif` 分岐。
- **なぜ**：上の条件が偽のときに次の条件へ。
- **注意**：順番が意味を持つ（例：`VIOLATION` を先に判定しないと分類が崩れる）。

---

## L025

**スコープ**：module Metrics > function classify_B > if

**コード**：
```julia
        return "CAUTION"
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L026

**スコープ**：module Metrics > function classify_B > if

**コード**：
```julia
    else
```

**解説**：
- **何をしているか**：`else` 分岐。
- **なぜ**：上の条件がすべて偽のケースをまとめて処理できる。
- **注意**：ここに来るということは“これまでの条件に当てはまらない”という意味。条件設計の漏れに気づく手がかりになる。

---

## L027

**スコープ**：module Metrics > function classify_B > if

**コード**：
```julia
        return "OK"
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L028

**スコープ**：module Metrics > function classify_B > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L029

**スコープ**：module Metrics > function classify_B

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`function classify_B` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L030

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L031

**スコープ**：module Metrics

**コード**：
```julia
function classify_I(Ipk_Wcm2::Float64, Iallow_Wcm2::Float64)
```

**解説**：
- **何をしているか**：関数 `classify_I` の定義開始。
- **なぜ**：`metrics.jl` は“計測/評価ロジック”を solver から分離して、最適化や安全判定で再利用しやすくするため。
- **注意**：この行では引数型（例：`::Float64`）を付けている。型を固定することで（1）意図しない入力を弾ける、（2）JIT最適化が効きやすい。

---

## L032

**スコープ**：module Metrics > function classify_I

**コード**：
```julia
    return (Ipk_Wcm2 > Iallow_Wcm2) ? "VIOLATION" : "OK"
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L033

**スコープ**：module Metrics > function classify_I

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`function classify_I` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L034

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L035

**スコープ**：module Metrics

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：Julia の docstring（ドキュメント文字列）の開始。
- **なぜ**：直後の関数に「ヘルプとして表示される説明」を付けるため。REPL で `?関数名` とするとここが出る。
- **注意**：`"""` は“文字列リテラル”なので、コード的には実行時に評価されるが、通常はドキュメントとして扱われる。

---

## L036

**スコープ**：module Metrics

**コード**：
```julia
Aeff at z-grid index `idx` (1-based).
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`Aeff at z-grid index `idx` (1-based).`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L037

**スコープ**：module Metrics

**コード**：
```julia
When Aeff_hist is provided (self-focusing), read from it;
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`When Aeff_hist is provided (self-focusing), read from it;`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L038

**スコープ**：module Metrics

**コード**：
```julia
otherwise fall back to static beam profile at z_mm[idx].
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`otherwise fall back to static beam profile at z_mm[idx].`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L039

**スコープ**：module Metrics

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：docstring の終了。
- **なぜ**：この範囲のテキストが “ひとまとまりの説明” として扱われる。
- **注意**：閉じ忘れると以降のコードが全部文字列扱いになり、構文エラーになる。

---

## L040

**スコープ**：module Metrics

**コード**：
```julia
function _get_Aeff_at(idx::Int, cfg::NLSESolver.NLSEConfig,
```

**解説**：
- **何をしているか**：関数 `_get_Aeff_at` の定義開始。
- **なぜ**：`metrics.jl` は“計測/評価ロジック”を solver から分離して、最適化や安全判定で再利用しやすくするため。
- **注意**：この行では引数型（例：`::Float64`）を付けている。型を固定することで（1）意図しない入力を弾ける、（2）JIT最適化が効きやすい。

---

## L041

**スコープ**：module Metrics > function _get_Aeff_at

**コード**：
```julia
                      Aeff_hist::Union{Vector{Float64}, Nothing})
```

**解説**：
- **何をしているか**：`Aeff_hist` を「配列」か「nothing（未提供）」のどちらでも受け取れるように型指定。
- **なぜ**：自己収束を有効にした場合は `propagate!` が `beam_hist.Aeff` を返すので、それをここに渡して評価を一致させたい。
- **注意**：`Union` は便利だが、分岐が増える。内部ヘルパ `_get_Aeff_*` に切り出して見通しを良くしているのがポイント。

---

## L042

**スコープ**：module Metrics > function _get_Aeff_at

**コード**：
```julia
    if Aeff_hist !== nothing
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L043

**スコープ**：module Metrics > function _get_Aeff_at > if

**コード**：
```julia
        @assert 1 ≤ idx ≤ length(Aeff_hist) "Aeff_hist index out of bounds: idx=$idx, len=$(length(Aeff_hist))"
```

**解説**：
- **何をしているか**：実行時アサーション。
- **なぜ**：`Aeff_hist[idx]` のような配列アクセスは、範囲外だと即バグになるので、原因を明確にして止める。
- **注意**：最適化ループで大量に呼ぶとアサートのコストが気になる場合もあるが、まずは“壊れ方を見える化”が優先。

---

## L044

**スコープ**：module Metrics > function _get_Aeff_at > if

**コード**：
```julia
        return Aeff_hist[idx]
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L045

**スコープ**：module Metrics > function _get_Aeff_at > if

**コード**：
```julia
    else
```

**解説**：
- **何をしているか**：`else` 分岐。
- **なぜ**：上の条件がすべて偽のケースをまとめて処理できる。
- **注意**：ここに来るということは“これまでの条件に当てはまらない”という意味。条件設計の漏れに気づく手がかりになる。

---

## L046

**スコープ**：module Metrics > function _get_Aeff_at > if

**コード**：
```julia
        return Beam.A_eff(cfg.beam, cfg.z_mm[idx])
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L047

**スコープ**：module Metrics > function _get_Aeff_at > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L048

**スコープ**：module Metrics > function _get_Aeff_at

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`function _get_Aeff_at` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L049

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L050

**スコープ**：module Metrics

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：Julia の docstring（ドキュメント文字列）の開始。
- **なぜ**：直後の関数に「ヘルプとして表示される説明」を付けるため。REPL で `?関数名` とするとここが出る。
- **注意**：`"""` は“文字列リテラル”なので、コード的には実行時に評価されるが、通常はドキュメントとして扱われる。

---

## L051

**スコープ**：module Metrics

**コード**：
```julia
Aeff at midpoint between z-grid indices `iz` and `iz+1`.
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`Aeff at midpoint between z-grid indices `iz` and `iz+1`.`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L052

**スコープ**：module Metrics

**コード**：
```julia
When Aeff_hist is provided, linearly interpolate between iz and iz+1;
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`When Aeff_hist is provided, linearly interpolate between iz and iz+1;`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L053

**スコープ**：module Metrics

**コード**：
```julia
otherwise use beam profile at the midpoint z.
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`otherwise use beam profile at the midpoint z.`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L054

**スコープ**：module Metrics

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：docstring の終了。
- **なぜ**：この範囲のテキストが “ひとまとまりの説明” として扱われる。
- **注意**：閉じ忘れると以降のコードが全部文字列扱いになり、構文エラーになる。

---

## L055

**スコープ**：module Metrics

**コード**：
```julia
function _get_Aeff_mid(iz::Int, cfg::NLSESolver.NLSEConfig,
```

**解説**：
- **何をしているか**：関数 `_get_Aeff_mid` の定義開始。
- **なぜ**：`metrics.jl` は“計測/評価ロジック”を solver から分離して、最適化や安全判定で再利用しやすくするため。
- **注意**：この行では引数型（例：`::Float64`）を付けている。型を固定することで（1）意図しない入力を弾ける、（2）JIT最適化が効きやすい。

---

## L056

**スコープ**：module Metrics > function _get_Aeff_mid

**コード**：
```julia
                       Aeff_hist::Union{Vector{Float64}, Nothing})
```

**解説**：
- **何をしているか**：`Aeff_hist` を「配列」か「nothing（未提供）」のどちらでも受け取れるように型指定。
- **なぜ**：自己収束を有効にした場合は `propagate!` が `beam_hist.Aeff` を返すので、それをここに渡して評価を一致させたい。
- **注意**：`Union` は便利だが、分岐が増える。内部ヘルパ `_get_Aeff_*` に切り出して見通しを良くしているのがポイント。

---

## L057

**スコープ**：module Metrics > function _get_Aeff_mid

**コード**：
```julia
    if Aeff_hist !== nothing
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L058

**スコープ**：module Metrics > function _get_Aeff_mid > if

**コード**：
```julia
        @assert 1 ≤ iz && iz+1 ≤ length(Aeff_hist) "Aeff_hist index out of bounds: iz=$iz, len=$(length(Aeff_hist))"
```

**解説**：
- **何をしているか**：実行時アサーション。
- **なぜ**：`Aeff_hist[idx]` のような配列アクセスは、範囲外だと即バグになるので、原因を明確にして止める。
- **注意**：最適化ループで大量に呼ぶとアサートのコストが気になる場合もあるが、まずは“壊れ方を見える化”が優先。

---

## L059

**スコープ**：module Metrics > function _get_Aeff_mid > if

**コード**：
```julia
        return 0.5 * (Aeff_hist[iz] + Aeff_hist[iz+1])
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L060

**スコープ**：module Metrics > function _get_Aeff_mid > if

**コード**：
```julia
    else
```

**解説**：
- **何をしているか**：`else` 分岐。
- **なぜ**：上の条件がすべて偽のケースをまとめて処理できる。
- **注意**：ここに来るということは“これまでの条件に当てはまらない”という意味。条件設計の漏れに気づく手がかりになる。

---

## L061

**スコープ**：module Metrics > function _get_Aeff_mid > if

**コード**：
```julia
        z_mid_mm = 0.5 * (cfg.z_mm[iz] + cfg.z_mm[iz+1])
```

**解説**：
- **何をしているか**：z ステップ `[iz, iz+1]` の中点位置（mm）を計算。
- **なぜ**：係数評価（n₂など）を中点で行うと、Split-Step 的に“線形・非線形の結合”が改善しやすい（solver 側も同思想）。
- **注意**：中点を使うのは“係数が滑らかに変化する”前提。プレート境界の急変では、中点が境界をまたぐときの扱いが重要になる。

---

## L062

**スコープ**：module Metrics > function _get_Aeff_mid > if

**コード**：
```julia
        return Beam.A_eff(cfg.beam, z_mid_mm)
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L063

**スコープ**：module Metrics > function _get_Aeff_mid > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L064

**スコープ**：module Metrics > function _get_Aeff_mid

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`function _get_Aeff_mid` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L065

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L066

**スコープ**：module Metrics

**コード**：
```julia
function analyze_plate_limits(Itz::Array{Float64,2}, cfg::NLSESolver.NLSEConfig;
```

**解説**：
- **何をしているか**：関数 `analyze_plate_limits` の定義開始。
- **なぜ**：`metrics.jl` は“計測/評価ロジック”を solver から分離して、最適化や安全判定で再利用しやすくするため。
- **注意**：この行では引数型（例：`::Float64`）を付けている。型を固定することで（1）意図しない入力を弾ける、（2）JIT最適化が効きやすい。

---

## L067

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
                              B_warn_rad::Float64,
```

**解説**：
- **何をしているか**：実行行（具体処理）。
- **読み方のコツ**：この行が参照する変数が“どこで定義され、どんな単位/意味を持つか”を直前で確認する。
- **注意**：行単体では意味が薄い場合があるので、同じブロック（if/for/function）の範囲で因果関係を見る。

---

## L068

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
                              B_limit_rad::Float64,
```

**解説**：
- **何をしているか**：実行行（具体処理）。
- **読み方のコツ**：この行が参照する変数が“どこで定義され、どんな単位/意味を持つか”を直前で確認する。
- **注意**：行単体では意味が薄い場合があるので、同じブロック（if/for/function）の範囲で因果関係を見る。

---

## L069

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
                              safety_factor::Float64,
```

**解説**：
- **何をしているか**：実行行（具体処理）。
- **読み方のコツ**：この行が参照する変数が“どこで定義され、どんな単位/意味を持つか”を直前で確認する。
- **注意**：行単体では意味が薄い場合があるので、同じブロック（if/for/function）の範囲で因果関係を見る。

---

## L070

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
                              Aeff_hist::Union{Vector{Float64}, Nothing}=nothing)
```

**解説**：
- **何をしているか**：`Aeff_hist` を「配列」か「nothing（未提供）」のどちらでも受け取れるように型指定。
- **なぜ**：自己収束を有効にした場合は `propagate!` が `beam_hist.Aeff` を返すので、それをここに渡して評価を一致させたい。
- **注意**：`Union` は便利だが、分岐が増える。内部ヘルパ `_get_Aeff_*` に切り出して見通しを良くしているのがポイント。

---

## L071

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    nplates = length(cfg.plates)
```

**解説**：
- **何をしているか**：代入で `nplates` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L072

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    I_damage_Wcm2_per_plate = [p.I_damage_Wcm2 for p in cfg.plates]
```

**解説**：
- **何をしているか**：各プレート `p` が持つダメージ閾値 `I_damage_Wcm2` を配列として取り出す。
- **なぜ**：プレート材料やコーティングで耐力が違うので、プレートごとに別の許容強度を持てる設計にしている。
- **注意**：この値は **W/cm²**。後で計算する `Ipk_Wcm2` と単位を揃えるのが重要。

---

## L073

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    B_per_plate = zeros(Float64, nplates)
```

**解説**：
- **何をしているか**：代入で `B_per_plate` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L074

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    Ipk_per_plate = zeros(Float64, nplates)
```

**解説**：
- **何をしているか**：代入で `Ipk_per_plate` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L075

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    z_Ipk_mm = fill(NaN, nplates)
```

**解説**：
- **何をしているか**：代入で `z_Ipk_mm` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L076

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    I_allow_Wcm2_per_plate = I_damage_Wcm2_per_plate ./ safety_factor
```

**解説**：
- **何をしているか**：各プレート `p` が持つダメージ閾値 `I_damage_Wcm2` を配列として取り出す。
- **なぜ**：プレート材料やコーティングで耐力が違うので、プレートごとに別の許容強度を持てる設計にしている。
- **注意**：この値は **W/cm²**。後で計算する `Ipk_Wcm2` と単位を揃えるのが重要。

---

## L077

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L078

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    for iz in 1:(length(cfg.z_mm)-1)
```

**解説**：
- **何をしているか**：`for` ループ開始。
- **なぜ**：z ステップ（`iz`）やプレート配列（`enumerate`）を走査して集計するため。
- **注意**：このプロジェクトでは `cfg.z_mm` が mm、`cfg.dz` が m なので、ループ変数が扱う単位を常に意識する必要がある。

---

## L079

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        z_mid_mm = 0.5 * (cfg.z_mm[iz] + cfg.z_mm[iz+1])
```

**解説**：
- **何をしているか**：z ステップ `[iz, iz+1]` の中点位置（mm）を計算。
- **なぜ**：係数評価（n₂など）を中点で行うと、Split-Step 的に“線形・非線形の結合”が改善しやすい（solver 側も同思想）。
- **注意**：中点を使うのは“係数が滑らかに変化する”前提。プレート境界の急変では、中点が境界をまたぐときの扱いが重要になる。

---

## L080

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        pidx = plate_index_at_z(z_mid_mm, cfg.plates)
```

**解説**：
- **何をしているか**：代入で `pidx` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L081

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        if pidx === nothing
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L082

**スコープ**：module Metrics > function analyze_plate_limits > for > if

**コード**：
```julia
            continue
```

**解説**：
- **何をしているか**：このループ周回を中断して次へ進む。
- **なぜ**：プレート外・非線形ゼロ・数値不正など、評価する意味がない／危険なケースを早期に捨てている。
- **注意**：`continue` が多いと“静かに何も計算していない”状況が起き得る。ログが欲しい場合は `@warn` を入れる設計もあり。

---

## L083

**スコープ**：module Metrics > function analyze_plate_limits > for > if

**コード**：
```julia
        end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L084

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L085

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        _, _, n2_here = Plates.coeffs_at_z(z_mid_mm, cfg.plates, cfg.beam, cfg.λ0)
```

**解説**：
- **何をしているか**：位置 `z_mid_mm` における `(β2, β3, n2)` を取得し、ここでは `n2` だけ使う。
- **なぜ**：B積分や Kerr レンズ・SPM の強さは `n2` が主役。分散係数はここでは不要。
- **注意**：`_, _, n2_here` の `_` は“使わない値”の受け皿。ここで捨てた β₂,β₃ を後で使いたくなったら戻す。

---

## L086

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        Aeff_end = _get_Aeff_at(iz + 1, cfg, Aeff_hist)
```

**解説**：
- **何をしているか**：代入で `Aeff_end` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L087

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        if n2_here == 0.0 || Aeff_end <= 0.0 || !isfinite(Aeff_end)
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L088

**スコープ**：module Metrics > function analyze_plate_limits > for > if

**コード**：
```julia
            continue
```

**解説**：
- **何をしているか**：このループ周回を中断して次へ進む。
- **なぜ**：プレート外・非線形ゼロ・数値不正など、評価する意味がない／危険なケースを早期に捨てている。
- **注意**：`continue` が多いと“静かに何も計算していない”状況が起き得る。ログが欲しい場合は `@warn` を入れる設計もあり。

---

## L089

**スコープ**：module Metrics > function analyze_plate_limits > for > if

**コード**：
```julia
        end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L090

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L091

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        gamma = n2_here * cfg.ω0 / (NLSESolver.c0 * Aeff_end)
```

**解説**：
- **何をしているか**：非線形係数 `γ` を計算（power-envelope 形式）。
- **式の意味**：`γ = n₂ ω₀ / (c A_eff)`。ここで `A_eff` が小さい（強い集光）ほど γ が大きくなり、同じパワーでも非線形位相が増える。
- **注意**：`n2_here` の単位と `A` の定義が噛み合っている必要がある（solver 側に `# power-envelope form` とあるのがその根拠）。

---

## L092

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        Ppeak = maximum(Itz[:, iz+1])
```

**解説**：
- **何をしているか**：その z 点における時間波形の最大値（ピーク）を取る。
- **なぜ**：B積分や Kerr レンズは最も強い瞬間（ピーク）が支配的、という近似を採用している。
- **注意**：多峰性パルス（サブパルスが複数）だと“最大値だけ”では実態を過小/過大評価することがある。より厳密には時間積分 `∫γP(t)dz` を取る方法もある。

---

## L093

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        if !isfinite(gamma) || !isfinite(Ppeak)
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L094

**スコープ**：module Metrics > function analyze_plate_limits > for > if

**コード**：
```julia
            continue
```

**解説**：
- **何をしているか**：このループ周回を中断して次へ進む。
- **なぜ**：プレート外・非線形ゼロ・数値不正など、評価する意味がない／危険なケースを早期に捨てている。
- **注意**：`continue` が多いと“静かに何も計算していない”状況が起き得る。ログが欲しい場合は `@warn` を入れる設計もあり。

---

## L095

**スコープ**：module Metrics > function analyze_plate_limits > for > if

**コード**：
```julia
        end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L096

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L097

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        B_per_plate[pidx] += gamma * Ppeak * cfg.dz
```

**解説**：
- **何をしているか**：プレート `pidx` の B積分に `γ P_peak dz` を加算。
- **物理的意味**：B積分は Kerr による非線形位相 `φ_NL` の代表値（概ね `φ_NL ~ B`）。大きいほどスペクトル拡がりや自己収束が強い。
- **注意**：ここは `Aeff_end` を使って γ を計算しているので、“ステップ終端のビーム径”基準の評価になっている（`compute_B` は中点基準）。この違いは数％〜十数％の差になり得る。

---

## L098

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L099

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        Ipk_Wcm2 = (2.0 * Ppeak / Aeff_end) / 1e4
```

**解説**：
- **何をしているか**：ピーク強度 `I_peak` をガウシアン中心値として計算し、W/cm² に変換。
- **式の由来**：ガウシアンの全パワー `P` と中心強度 `I0` は `P = (I0/2) A_eff`（A_eff=πwxwy 定義）→ `I0 = 2P/A_eff`。
- **注意**：この式は“空間ガウシアン”前提。トップハットや M²>1 のビームだと中心強度が変わる。実験での安全率に織り込むべき。

---

## L100

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
        if Ipk_Wcm2 > Ipk_per_plate[pidx]
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L101

**スコープ**：module Metrics > function analyze_plate_limits > for > if

**コード**：
```julia
            Ipk_per_plate[pidx] = Ipk_Wcm2
```

**解説**：
- **何をしているか**：代入で `Ipk_per_plate[pidx]` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L102

**スコープ**：module Metrics > function analyze_plate_limits > for > if

**コード**：
```julia
            z_Ipk_mm[pidx] = z_mid_mm
```

**解説**：
- **何をしているか**：代入で `z_Ipk_mm[pidx]` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L103

**スコープ**：module Metrics > function analyze_plate_limits > for > if

**コード**：
```julia
        end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L104

**スコープ**：module Metrics > function analyze_plate_limits > for

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`for` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L105

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L106

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    B_total = sum(B_per_plate)
```

**解説**：
- **何をしているか**：代入で `B_total` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L107

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    B_status = [classify_B(Bi, B_warn_rad, B_limit_rad) for Bi in B_per_plate]
```

**解説**：
- **何をしているか**：代入で `B_status` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L108

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    I_status = [classify_I(Ipk_per_plate[i], I_allow_Wcm2_per_plate[i]) for i in 1:nplates]
```

**解説**：
- **何をしているか**：代入で `I_status` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L109

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    has_violation = any(s -> s == "VIOLATION", B_status) || any(s -> s == "VIOLATION", I_status)
```

**解説**：
- **何をしているか**：実行行（具体処理）。
- **読み方のコツ**：この行が参照する変数が“どこで定義され、どんな単位/意味を持つか”を直前で確認する。
- **注意**：行単体では意味が薄い場合があるので、同じブロック（if/for/function）の範囲で因果関係を見る。

---

## L110

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L111

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    return (
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L112

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
        B_per_plate = B_per_plate,
```

**解説**：
- **何をしているか**：代入で `B_per_plate` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L113

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
        Ipk_per_plate = Ipk_per_plate,
```

**解説**：
- **何をしているか**：代入で `Ipk_per_plate` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L114

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
        z_Ipk_mm = z_Ipk_mm,
```

**解説**：
- **何をしているか**：代入で `z_Ipk_mm` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L115

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
        B_total = B_total,
```

**解説**：
- **何をしているか**：代入で `B_total` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L116

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
        B_status = B_status,
```

**解説**：
- **何をしているか**：代入で `B_status` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L117

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
        I_status = I_status,
```

**解説**：
- **何をしているか**：代入で `I_status` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L118

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
        I_allow_Wcm2_per_plate = I_allow_Wcm2_per_plate,
```

**解説**：
- **何をしているか**：許容強度 `I_allow = I_damage / safety_factor` を計算。
- **なぜ**：ダメージ閾値は“ギリギリ”なので、安全率で余裕を持たせる（実験系では必須の発想）。
- **注意**：`safety_factor` は 1 以上を想定。1 未満だと逆に許容が甘くなる（設定ミスを検出したいなら assert しても良い）。

---

## L119

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
        has_violation = has_violation
```

**解説**：
- **何をしているか**：代入で `has_violation` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L120

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
    )
```

**解説**：
- **何をしているか**：実行行（具体処理）。
- **読み方のコツ**：この行が参照する変数が“どこで定義され、どんな単位/意味を持つか”を直前で確認する。
- **注意**：行単体では意味が薄い場合があるので、同じブロック（if/for/function）の範囲で因果関係を見る。

---

## L121

**スコープ**：module Metrics > function analyze_plate_limits

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`function analyze_plate_limits` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L122

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L123

**スコープ**：module Metrics

**コード**：
```julia
function compute_B(Itz::Array{Float64,2}, cfg::NLSESolver.NLSEConfig;
```

**解説**：
- **何をしているか**：関数 `compute_B` の定義開始。
- **なぜ**：`metrics.jl` は“計測/評価ロジック”を solver から分離して、最適化や安全判定で再利用しやすくするため。
- **注意**：この行では引数型（例：`::Float64`）を付けている。型を固定することで（1）意図しない入力を弾ける、（2）JIT最適化が効きやすい。

---

## L124

**スコープ**：module Metrics > function compute_B

**コード**：
```julia
                   Aeff_hist::Union{Vector{Float64}, Nothing}=nothing)
```

**解説**：
- **何をしているか**：`Aeff_hist` を「配列」か「nothing（未提供）」のどちらでも受け取れるように型指定。
- **なぜ**：自己収束を有効にした場合は `propagate!` が `beam_hist.Aeff` を返すので、それをここに渡して評価を一致させたい。
- **注意**：`Union` は便利だが、分岐が増える。内部ヘルパ `_get_Aeff_*` に切り出して見通しを良くしているのがポイント。

---

## L125

**スコープ**：module Metrics > function compute_B

**コード**：
```julia
    Nz = length(cfg.z_mm) - 1
```

**解説**：
- **何をしているか**：代入で `Nz` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L126

**スコープ**：module Metrics > function compute_B

**コード**：
```julia
    B_total = 0.0
```

**解説**：
- **何をしているか**：代入で `B_total` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L127

**スコープ**：module Metrics > function compute_B

**コード**：
```julia
    for iz in 1:Nz
```

**解説**：
- **何をしているか**：`for` ループ開始。
- **なぜ**：z ステップ（`iz`）やプレート配列（`enumerate`）を走査して集計するため。
- **注意**：このプロジェクトでは `cfg.z_mm` が mm、`cfg.dz` が m なので、ループ変数が扱う単位を常に意識する必要がある。

---

## L128

**スコープ**：module Metrics > function compute_B > for

**コード**：
```julia
        z_mid_mm = 0.5 * (cfg.z_mm[iz] + cfg.z_mm[iz+1])
```

**解説**：
- **何をしているか**：z ステップ `[iz, iz+1]` の中点位置（mm）を計算。
- **なぜ**：係数評価（n₂など）を中点で行うと、Split-Step 的に“線形・非線形の結合”が改善しやすい（solver 側も同思想）。
- **注意**：中点を使うのは“係数が滑らかに変化する”前提。プレート境界の急変では、中点が境界をまたぐときの扱いが重要になる。

---

## L129

**スコープ**：module Metrics > function compute_B > for

**コード**：
```julia
        _, _, n2_here = Plates.coeffs_at_z(z_mid_mm, cfg.plates, cfg.beam, cfg.λ0)
```

**解説**：
- **何をしているか**：位置 `z_mid_mm` における `(β2, β3, n2)` を取得し、ここでは `n2` だけ使う。
- **なぜ**：B積分や Kerr レンズ・SPM の強さは `n2` が主役。分散係数はここでは不要。
- **注意**：`_, _, n2_here` の `_` は“使わない値”の受け皿。ここで捨てた β₂,β₃ を後で使いたくなったら戻す。

---

## L130

**スコープ**：module Metrics > function compute_B > for

**コード**：
```julia
        if n2_here == 0.0
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L131

**スコープ**：module Metrics > function compute_B > for > if

**コード**：
```julia
            continue
```

**解説**：
- **何をしているか**：このループ周回を中断して次へ進む。
- **なぜ**：プレート外・非線形ゼロ・数値不正など、評価する意味がない／危険なケースを早期に捨てている。
- **注意**：`continue` が多いと“静かに何も計算していない”状況が起き得る。ログが欲しい場合は `@warn` を入れる設計もあり。

---

## L132

**スコープ**：module Metrics > function compute_B > for > if

**コード**：
```julia
        end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L133

**スコープ**：module Metrics > function compute_B > for

**コード**：
```julia
        Aeff_mid = _get_Aeff_mid(iz, cfg, Aeff_hist)
```

**解説**：
- **何をしているか**：代入で `Aeff_mid` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L134

**スコープ**：module Metrics > function compute_B > for

**コード**：
```julia
        if Aeff_mid < 1e-20 || !isfinite(Aeff_mid)
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L135

**スコープ**：module Metrics > function compute_B > for > if

**コード**：
```julia
            @warn "compute_B: skipping step $iz — Aeff dangerously small or non-finite" Aeff_mid
```

**解説**：
- **何をしているか**：警告ログを出す（処理は継続）。
- **なぜ**：`compute_B` は“多少の異常ならスキップしてでも B を返す”という運用を想定している。
- **注意**：警告が大量に出るとログが埋まる。最適化時は頻度制限やカウンタ集計にするのも手。

---

## L136

**スコープ**：module Metrics > function compute_B > for > if

**コード**：
```julia
            continue
```

**解説**：
- **何をしているか**：このループ周回を中断して次へ進む。
- **なぜ**：プレート外・非線形ゼロ・数値不正など、評価する意味がない／危険なケースを早期に捨てている。
- **注意**：`continue` が多いと“静かに何も計算していない”状況が起き得る。ログが欲しい場合は `@warn` を入れる設計もあり。

---

## L137

**スコープ**：module Metrics > function compute_B > for > if

**コード**：
```julia
        end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L138

**スコープ**：module Metrics > function compute_B > for

**コード**：
```julia
        gamma = n2_here * cfg.ω0 / (NLSESolver.c0 * Aeff_mid)
```

**解説**：
- **何をしているか**：非線形係数 `γ` を計算（power-envelope 形式）。
- **式の意味**：`γ = n₂ ω₀ / (c A_eff)`。ここで `A_eff` が小さい（強い集光）ほど γ が大きくなり、同じパワーでも非線形位相が増える。
- **注意**：`n2_here` の単位と `A` の定義が噛み合っている必要がある（solver 側に `# power-envelope form` とあるのがその根拠）。

---

## L139

**スコープ**：module Metrics > function compute_B > for

**コード**：
```julia
        Ppeak = maximum(Itz[:, iz+1])
```

**解説**：
- **何をしているか**：その z 点における時間波形の最大値（ピーク）を取る。
- **なぜ**：B積分や Kerr レンズは最も強い瞬間（ピーク）が支配的、という近似を採用している。
- **注意**：多峰性パルス（サブパルスが複数）だと“最大値だけ”では実態を過小/過大評価することがある。より厳密には時間積分 `∫γP(t)dz` を取る方法もある。

---

## L140

**スコープ**：module Metrics > function compute_B > for

**コード**：
```julia
        if !isfinite(Ppeak) || !isfinite(gamma)
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L141

**スコープ**：module Metrics > function compute_B > for > if

**コード**：
```julia
            @warn "compute_B: skipping step $iz — non-finite gamma or Ppeak" gamma Ppeak
```

**解説**：
- **何をしているか**：警告ログを出す（処理は継続）。
- **なぜ**：`compute_B` は“多少の異常ならスキップしてでも B を返す”という運用を想定している。
- **注意**：警告が大量に出るとログが埋まる。最適化時は頻度制限やカウンタ集計にするのも手。

---

## L142

**スコープ**：module Metrics > function compute_B > for > if

**コード**：
```julia
            continue
```

**解説**：
- **何をしているか**：このループ周回を中断して次へ進む。
- **なぜ**：プレート外・非線形ゼロ・数値不正など、評価する意味がない／危険なケースを早期に捨てている。
- **注意**：`continue` が多いと“静かに何も計算していない”状況が起き得る。ログが欲しい場合は `@warn` を入れる設計もあり。

---

## L143

**スコープ**：module Metrics > function compute_B > for > if

**コード**：
```julia
        end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L144

**スコープ**：module Metrics > function compute_B > for

**コード**：
```julia
        B_total += gamma * Ppeak * cfg.dz
```

**解説**：
- **何をしているか**：代入で `B_total +` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L145

**スコープ**：module Metrics > function compute_B > for

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`for` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L146

**スコープ**：module Metrics > function compute_B

**コード**：
```julia
    return B_total
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L147

**スコープ**：module Metrics > function compute_B

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`function compute_B` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L148

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L149

**スコープ**：module Metrics

**コード**：
```julia
# ===============================
```

**解説**：
- **何をしているか**：コメント行（無視される）。
- **なぜ**：コードの意図、区切り、セクション名を残す。
- **注意**：コメントが仕様説明の唯一の場所になっていると、実装変更時に破綻しやすい。

---

## L150

**スコープ**：module Metrics

**コード**：
```julia
# New metric functions
```

**解説**：
- **何をしているか**：コメント行（無視される）。
- **なぜ**：コードの意図、区切り、セクション名を残す。
- **注意**：コメントが仕様説明の唯一の場所になっていると、実装変更時に破綻しやすい。

---

## L151

**スコープ**：module Metrics

**コード**：
```julia
# ===============================
```

**解説**：
- **何をしているか**：コメント行（無視される）。
- **なぜ**：コードの意図、区切り、セクション名を残す。
- **注意**：コメントが仕様説明の唯一の場所になっていると、実装変更時に破綻しやすい。

---

## L152

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L153

**スコープ**：module Metrics

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：Julia の docstring（ドキュメント文字列）の開始。
- **なぜ**：直後の関数に「ヘルプとして表示される説明」を付けるため。REPL で `?関数名` とするとここが出る。
- **注意**：`"""` は“文字列リテラル”なので、コード的には実行時に評価されるが、通常はドキュメントとして扱われる。

---

## L154

**スコープ**：module Metrics

**コード**：
```julia
    spectral_bandwidth_dB(A_end, ω; threshold_dB=-20.0) -> Float64
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`spectral_bandwidth_dB(A_end, ω; threshold_dB=-20.0) -> Float64`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L155

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：docstring 内の空行（段落区切り）。
- **なぜ**：ヘルプ表示の可読性を上げる。
- **注意**：docstring はそのまま表示されるので、空行・インデントは見た目に影響する。

---

## L156

**スコープ**：module Metrics

**コード**：
```julia
Compute the spectral bandwidth [rad/s] at `threshold_dB` below the peak.
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`Compute the spectral bandwidth [rad/s] at `threshold_dB` below the peak.`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L157

**スコープ**：module Metrics

**コード**：
```julia
Returns 0.0 if no points are above the threshold.
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`Returns 0.0 if no points are above the threshold.`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L158

**スコープ**：module Metrics

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：docstring の終了。
- **なぜ**：この範囲のテキストが “ひとまとまりの説明” として扱われる。
- **注意**：閉じ忘れると以降のコードが全部文字列扱いになり、構文エラーになる。

---

## L159

**スコープ**：module Metrics

**コード**：
```julia
function spectral_bandwidth_dB(A_end::Vector{ComplexF64}, ω::Vector{Float64};
```

**解説**：
- **何をしているか**：関数 `spectral_bandwidth_dB` の定義開始。
- **なぜ**：`metrics.jl` は“計測/評価ロジック”を solver から分離して、最適化や安全判定で再利用しやすくするため。
- **注意**：この行では引数型（例：`::Float64`）を付けている。型を固定することで（1）意図しない入力を弾ける、（2）JIT最適化が効きやすい。

---

## L160

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
                                threshold_dB::Float64=-20.0)
```

**解説**：
- **何をしているか**：代入で `threshold_dB::Float64` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L161

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    Aω = fft(A_end)
```

**解説**：
- **何をしているか**：最終時間波形 `A_end(t)` を FFT してスペクトル `A(ω)` を得る。
- **なぜ**：スペクトル帯域や FTL パルス幅は周波数領域の情報が本体。
- **注意**：FFT のスケーリング（正規化係数）は FFTW の規約に従う。帯域“幅”を取るだけなら係数は消えるが、絶対値を比較する場合は注意。

---

## L162

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    S = abs2.(Aω)
```

**解説**：
- **何をしているか**：スペクトル強度（パワースペクトル）`S(ω)=|A(ω)|²` を作る。
- **なぜ**：dB 閾値で帯域を測るには“振幅”より“強度”で扱うのが自然（10log10）。
- **注意**：ここでの `S` は“正規化前”。後で `S_max` で割って相対値にしている。

---

## L163

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    S_max = maximum(S)
```

**解説**：
- **何をしているか**：代入で `S_max` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L164

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    if S_max <= 0.0
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L165

**スコープ**：module Metrics > function spectral_bandwidth_dB > if

**コード**：
```julia
        return 0.0
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L166

**スコープ**：module Metrics > function spectral_bandwidth_dB > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L167

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    S_norm = S ./ S_max
```

**解説**：
- **何をしているか**：代入で `S_norm` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L168

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    threshold_lin = 10.0^(threshold_dB / 10.0)
```

**解説**：
- **何をしているか**：dB で与えた閾値を線形比（強度比）へ変換。
- **なぜ**：`threshold_dB=-20` なら `S/Smax >= 10^{-2}` が条件。dB はログ表現なので線形に戻す必要がある。
- **注意**：強度 dB なので `10^(dB/10)`。振幅 dB なら `20` が分母になるので混同注意。

---

## L169

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L170

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    # Find frequency indices above threshold
```

**解説**：
- **何をしているか**：コメント行（無視される）。
- **なぜ**：コードの意図、区切り、セクション名を残す。
- **注意**：コメントが仕様説明の唯一の場所になっていると、実装変更時に破綻しやすい。

---

## L171

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    ω_sorted_idx = sortperm(ω)
```

**解説**：
- **何をしているか**：`ω` を昇順ソートするためのインデックス配列を作る。
- **なぜ**：FFT の周波数軸はしばしば “負→正” が連結された順序になる。ソートしてから幅を取ると端点検出が安定する。
- **注意**：ただし、ソートすると“本来は周期的に巻き戻る”軸が直線化される。多峰スペクトルの幅を単純に `max-min` で測るのは保守的（広め）になりがち。

---

## L172

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    ω_sorted = ω[ω_sorted_idx]
```

**解説**：
- **何をしているか**：代入で `ω_sorted` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L173

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    S_sorted = S_norm[ω_sorted_idx]
```

**解説**：
- **何をしているか**：代入で `S_sorted` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L174

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L175

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    above = findall(x -> x >= threshold_lin, S_sorted)
```

**解説**：
- **何をしているか**：実行行（具体処理）。
- **読み方のコツ**：この行が参照する変数が“どこで定義され、どんな単位/意味を持つか”を直前で確認する。
- **注意**：行単体では意味が薄い場合があるので、同じブロック（if/for/function）の範囲で因果関係を見る。

---

## L176

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    if isempty(above)
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L177

**スコープ**：module Metrics > function spectral_bandwidth_dB > if

**コード**：
```julia
        return 0.0
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L178

**スコープ**：module Metrics > function spectral_bandwidth_dB > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L179

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    ω_min = ω_sorted[first(above)]
```

**解説**：
- **何をしているか**：代入で `ω_min` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L180

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    ω_max = ω_sorted[last(above)]
```

**解説**：
- **何をしているか**：代入で `ω_max` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L181

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
    return ω_max - ω_min
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L182

**スコープ**：module Metrics > function spectral_bandwidth_dB

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`function spectral_bandwidth_dB` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L183

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L184

**スコープ**：module Metrics

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：Julia の docstring（ドキュメント文字列）の開始。
- **なぜ**：直後の関数に「ヘルプとして表示される説明」を付けるため。REPL で `?関数名` とするとここが出る。
- **注意**：`"""` は“文字列リテラル”なので、コード的には実行時に評価されるが、通常はドキュメントとして扱われる。

---

## L185

**スコープ**：module Metrics

**コード**：
```julia
    pulse_fwhm_fs(A_end, t) -> Float64
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`pulse_fwhm_fs(A_end, t) -> Float64`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L186

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：docstring 内の空行（段落区切り）。
- **なぜ**：ヘルプ表示の可読性を上げる。
- **注意**：docstring はそのまま表示されるので、空行・インデントは見た目に影響する。

---

## L187

**スコープ**：module Metrics

**コード**：
```julia
Compute the temporal FWHM [fs] of |A|^2.
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`Compute the temporal FWHM [fs] of |A|^2.`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L188

**スコープ**：module Metrics

**コード**：
```julia
Returns 0.0 if the pulse is zero.
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`Returns 0.0 if the pulse is zero.`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L189

**スコープ**：module Metrics

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：docstring の終了。
- **なぜ**：この範囲のテキストが “ひとまとまりの説明” として扱われる。
- **注意**：閉じ忘れると以降のコードが全部文字列扱いになり、構文エラーになる。

---

## L190

**スコープ**：module Metrics

**コード**：
```julia
function pulse_fwhm_fs(A_end::Vector{ComplexF64}, t::Vector{Float64})
```

**解説**：
- **何をしているか**：関数 `pulse_fwhm_fs` の定義開始。
- **なぜ**：`metrics.jl` は“計測/評価ロジック”を solver から分離して、最適化や安全判定で再利用しやすくするため。
- **注意**：この行では引数型（例：`::Float64`）を付けている。型を固定することで（1）意図しない入力を弾ける、（2）JIT最適化が効きやすい。

---

## L191

**スコープ**：module Metrics > function pulse_fwhm_fs

**コード**：
```julia
    I = abs2.(A_end)
```

**解説**：
- **何をしているか**：代入で `I` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L192

**スコープ**：module Metrics > function pulse_fwhm_fs

**コード**：
```julia
    I_max = maximum(I)
```

**解説**：
- **何をしているか**：代入で `I_max` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L193

**スコープ**：module Metrics > function pulse_fwhm_fs

**コード**：
```julia
    if I_max <= 0.0
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L194

**スコープ**：module Metrics > function pulse_fwhm_fs > if

**コード**：
```julia
        return 0.0
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L195

**スコープ**：module Metrics > function pulse_fwhm_fs > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L196

**スコープ**：module Metrics > function pulse_fwhm_fs

**コード**：
```julia
    half_max = 0.5 * I_max
```

**解説**：
- **何をしているか**：代入で `half_max` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L197

**スコープ**：module Metrics > function pulse_fwhm_fs

**コード**：
```julia
    above = findall(x -> x >= half_max, I)
```

**解説**：
- **何をしているか**：実行行（具体処理）。
- **読み方のコツ**：この行が参照する変数が“どこで定義され、どんな単位/意味を持つか”を直前で確認する。
- **注意**：行単体では意味が薄い場合があるので、同じブロック（if/for/function）の範囲で因果関係を見る。

---

## L198

**スコープ**：module Metrics > function pulse_fwhm_fs

**コード**：
```julia
    if isempty(above)
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：プレート外領域のスキップ、NaN/Inf ガード、閾値判定など“安全に走らせる”ため。
- **注意**：このコードは“壊れた入力をなるべくスキップして走り続ける”設計が混ざっている（`compute_B` は warn+skip、`analyze_plate_limits` は黙って skip）。

---

## L199

**スコープ**：module Metrics > function pulse_fwhm_fs > if

**コード**：
```julia
        return 0.0
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L200

**スコープ**：module Metrics > function pulse_fwhm_fs > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`if` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L201

**スコープ**：module Metrics > function pulse_fwhm_fs

**コード**：
```julia
    dt_range = t[last(above)] - t[first(above)]
```

**解説**：
- **何をしているか**：半値以上の領域の最初と最後の時刻差を FWHM として採用。
- **なぜ**：サンプル点ベースで簡潔に FWHM を得る方法。
- **注意**：補間していないので `Δt` 解像度に依存する。精密にやるなら半値交点を線形補間で求める実装に拡張する。

---

## L202

**スコープ**：module Metrics > function pulse_fwhm_fs

**コード**：
```julia
    return dt_range * 1e15  # convert s -> fs
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L203

**スコープ**：module Metrics > function pulse_fwhm_fs

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`function pulse_fwhm_fs` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L204

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L205

**スコープ**：module Metrics

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：Julia の docstring（ドキュメント文字列）の開始。
- **なぜ**：直後の関数に「ヘルプとして表示される説明」を付けるため。REPL で `?関数名` とするとここが出る。
- **注意**：`"""` は“文字列リテラル”なので、コード的には実行時に評価されるが、通常はドキュメントとして扱われる。

---

## L206

**スコープ**：module Metrics

**コード**：
```julia
    compressed_fwhm_fs(A_end, t) -> Float64
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`compressed_fwhm_fs(A_end, t) -> Float64`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L207

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：docstring 内の空行（段落区切り）。
- **なぜ**：ヘルプ表示の可読性を上げる。
- **注意**：docstring はそのまま表示されるので、空行・インデントは見た目に影響する。

---

## L208

**スコープ**：module Metrics

**コード**：
```julia
Fourier-transform-limited (FTL) pulse duration [fs].
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`Fourier-transform-limited (FTL) pulse duration [fs].`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L209

**スコープ**：module Metrics

**コード**：
```julia
Computed by phase-flattening the spectrum (setting all spectral phases to zero)
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`Computed by phase-flattening the spectrum (setting all spectral phases to zero)`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L210

**スコープ**：module Metrics

**コード**：
```julia
and measuring the FWHM of the resulting compressed-pulse intensity.
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`and measuring the FWHM of the resulting compressed-pulse intensity.`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L211

**スコープ**：module Metrics

**コード**：
```julia
This is the minimum achievable pulse duration given the current spectral bandwidth.
```

**解説**：
- **何をしているか**：docstring の本文（人間向け説明）。
- **この行が言っていること**：`This is the minimum achievable pulse duration given the current spectral bandwidth.`
- **注意**：docstring は仕様の“宣言”なので、実装とズレると後で混乱の元。

---

## L212

**スコープ**：module Metrics

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：docstring の終了。
- **なぜ**：この範囲のテキストが “ひとまとまりの説明” として扱われる。
- **注意**：閉じ忘れると以降のコードが全部文字列扱いになり、構文エラーになる。

---

## L213

**スコープ**：module Metrics

**コード**：
```julia
function compressed_fwhm_fs(A_end::Vector{ComplexF64}, t::Vector{Float64})
```

**解説**：
- **何をしているか**：関数 `compressed_fwhm_fs` の定義開始。
- **なぜ**：`metrics.jl` は“計測/評価ロジック”を solver から分離して、最適化や安全判定で再利用しやすくするため。
- **注意**：この行では引数型（例：`::Float64`）を付けている。型を固定することで（1）意図しない入力を弾ける、（2）JIT最適化が効きやすい。

---

## L214

**スコープ**：module Metrics > function compressed_fwhm_fs

**コード**：
```julia
    Aω = fft(A_end)
```

**解説**：
- **何をしているか**：最終時間波形 `A_end(t)` を FFT してスペクトル `A(ω)` を得る。
- **なぜ**：スペクトル帯域や FTL パルス幅は周波数領域の情報が本体。
- **注意**：FFT のスケーリング（正規化係数）は FFTW の規約に従う。帯域“幅”を取るだけなら係数は消えるが、絶対値を比較する場合は注意。

---

## L215

**スコープ**：module Metrics > function compressed_fwhm_fs

**コード**：
```julia
    # Phase-flat spectrum: keep amplitudes, discard phases
```

**解説**：
- **何をしているか**：コメント行（無視される）。
- **なぜ**：コードの意図、区切り、セクション名を残す。
- **注意**：コメントが仕様説明の唯一の場所になっていると、実装変更時に破綻しやすい。

---

## L216

**スコープ**：module Metrics > function compressed_fwhm_fs

**コード**：
```julia
    Aω_flat = complex.(abs.(Aω))
```

**解説**：
- **何をしているか**：スペクトルの位相を捨てて振幅のみ（実数・非負）を残す＝位相ゼロ化。
- **なぜ**：FTL（Fourier-transform-limited）は“与えられたスペクトル振幅で最短”の時間波形。位相を平坦化することでそれを構成できる。
- **注意**：これは理想圧縮器（完全位相補償）を仮定した指標。実験で実現可能かは位相の形・補償素子の自由度に依存する。

---

## L217

**スコープ**：module Metrics > function compressed_fwhm_fs

**コード**：
```julia
    A_compressed = ifft(Aω_flat)
```

**解説**：
- **何をしているか**：代入で `A_compressed` を更新/定義。
- **なぜ**：このプロジェクトは“途中結果を変数名で明示して”読みやすくするスタイル。
- **注意**：ここでの変数はスコープ（関数内/ループ内）に閉じる。外から見える状態は返り値（NamedTuple 等）だけ。

---

## L218

**スコープ**：module Metrics > function compressed_fwhm_fs

**コード**：
```julia
    # ifft of a real positive spectrum produces a pulse centered at index 1 (t[1]).
```

**解説**：
- **何をしているか**：コメント行（無視される）。
- **なぜ**：コードの意図、区切り、セクション名を残す。
- **注意**：コメントが仕様説明の唯一の場所になっていると、実装変更時に破綻しやすい。

---

## L219

**スコープ**：module Metrics > function compressed_fwhm_fs

**コード**：
```julia
    # ifftshift re-centers it to the middle of the time window.
```

**解説**：
- **何をしているか**：コメント行（無視される）。
- **なぜ**：コードの意図、区切り、セクション名を残す。
- **注意**：コメントが仕様説明の唯一の場所になっていると、実装変更時に破綻しやすい。

---

## L220

**スコープ**：module Metrics > function compressed_fwhm_fs

**コード**：
```julia
    return pulse_fwhm_fs(ifftshift(A_compressed), t)
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：判定関数（`classify_*`）は分岐したら即 return する方が読みやすい。
- **注意**：この行以降は実行されない。return の位置が変わるとロジックが大きく変わる。

---

## L221

**スコープ**：module Metrics > function compressed_fwhm_fs

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どのブロック？**：`function compressed_fwhm_fs` を閉じる（スタック推定）。
- **注意**：Julia は `if/for/function/module` をすべて `end` で閉じる。対応が崩れると構文エラーになる。

---

## L222

**スコープ**：module Metrics

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。実行には影響しない。
- **なぜ**：関数やブロックの境界を視覚的に分けて読みやすくする。
- **注意**：Julia では空行は意味を持たない（Python のようにインデントでブロックが決まる言語ではない）。

---

## L223

**スコープ**：module Metrics

**コード**：
```julia
end # module
```

**解説**：
- **何をしているか**：モジュール定義の終了。
- **なぜ**：`module Metrics` のスコープを閉じる。
- **注意**：この `end` 以降に書いたものは `Metrics` の外側になる（意図せず外に出る事故が起きやすいポイント）。

---

