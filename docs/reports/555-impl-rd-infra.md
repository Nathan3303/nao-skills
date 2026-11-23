# 实施报告 · T555 纯 herdr 化 + 脚本减重（rd-infra）

- 状态：待 PM 验收 · 更新：2026-11-22 · Owner：rd-infra
- 指针：PRD `docs/prds/2026-11-22-herdr-only.md` · ADR `docs/adr/2026-11-22-herdr-only.md` · 判据 `docs/reports/555-lite-spec.md`（§7 D1–D5 为最终口径）· Issue #156
- 基线：分支 `feat/555-herdr-only`，起点 `8bc9837`

## TL;DR

- **D1 达成**：`nao-fleet.sh` 5482 → **4531** 行（**−951 · −17.35%**，目标 ≤4933）；函数数 163 → **131**（目标 ≤136，**−32**，逐条清单见 §二）。
- **D2/D3/D4 达成**：旧后端变量 ⇒ rc=2 单行；`cleanup -S` ⇒ rc=2 指路 `--session`；`NAO_TMUX_*` 死配置与 check 布局节整组删；`tests/t4/backends/` + 注册器 + `run-dual.sh` 删除（run.sh −153 行）。
- **门禁**：`check` rc=0（连跑 2 次逐字一致）· 全量 T4 **38 例全 PASS**（`RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=17）`）· `npm test` rc=0（数字见 §四，HEAD 随最终提交）。
- **待 PM 裁一处偏离**：`term-facade-herdr` 区有 **9 行文案**改动（原「或 NAO_TERMINAL=tmux 回退」→ 迁移指路），**零逻辑 diff**；不删则文案指向已不存在的后端（判据 §5 的「零 diff」按字面未满足）。
- 断言数：静态 **2170 → 2103（−67）** = 退役 **130** 条（全部来自 tmux-only 分支/组与 25 的 23 条；逐条归因见 §三）+ 新增 `cases/41` **61** 条 + 13 号 **+2**。`12` 是 wrapper（文件内静态断言 0，实体在 QA 冻结脚本），**不计入**本表。QA 点检时点（HEAD `0a32d2f`）实测为 2096 / 退役 130、`06` 303；本轮 P3-1/P3-2 再 +7 ⇒ 2103。
- **QA 一轮整改已落**（P1 `cases/34` 锚点加固 · P2-2 `t4_scan_tmux_residue` 扩四形态 + `cases/41` 双控 · 本报告与 `tests/README.md` 计数订正），详见 §七。

## 一、体量实测（D1）

- `wc -l .agents/scripts/nao-fleet.sh`：**5482 → 4531**（−951 行 = −17.35%；D1 口径「≥10% ⇒ ≤4933」，余量 402 行）。
- 函数数（`grep -cE '^[a-zA-Z_][A-Za-z0-9_]*\(\) *\{'`）：**163 → 131**（−32；D1 口径「≤136」，余量 5）。
- 其余体量：`tests/t4/lib-backend.sh` 910 → 761（−149）· `tests/t4/run.sh` −153 · 删除 `run-dual.sh`（72）· `tests/t4/backends/herdr.txt`（47）。
- 未动 herdr 实现（见 §五偏离说明）：`term-facade-herdr` 区间行数 1140 → 1140。

## 二、整体消失的函数（32 个）

`apply_main_col` · `apply_tmux_layout` · `build_main_row2_layout` · `fallback_pane_for` · `find_pane_by_title` · `find_pane_for` · `find_pane_for_any_repo` · `_layout_checksum` · `main_col_right_w` · `main_row2_geom` · `main_row2_min_col` · `pane_busy` · `pane_hosts_caller` · `pi_panes` · `pi_pids_for` · `prod_sock_candidates` · `require_tmux` · `resolve_host_window` · `roster_pane_claims` · `self_pane_refuse` · `spawn_tmux` · `_term_tmux_argv` · `_term_tmux_cleanup` · `_term_tmux_current_session` · `_term_tmux_deliver` · `_term_tmux_liveness` · `_term_tmux_names` · `_term_tmux_pane_cwds` · `_term_tmux_reclaim` · `_term_tmux_snapshot` · `tmux_pane_live` · `unattributed_pi_panes`

归口：七区间 25 个（判据 §1）+ 区间外 `require_tmux` / `_term_tmux_snapshot` + **布局几何 5 个**（`_layout_checksum` / `main_row2_geom` / `main_row2_min_col` / `main_col_right_w` / `build_main_row2_layout`）+ 宿主/pane 定位与回收句柄 2 个（`resolve_host_window` / `unattributed_pi_panes`）。判据只估到 27 个，多出的 5 个是 tmux 布局算式（D3 整组删的连带对象，非凑数）。

## 三、退役与迁移逐条（断言数 = `t4_assert*|ok|bad|skip` 静态计数）

- **06（306→303，−3）**：减项全在「后端专属组」——① 门面负控 A（`cmd_status` 注入 tmux）3→2（改打旧面 lint，−1）；② 显式 `=tmux check` 组 5→4（旧 golden 组随后端退役，改钉 rc=2/单行/零副作用，−1）；③ `B2④ 显式 =tmux session-start` 3 条随后端删除（−3）；④ P2②/P2③ 计数断言按新事实重算 **+1**（exit-3 站点 8→7、用例数 39→38、`be_fleet_handles` 两后端→单后端）；⑤ 新增「5 个 lint helper 均已定义」前置 **+1**（QA 轮抓到的 127 假绿防线，见 §六）。
- **12（wrapper 文件删；用例文件内静态断言 = 0）**：原文件只是**挂载器**（`exec` 冻结脚本 `docs/reports/2026-10-13-T517-derived-pane-window-regression.sh --t4`，自身 `t4_assert*` = 0）。断言实体（17 条 `ok/bad` 调用）在 QA 冻结脚本里，**不属 T4 计数**；wrapper 删除后该脚本不再被 T4 调用（其对象 tmux 宿主窗口寻址已随 `resolve_host_window` 删除）⇒ **留档处置归 PM/QA 文档面**（本报告只记口径，不重复判据 §2 的「12 断言」估法）。herdr 放置由 32/33/40/41 覆盖。
- **25（23→文件删）**：判据是 tmux 列宽算式 + 活体 pane 数；D3 整组删 ⇒ 连带布局几何函数一起删。
- **13（13→15，+2）**：①②③ 改为旧后端变量 fail loud（rc=2 / stdout 空 / stderr 单行含「已移除」+ herdr）；⑥⑦ 改 herdr 前提（`HERDR_ENV` 缺 ⇒ exit 3；空场 ⇒ 「未运行」rc=0）——原「tmux new -s nao」文案断言退役，新增「需要 herdr pane」与「空场 rc=0」各 1。
- **15（53→37，−16）**：全部减项在 `[ tmux ]` 分支（T1 名册隐藏口径 2 条 / T8 孤儿 pane 组 5 条 / T9 前缀边界组 9 条）；herdr 侧同名断言保留并补 `backend-gate` NOTE。
- **19（65→54，−11）**：减项全在 tmux 臂（③ 不可判定归属夹具 3 + AC4 3 + AC5① 基线对照 5）；herdr 两态（本仓/他仓）与 fail-closed 断言不动。
- **20（81→80，−1）**：tmux「新 pane 与调用者同窗口」布局语义断言退役（herdr 拓扑归 AC3.1，已有 NOTE）。
- **21（40→40）**：只删 tmux 夹具分支，断言数不变。
- **22（72→61，−11）**：`[ tmux ]` 臂 11 条（三态输出桩分支）退役；herdr 侧三态/计数断言全保留；J5 指路第三动作由「切布局（回退 tmux）」改为「换更大窗口/显示器后 attach」。
- **23（79→72，−7）**：tmux 投递通道 4 条（paste-buffer / Enter / bracket_paste_flag / 换行归一）**合并为 1 条反向断言**（0 处旧面），tmux 专属 AC2①/AC4① 分支 4 条退役；herdr 通道 3 条静态断言逐字保留。
- **27（85→81，−4）**：tmux 臂（生产 socket 锚点 2 / 隔离 socket 2）退役；herdr 端点锚点与零渗透断言保留。**口径说明**：判据 §2 原估「删 tmux 臂 7 条 + 1 条静态 ⇒ 85→78」，实测减 **4**（QA 复核同为 81）；差在「7 条」是判据起草时的口径（把门面分派名等静态项算进了臂），以实测为准。
- **28（390→340，−50）**：三组随后端退役并留痕（每组一行 `t4_ok`/注释）——C2① status golden（双 tmux 场 + 标题 pane 夹具）、C2② ensure golden + P2-1 命名预算 + P3-2 同场显示（同夹具）、BR1 tmux 逐字 golden（4 条）；herdr golden / 默认值反向断言 / 变异自证、C1 codec + M1–M5、C3 五组 lint、B2/B3 herdr 桩节全部保留。
- **32（58→同）**：仅 J5 文案断言改新口径（1 条）；其余不动。
- **34（58→同）**：check 的 tmux 声明 warn 改「不一致 + 已移除」双义文案（旧 4 条断言因此逐字仍成立）；无断言减少。
- **36/35**：只删 PATH 内 tmux 桩与「A4 仅 tmux 后端」相关行数断言（35 断言数不变）。
- **38（27→23，−4）**：减项全在 tmux 臂（`g2` 作用域 rc / pane 存活 / 标题定位 3 条 + 1 条 tmux cwd 镜像）；herdr 侧 g1/g2 去重与拒绝理由断言保留。
- **41（新增 45 → QA 两轮整改后 61）**：fail loud 三态（旧后端变量 / `cleanup -S` / `NAO_TEST_TERMINAL`）+ `--case 12` 不存在 + 退役面不存在（`backends/`、`run-dual.sh`、package.json script、`term-impl-tmux`、`PENDING|TMUX-ONLY`）+ AC8 lint **四形态正控**（命令位注入 / 原样 `tmux)` 臂 / 比较式 `[ "${NAO_TERMINAL:-…}" = "tmux" ]` / 单行 `case … in tmux) exec tmux`）+ **守卫臂白名单双向**（含「已移除」放行 · 摘掉文案即红 · 改赋值式即红）+ **五类负控**（注释迁移提示 / `command -v tmux` / 注释旧命令 / `tmuxPane`+宿主句柄名表 / 非 tmux 的 `screen)` 臂）+ 真件 3 个脚本 0 命中 + D3 删除面。
  第二轮（QA 点检 P3-1/P3-2）再 +7：`herdr|tmux)` 臂 / `tmux*)` glob 臂 / 声明边界 `case "$TERM" in tmux)` 三条正控 + 注释穿透 `;; esac # 已移除` / 「只有文案无 `exit|return 2`」两条正控 + 真守卫放行 + `(herdr|tmux)` 正则字面量不误伤（`|` 臂判据边界自证）。
- **34（58→58）**：无断言增删；仅**变异锚点加固**（`s/默认 herdr/默认 tmux/` → helper `mut_decl_tmux`，锚 = 「默认后端」+ 其后后端名，不绑等号/空格写法）+ 两处自证同步（`grep '默认 tmux'` → `decl_is_tmux`）。QA P1：PM 改写 `AGENTS.md:34` 为「默认后端 = herdr（唯一）」后旧锚 0 命中 ⇒ 6 条 FAIL；加固后同文案微调不再空转，判据强度不变。

## 四、门禁与证据

- `bash .agents/scripts/nao-fleet.sh check` —— rc=0；连跑 2 次输出 `diff` 空（effect=0）。
- `bash tests/t4/run.sh` / `npm run test:t4:full`（单后端全量）—— **38 例 · 2420 PASS / 0 FAIL · `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=17 · 白名单=17）`** · SKIP=0 / DEGRADE=0（HEAD 见修订行；未用 `--fast` 替代）。
- `npm test`（`test:agents` + `test:t4`）—— rc=0（同一工作树内容）· stderr「未找到命令」噪声 **0**（QA 第一轮顺手清掉 7 处断言文案里的裸反引号）。
- `npm run test:fast` —— rc=0（白名单 14 例 · NOTE=2 白名单）。
- `npm run test:t4:full`（最终 HEAD）—— rc=0 · `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=17 · NOTE白名单=17）`。
- 幂等：`tests/t4/run.sh --case 41` 连跑 2 次均 rc=0（PASS 数 = 该例当前断言数）。
- 零敏感值：`grep -rnE '/home/[a-z]+|/Users/|ghp_|sk-|PRIVATE KEY|npm_[A-Za-z0-9]{20,}'` 在改动文件上 0 命中。
- 静态 lint：`t4_scan_tmux_residue` 对 `.agents/scripts/*.sh` + `tests/t4/run.sh` 全 0；**四形态**正控（命令位 / 原样 `tmux)` 臂 / 比较式 / 单行 case 臂）+ 守卫臂白名单双向 + 五类负控均在 `cases/41` 固化（T555/QA P2-2 扩形态后仍 0 命中）。

## 五、偏离与风险（需 PM 知悉/裁定）

- **`term-facade-herdr` 区 9 行文案改动（零逻辑）—— PM 已裁定接受**：`_term_herdr_require` / `_term_herdr_live_gate` / 两个 J1/J5 空间告警的「或 NAO_TERMINAL=tmux 回退」已改为「旧版 tmux 后端已移除 / pin 回 ≤0.27.x / 换更大窗口」。PM 独立 old/new 全区间 diff 复核：1140 → 1140 行、仅此类文案 ⇒ 属 AC1/D5 的「已声明退役面」，不回退。
- **ac 边界（D5）**：`check` 摘要首行 `layout=` 字段随 D3 删除（`check: OK · roles=7 · files=52`）；`check` 恒 3 行（摘要 + codegraph + 生效后端）。cases/06 的 P2④ 已按新口径钉住。
- **28 的退役量最大（−50）**：对象是「基线 fixture（tmux 时代整脚本）vs 新版」对照与命名预算组；等价覆盖指针见 §三。若 PM 要求更强覆盖，建议新立项把命名预算组迁到 herdr 有状态桩（本批不做，避免超范围）。
- **发布面（PM 负责）**：`NAO_TERMINAL=tmux` / `cleanup -S` 从「可用」变 rc=2 —— 发布说明首屏须给一行迁移；`package.json` 的 `test:t4:full:dual` 已删。
- **未做（明确超范围）**：`docs/`（README/INSTALL/AGENTS/ADR 注记/tasks-state/PRD 索引）由 PM 改；`.agents/common/intercom-protocol.md` 若仍写「默认 herdr + tmux 回退」会被 `check` 的端前提 warn 点名（现协议只有「默认 herdr」声明，故 0 warn）。

## 六、QA 两轮整改（第一轮 CONDITIONAL · 第二轮点检 done(full) 的 5×P3）

### 第一轮（1×P1 + 2×P2）

- **P1 `cases/34` 锚点跟随新文案**：PM 把 `AGENTS.md:34` 改写为「默认后端 = herdr（唯一，≥0.9.1）」后，旧变异 `sed s/默认 herdr/默认 tmux/` **0 命中** ⇒ 6 条 FAIL（红样：`C2a/C2c/C2d/C2e/C3b/C3d`）。修法兼加固：抽 `mut_decl_tmux`（锚 = 「默认后端」+ 其后后端名，不绑等号/空格写法）+ `decl_is_tmux` 自证；判据强度不变（仍要求变异必命中、warn 必须点名 `AGENTS.md:<行>`）。
- **P2-2 `t4_scan_tmux_residue` 放过真实复活形态**：旧 `re` 只认命令位与赋值字面量 ⇒ QA 三形态（`tmux)` 臂 / `${NAO_TERMINAL:-herdr} = tmux` 比较 / 单行 `case … in tmux) exec tmux`）全放过，`cases/41 ⑫` 的正控因此自证被架空（先改写成 lint 认识的形状再测）。扩为 **四判据**（命令位 · 赋值 · 比较式 · case 臂）+ 守卫臂白名单（臂体至首个 `;;` 含「已移除」才放行）；`cases/41` 加 4 正控（含原样 `tmux)`）、白名单双向 2 条、5 负控（含 `command -v tmux` 与 `case "$TERM" in screen)` 防误伤）。**边界**：case 臂前缀只认行首/空白/`;`/`&`（**不含 `|`**），避免把 `(herdr|tmux)` 这类正则字面量误判成臂。
- **P3 报告订正**：补 `06(−4)` / `38(−4)` 归因；`12` 改 wrapper 口径；例数 39→38；断言总数 2170→2095；27 的「7 条」注明是判据原估（实测 4）。
- **P3 `tests/README.md`**：例数 38 · 修 `- -` 双横线 · **基线 fixture 处置 = 保留归档**（复核发现**并非零引用**：`cases/19` AC5① 与 `cases/28` C2 仍有「存在 / 来源 sha / 非自等价」静态断言，共 6 条；删 fixture 会连带删断言 ⇒ 选择保留并在 README 注明「仅存档 + 上述静态引用，不再承担 tmux golden diff」）。


### 第二轮（QA 点检 5×P3：P3-1/P3-2/P3-5/P3-3 归我；P3-4 归 PM）

- **P3-1（假绿，必修）`t4_scan_tmux_residue` 白名单被注释穿透**：QA 实测 `case "$BE" in tmux) exec tmux new -s nao ;; esac  # 已移除` ⇒ **绿**。根因 = 白名单看「起始行起 9 行整段」，`;;` 之后的同行注释也被算进「臂体含已移除」。修法三件套（缺一不可）：
  ① 判定前**先剥 `#` 注释**（最小实现：`[[:space:]]#` 起剥）并**截到首个 `;;`**；
  ② 白名单**同时要求真出口** `exit 2` / `return 2`（只有文案不算守卫）；
  ③ 该臂行本身不得命中命令位/赋值/比较三条（防「顺手把调用写进臂里」）。
  同轮补两个**漏判形态**：`case … in herdr|tmux)`（`|` 前缀**只在同行含 `case … in` 时**算臂）与 `tmux*)` glob 臂；各配正控 + **`(herdr|tmux)` 正则字面量不误伤**的自证断言。
- **P3-2 边界误伤声明（取方案 ①）**：`case "$TERM" in tmux)`（检测「自己是否在 tmux 里」）**同样算旧面**、会红 —— 已在 `lib.sh` 注释显式声明，并配 1 条「已声明边界」正控钉住；替代方案（把臂规则限定到 `NAO_TERMINAL` 上下文）不采纳，因为 `case "$BE" in tmux)`（`BE=${NAO_TERMINAL}`）会漏判。迁移建议：判断是否装过用 `command -v tmux`，提示迁移写注释（两者均不红）。
- **P3-5 `cases/34` 注释与实现不符**：helper 注释曾称 `默认herdr` 也认（实现硬前缀是「默认后端」）⇒ 注释已按实现改写（`默认后端 = herdr` / `默认后端 herdr` 认，`默认herdr` 不认），C2a 自证强度未降。
- **P3-3 报告回填**：`06` 行改 **303（−3）**、断言总数 **2103**、退役合计 **130**（QA 实测时点 2096/130 + 本轮 P3-1/P3-2 新增 7 条）。
## 七、遗留项三出口建议

- **关闭**：判据 §1 的「函数数 27 个消失」估算偏低（实为 32）—— 已按 D1 实测口径落定，建议在判据稿加一行更正。
- **接受（含到期）**：`t4_scan_term_bare_calls` 的第 2 参（旧 tmux 台账）已无对象但签名保留；`fixtures/term-legacy-allowlist.txt`（baseline 0 条）保留为「不回暖」判据。到期 2026-12-31：若仍无第二台账条目，删除文件与 `t4_verify_term_ledger`（连同 cases/06 的 4 条负控）。
- **转办（PM）**：README/INSTALL/AGENTS 三处文档同步 + 发布说明迁移段（`docs/` 属 PM 边界）。

---

- 修订：2026-11-23 QA 两轮整改版（P1 锚点 · P2-2/Point-3-1 lint 扩形态与白名单双重条件 · 计数订正；HEAD `933695c`）
