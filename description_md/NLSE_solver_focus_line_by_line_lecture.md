# `NLSE_solver_focus.jl` 1行ずつ「講師レベル」で解説（圧倒的に丁寧版）

- 対象: `NLSE_solver_focus.jl`（312行）
- MD5: `5f93ffb26465de002dc6cc08a4328632`
- 参照時刻（ローカルmtime）: `2026-02-24T15:06:01`

## このファイルの役割（最初に全体像）

- これは **1D NLSE を z 方向に伝搬**させる solver 本体。
- コアは `propagate!`：
  1) zごとに係数（β₂, β₃, n₂）を取得（`Plates.coeffs_at_z`）
  2) （任意）集光/自己収束を Aeff に反映（2つの流儀：`apply_beam_scaling` or `enable_self_focusing`）
  3) 対称SSFM：`L(dz/2) → N(dz) → L(dz/2)`
  4) `Itz`（時間パワー）と `Ifz`（スペクトル強度）を保存

### 2つの“ビーム半径の扱い”がある（重要）

- **(A) apply_beam_scaling**：幾何学的ビーム面積 `A_eff(z)` を使って、電場包絡 `A` を `sqrt(A_eff)` 比でスケーリングして“集光による強度変化”を1Dへ取り込む。
- **(B) enable_self_focusing**：qパラメータを進めて（Kerr thin-lens で）`w(z)` 自体を更新し、その結果の `A_eff(z)` で `γ` を更新する（自己収束を擬似的に入れる）。
- この2つは同時に使うと二重に効くので、コンストラクタで排他にしている。

> **講師の視点**：ここがこの solver の“肝”です。あなたが焦点近傍で thin-lens 近似の妥当性を気にしているのは、まさにこの(B)の部分。

---

## L001

**スコープ**：(トップレベル)

**コード**：
```julia
module NLSESolver
```

**解説**：
- **何をしているか**：モジュール `NLSESolver` の開始。
- **なぜ**：Solver の定義を名前空間に閉じ込め、`export` で外部公開APIを制御する。
- **注意**：最後の `end` までがこのモジュールスコープ。

---

## L002

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L003

**スコープ**：module NLSESolver

**コード**：
```julia
using FFTW
```

**解説**：
- **何をしているか**：依存モジュールを読み込む。
- **なぜ**：SSFMで FFT が必須（FFTW）、媒質係数（Plates）、ビーム幾何（Beam）を使う。
- **注意**：`using ..X` は相対参照。プロジェクトのモジュール階層に依存する。

---

## L004

**スコープ**：module NLSESolver

**コード**：
```julia
using ..Plates
```

**解説**：
- **何をしているか**：依存モジュールを読み込む。
- **なぜ**：SSFMで FFT が必須（FFTW）、媒質係数（Plates）、ビーム幾何（Beam）を使う。
- **注意**：`using ..X` は相対参照。プロジェクトのモジュール階層に依存する。

---

## L005

**スコープ**：module NLSESolver

**コード**：
```julia
using ..Beam
```

**解説**：
- **何をしているか**：依存モジュールを読み込む。
- **なぜ**：SSFMで FFT が必須（FFTW）、媒質係数（Plates）、ビーム幾何（Beam）を使う。
- **注意**：`using ..X` は相対参照。プロジェクトのモジュール階層に依存する。

---

## L006

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L007

**スコープ**：module NLSESolver

**コード**：
```julia
export NLSEConfig, propagate!, w_from_q, Aeff_from_q, beam_half_step
```

**解説**：
- **何をしているか**：外部公開する識別子（型/関数）の宣言。
- **なぜ**：利用者に見せたいのは `NLSEConfig` と `propagate!` が中心。q補助も公開している。
- **注意**：`export` してなくても `NLSESolver.w_from_q` のように完全修飾すれば呼べる。

---

## L008

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L009

**スコープ**：module NLSESolver

**コード**：
```julia
const ε0  = 8.8541878128e-12
```

**解説**：
- **何をしているか**：定数（`const`）を定義。
- **なぜ**：物理定数（ε0, c0）や“ガード用パラメータ”は不変なので const にしておくと速く・意図が明確。
- **注意**：`c0` は後で γ 計算に使う。単位は m/s。

---

## L010

**スコープ**：module NLSESolver

**コード**：
```julia
const c0  = 2.99792458e8
```

**解説**：
- **何をしているか**：定数（`const`）を定義。
- **なぜ**：物理定数（ε0, c0）や“ガード用パラメータ”は不変なので const にしておくと速く・意図が明確。
- **注意**：`c0` は後で γ 計算に使う。単位は m/s。

---

## L011

**スコープ**：module NLSESolver

**コード**：
```julia
const _W_FROM_Q_TOL = 1e-30  # tolerance for imag(1/q) physical-beam check
```

**解説**：
- **何をしているか**：定数（`const`）を定義。
- **なぜ**：物理定数（ε0, c0）や“ガード用パラメータ”は不変なので const にしておくと速く・意図が明確。
- **注意**：`c0` は後で γ 計算に使う。単位は m/s。

---

## L012

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L013

**スコープ**：module NLSESolver

**コード**：
```julia
# =============================================
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L014

**スコープ**：module NLSESolver

**コード**：
```julia
# q-parameter helpers (ported from NLSE_step5)
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L015

**スコープ**：module NLSESolver

**コード**：
```julia
# =============================================
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L016

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L017

**スコープ**：module NLSESolver

**コード**：
```julia
"Beam radius from q-parameter (air approximation), with numerical guard"
```

**解説**：
- **何をしているか**：短い docstring（1行版）。直後の関数/型の説明になる。
- **なぜ**：ヘルプとして残しつつ、コードの見通しも良くする。
- **注意**：コメント `#` と違い、docstring は `?` で参照される。

---

## L018

**スコープ**：module NLSESolver

**コード**：
```julia
@inline function w_from_q(q::ComplexF64, λ0::Float64)
```

**解説**：
- **何をしているか**：関数 `w_from_q` を `@inline` 指示付きで定義開始。
- **なぜ**：小さな数式関数（q→w など）は inlining すると呼び出しコストが消えやすい。
- **講師メモ**：この関数は“自己収束モデル（qパラメータ）”の土台なので、式の符号や単位を丁寧に追う。

---

## L019

**スコープ**：module NLSESolver > function w_from_q

**コード**：
```julia
    if q == 0.0 + 0.0im
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L020

**スコープ**：module NLSESolver > function w_from_q > if

**コード**：
```julia
        error("w_from_q: q = 0 (singular). Beam has collapsed.")
```

**解説**：
- **何をしているか**：例外を投げて即停止。
- **なぜ**：ここに来たら“物理的に破綻（ビーム崩壊、非物理q）”という設計。
- **講師メモ**：最適化中に頻発するなら、（1）モデルの限界、（2）パラメータ探索範囲の過大、（3）ガード設定の不整合 を疑う。

---

## L021

**スコープ**：module NLSESolver > function w_from_q > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L022

**スコープ**：module NLSESolver > function w_from_q

**コード**：
```julia
    invq = 1.0 / q
```

**解説**：
- **何をしているか**：qパラメータの逆数 `1/q` を計算。
- **物理背景**：ガウシアンビームでは
  \[
  \frac{1}{q} = \frac{1}{R} - i\,\frac{\lambda}{\pi w^2}
  \]
  なので、虚部が **必ず負**（`-λ/(πw²)`）でないと“物理的ビーム”にならない。
- **注意**：q=0 に近づくと `1/q` が発散するので、その前に停止させている。

---

## L023

**スコープ**：module NLSESolver > function w_from_q

**コード**：
```julia
    if !isfinite(real(invq)) || !isfinite(imag(invq))
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L024

**スコープ**：module NLSESolver > function w_from_q > if

**コード**：
```julia
        error("w_from_q: 1/q is not finite (1/q = $invq, q = $q).")
```

**解説**：
- **何をしているか**：例外を投げて即停止。
- **なぜ**：ここに来たら“物理的に破綻（ビーム崩壊、非物理q）”という設計。
- **講師メモ**：最適化中に頻発するなら、（1）モデルの限界、（2）パラメータ探索範囲の過大、（3）ガード設定の不整合 を疑う。

---

## L025

**スコープ**：module NLSESolver > function w_from_q > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L026

**スコープ**：module NLSESolver > function w_from_q

**コード**：
```julia
    imag_invq = imag(invq)
```

**解説**：
- **何をしているか**：`imag(1/q)` を取り出し、物理的条件（負であること）をチェック。
- **なぜ**：`imag(1/q) >= 0` になるのは“ビーム崩壊/モデル破綻/数値事故”のサイン。
- **講師メモ**：ここで `tol` を入れているのは、遠方でほぼ平行光（imagが -0 に丸め込まれる）ときに誤爆しないため。

---

## L027

**スコープ**：module NLSESolver > function w_from_q

**コード**：
```julia
    # imag(1/q) must be negative for a physical beam.
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L028

**スコープ**：module NLSESolver > function w_from_q

**コード**：
```julia
    # Use tolerance to avoid false trigger from floating-point rounding
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L029

**スコープ**：module NLSESolver > function w_from_q

**コード**：
```julia
    # (e.g. wide/collimated beams where imag(1/q) ≈ -0).
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L030

**スコープ**：module NLSESolver > function w_from_q

**コード**：
```julia
    if imag_invq > -_W_FROM_Q_TOL
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L031

**スコープ**：module NLSESolver > function w_from_q > if

**コード**：
```julia
        error("w_from_q: non-physical q-parameter (imag(1/q) = $imag_invq ≥ -tol). " *
```

**解説**：
- **何をしているか**：例外を投げて即停止。
- **なぜ**：ここに来たら“物理的に破綻（ビーム崩壊、非物理q）”という設計。
- **講師メモ**：最適化中に頻発するなら、（1）モデルの限界、（2）パラメータ探索範囲の過大、（3）ガード設定の不整合 を疑う。

---

## L032

**スコープ**：module NLSESolver > function w_from_q > if

**コード**：
```julia
              "Beam has collapsed or q has become unphysical. " *
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L033

**スコープ**：module NLSESolver > function w_from_q > if

**コード**：
```julia
              "q = $q")
```

**解説**：
- **何をしているか**：代入で `"q` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L034

**スコープ**：module NLSESolver > function w_from_q > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L035

**スコープ**：module NLSESolver > function w_from_q

**コード**：
```julia
    return sqrt(-λ0 / (π * imag_invq))
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L036

**スコープ**：module NLSESolver > function w_from_q

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`function w_from_q` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L037

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L038

**スコープ**：module NLSESolver

**コード**：
```julia
"Effective area and beam radii from q-parameters"
```

**解説**：
- **何をしているか**：短い docstring（1行版）。直後の関数/型の説明になる。
- **なぜ**：ヘルプとして残しつつ、コードの見通しも良くする。
- **注意**：コメント `#` と違い、docstring は `?` で参照される。

---

## L039

**スコープ**：module NLSESolver

**コード**：
```julia
@inline function Aeff_from_q(qx::ComplexF64, qy::ComplexF64, λ0::Float64)
```

**解説**：
- **何をしているか**：関数 `Aeff_from_q` を `@inline` 指示付きで定義開始。
- **なぜ**：小さな数式関数（q→w など）は inlining すると呼び出しコストが消えやすい。
- **講師メモ**：この関数は“自己収束モデル（qパラメータ）”の土台なので、式の符号や単位を丁寧に追う。

---

## L040

**スコープ**：module NLSESolver > function Aeff_from_q

**コード**：
```julia
    wx = w_from_q(qx, λ0)
```

**解説**：
- **何をしているか**：代入で `wx` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L041

**スコープ**：module NLSESolver > function Aeff_from_q

**コード**：
```julia
    wy = w_from_q(qy, λ0)
```

**解説**：
- **何をしているか**：代入で `wy` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L042

**スコープ**：module NLSESolver > function Aeff_from_q

**コード**：
```julia
    return π * wx * wy, wx, wy
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L043

**スコープ**：module NLSESolver > function Aeff_from_q

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`function Aeff_from_q` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L044

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L045

**スコープ**：module NLSESolver

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：docstring（ドキュメント文字列）の開始。
- **なぜ**：直後の関数（または型）にヘルプ文を付け、`?名前` で参照できるようにする。
- **読み方**：ここから次の `"""` までが“人間向け仕様”。実装とズレると事故るので要注意。

---

## L046

**スコープ**：module NLSESolver

**コード**：
```julia
Beam half-step: free-propagate dz_half/2, apply Kerr thin-lens, free-propagate dz_half/2.
```

**解説**：
- **何をしているか**：docstring の本文。
- **この行の内容**：`Beam half-step: free-propagate dz_half/2, apply Kerr thin-lens, free-propagate dz_half/2.`
- **講師メモ**：ここは“利用者に約束している仕様”なので、後でコードをいじるときに必ず整合を取る。

---

## L047

**スコープ**：module NLSESolver

**コード**：
```julia
When enable_self_focusing=false or n2_here==0, only free propagation is applied.
```

**解説**：
- **何をしているか**：docstring の本文。
- **この行の内容**：`When enable_self_focusing=false or n2_here==0, only free propagation is applied.`
- **講師メモ**：ここは“利用者に約束している仕様”なので、後でコードをいじるときに必ず整合を取る。

---

## L048

**スコープ**：module NLSESolver

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：docstring の終了。
- **注意**：閉じ忘れは構文エラーになる。

---

## L049

**スコープ**：module NLSESolver

**コード**：
```julia
function beam_half_step(qx::ComplexF64, qy::ComplexF64;
```

**解説**：
- **何をしているか**：関数 `beam_half_step` の定義開始。
- **なぜ**：SSFM の各ステップ（線形/非線形）や propagate 本体を分離し、テストしやすくする。
- **講師メモ**：`propagate!` は副作用というより“状態を更新しつつ結果も返す”設計。`!` はその意図の表明。

---

## L050

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
                        dz_half::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L051

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
                        n2_here::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L052

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
                        Ppeak::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L053

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
                        λ0::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L054

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
                        enable_self_focusing::Bool)
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L055

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
    # free propagate to mid-plane
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L056

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
    qx_mid = qx + dz_half / 2
```

**解説**：
- **何をしているか**：自由空間伝搬で q を更新（半ステップの中点まで）。
- **物理背景**：均一媒質での自由伝搬は `q(z+Δz)=q(z)+Δz`（n≈1仮定）。
- **注意**：このコードは `dz_half` を **m** で扱う。`z_mm` と混ぜるとスケールが崩壊する。

---

## L057

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
    qy_mid = qy + dz_half / 2
```

**解説**：
- **何をしているか**：自由空間伝搬で q を更新（半ステップの中点まで）。
- **物理背景**：均一媒質での自由伝搬は `q(z+Δz)=q(z)+Δz`（n≈1仮定）。
- **注意**：このコードは `dz_half` を **m** で扱う。`z_mm` と混ぜるとスケールが崩壊する。

---

## L058

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L059

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
    # Kerr lens at mid-plane
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L060

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
    if enable_self_focusing && n2_here != 0.0 && Ppeak > 0.0
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L061

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
```julia
        _Aeff_mid, wx_mid, wy_mid = Aeff_from_q(qx_mid, qy_mid, λ0)
```

**解説**：
- **何をしているか**：代入で `_Aeff_mid, wx_mid, wy_mid` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L062

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L063

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
```julia
        # on-axis intensity (elliptic Gaussian): I0 = 2P / (π wx wy)
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L064

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
```julia
        I0 = 2.0 * Ppeak / (π * wx_mid * wy_mid)
```

**解説**：
- **何をしているか**：楕円ガウシアンの中心強度 `I0` を計算。
- **式**：`I0 = 2 P / (π w_x w_y)`。
- **注意**：ここでの `Ppeak` は“時間的ピークパワー”。空間ピークと時間ピークを掛け合わせて最悪ケースの Kerr を見積もっている。

---

## L065

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L066

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
```julia
        # thin-lens strengths from 2nd-order expansion
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L067

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
```julia
        invfx = 4.0 * n2_here * I0 * dz_half / (wx_mid^2)
```

**解説**：
- **何をしているか**：Kerr レンズの薄レンズ強度 `1/f` を計算。
- **物理背景（概念）**：Kerr により屈折率が `n(r)=n0+n2 I(r)` となり、ガウシアン強度を2次まで展開すると“放物線屈折率”→レンズに相当。
- **注意**：係数（4.0 など）はこの2次展開と定義（wの定義）に依存。ここが最もモデル依存で壊れやすい。

---

## L068

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
```julia
        invfy = 4.0 * n2_here * I0 * dz_half / (wy_mid^2)
```

**解説**：
- **何をしているか**：Kerr レンズの薄レンズ強度 `1/f` を計算。
- **物理背景（概念）**：Kerr により屈折率が `n(r)=n0+n2 I(r)` となり、ガウシアン強度を2次まで展開すると“放物線屈折率”→レンズに相当。
- **注意**：係数（4.0 など）はこの2次展開と定義（wの定義）に依存。ここが最もモデル依存で壊れやすい。

---

## L069

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L070

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
```julia
        qx_mid = 1.0 / (1.0 / qx_mid - invfx)
```

**解説**：
- **何をしているか**：薄レンズ通過の q変換。
- **式**：薄レンズは `1/q_out = 1/q_in - 1/f`。
- **注意**：`invf` が大きい（強い自己収束）と q が非物理に飛びやすい。だから `w_from_q` の物理チェックが重要。

---

## L071

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
```julia
        qy_mid = 1.0 / (1.0 / qy_mid - invfy)
```

**解説**：
- **何をしているか**：代入で `qy_mid` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L072

**スコープ**：module NLSESolver > function beam_half_step > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L073

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L074

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
    # free propagate to end of half-step
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L075

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
    qx_next = qx_mid + dz_half / 2
```

**解説**：
- **何をしているか**：代入で `qx_next` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L076

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
    qy_next = qy_mid + dz_half / 2
```

**解説**：
- **何をしているか**：代入で `qy_next` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L077

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
    return qx_next, qy_next
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L078

**スコープ**：module NLSESolver > function beam_half_step

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`function beam_half_step` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L079

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L080

**スコープ**：module NLSESolver

**コード**：
```julia
# =============================================
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L081

**スコープ**：module NLSESolver

**コード**：
```julia
# Config
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L082

**スコープ**：module NLSESolver

**コード**：
```julia
# =============================================
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L083

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L084

**スコープ**：module NLSESolver

**コード**：
```julia
"NLSE の設定一式"
```

**解説**：
- **何をしているか**：短い docstring（1行版）。直後の関数/型の説明になる。
- **なぜ**：ヘルプとして残しつつ、コードの見通しも良くする。
- **注意**：コメント `#` と違い、docstring は `?` で参照される。

---

## L085

**スコープ**：module NLSESolver

**コード**：
```julia
struct NLSEConfig
```

**解説**：
- **何をしているか**：不変構造体 `NLSEConfig` の定義開始。
- **なぜ**：設定パラメータを1つにまとめ、関数の引数をスッキリさせる。
- **注意**：`struct` は基本的にイミュータブル。設定を変えたいなら新しい `NLSEConfig` を作る。

---

## L086

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    λ0::Float64             # 中心波長 [m]
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L087

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    ω0::Float64             # 中心角周波数 [rad/s]
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L088

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    t::Vector{Float64}      # 時間軸 [s]
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L089

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    ω::Vector{Float64}      # 周波数軸 [rad/s]
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L090

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    z_mm::Vector{Float64}   # 伝搬位置 [mm]
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L091

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    dz::Float64             # z ステップ [m]
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L092

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    plates::Vector{Plates.Plate}
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L093

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    beam::Beam.AbstractBeam
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L094

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    apply_beam_scaling::Bool  # if true, rescale A by sqrt(A_eff) to include focusing
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L095

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    enable_dispersion::Bool
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L096

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    enable_spm::Bool
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L097

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    enable_self_steepening::Bool
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L098

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    enable_self_focusing::Bool  # Kerr self-focusing via q-parameter
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L099

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    qx0::ComplexF64             # 初期 q-parameter (x)
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L100

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    qy0::ComplexF64             # 初期 q-parameter (y)
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L101

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
    aeff_min_m2::Float64        # Aeff 下限ガード [m²] (0 = 無効)
```

**解説**：
- **何をしているか**：代入で `aeff_min_m2::Float64        # Aeff 下限ガード [m²] (0` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L102

**スコープ**：module NLSESolver > struct NLSEConfig

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`struct NLSEConfig` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L103

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L104

**スコープ**：module NLSESolver

**コード**：
```julia
"Convenience constructor with validation"
```

**解説**：
- **何をしているか**：短い docstring（1行版）。直後の関数/型の説明になる。
- **なぜ**：ヘルプとして残しつつ、コードの見通しも良くする。
- **注意**：コメント `#` と違い、docstring は `?` で参照される。

---

## L105

**スコープ**：module NLSESolver

**コード**：
```julia
function NLSEConfig(λ0, ω0, t, ω, z_mm, dz, plates, beam;
```

**解説**：
- **何をしているか**：関数 `NLSEConfig` の定義開始。
- **なぜ**：SSFM の各ステップ（線形/非線形）や propagate 本体を分離し、テストしやすくする。
- **講師メモ**：`propagate!` は副作用というより“状態を更新しつつ結果も返す”設計。`!` はその意図の表明。

---

## L106

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
           apply_beam_scaling=false,
```

**解説**：
- **何をしているか**：代入で `apply_beam_scaling` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L107

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
           enable_dispersion=true,
```

**解説**：
- **何をしているか**：代入で `enable_dispersion` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L108

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
           enable_spm=true,
```

**解説**：
- **何をしているか**：代入で `enable_spm` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L109

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
           enable_self_steepening=true,
```

**解説**：
- **何をしているか**：代入で `enable_self_steepening` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L110

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
           enable_self_focusing=false,
```

**解説**：
- **何をしているか**：代入で `enable_self_focusing` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L111

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
           qx0=ComplexF64(0, 1),
```

**解説**：
- **何をしているか**：代入で `qx0` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L112

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
           qy0=ComplexF64(0, 1),
```

**解説**：
- **何をしているか**：代入で `qy0` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L113

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
           aeff_min_m2=0.0)
```

**解説**：
- **何をしているか**：代入で `aeff_min_m2` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L114

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
    if enable_self_focusing && apply_beam_scaling
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L115

**スコープ**：module NLSESolver > function NLSEConfig > if

**コード**：
```julia
        error("enable_self_focusing and apply_beam_scaling are mutually exclusive. " *
```

**解説**：
- **何をしているか**：例外を投げて即停止。
- **なぜ**：ここに来たら“物理的に破綻（ビーム崩壊、非物理q）”という設計。
- **講師メモ**：最適化中に頻発するなら、（1）モデルの限界、（2）パラメータ探索範囲の過大、（3）ガード設定の不整合 を疑う。

---

## L116

**スコープ**：module NLSESolver > function NLSEConfig > if

**コード**：
```julia
              "Use one or the other.")
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L117

**スコープ**：module NLSESolver > function NLSEConfig > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L118

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
    if enable_self_focusing && qx0 == ComplexF64(0, 1) && qy0 == ComplexF64(0, 1)
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L119

**スコープ**：module NLSESolver > function NLSEConfig > if

**コード**：
```julia
        @warn "enable_self_focusing=true but qx0/qy0 are default dummy values. " *
```

**解説**：
- **何をしているか**：警告ログを出す（停止はしない）。
- **なぜ**：致命ではないが“怪しい設定”を利用者に知らせる。
- **注意**：最適化ではログが増えがち。必要なら警告の頻度制限や一括集計にする。

---

## L120

**スコープ**：module NLSESolver > function NLSEConfig > if

**コード**：
```julia
              "Set qx0/qy0 from Beam.initial_q() for physically meaningful results."
```

**解説**：
- **何をしているか**：短い docstring（1行版）。直後の関数/型の説明になる。
- **なぜ**：ヘルプとして残しつつ、コードの見通しも良くする。
- **注意**：コメント `#` と違い、docstring は `?` で参照される。

---

## L121

**スコープ**：module NLSESolver > function NLSEConfig > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L122

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
    return NLSEConfig(λ0, ω0, t, ω, z_mm, dz, plates, beam,
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L123

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
               apply_beam_scaling, enable_dispersion, enable_spm, enable_self_steepening,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L124

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
               enable_self_focusing, qx0, qy0, aeff_min_m2)
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L125

**スコープ**：module NLSESolver > function NLSEConfig

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`function NLSEConfig` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L126

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L127

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L128

**スコープ**：module NLSESolver

**コード**：
```julia
"線形ステップ: GVD + TOD を周波数領域で進める"
```

**解説**：
- **何をしているか**：短い docstring（1行版）。直後の関数/型の説明になる。
- **なぜ**：ヘルプとして残しつつ、コードの見通しも良くする。
- **注意**：コメント `#` と違い、docstring は `?` で参照される。

---

## L129

**スコープ**：module NLSESolver

**コード**：
```julia
function linear_step(A::Vector{ComplexF64},
```

**解説**：
- **何をしているか**：関数 `linear_step` の定義開始。
- **なぜ**：SSFM の各ステップ（線形/非線形）や propagate 本体を分離し、テストしやすくする。
- **講師メモ**：`propagate!` は副作用というより“状態を更新しつつ結果も返す”設計。`!` はその意図の表明。

---

## L130

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
                     dz::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L131

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
                     β2_here::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L132

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
                     β3_here::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L133

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
                     ω::Vector{Float64},
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L134

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
                     enable_dispersion::Bool)
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L135

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
    if !enable_dispersion
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L136

**スコープ**：module NLSESolver > function linear_step > if

**コード**：
```julia
        return A
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L137

**スコープ**：module NLSESolver > function linear_step > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L138

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
    if β2_here == 0.0 && β3_here == 0.0
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L139

**スコープ**：module NLSESolver > function linear_step > if

**コード**：
```julia
        return A
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L140

**スコープ**：module NLSESolver > function linear_step > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L141

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
    Aω = fft(A)
```

**解説**：
- **何をしているか**：代入で `Aω` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L142

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
    phaseL = exp.(1im .* ((β2_here/2) .* (ω.^2) .+ (β3_here/6) .* (ω.^3)) .* dz)
```

**解説**：
- **何をしているか**：分散による線形位相因子を周波数領域で作る。
- **式**：`exp(i[ β2/2 ω² + β3/6 ω³ ] dz)`。
- **注意**：ここでの `ω` は“中心周波数からのオフセット”として定義されている必要がある。もし絶対ωなら項が変わる。`config.jl` 側での ω 軸定義を必ず確認。

---

## L143

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
    Aω .*= phaseL
```

**解説**：
- **何をしているか**：代入で `Aω .*` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L144

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
    return ifft(Aω)
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L145

**スコープ**：module NLSESolver > function linear_step

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`function linear_step` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L146

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L147

**スコープ**：module NLSESolver

**コード**：
```julia
"非線形演算子（self-steepening 含む）"
```

**解説**：
- **何をしているか**：短い docstring（1行版）。直後の関数/型の説明になる。
- **なぜ**：ヘルプとして残しつつ、コードの見通しも良くする。
- **注意**：コメント `#` と違い、docstring は `?` で参照される。

---

## L148

**スコープ**：module NLSESolver

**コード**：
```julia
function N_op(A::Vector{ComplexF64},
```

**解説**：
- **何をしているか**：関数 `N_op` の定義開始。
- **なぜ**：SSFM の各ステップ（線形/非線形）や propagate 本体を分離し、テストしやすくする。
- **講師メモ**：`propagate!` は副作用というより“状態を更新しつつ結果も返す”設計。`!` はその意図の表明。

---

## L149

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
              γ_here::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L150

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
              ω0::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L151

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
              ω::Vector{Float64},
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L152

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
              enable_spm::Bool,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L153

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
              enable_self_steepening::Bool)
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L154

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
    if γ_here == 0.0
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L155

**スコープ**：module NLSESolver > function N_op > if

**コード**：
```julia
        return zeros(ComplexF64, length(A))
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L156

**スコープ**：module NLSESolver > function N_op > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L157

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
    I  = abs2.(A)
```

**解説**：
- **何をしているか**：時間領域のパワー（強度）`I(t)=|A(t)|²` を作る。
- **注意**：この solver は `A` を **power envelope** として扱う設計（`|A|² = P[W]`）。電場振幅（V/m）ではない。

---

## L158

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
    S  = I .* A
```

**解説**：
- **何をしているか**：`S = |A|² A` を作る。
- **なぜ**：SPM の項は `i γ |A|² A`。self-steepening も `∂(|A|² A)/∂t` が登場するので共通因子としてまとめている。

---

## L159

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
    term_spm = enable_spm ? S : zero.(S)
```

**解説**：
- **何をしているか**：代入で `term_spm` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L160

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
    if enable_self_steepening
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L161

**スコープ**：module NLSESolver > function N_op > if

**コード**：
```julia
        Sω = fft(S)
```

**解説**：
- **何をしているか**：代入で `Sω` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L162

**スコープ**：module NLSESolver > function N_op > if

**コード**：
```julia
        dSdt = ifft(1im .* ω .* Sω)
```

**解説**：
- **何をしているか**：周波数領域で時間微分を計算（`∂/∂t` は `iω` に対応）。
- **なぜ**：有限差分より FFT 微分の方が高精度・高速になりやすい。
- **注意**：FFT 微分は周期境界条件を暗黙に仮定する。時間窓端で信号がゼロに落ちていないと“巻き込み誤差”が出る。

---

## L163

**スコープ**：module NLSESolver > function N_op > if

**コード**：
```julia
        term_ss = (1im/ω0) .* dSdt
```

**解説**：
- **何をしているか**：代入で `term_ss` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L164

**スコープ**：module NLSESolver > function N_op > if

**コード**：
```julia
    else
```

**解説**：
- **何をしているか**：`else`。
- **なぜ**：上の条件に当てはまらないケースの処理をまとめる。

---

## L165

**スコープ**：module NLSESolver > function N_op > if

**コード**：
```julia
        term_ss = zero.(S)
```

**解説**：
- **何をしているか**：代入で `term_ss` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L166

**スコープ**：module NLSESolver > function N_op > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L167

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
    return 1im * γ_here .* (term_spm .+ term_ss)
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L168

**スコープ**：module NLSESolver > function N_op

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`function N_op` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L169

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L170

**スコープ**：module NLSESolver

**コード**：
```julia
"非線形ステップを z 方向に RK4 で進める"
```

**解説**：
- **何をしているか**：短い docstring（1行版）。直後の関数/型の説明になる。
- **なぜ**：ヘルプとして残しつつ、コードの見通しも良くする。
- **注意**：コメント `#` と違い、docstring は `?` で参照される。

---

## L171

**スコープ**：module NLSESolver

**コード**：
```julia
function nonlinear_step_rk4(A::Vector{ComplexF64},
```

**解説**：
- **何をしているか**：関数 `nonlinear_step_rk4` の定義開始。
- **なぜ**：SSFM の各ステップ（線形/非線形）や propagate 本体を分離し、テストしやすくする。
- **講師メモ**：`propagate!` は副作用というより“状態を更新しつつ結果も返す”設計。`!` はその意図の表明。

---

## L172

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
                            dz::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L173

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
                            γ_here::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L174

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
                            ω0::Float64,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L175

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
                            ω::Vector{Float64},
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L176

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
                            enable_spm::Bool,
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L177

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
                            enable_self_steepening::Bool)
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L178

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
    if γ_here == 0.0
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L179

**スコープ**：module NLSESolver > function nonlinear_step_rk4 > if

**コード**：
```julia
        return A
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L180

**スコープ**：module NLSESolver > function nonlinear_step_rk4 > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L181

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
    if !enable_spm && !enable_self_steepening
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L182

**スコープ**：module NLSESolver > function nonlinear_step_rk4 > if

**コード**：
```julia
        return A
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L183

**スコープ**：module NLSESolver > function nonlinear_step_rk4 > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L184

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
    k1 = N_op(A, γ_here, ω0, ω, enable_spm, enable_self_steepening)
```

**解説**：
- **何をしているか**：RK4 の 1段目（`k1`）を計算。
- **なぜ**：非線形項は時間領域で非線形なので、単純な指数作用素（解析的 exp）を使いにくい。RK4 で z 積分している。
- **注意**：RK4 は安定だがコストは4回 N_op。計算が重いときは SSFM の指数近似（`A*=exp(iγ|A|²dz)`）に戻す選択肢もある。

---

## L185

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
    k2 = N_op(A .+ 0.5 * dz .* k1, γ_here, ω0, ω, enable_spm, enable_self_steepening)
```

**解説**：
- **何をしているか**：代入で `k2` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L186

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
    k3 = N_op(A .+ 0.5 * dz .* k2, γ_here, ω0, ω, enable_spm, enable_self_steepening)
```

**解説**：
- **何をしているか**：代入で `k3` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L187

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
    k4 = N_op(A .+ dz .* k3,      γ_here, ω0, ω, enable_spm, enable_self_steepening)
```

**解説**：
- **何をしているか**：代入で `k4` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L188

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
    return A .+ (dz/6.0) .* (k1 .+ 2k2 .+ 2k3 .+ k4)
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L189

**スコープ**：module NLSESolver > function nonlinear_step_rk4

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`function nonlinear_step_rk4` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L190

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L191

**スコープ**：module NLSESolver

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：docstring（ドキュメント文字列）の開始。
- **なぜ**：直後の関数（または型）にヘルプ文を付け、`?名前` で参照できるようにする。
- **読み方**：ここから次の `"""` までが“人間向け仕様”。実装とズレると事故るので要注意。

---

## L192

**スコープ**：module NLSESolver

**コード**：
```julia
伝搬本体
```

**解説**：
- **何をしているか**：docstring の本文。
- **この行の内容**：`伝搬本体`
- **講師メモ**：ここは“利用者に約束している仕様”なので、後でコードをいじるときに必ず整合を取る。

---

## L193

**スコープ**：module NLSESolver

**コード**：
```julia
- A0: z = z_min での初期包絡（電場）
```

**解説**：
- **何をしているか**：docstring の本文。
- **この行の内容**：`- A0: z = z_min での初期包絡（電場）`
- **講師メモ**：ここは“利用者に約束している仕様”なので、後でコードをいじるときに必ず整合を取る。

---

## L194

**スコープ**：module NLSESolver

**コード**：
```julia
- cfg: NLSEConfig
```

**解説**：
- **何をしているか**：docstring の本文。
- **この行の内容**：`- cfg: NLSEConfig`
- **講師メモ**：ここは“利用者に約束している仕様”なので、後でコードをいじるときに必ず整合を取る。

---

## L195

**スコープ**：module NLSESolver

**コード**：
```julia
返り値:
```

**解説**：
- **何をしているか**：docstring の本文。
- **この行の内容**：`返り値:`
- **講師メモ**：ここは“利用者に約束している仕様”なので、後でコードをいじるときに必ず整合を取る。

---

## L196

**スコープ**：module NLSESolver

**コード**：
```julia
- A_end: 出口の包絡
```

**解説**：
- **何をしているか**：docstring の本文。
- **この行の内容**：`- A_end: 出口の包絡`
- **講師メモ**：ここは“利用者に約束している仕様”なので、後でコードをいじるときに必ず整合を取る。

---

## L197

**スコープ**：module NLSESolver

**コード**：
```julia
- Itz: 時間強度 vs z（nt × nz_frames）
```

**解説**：
- **何をしているか**：docstring の本文。
- **この行の内容**：`- Itz: 時間強度 vs z（nt × nz_frames）`
- **講師メモ**：ここは“利用者に約束している仕様”なので、後でコードをいじるときに必ず整合を取る。

---

## L198

**スコープ**：module NLSESolver

**コード**：
```julia
- Ifz: スペクトル強度 vs z（nt × nz_frames）
```

**解説**：
- **何をしているか**：docstring の本文。
- **この行の内容**：`- Ifz: スペクトル強度 vs z（nt × nz_frames）`
- **講師メモ**：ここは“利用者に約束している仕様”なので、後でコードをいじるときに必ず整合を取る。

---

## L199

**スコープ**：module NLSESolver

**コード**：
```julia
- beam_hist: (wx=..., wy=..., Aeff=...) NamedTuple of beam history arrays
```

**解説**：
- **何をしているか**：docstring の本文。
- **この行の内容**：`- beam_hist: (wx=..., wy=..., Aeff=...) NamedTuple of beam history arrays`
- **講師メモ**：ここは“利用者に約束している仕様”なので、後でコードをいじるときに必ず整合を取る。

---

## L200

**スコープ**：module NLSESolver

**コード**：
```julia
"""
```

**解説**：
- **何をしているか**：docstring の終了。
- **注意**：閉じ忘れは構文エラーになる。

---

## L201

**スコープ**：module NLSESolver

**コード**：
```julia
function propagate!(A0::Vector{ComplexF64}, cfg::NLSEConfig)
```

**解説**：
- **何をしているか**：関数 `propagate!` の定義開始。
- **なぜ**：SSFM の各ステップ（線形/非線形）や propagate 本体を分離し、テストしやすくする。
- **講師メモ**：`propagate!` は副作用というより“状態を更新しつつ結果も返す”設計。`!` はその意図の表明。

---

## L202

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    A = copy(A0)
```

**解説**：
- **何をしているか**：代入で `A` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L203

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    nt = length(cfg.t)
```

**解説**：
- **何をしているか**：代入で `nt` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L204

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    Nz = length(cfg.z_mm) - 1
```

**解説**：
- **何をしているか**：代入で `Nz` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L205

**スコープ**：module NLSESolver > function propagate!

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L206

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    nz_frames = Nz + 1
```

**解説**：
- **何をしているか**：代入で `nz_frames` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L207

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    Itz = zeros(Float64, nt, nz_frames)
```

**解説**：
- **何をしているか**：代入で `Itz` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L208

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    Ifz = zeros(Float64, nt, nz_frames)
```

**解説**：
- **何をしているか**：代入で `Ifz` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L209

**スコープ**：module NLSESolver > function propagate!

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L210

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    # beam history arrays
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L211

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    wx_hist   = zeros(Float64, nz_frames)
```

**解説**：
- **何をしているか**：代入で `wx_hist` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L212

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    wy_hist   = zeros(Float64, nz_frames)
```

**解説**：
- **何をしているか**：代入で `wy_hist` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L213

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    Aeff_hist = zeros(Float64, nz_frames)
```

**解説**：
- **何をしているか**：代入で `Aeff_hist` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L214

**スコープ**：module NLSESolver > function propagate!

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L215

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    # z = z_min
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L216

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    Itz[:, 1] .= abs2.(A)
```

**解説**：
- **何をしているか**：代入で `Itz[:, 1] .` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L217

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    S0 = fft(A)
```

**解説**：
- **何をしているか**：代入で `S0` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L218

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    Ifz[:, 1] .= fftshift(abs2.(S0))
```

**解説**：
- **何をしているか**：代入で `Ifz[:, 1] .` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L219

**スコープ**：module NLSESolver > function propagate!

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L220

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    # initialise q-parameters and beam history at z_min
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L221

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    qx = cfg.qx0
```

**解説**：
- **何をしているか**：代入で `qx` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L222

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    qy = cfg.qy0
```

**解説**：
- **何をしているか**：代入で `qy` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L223

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    if cfg.enable_self_focusing
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L224

**スコープ**：module NLSESolver > function propagate! > if

**コード**：
```julia
        Aeff_0, wx_0, wy_0 = Aeff_from_q(qx, qy, cfg.λ0)
```

**解説**：
- **何をしているか**：代入で `Aeff_0, wx_0, wy_0` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L225

**スコープ**：module NLSESolver > function propagate! > if

**コード**：
```julia
        wx_hist[1]   = wx_0
```

**解説**：
- **何をしているか**：代入で `wx_hist[1]` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L226

**スコープ**：module NLSESolver > function propagate! > if

**コード**：
```julia
        wy_hist[1]   = wy_0
```

**解説**：
- **何をしているか**：代入で `wy_hist[1]` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L227

**スコープ**：module NLSESolver > function propagate! > if

**コード**：
```julia
        Aeff_hist[1] = Aeff_0
```

**解説**：
- **何をしているか**：代入で `Aeff_hist[1]` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L228

**スコープ**：module NLSESolver > function propagate! > if

**コード**：
```julia
    else
```

**解説**：
- **何をしているか**：`else`。
- **なぜ**：上の条件に当てはまらないケースの処理をまとめる。

---

## L229

**スコープ**：module NLSESolver > function propagate! > if

**コード**：
```julia
        z_min_mm = cfg.z_mm[1]
```

**解説**：
- **何をしているか**：代入で `z_min_mm` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L230

**スコープ**：module NLSESolver > function propagate! > if

**コード**：
```julia
        wx_hist[1]   = Beam.wx(cfg.beam, z_min_mm)
```

**解説**：
- **何をしているか**：代入で `wx_hist[1]` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L231

**スコープ**：module NLSESolver > function propagate! > if

**コード**：
```julia
        wy_hist[1]   = Beam.wy(cfg.beam, z_min_mm)
```

**解説**：
- **何をしているか**：代入で `wy_hist[1]` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L232

**スコープ**：module NLSESolver > function propagate! > if

**コード**：
```julia
        Aeff_hist[1] = Beam.A_eff(cfg.beam, z_min_mm)
```

**解説**：
- **何をしているか**：代入で `Aeff_hist[1]` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L233

**スコープ**：module NLSESolver > function propagate! > if

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L234

**スコープ**：module NLSESolver > function propagate!

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L235

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    for iz in 1:Nz
```

**解説**：
- **何をしているか**：`for` ループ開始。
- **なぜ**：z ステップ `iz` を 1..Nz で回して SSFM を進める。
- **注意（単位）**：このループでは `z_here_mm`（mm）と `cfg.dz`（m）を同時に扱う。混ぜない。

---

## L236

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        z_here_mm = cfg.z_mm[iz]
```

**解説**：
- **何をしているか**：代入で `z_here_mm` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L237

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        z_next_mm = cfg.z_mm[iz+1]
```

**解説**：
- **何をしているか**：代入で `z_next_mm` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L238

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        z_mid_mm  = 0.5 * (z_here_mm + z_next_mm)
```

**解説**：
- **何をしているか**：代入で `z_mid_mm` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L239

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L240

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        # Dispersion/nonlinearity coefficients (use midpoint for better coupling)
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L241

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        β2_here, β3_here, n2_here =
```

**解説**：
- **何をしているか**：代入で `β2_here, β3_here, n2_here` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L242

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
            Plates.coeffs_at_z(z_mid_mm, cfg.plates, cfg.beam, cfg.λ0)
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L243

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L244

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        if cfg.enable_self_focusing
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L245

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            # --- Self-focusing path (q-parameter) ---
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L246

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            # 1st beam half-step
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L247

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            Ppeak1 = maximum(abs2.(A))
```

**解説**：
- **何をしているか**：代入で `Ppeak1` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L248

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            qx, qy = beam_half_step(qx, qy;
```

**解説**：
- **何をしているか**：代入で `qx, qy` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L249

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
                dz_half=cfg.dz/2, n2_here=n2_here, Ppeak=Ppeak1,
```

**解説**：
- **何をしているか**：代入で `dz_half` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L250

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
                λ0=cfg.λ0, enable_self_focusing=true)
```

**解説**：
- **何をしているか**：代入で `λ0` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L251

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            Aeff_mid, _wx_mid, _wy_mid = Aeff_from_q(qx, qy, cfg.λ0)
```

**解説**：
- **何をしているか**：代入で `Aeff_mid, _wx_mid, _wy_mid` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L252

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            if cfg.aeff_min_m2 > 0.0 && Aeff_mid < cfg.aeff_min_m2
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L253

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                error("propagate!: Aeff dropped below minimum guard " *
```

**解説**：
- **何をしているか**：例外を投げて即停止。
- **なぜ**：ここに来たら“物理的に破綻（ビーム崩壊、非物理q）”という設計。
- **講師メモ**：最適化中に頻発するなら、（1）モデルの限界、（2）パラメータ探索範囲の過大、（3）ガード設定の不整合 を疑う。

---

## L254

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                      "(Aeff_mid=$(Aeff_mid) m² < aeff_min=$(cfg.aeff_min_m2) m²). " *
```

**解説**：
- **何をしているか**：代入で `"(Aeff_mid` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L255

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                      "Beam has collapsed (thin-lens approximation breakdown).")
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L256

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
            end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L257

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
        else
```

**解説**：
- **何をしているか**：`else`。
- **なぜ**：上の条件に当てはまらないケースの処理をまとめる。

---

## L258

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            # --- Existing beam-scaling path ---
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L259

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            if cfg.apply_beam_scaling
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L260

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                Aeff_here = Beam.A_eff(cfg.beam, z_here_mm)
```

**解説**：
- **何をしているか**：代入で `Aeff_here` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L261

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                Aeff_mid  = Beam.A_eff(cfg.beam, z_mid_mm)
```

**解説**：
- **何をしているか**：代入で `Aeff_mid` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L262

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                A .*= sqrt(Aeff_here / Aeff_mid)
```

**解説**：
- **何をしているか**：代入で `A .*` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L263

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
            end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L264

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            Aeff_mid = Beam.A_eff(cfg.beam, z_mid_mm)
```

**解説**：
- **何をしているか**：代入で `Aeff_mid` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L265

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
        end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L266

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L267

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        # gamma from current Aeff (power-envelope form)
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L268

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        γ_here = (n2_here == 0.0) ? 0.0 : (n2_here * cfg.ω0 / (c0 * Aeff_mid))
```

**解説**：
- **何をしているか**：非線形係数 γ を、現在の Aeff（中点）から計算。
- **式**：`γ = n2 ω0 / (c0 Aeff_mid)`（power-envelope 形式）。
- **注意**：self-focusing 有効時は `Aeff_mid` が q更新で変わる。無効時は `Beam.A_eff` で幾何学的収束を反映する。

---

## L269

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L270

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        # Inner NLSE: symmetric split-step (L/2 -> N -> L/2)
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L271

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        A = linear_step(A, cfg.dz/2, β2_here, β3_here, cfg.ω, cfg.enable_dispersion)
```

**解説**：
- **何をしているか**：対称SSFMの線形半ステップ（L/2）。
- **なぜ**：Strang splitting（対称分割）は 2次精度で、線形と非線形のカップリング誤差が小さい。
- **注意**：ここで β2,β3,n2 を中点 `z_mid` で評価しているのが“結合を良くする”ポイント。

---

## L272

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        A = nonlinear_step_rk4(A, cfg.dz,  γ_here, cfg.ω0, cfg.ω,
```

**解説**：
- **何をしているか**：代入で `A` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L273

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
                               cfg.enable_spm, cfg.enable_self_steepening)
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L274

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        A = linear_step(A, cfg.dz/2, β2_here, β3_here, cfg.ω, cfg.enable_dispersion)
```

**解説**：
- **何をしているか**：対称SSFMの線形半ステップ（L/2）。
- **なぜ**：Strang splitting（対称分割）は 2次精度で、線形と非線形のカップリング誤差が小さい。
- **注意**：ここで β2,β3,n2 を中点 `z_mid` で評価しているのが“結合を良くする”ポイント。

---

## L275

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L276

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        if cfg.enable_self_focusing
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L277

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            # 2nd beam half-step (Ppeak AFTER NLSE step)
```

**解説**：
- **何をしているか**：コメント。
- **なぜ**：アルゴリズムの意図（SSFM / self-focusing / 単位）を未来の自分に残す。
- **講師メモ**：このファイルは“物理モデルの前提”がコメントに埋まっている。コメントは仕様の一部だと思って読む。

---

## L278

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            Ppeak2 = maximum(abs2.(A))
```

**解説**：
- **何をしているか**：代入で `Ppeak2` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L279

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            qx, qy = beam_half_step(qx, qy;
```

**解説**：
- **何をしているか**：代入で `qx, qy` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L280

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
                dz_half=cfg.dz/2, n2_here=n2_here, Ppeak=Ppeak2,
```

**解説**：
- **何をしているか**：代入で `dz_half` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L281

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
                λ0=cfg.λ0, enable_self_focusing=true)
```

**解説**：
- **何をしているか**：代入で `λ0` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L282

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            Aeff_now, wx_now, wy_now = Aeff_from_q(qx, qy, cfg.λ0)
```

**解説**：
- **何をしているか**：代入で `Aeff_now, wx_now, wy_now` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L283

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            if cfg.aeff_min_m2 > 0.0 && Aeff_now < cfg.aeff_min_m2
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L284

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                error("propagate!: Aeff dropped below minimum guard " *
```

**解説**：
- **何をしているか**：例外を投げて即停止。
- **なぜ**：ここに来たら“物理的に破綻（ビーム崩壊、非物理q）”という設計。
- **講師メモ**：最適化中に頻発するなら、（1）モデルの限界、（2）パラメータ探索範囲の過大、（3）ガード設定の不整合 を疑う。

---

## L285

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                      "(Aeff_now=$(Aeff_now) m² < aeff_min=$(cfg.aeff_min_m2) m²). " *
```

**解説**：
- **何をしているか**：代入で `"(Aeff_now` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L286

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                      "Beam has collapsed (thin-lens approximation breakdown).")
```

**解説**：
- **何をしているか**：実行行。
- **講師メモ**：この行が参照している変数の“意味（物理量）と単位”を、直前で必ず確認する。

---

## L287

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
            end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L288

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
        else
```

**解説**：
- **何をしているか**：`else`。
- **なぜ**：上の条件に当てはまらないケースの処理をまとめる。

---

## L289

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            if cfg.apply_beam_scaling
```

**解説**：
- **何をしているか**：条件分岐 `if` の開始。
- **なぜ**：物理的に意味が無い/危険なケースを早期に弾く（q=0、Aeff≤0、係数ゼロなど）。
- **講師メモ**：この solver は“落とすべき異常（error）”と“スキップする異常”を分けている。どっちが正しいかは運用（最適化/本番計算）で決める。

---

## L290

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                Aeff_mid  = Beam.A_eff(cfg.beam, z_mid_mm)
```

**解説**：
- **何をしているか**：代入で `Aeff_mid` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L291

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                Aeff_next = Beam.A_eff(cfg.beam, z_next_mm)
```

**解説**：
- **何をしているか**：代入で `Aeff_next` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L292

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
                A .*= sqrt(Aeff_mid / Aeff_next)
```

**解説**：
- **何をしているか**：代入で `A .*` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L293

**スコープ**：module NLSESolver > function propagate! > for > if > if

**コード**：
```julia
            end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L294

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            wx_now   = Beam.wx(cfg.beam, z_next_mm)
```

**解説**：
- **何をしているか**：代入で `wx_now` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L295

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            wy_now   = Beam.wy(cfg.beam, z_next_mm)
```

**解説**：
- **何をしているか**：代入で `wy_now` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L296

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
            Aeff_now = Beam.A_eff(cfg.beam, z_next_mm)
```

**解説**：
- **何をしているか**：代入で `Aeff_now` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L297

**スコープ**：module NLSESolver > function propagate! > for > if

**コード**：
```julia
        end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`if` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L298

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L299

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        Itz[:, iz+1] .= abs2.(A)
```

**解説**：
- **何をしているか**：この z 点での時間パワー波形を保存（`Itz`）。
- **なぜ**：後で B積分、ピーク強度、最適化指標（FWHMなど）を z 方向に追跡したい。
- **注意**：`Itz` の定義が“パワー”であることが、metrics 側の強度計算と直結する。

---

## L300

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        S = fft(A)
```

**解説**：
- **何をしているか**：代入で `S` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L301

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        Ifz[:, iz+1] .= fftshift(abs2.(S))
```

**解説**：
- **何をしているか**：スペクトル強度を保存（`Ifz`）。
- **なぜ**：スペクトル広がりや圧縮可能性（FTL幅）を見るため。
- **注意**：`fftshift` しているので周波数軸の並び（負→正）が中央に来る。プロット側も同じ前提にする。

---

## L302

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L303

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        wx_hist[iz+1]   = wx_now
```

**解説**：
- **何をしているか**：代入で `wx_hist[iz+1]` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L304

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        wy_hist[iz+1]   = wy_now
```

**解説**：
- **何をしているか**：代入で `wy_hist[iz+1]` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L305

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
        Aeff_hist[iz+1] = Aeff_now
```

**解説**：
- **何をしているか**：代入で `Aeff_hist[iz+1]` を更新/定義。
- **なぜ**：途中結果を名前付き変数に置くことで、デバッグと物理チェックがしやすくなる。
- **注意**：単位（m/mm, W, rad/s）を暗黙に持つ変数が多い。変数名だけでなくコメント/呼び出し元で単位を確認する癖を付ける。

---

## L306

**スコープ**：module NLSESolver > function propagate! > for

**コード**：
```julia
    end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`for` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L307

**スコープ**：module NLSESolver > function propagate!

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L308

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    beam_hist = (wx=wx_hist, wy=wy_hist, Aeff=Aeff_hist)
```

**解説**：
- **何をしているか**：ビーム履歴を NamedTuple にまとめて返す。
- **なぜ**：`wx(z), wy(z), Aeff(z)` がわかれば、自己収束の挙動や安全判定（Aeff_min）を後から解析できる。
- **注意**：metrics 側が `Aeff_hist` を受け取れるようになっているのは、この返り値を想定している。

---

## L309

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
    return A, Itz, Ifz, beam_hist
```

**解説**：
- **何をしているか**：値を返して関数を終了。
- **なぜ**：ガード条件で早期return、または最終結果を返す。
- **注意**：`propagate!` は `A, Itz, Ifz, beam_hist` を返す。呼び出し側は順番を間違えると悲惨。

---

## L310

**スコープ**：module NLSESolver > function propagate!

**コード**：
```julia
end
```

**解説**：
- **何をしているか**：ブロック終端（`end`）。
- **どれを閉じた？**：`function propagate!` を閉じる（スタック推定）。
- **注意**：対応がズレると構文エラー。長い関数ほど `end` 対応は見失いやすいので、エディタの構造表示を使うと良い。

---

## L311

**スコープ**：module NLSESolver

**コード**：
*（空行）*

**解説**：
- **何をしているか**：空行。
- **なぜ**：セクションや関数の区切りを明確にして読みやすくする（実行には無関係）。

---

## L312

**スコープ**：module NLSESolver

**コード**：
```julia
end # module
```

**解説**：
- **何をしているか**：モジュールの終端。
- **なぜ**：`module NLSESolver` のスコープを閉じる。
- **注意**：外部から見えるのは `export` したもの＋修飾アクセス可能な内部定義。

---

