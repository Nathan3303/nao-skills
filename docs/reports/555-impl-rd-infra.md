# 实施报告 · T555 纯 herdr 化 + 脚本减重（rd-infra）

- 状态：待 PM 验收 · 更新：2026-11-22 · Owner：rd-infra
- 指针：PRD `docs/prds/2026-11-22-herdr-only.md` · ADR `docs/adr/2026-11-22-herdr-only.md` · 判据 `docs/reports/555-lite-spec.md`（§7 D1–D5 为最终口径）· Issue #156
- 基线：分支 `feat/555-herdr-only`，起点 `8bc9837`

## TL;DR

- **D1 达成**：`nao-fleet.sh` 5482 → **4531** 行（**−951 · −17.35%**，目标 ≤4933）；函数数 163 → **131**（目标 ≤136，**−32**，逐条清单见 §二）。
- **D2/D3/D4 达成**：旧后端变量 ⇒ rc=2 单行；`cleanup -S` ⇒ rc=2 指路 `--session`；`NAO_TMUX_*` 死配置与 check 布局节整组删；`tests/t4/backends/` + 注册器 + `run-dual.sh` 删除（run.sh −153 行）。
- **门禁**：`check` rc=0（连跑 2 次逐字一致）· 全量 T4 **39 例 PASS**（`RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=17）`）· `npm test` rc=0。
- **待 PM 裁一处偏离**：`term-facade-herdr` 区有 **9 行文案**改动（原「或 NAO_TERMINAL=tmux 回退」→ 迁移指路），**零逻辑 diff**；不删则文案指向已不存在的后端（判据 §5 的「零 diff」按字面未满足）。
- 退役断言 **84 条静态**（全部来自 tmux-only 分支/组），新增 `cases/41` 45 条 ⇒ 净 −39；逐条归因见 §三。

## 一、体量实测（D1）

- `wc -l .agents/scripts/nao-fleet.sh`：**5482 → 4531**（−951 行 = −17.35%；D1 口径「≥10% ⇒ ≤4933」，余量 402 行）。
- 函数数（`grep -cE '^[a-zA-Z_][A-Za-z0-9_]*\(\) *\{'`）：**163 → 131**（−32；D1 口径「≤136」，余量 5）。
- 其余体量：`tests/t4/lib-backend.sh` 910 → 761（−149）· `tests/t4/run.sh` −153 · 删除 `run-dual.sh`（72）· `tests/t4/backends/herdr.txt`（47）。
- 未动 herdr 实现（见 §五偏离说明）：`term-facade-herdr` 区间行数 1140 → 1140。

## 二、整体消失的函数（32 个）

`apply_main_col` · `apply_tmux_layout` · `build_main_row2_layout` · `fallback_pane_for` · `find_pane_by_title` · `find_pane_for` · `find_pane_for_any_repo` · `_layout_checksum` · `main_col_right_w` · `main_row2_geom` · `main_row2_min_col` · `pane_busy` · `pane_hosts_caller` · `pi_panes` · `pi_pids_for` · `prod_sock_candidates` · `require_tmux` · `resolve_host_window` · `roster_pane_claims` · `self_pane_refuse` · `spawn_tmux` · `_term_tmux_argv` · `_term_tmux_cleanup` · `_term_tmux_current_session` · `_term_tmux_deliver` · `_term_tmux_liveness` · `_term_tmux_names` · `_term_tmux_pane_cwds` · `_term_tmux_reclaim` · `_term_tmux_snapshot` · `tmux_pane_live` · `unattributed_pi_panes`

归口：七区间 25 个（判据 §1）+ 区间外 `require_tmux` / `_term_tmux_snapshot` + **布局几何 5 个**（`_layout_checksum` / `main_row2_geom` / `main_row2_min_col` / `main_col_right_w` / `build_main_row2_layout`）+ 宿主/pane 定位与回收句柄 2 个（`resolve_host_window` / `unattributed_pi_panes`）。判据只估到 27 个，多出的 5 个是 tmux 布局算式（D3 整组删的连带对象，非凑数）。

## 三、退役与迁移逐条（断言数 = `t4_assert*|ok|bad|skip` 静态计数）

- **12（12→文件删）**：tmux 宿主窗口显式寻址面随 `resolve_host_window` 删除；herdr 放置由 32/33/40/41 覆盖。
- **25（23→文件删）**：判据是 tmux 列宽算式 + 活体 pane 数；D3 整组删 ⇒ 连带布局几何函数一起删。
- **13（13→15，+2）**：①②③ 改为旧后端变量 fail loud（rc=2 / stdout 空 / stderr 单行含「已移除」+ herdr）；⑥⑦ 改 herdr 前提（`HERDR_ENV` 缺 ⇒ exit 3；空场 ⇒ 「未运行」rc=0）——原「tmux new -s nao」文案断言退役，新增「需要 herdr pane」与「空场 rc=0」各 1。
- **15（53→37，−16）**：全部减项在 `[ tmux ]` 分支（T1 名册隐藏口径 2 条 / T8 孤儿 pane 组 5 条 / T9 前缀边界组 9 条）；herdr 侧同名断言保留并补 `backend-gate` NOTE。
- **19（65→54，−11）**：减项全在 tmux 臂（③ 不可判定归属夹具 3 + AC4 3 + AC5① 基线对照 5）；herdr 两态（本仓/他仓）与 fail-closed 断言不动。
- **20（81→80，−1）**：tmux「新 pane 与调用者同窗口」布局语义断言退役（herdr 拓扑归 AC3.1，已有 NOTE）。
- **21（40→40）**：只删 tmux 夹具分支，断言数不变。
- **22（72→61，−11）**：`[ tmux ]` 臂 11 条（三态输出桩分支）退役；herdr 侧三态/计数断言全保留；J5 指路第三动作由「切布局（回退 tmux）」改为「换更大窗口/显示器后 attach」。
- **23（79→72，−7）**：tmux 投递通道 4 条（paste-buffer / Enter / bracket_paste_flag / 换行归一）**合并为 1 条反向断言**（0 处旧面），tmux 专属 AC2①/AC4① 分支 4 条退役；herdr 通道 3 条静态断言逐字保留。
- **27（85→81，−4）**：tmux 臂（生产 socket 锚点 2 / 隔离 socket 2）退役；herdr 端点锚点与零渗透断言保留。
- **28（390→340，−50）**：三组随后端退役并留痕（每组一行 `t4_ok`/注释）——C2① status golden（双 tmux 场 + 标题 pane 夹具）、C2② ensure golden + P2-1 命名预算 + P3-2 同场显示（同夹具）、BR1 tmux 逐字 golden（4 条）；herdr golden / 默认值反向断言 / 变异自证、C1 codec + M1–M5、C3 五组 lint、B2/B3 herdr 桩节全部保留。
- **32（58→同）**：仅 J5 文案断言改新口径（1 条）；其余不动。
- **34（58→同）**：check 的 tmux 声明 warn 改「不一致 + 已移除」双义文案（旧 4 条断言因此逐字仍成立）；无断言减少。
- **36/35**：只删 PATH 内 tmux 桩与「A4 仅 tmux 后端」相关行数断言（35 断言数不变）。
- **41（新增 45）**：fail loud 三态（旧后端变量 / `cleanup -S` / `NAO_TEST_TERMINAL`）+ `--case 12` 不存在 + 退役面不存在（`backends/`、`run-dual.sh`、package.json script、`term-impl-tmux`、`PENDING|TMUX-ONLY`）+ AC8 lint 正控 2（`tmux list-panes` 注入 / `NAO_TERMINAL=tmux)` 守卫字面量）+ 负控 2（注释迁移提示 / 白名单）+ 真件 4 个脚本 0 命中 + D3 删除面。

## 四、门禁与证据

- `bash .agents/scripts/nao-fleet.sh check` —— rc=0；连跑 2 次输出 `diff` 空（effect=0）。
- `bash tests/t4/run.sh`（单后端全量）—— **39 例 · RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=17 全白名单）**。
- `npm test`（`test:agents` + `test:t4`）—— rc=0（数字见交付回执）。
- 幂等：`tests/t4/run.sh --case 41` 连跑 2 次均 rc=0、PASS 数 49/49。
- 零敏感值：`grep -rnE '/home/[a-z]+|/Users/|ghp_|sk-|PRIVATE KEY|npm_[A-Za-z0-9]{20,}'` 在改动文件上 0 命中。
- 静态 lint：`t4_scan_tmux_residue` 对 `.agents/scripts/*.sh` + `tests/t4/run.sh` 全 0；正控（注入 `tmux list-panes` / `NAO_TERMINAL=tmux)` 各命中）与负控（注释迁移提示、`tmuxPane`、宿主句柄名表不红）均在 cases/41 固化。

## 五、偏离与风险（需 PM 知悉/裁定）

- **`term-facade-herdr` 区 9 行文案改动（零逻辑）**：`_term_herdr_require` / `_term_herdr_live_gate` / 两个 J1/J5 空间告警的「或 NAO_TERMINAL=tmux 回退」已改为「旧版 tmux 后端已移除 / pin 回 ≤0.27.x / 换更大窗口」。理由：留着即让 fail loud 文案指向不存在的后端；且 cases/22/32/41 的新断言依赖新文案。**若 PM 坚持判据 §5 的「逐字零 diff」**，可回退这 9 行（代价：文案说谎 + 3 条用例断言需再改）。
- **ac 边界（D5）**：`check` 摘要首行 `layout=` 字段随 D3 删除（`check: OK · roles=7 · files=52`）；`check` 恒 3 行（摘要 + codegraph + 生效后端）。cases/06 的 P2④ 已按新口径钉住。
- **28 的退役量最大（−50）**：对象是「基线 fixture（tmux 时代整脚本）vs 新版」对照与命名预算组；等价覆盖指针见 §三。若 PM 要求更强覆盖，建议新立项把命名预算组迁到 herdr 有状态桩（本批不做，避免超范围）。
- **发布面（PM 负责）**：`NAO_TERMINAL=tmux` / `cleanup -S` 从「可用」变 rc=2 —— 发布说明首屏须给一行迁移；`package.json` 的 `test:t4:full:dual` 已删。
- **未做（明确超范围）**：`docs/`（README/INSTALL/AGENTS/ADR 注记/tasks-state/PRD 索引）由 PM 改；`.agents/common/intercom-protocol.md` 若仍写「默认 herdr + tmux 回退」会被 `check` 的端前提 warn 点名（现协议只有「默认 herdr」声明，故 0 warn）。

## 六、遗留项三出口建议

- **关闭**：判据 §1 的「函数数 27 个消失」估算偏低（实为 32）—— 已按 D1 实测口径落定，建议在判据稿加一行更正。
- **接受（含到期）**：`t4_scan_term_bare_calls` 的第 2 参（旧 tmux 台账）已无对象但签名保留；`fixtures/term-legacy-allowlist.txt`（baseline 0 条）保留为「不回暖」判据。到期 2026-12-31：若仍无第二台账条目，删除文件与 `t4_verify_term_ledger`（连同 cases/06 的 4 条负控）。
- **转办（PM）**：README/INSTALL/AGENTS 三处文档同步 + 发布说明迁移段（`docs/` 属 PM 边界）。

---

- 修订：2026-11-22 首版（T555 实施完成，待 PM 验收）
