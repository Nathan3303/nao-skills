# 判据 · T555 纯 herdr 化（单后端 + 减重）· 只读设计稿

- 状态：待 PM 拍板（D1–D5）· 2026-11-22 · Owner：arch-designer · HEAD `e49bd13`
- 指针：PRD `docs/prds/2026-11-22-herdr-only.md` · ADR `docs/adr/2026-11-22-herdr-only.md` · Issue #156

## 0 数据通道（单后端后「后端事实」从哪来）

- **生产**：`NAO_TERMINAL` 仍是唯一赋值点（常量 `herdr`），`term_backend()` 收窄为守卫（无输出放行 / 非法值 exit 2）。**禁**读 `$TMUX` 判后端（herdr 从 tmux shell 起会渗句柄）、**禁**用空输出或 rc 承载「后端不可知」。
- **测试**：删 `be_backend()` 与 `NAO_TEST_TERMINAL`；`be_*` 恒 herdr，`be_herdr`（`--session` 注入）仍是唯一入口不动。设 `NAO_TEST_TERMINAL` 任意值 ⇒ run.sh rc=1 + 指路（fail loud，等价测试侧 S1）。
- **登记集**：删 `tests/t4/backends/herdr.txt` + run.sh 的注册器/`TMUX-ONLY`/`PENDING` 概念；用例清点单一事实 = `cases/*.sh` + `CASE_IDS`/`CASE_TITLE`，缺口由既有「新增用例未分类 ⇒ 参数错误」兜住；新增静态断言「`tests/t4/backends/` 不存在」。

## 1 基线（命令自测，非引用 PM 数字）

`wc -l .agents/scripts/nao-fleet.sh` = **5482**；`grep -cE '^[a-zA-Z_][A-Za-z0-9_]*\(\) *\{'` = **163** 函数；`grep -c -i tmux` = **341** 行（其中区间外 184 行 = 代码 79 + 注释 105）。

七区间（`# >>> term-impl-tmux BEGIN` 至 `END`，含标记行）：
`pane 定位 2609–2628 = 20` · `回收/自身/忙闲 2630–2826 = 197` · `pane 枚举/argv/在线 2863–2971 = 109` · `会话名/未归属 3067–3109 = 43` · `布局/窄列 3281–3367 = 87` · `spawn 3370–3512 = 143` · `pane cwd 3922–3937 = 16` ⇒ **合计 615 行**（与 QA 估 615 一致）。

- 区间内函数 **25** 个；区间外 tmux 专有函数 2 个（`require_tmux` 6 行 · `_term_tmux_snapshot` 14 行）⇒ **27 个函数整体消失（163 → ≈136，−16.6%）**。
  - **实测定稿（PM 订正 2026-11-22 · 关闭项）**：实际消失 **32 个**（163 → **131**）。差额 5 = D3「整组删」连带删掉的布局几何 `_layout_checksum` / `main_row2_geom` / `main_row2_min_col` / `main_col_right_w` / `build_main_row2_layout`。**这是 D3 拍板的预期后果，不是超范围删除**；herdr 侧函数零改动。
- 门面 tmux 臂 10 处（各 1 行）+ `tmux` 命令位 **64** 行 + `NAO_TERMINAL=tmux` 字面量 **21** 处（多数要改写为 fail loud 文案，不随之行）。
- 测试侧：`lib-backend.sh` 910 行 / 60 个 `be_*` / tmux 臂 19 处；`run.sh` 后端面 38 行；`run-dual.sh` 72 行；`herdr.txt` 47 行（登记 39 例，`# tmux-only: 12 25`）。
- 耗时参照：143-profile 的 herdr 单组全量 **774.907s**（34 例）。「单后端 ≤ 双后端 60%」必须在落地后同机实测，不得由本稿推断。
- **减重算式（关键）**：可删上限 = 615 + 79 + 105 = **799** 行（其中 `"tmuxPane"` 名册字段与 `_TERM_HOST_HANDLE_VARS` 必须在，实际可删略低）；必须新增 ≈20 行（守卫 + 两条 fail loud + 迁移指路）⇒ 净 **−13.5%~−14.2%**（落 ≈4700~4740 行）。PRD 要求的 −15% = 删 **≥823** 行，**在「只删不加」下不可达** ⇒ D1。

## 2 退役与迁移清单（断言数 = `grep -cE '^\s*t4_(assert|ok|bad|skip)'`）

- **12**（wrapper → 冻结脚本 12 断言）：**退役** 12→0。理由：tmux 宿主窗口显式寻址面不存在（`resolve_host_window` 随区间删）；herdr 放置由 32/33/40/29 覆盖。
- **25**（23 断言）：**退役** 23→0，理由：判据是 tmux 列宽算式 + 活体 pane 数，herdr 布局是 tab 拓扑（结构判据，不靠几何）；137/184 拍板值属 tmux 专有。若 D3 选「保留死配置」则改为「保留 M1/M3/M4（≈12）、删 M2 活体（≈11）」。
- **27**（85 断言）：**迁移** 85→78。删 tmux 臂 7 条 + 第 122 行「`_be_tmux` 裸调用」静态断言 1 条（对象消失 ⇒ 断言不成立）；herdr 侧 78 条逐字不动。
  - **QA 实测订正（2026-11-22）**：实际 **85 → 81（−4）**，herdr 侧 **81 条**。4 条全部落在 `case "$BE_NAME" in tmux)` 分支（生产 socket 锚点 2 + 实验 socket 2），herdr 分支仅**整体去缩进、逐字未动**。「7 条 tmux 臂」与「herdr 78 条」均不成立。
- **13**（13 断言）：**迁移** 13→13。①②③ 改为 fail loud 断言（rc=2 + 单行 stderr 含「已移除 / herdr / `--session`」）；⑥⑦ 迁移为 herdr 前提（`HERDR_SESSION` 空 ⇒ exit 3；pane list 空 + 名册空 ⇒ rc=0「未运行（无需回收）」）；④⑤ 保留（顺带覆盖「tmux 阶梯取值域仍为 0」）。
- **19 / 20 / 21 / 22 / 23 / 24**（65 / 81 / 40 / 72 / 79 / 42）：**迁移**。事实更正：这 6 例在登记集里是 `shared`，今天已在 herdr 后端跑绿，**并非「需真 tmux」**；仅删夹具分支 + 把 `backend-gate` NOTE 改成「tmux 面已删除」注记。
  - **QA 实测订正（2026-11-22）**：「断言数不变」不成立 —— 实测 **20 81→80、22 72→61、23 79→72**（21/24 确为不变）。减项**全部**在 `[ "$BE_NAME" = "tmux" ]` 分支内，herdr 侧同名断言全部保留 ⇒ 归类成立，但原文「tmux 臂内 0 条断言」是错的。
- **34**（58→59）：删 PATH 内 tmux 桩与「A4 仅 tmux 后端」行数断言（1 条，herdr 下本就未执行），新增「端前提声明含 `tmux` ⇒ warn 点名『已移除』且 rc 仍 0」（1 条）。
- **35 / 36**（83 / —）：只删 PATH 内 tmux 桩，断言不变。
- **`run-dual.sh` + `npm run test:t4:full:dual`**：整体删除；新增断言「package.json 无该 script」。发布前置 = `test:t4:full` 单组（原 full 语义）。

## 3 各态 wired（每态必 PASS 或 SKIP；禁 FAIL、禁静默）

1. `NAO_TERMINAL=tmux` + `ensure` ⇒ rc=2，stderr 恰 1 行含「已移除」「herdr」；PATH 桩 `herdr` 0 命中（零副作用）。
2. `NAO_TERMINAL=tmux` + `check` ⇒ rc 与文案（rc 取值见 D2）；不得静默按 herdr 跑。
3. `cleanup -S /tmp/x` ⇒ rc=2 + 指路 `--session <名>`；`-S` 用于非 cleanup 子命令 ⇒ 仍 rc=2（既有守卫保留）。
4. `cleanup --session default` 无 `--force` ⇒ 拒；带 `--force` ⇒ 执行（与 v0.27.0 逐字一致）；`--session nao-fleet` 不受影响。
5. `NAO_TEST_TERMINAL=tmux bash tests/t4/run.sh` ⇒ rc=1 + 指路（新增，测试侧 fail loud）。
6. `--case 12`（文件已删）⇒ 明确报「用例不存在」，**不得**退化为 PENDING/SKIP。
7. 环境缺失类（herdr 不在 PATH / 无 tsx）仍走既有 SKIP/DEGRADE + NOTE；其余一律 PASS。

## 4 静态 lint 设计（AC8）+ 变异自证

- 新 `t4_scan_tmux_residue <script>`：行级，命中 ①命令位 `(^|[|;&(]|\$\()[[:space:]]*(exec[[:space:]]+)?tmux([[:space:]]|$)` 或 ②`NAO_TERMINAL[[:space:]]*=[[:space:]]*["']?tmux`。
- 作用域：`.agents/scripts/*.sh` + `tests/t4/run.sh`（不扫 `docs/`：文档必须保留迁移指路）；旧 `t4_scan_term_bare_calls` 的 tmux 段与 `term-impl-tmux` 区间逻辑同时删除，只留 herdr 唯一入口判据。
- 允许名单（逐条注释，缺任一条即误伤）：① 名册字段 `"tmuxPane"`（外部 JSON 契约）② `_TERM_HOST_HANDLE_VARS=(TMUX TMUX_PANE TMUX_TMPDIR)`（herdr 起 server 前清宿主句柄）③ 注释/文案里「已移除 tmux」的迁移指路。
- **正控（必红）**：夹具副本追加 `tmux list-panes` 一行 ⇒ 命中并带行号；把守卫改成 `NAO_TERMINAL=tmux) :` ⇒ 命中 ②。**负控**：仅 `command -v tmux` 的迁移提示 ⇒ 不红。正控与负控各 1 条断言（仿 `t4_scan_term_herdr_forbidden` 的负控写法）。

## 5 禁改区

- `term-facade-herdr` 区间与全部 `_term_herdr_*`：**零 diff**（本批只删不加，不许「顺手优化 herdr」）。
- `_term_herdr_self_refuse` / `_term_herdr_busy` / `repo_contains_path` 归属谓词 / `_term_herdr_exec` 的 `--session` 唯一入口：逐字不动（AC7 的实体）。
- 命名契约 v2（`<role>(T<task>)` / 槽位）、`fleet_manifest_*`、`intercom-probe.mts` 契约：不动。
- `.agents/**` 与 `tests/**` 的实现由 RD 落；台账 `docs/tasks-state.md` 由 PM/RD 维护，本稿只读。

## 6 风险与否定条件

- **最大风险**：减重目标落空（净 ≈ −13.5~14.2% ≠ PRD −15%），若强行凑数必然去动 herdr 实现或降断言 ⇒ 违硬约束。**否定条件**：改动后 `wc -l` > 4750 或函数数 > 140 ⇒ 停批回 PM。
- fail loud 文案使 `check` 输出不再与 v0.27.0 逐字一致（AC1 措辞需改为「除 tmux 专有输出面外逐字一致」）。
- 存量 `NAO_TERMINAL=tmux`（用户 shell profile / CI / 下游脚本）一次性 rc=2：发布说明首屏必须给一行迁移。
- 静态 lint 过宽误伤（`tmuxPane` / 注释文案）或过窄空转：靠正控红 + 负控不红双向钉住。

## 7 待 PM 拍板

- **D1 减重口径**：A 改为「≥ −10% 且函数数 163→136」（推荐，可验证且不需第二轴）；B 追加第二轴（门面收直 + 单后端死分支，估 +50~80 行，仍 ≈ −14%）；C 只认函数数、不认行数。
- **D2 `NAO_TERMINAL=tmux` 的 rc**：2（用法守卫，与 `-S` 同口径，推荐）vs 1（体检失败，`check` 仍能出完整体检报告）。
- **D3 布局死配置**：`NAO_TMUX_LAYOUT|MAIN_WIDTH|MIN_PANE_WIDTH` 与 `check` 的「== tmux 布局 ==」节整组删（−29 行，用例 25 全退役）还是保留（check 输出不变、行数目标更难）。
- **D4 登记集去留**：删 `backends/` + 注册器（推荐，run.sh −38 行）vs 保留为纯清单（保留 PENDING 保护网）。
- **D5 AC1 边界**：是否接受「除 tmux 专有输出行外逐字一致」（D2/D3 任一采纳都会改变 `check` 文案）。
**PM 拍板（2026-11-22 · 用户睡眠期授权自主决定）**：
- **D1 = A**：「行数 ≥ −10% **且** 函数数 163→≤136」。理由：函数数是更诚实的指标；PRD 的 −15% 在「只删不加」下不可达，**不为凑数动 herdr 实现或降断言**（明确禁止的作弊路径）。
- **D2 = rc 2**（用法守卫，与 `-S` 同口径）。
- **D3 = 整组删**（`NAO_TMUX_LAYOUT|MAIN_WIDTH|MIN_PANE_WIDTH` + `check` 的 tmux 布局节，`cases/25` 全退役）—— 死配置跟着后端一起死。
- **D4 = 删** `backends/` + 注册器（run.sh −38 行）。理由：多后端时代才有「后端登记集」，单后端下它只剩一层可静默 PENDING 的壳，与「不静默」规矩相悖。
- **D5 = 接受**：AC1 收敛为「**除 tmux 专有输出行与已声明退役面外**，`ensure`/`status`/`close`/`cleanup` 输出逐字一致」。
