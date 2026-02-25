# `config.jl` の1行ずつ解説

このファイルは **「実行条件の単一の真実（Single Source of Truth）」**です。  
`main_focus_withplots.jl`（単発実行）と `optimize_plates.jl`（最適化）が、ここに書かれた値を参照して動きます。

> 重要：この `config.jl` の中では `Material.Si_48um` など **Materialモジュールの定数**を参照しています。  
> そのため、読み込み順序として **先に `material.jl` を `include` して `Material` を使える状態にしてから**、この `config.jl` を読み込む必要があります。

---

## 対象ファイル（そのまま）

```julia
# ========== パルス条件 ==========
λ0       = 4.8e-6        # 中心波長 [m]
Ep       = 50e-6        # パルスエネルギー [J]
τ_fwhm   = 100e-15       # パルス幅 FWHM [s]

# ========== 時間グリッド ==========
T_window = 2e-12         # 時間窓 [s]
N        = 2^14          # グリッド点数

# ========== 空間グリッド ==========
z_min_mm = 0.0           # [mm]
z_max_mm = 50.0          # [mm]
Nz       = 4000

# ========== ビーム設定 ==========
BEAM_MODE = :focus    # :constant or :focus

# constant beam
const_diam_x_mm = 2      # [mm]
const_diam_y_mm = 2      # [mm]

# focused beam (knife-edge)
focus_w0x_mm = 0.125
focus_z0x_mm = 25.0
focus_zRx_mm = 0.9
focus_w0y_mm = 0.057
focus_z0y_mm = 24.9
focus_zRy_mm = 0.5
focus_waist_is_diameter = true

# ========== 非線形トグル ==========
ENABLE_SPM             = true
ENABLE_SELF_STEEPENING = true
ENABLE_SELF_FOCUSING   = true

# ========== プレート定義 ==========
# main用: Plate(z_start, z_end, material, β2, β3, I_damage)
plate_defs = [
    (z_start=8.0, z_end=13.0, material=Material.Si_48um, β2=0.0, β3=0.0, I_damage=4.0e11),
]

# optimize用: PlateSpec(material, thick, β2, β3, I_damage, z_init, fixed, z_range)
plate_specs_defs = [
    (mat=Material.Si_48um, thick=2.0, β2=316, β3=0.0, I_damage=4.0e11, z_init=3.0,  fixed=false,  z_range=(0.0, 10.0)),
    (mat=Material.NaCl_48um, thick=2.0, β2=-112, β3=0.0, I_damage=1.0e13, z_init=8.0,  fixed=false, z_range=(25.0, 29.0)),
    (mat=Material.Si_48um, thick=2.0, β2=316, β3=0.0, I_damage=4.0e11, z_init=14.0, fixed=false, z_range=(35.0, 45.0)),
    (mat=Material.CaF2_48um, thick=1.0, β2=-500, β3=0.0, I_damage=1.0e13, z_init=49.0, fixed=true, z_range=(15.0, 25.0)),
]

# ========== 制約・安全設定 ==========
B_WARN_PER_PLATE_RAD  = π
B_LIMIT_PER_PLATE_RAD = 2.0π
I_SAFETY_FACTOR       = 1.5
LIMIT_ACTION          = :warn   # :warn or :error

# ========== Aeff ガード設定 ==========
# 0.0 = 無効; Kerr薄レンズ近似の破綻を早期に検出するためのAeff下限 [m²]
# 典型例: 10 × 回折限界 = 10 × λ0²/π ≈ 7.3e-11 m² (@λ0=4.8μm)
AEFF_MIN_GUARD_M2 = 0.0

# ========== 最適化設定 ==========
OPT_MAX_EVALS   = 300
OPT_N_RESTARTS  = 3
OPT_λ_OVERLAP   = 1e4
OPT_λ_B         = 1e2
```

---

## 1行ずつ解説（L1〜）

### L1 `# ========== パルス条件 ==========`
- ここから「入力パルスの物理条件」をまとめるセクション、という見出し。
- 実行には影響しないが、設定の読みやすさを上げる。

### L2 `λ0       = 4.8e-6        # 中心波長 [m]`
- 中心波長 `λ0` を **メートル単位**で指定（4.8 µm）。
- `NLSE_solver_focus.jl` 側で `ω0 = 2πc/λ0` や、self-steepening 係数（`1/ω0`）などに使われる。
- 単位を間違えると（µmのつもりでmにしない等）すべて崩壊する、最重要パラメータ。

### L3 `Ep       = 50e-6        # パルスエネルギー [J]`
- 入力パルスのエネルギー（50 µJ）。
- `main_focus_withplots.jl` では、この `Ep` と `τ_fwhm` からピークパワー `P0` を作るために使われる（ガウシアン換算係数が入る設計）。
- 「|A|^2 = P[W]」のパワー包絡の流儀なので、最終的に A0 の規格化に効く。

### L4 `τ_fwhm   = 100e-15       # パルス幅 FWHM [s]`
- 入力パルスの時間幅（100 fs, FWHM）。
- `Ep` とセットでピークパワー推定に使われ、非線形量（B積分、スペクトル広がり、損傷判定）に直結する。

### L5 （空行）
- 見やすさのため。機能は変わらない。

---

### L6 `# ========== 時間グリッド ==========`
- 時間軸（t軸）の離散化設定の見出し。

### L7 `T_window = 2e-12         # 時間窓 [s]`
- シミュレーションで扱う時間窓（±ではなく全幅のつもりで 2 ps を置いている設計が多い）。
- 窓が狭すぎるとパルスやチャープ成分が窓外へ出て **周期境界（FFT前提）で折り返し**事故が起きる。
- 窓が広すぎると dt が粗くなる（N固定なら）ので、分解能が落ちる。

### L8 `N        = 2^14          # グリッド点数`
- 時間サンプル数。`2^14 = 16384`。
- FFTを多用するので 2の冪が都合が良い。
- dt は `dt = T_window/N` で決まる。dtが大きいと self-steepening の時間微分や高周波成分が壊れる。

### L9 （空行）
- 見やすさのため。

---

### L10 `# ========== 空間グリッド ==========`
- z方向（伝搬方向）の離散化設定の見出し。

### L11 `z_min_mm = 0.0           # [mm]`
- 伝搬計算の開始位置。単位は **mm**。
- あなたのコード設計は「外部に見せるzはmm」で統一しており、内部でmに変換する箇所がある（混乱防止としては良い方針）。

### L12 `z_max_mm = 50.0          # [mm]`
- 伝搬計算の終了位置（50 mm）。
- plate_defs の z_start/z_end と整合している必要がある。範囲外のプレートを定義すると無視される／意図せず空になる等が起きる。

### L13 `Nz       = 4000`
- z方向のステップ数（= 分割数）。
- ステップ幅は `dz ≈ (z_max_mm - z_min_mm)/Nz`（mm → m変換込み）で決まる。
- self-focusing を入れている場合、dzが大きいと thin-lens 近似の破綻が早く出る。

### L14 （空行）
- 見やすさのため。

---

### L15 `# ========== ビーム設定 ==========`
- ビーム（空間モード）設定の見出し。

### L16 `BEAM_MODE = :focus    # :constant or :focus`
- ビームモデルのモード選択。
  - `:constant`：ビーム径を一定として扱う（Aeff一定）
  - `:focus`：外部集光（knife-edgeフィット等）の z 依存 w(z) を使う
- `main_focus_withplots.jl` で分岐に使われ、`Beam.constant_beam(...)` や `Beam.knifeedge_beam(...)` の生成を切り替える。

### L17 （空行）
- 見やすさのため。

---

### L18 `# constant beam`
- `BEAM_MODE == :constant` のときに使うパラメータ群の見出し。

### L19 `const_diam_x_mm = 2      # [mm]`
- x方向のビーム直径（mm）。
- 実装側で「直径→半径」に直して使うはずなので、どちらで入れるか（diameterかradiusか）を揃えるのが重要。

### L20 `const_diam_y_mm = 2      # [mm]`
- y方向のビーム直径（mm）。
- xとyを分けているので、楕円ビームも設定できる。

### L21 （空行）
- 見やすさのため。

---

### L22 `# focused beam (knife-edge)`
- `BEAM_MODE == :focus` のときに使う「knife-edgeフィット（ガウシアンビーム）」のパラメータ群。

### L23 `focus_w0x_mm = 0.125`
- x方向のビームウエスト（w0x）。単位mm。
- “w0”が「半径」なのか「直径」なのかがややこしいので、L29でフラグを持たせている。

### L24 `focus_z0x_mm = 25.0`
- x方向のウエスト位置 z0x（mm）。
- `w(z) = w0 * sqrt(1 + ((z - z0)/zR)^2)` の z0 に入る。

### L25 `focus_zRx_mm = 0.9`
- x方向のレイリー長 zRx（mm）。
- zRが小さいほど急峻に集光する（＝強度が上がりやすい）ので、非線形や損傷に直結する。

### L26 `focus_w0y_mm = 0.057`
- y方向のビームウエスト w0y（mm）。
- xとyで異なる値なので楕円（非対称）集光を表現できる。

### L27 `focus_z0y_mm = 24.9`
- y方向のウエスト位置 z0y（mm）。

### L28 `focus_zRy_mm = 0.5`
- y方向のレイリー長 zRy（mm）。

### L29 `focus_waist_is_diameter = true`
- w0x/w0y が「直径として入力されているか」を示すフラグ。
- true なら内部で 1/2 して“半径”に直す想定。
- ここが間違うと Aeff が4倍ズレる→γが4倍ズレる→B積分や損傷が致命的にズレる、最重要フラグの1つ。

### L30 （空行）
- 見やすさのため。

---

### L31 `# ========== 非線形トグル ==========`
- NLSE内にどの非線形項を入れるかのスイッチ群。

### L32 `ENABLE_SPM             = true`
- SPM（自己位相変調）項を有効化。
- false にすると非線形スペクトル広がりが基本消える（分散だけの線形伝搬になる）。

### L33 `ENABLE_SELF_STEEPENING = true`
- self-steepening（光学ショック）項を有効化。
- 時間微分を含むので dt 設計が甘いと数値が壊れやすい。

### L34 `ENABLE_SELF_FOCUSING   = true`
- Kerr薄レンズ近似による自己収束（qパラメータ更新）を有効化。
- true なら「ビームのz依存は内部で動的に決まる」ため、外部集光スケーリングとの二重カウントを避ける設計になっているはず（solver側で排他）。

### L35 （空行）
- 見やすさのため。

---

### L36 `# ========== プレート定義 ==========`
- z方向に置く媒質（プレート）定義の見出し。  
- このプロジェクトでは「main用」と「optimize用」で定義形式が2種類ある。

### L37 `# main用: Plate(z_start, z_end, material, β2, β3, I_damage)`
- main（単発実行）で使う定義形式の説明コメント。
- ここでの β2/β3 は **plate内の分散**で、単位系は Plate側の実装に依存（多くは fs²/mm, fs³/mm を想定）。

### L38 `plate_defs = [`
- `plate_defs` という配列を作り始める。
- 1要素が1枚のプレート（区間）を表す。

### L39 `    (z_start=8.0, z_end=13.0, material=Material.Si_48um, β2=0.0, β3=0.0, I_damage=4.0e11),`
- 1枚目のプレートを NamedTuple で定義。
  - `z_start=8.0`, `z_end=13.0`：プレートが存在する z区間 [mm]
  - `material=Material.Si_48um`：Material側の定数（n2など）を参照
  - `β2=0.0, β3=0.0`：分散をゼロ扱い（意図があるならOK、ミスなら致命的）
  - `I_damage=4.0e11`：損傷閾値（W/cm²想定で使っている実装が多い）
- ここは main の挙動を完全に決めるので、手動でいじる前提の“実験条件”領域。

### L40 `]`
- `plate_defs` 配列の終端。

### L41 （空行）
- 見やすさのため。

---

### L42 `# optimize用: PlateSpec(material, thick, β2, β3, I_damage, z_init, fixed, z_range)`
- 最適化で使う “PlateSpec” 的な定義形式の説明。
- thick（厚み）と z_init, z_range が入り、**z_startを変数として動かせる**のが main用との違い。

### L43 `plate_specs_defs = [`
- 最適化用の定義配列 `plate_specs_defs` の開始。

### L44 `    (mat=Material.Si_48um, thick=2.0, β2=316, β3=0.0, I_damage=4.0e11, z_init=3.0,  fixed=false,  z_range=(0.0, 10.0)),`
- 1枚目（Si）の仕様：
  - `thick=2.0`：厚み 2 mm（z_end = z_start + thick の形式で生成される想定）
  - `β2=316`：分散（符号・単位が重要。ここだけ値の桁が大きいので fs²/mm想定っぽい）
  - `z_init=3.0`：初期配置（探索の初期点）
  - `fixed=false`：位置を最適化変数として動かす
  - `z_range=(0.0,10.0)`：探索範囲（mm）
- `mat` というキー名になっているので、読み込み側が `mat` を期待している設計。

### L45 `    (mat=Material.NaCl_48um, thick=2.0, β2=-112, β3=0.0, I_damage=1.0e13, z_init=8.0,  fixed=false, z_range=(25.0, 29.0)),`
- 2枚目（NaCl）：
  - β2が負（異符号分散）で、分散補償や自己圧縮狙いの典型設定に見える。
  - I_damage が大きい（=壊れにくい材料として設定している意図）。
  - z_range が 25〜29 mm に限定されていて、ここだけ“置きたい場所が強く決まっている”設計。

### L46 `    (mat=Material.Si_48um, thick=2.0, β2=316, β3=0.0, I_damage=4.0e11, z_init=14.0, fixed=false, z_range=(35.0, 45.0)),`
- 3枚目（Si）：
  - 1枚目と同じ材料・分散・損傷閾値。
  - ただし探索範囲が 35〜45 mm と後段に置く設計。

### L47 `    (mat=Material.CaF2_48um, thick=1.0, β2=-500, β3=0.0, I_damage=1.0e13, z_init=49.0, fixed=true, z_range=(15.0, 25.0)),`
- 4枚目（CaF2）：
  - `fixed=true` なので、最適化では位置を動かさない“固定プレート”。
  - `z_init=49.0` が固定位置として使われるはず（`z_range` は fixed=true なら実質使われない／使うなら警告が欲しいポイント）。
  - β2が -500 とかなり強い負分散設定で、圧縮や分散補償要素として置いている意図に見える。
  - Material側の `CaF2_48um` は `n2=0.0` になっているので、ここでは非線形ではなく「分散専用」扱いの意図かもしれない（要注意）。

### L48 `]`
- `plate_specs_defs` 配列の終端。

### L49 （空行）
- 見やすさのため。

---

### L50 `# ========== 制約・安全設定 ==========`
- 安全判定（B積分、損傷閾値）と、違反時の扱いをまとめるセクション。

### L51 `B_WARN_PER_PLATE_RAD  = π`
- 1枚あたりのB積分（位相）で「警告」を出す閾値（π rad）。
- B積分は一般に経験的指標で、ここは運用ルールの領域。

### L52 `B_LIMIT_PER_PLATE_RAD = 2.0π`
- 1枚あたりのB積分で「制限（limit）」とする閾値（2π rad）。
- `2.0π` は Julia では `2.0 * π` と同じ意味（掛け算が省略記法で書ける）。

### L53 `I_SAFETY_FACTOR       = 1.5`
- 損傷閾値に対する安全係数。
- 実装では多くの場合 `I_peak * I_SAFETY_FACTOR <= I_damage` のように使う。
- 安全側に倒すほど、最適化で許容される領域が狭くなる（=保守的になる）。

### L54 `LIMIT_ACTION          = :warn   # :warn or :error`
- 閾値違反の扱い。
  - `:warn`：警告を出して計算は続行
  - `:error`：例外を投げて停止（最適化では infeasible 扱いに落とせる）
- 安定に最適化したいなら、通常は `:error` の方が探索が暴れにくい。

### L55 （空行）
- 見やすさのため。

---

### L56 `# ========== Aeff ガード設定 ==========`
- self-focusing（Kerr薄レンズ近似）を入れたときの“破綻検知”に関する設定の見出し。

### L57 `# 0.0 = 無効; Kerr薄レンズ近似の破綻を早期に検出するためのAeff下限 [m²]`
- `AEFF_MIN_GUARD_M2` の意味を説明するコメント。
- Aeffが極端に小さくなる（=ビームが潰れる）と、thin-lens近似も数値も壊れやすいので、そこで止めるためのガード。

### L58 `# 典型例: 10 × 回折限界 = 10 × λ0²/π ≈ 7.3e-11 m² (@λ0=4.8μm)`
- “目安”の計算例コメント。
- 回折限界スケール `~ λ0²/π` を基準にして、例えば 10倍を下限にする案を示している。

### L59 `AEFF_MIN_GUARD_M2 = 0.0`
- 現状は 0.0 なので **ガード無効**。
- self-focusing を `true` にしている（L34）ので、強い条件ではここが原因で最適化がノイジーになったり、破綻検知が遅れて変な解が紛れたりするリスクがある。

### L60 （空行）
- 見やすさのため。

---

### L61 `# ========== 最適化設定 ==========`
- `optimize_plates.jl`（BlackBoxOptim）で使う設定の見出し。

### L62 `OPT_MAX_EVALS   = 300`
- 1回の最適化で評価する回数の上限。
- 大きいほど探索は進むが、計算時間が直線的に増える。

### L63 `OPT_N_RESTARTS  = 3`
- 最適化を何回リスタートするか（初期点や乱数を変えて探索し直す回数）。
- 非凸問題ではローカル解に落ちやすいので、リスタートは有効。

### L64 `OPT_λ_OVERLAP   = 1e4`
- プレートが重なるなど「物理的にあり得ない配置」を罰するペナルティの重み（λ）。
- これが小さいと重なったまま良い目的関数に見えてしまう危険がある。

### L65 `OPT_λ_B         = 1e2`
- B積分超過などを罰するペナルティ重み。
- 目的（帯域最大化など）と安全制約（B抑制）のトレードオフをここで調整する。

---

## 率直な注意（この設定の“事故ポイント”）
- **L34がtrueなのにL59が0.0（ガード無効）**：強い条件で破綻が出ると探索が荒れる可能性。
- **L39のβ2=0, β3=0**：main側で分散ゼロ扱いになる。意図ならOK、ミスなら結果が全く別物になる。
- **L47のCaF2はMaterial側でn2=0.0**：分散専用のつもりならOKだが、CaF2のSPMを見たいなら値を入れないと“非線形ゼロ”になる。

