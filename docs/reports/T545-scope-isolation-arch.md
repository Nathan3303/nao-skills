# T545 herdr 多 workspace scope 判定失真 · 架构评审

- 状态：**已拍板（D1=A · 2026-11-13）· 待 rd-infra 实现**
- 指针：Issue [#112](https://github.com/Nathan3303/nao-skills/issues/112) · ADR `docs/adr/2026-11-13-herdr-workspace-scope-key.md` · 既有决定 `docs/prds/2026-11-10-herdr-base.md`（AC3.1）· `docs/reports/96p3-layout-p1.md:22`

## 一、可行性结论与拍板

**有条件可行 → 已拍板可实施**。实现面 = `_term_herdr_spawn` 一处键 + 用例/文案，**命名契约零改动**；根因是**键的来源错位**（把可选的身份字段 scope 当必需的放置键，空值只能借无关的会话名兜底）。
用户拍板（ask-me · 2026-11-13）：**D1 = A**（双键分离）· **D2 = 接受废止** `96p3-layout-p1.md:22` 的 `HERDR_SESSION` 回退 · **D3 = scope 优先 / 仓 slug 兜底** · **D4 = 加静态 lint + 关闭遗留 `O2`** · **D5 = PATCH**（行为修复，无新能力）。

## 二、诊断复现（零污染 · 可重复）

```bash
# 替身 + 私有 XDG_CONFIG_HOME：不碰真 herdr、不碰用户会话；teardown 后 sessions/ 为空（实测「无输出」）
cd "${NAO_SKILLS:-.}"    # 本仓根
source tests/t4/lib.sh; source tests/t4/lib-backend.sh
export PATH="$PWD/tests/t4/fixtures/herdr-double:$PATH" NAO_TEST_TERMINAL=herdr
LAB="$T4_CACHE_DIR/lab-t545"; mkdir -p "$LAB/repo-b"; cp -r .agents "$LAB/.agents"
BE_CACHE_ROOT="$T4_CACHE_DIR"; be_init "$LAB" nao-skills; be_start_server
be_run_fleet "$LAB" ensure "rd-fe@$LAB/repo-b"; be_herdr "$BE_SESSION" workspace list
be_teardown; ls -A "$(be_sessions_dir)"      # 期望：无输出 = 零残留
```

- **期望**（AC3.1 + 用户预期）：pane 落在 label = 目标仓（`repo-b`）的 workspace；至少不得落进调用方 workspace。
- **实际 A**（会话名 `nao-skills` 恰等于调用方 label）：`w1 label=nao-skills panes=1→2`，新 pane `w1:p2 label=rd-fe cwd=…/repo-b`，**零新 workspace** ⇒ 现场复刻。**实际 D**（会话名 `nao-work` 与任何 label 不同）：凭空新建 `w2 label=nao-work`（与目标仓无关）。
- **对照**：`ensure --scope b` ⇒ `w2 label=b` + pane `rd-infra@b`；仓内 `.agents/fleet-scope=todo` ⇒ `w3 label=todo` + pane `qa@todo`。
- **现场时间线（实证）**：`18:40:06` nao-todo `.nao-version`→`0.23.0` · `18:45:47` 会话 `rd-infra-T724` 以 `cwd=…/nao-todo` 启动且名字无 `@` 后缀 · `18:49:01` `.agents/fleet-scope`（`todo`）才创建、`git status` = `??`（未跟踪）· `18:55:47` Issue 创建。
- **订正归因**：不是「fleet-scope 创建时未生效（被忽略）」，而是**创建时该文件不存在**（mtime 晚 3 分 14 秒）；空 scope 按设计合法，缺陷在「空 scope ⇒ 用 `HERDR_SESSION` 当放置键」。
- **取证**：`stat -c '%n %y' …/nao-todo/.agents/{.nao-version,fleet-scope}` · `git -C …/nao-todo status --short` ⇒ `?? .agents/fleet-scope` · `head -2 ~/.pi/agent/sessions/--home-nathan-Projects-nao-todo--/2026-11-13T10-45-47-930Z_*.jsonl` ⇒ `cwd` + `name` · `fleet_scope_slug` 实测：`repo-a` 与其 worktree **同键**、`nao-todo`⇒`nao-todo`、`nao-skills`⇒`nao-skills`（与用户手工 label 逐字相等）。

## 三、采纳与不采纳理由

- **A（采纳 · 双键分离）**：放置键 = 已声明 scope 否则 `fleet_scope_slug(目标仓)`；删 `HERDR_SESSION` 回退。键全域（slug 恒非空）、worktree 同键、用户手工按仓名命名的 workspace 可直接复用（现场 `w1`/`w2` 的 label 恰等于 slug ⇒ 零配置）、顺带关闭 `O2`。
- **B 不采纳（禁止跨仓 + fail loud）**：判据需「调用方 workspace 属哪仓」，herdr 0.9.1 `WorkspaceInfo` 无 cwd/worktree 字段（本机 `workspace list` 实测）⇒ 只能 pane cwd 启发式（cd 到别仓再 `ensure` 可绕过）；且 nao-skills 自身未声明 scope ⇒ 从任意 cwd `ensure` 立即受限。
- **C 不采纳（scope 总是派生 + 名字带 `@slug`）**：同 A 收益但破 BR1（`pm`→`pm@slug`）、用例/文档/下游全量改、旧会话双名期。

## 四、实施闸门（rd-infra 照做 · G1–G9）

- **G1 唯一必改点 `nao-fleet.sh:1083-1088`**：键 = 名字里 parse 出的 scope（**不重读** `.agents/fleet-scope`，防双源/时序漂移）；scope 空 ⇒ `label="$(fleet_scope_slug "$repo")"`；**删除** `[[ -n "$label" ]] || label="${HERDR_SESSION:-}"`，保留「空 ⇒ warn + `SPAWN_RC_FAIL`」守卫（文案改「scope 空且 slug 计算失败（repo=…）」）。
- **G2 连带（实现不改、语义随 G1 变）**：`:897-908` `_term_herdr_workspace_id_for` 保持按 label 精确匹配（`[[ -n "$label" ]] || return 0` 变纯防御，补注释「label 恒非空（ADR 2026-11-13）」；**禁**改成按 cwd/根 pane 匹配 —— herdr 无 workspace cwd，且会引入第二个键）· `:1165-1200` `workspace create --label "$label"` 形状与「空 workspace 关旧建新」逻辑勿动 · `:1710-1738` `fleet_scope_slug` 实现不改，仅新增 G1 一个调用点。
- **G3 `tests/t4/cases/32-real-herdr-roundtrip.sh:147-151` 必改判据**：目标 `$LAB/repo` 非 git ⇒ slug=`repo`。新判据 = `obj_for "$WS_JSON" label repo` 非空取 `WS_ID` **且** `WS_ID` ≠ 调用方首 pane 的 `workspace_id` **且** `obj_for "$WS_JSON" label "$SESS"` 为空（反向：不得复用会话名 workspace）；同步改 `:147` 注释「label=会话名/scope」→「label=scope（已声明）否则仓 slug」。
- **G4 新增用例（建议新文件 `cases/33`，不动既有例）**：U1 跨仓空 scope 且会话名 == 调用方 label ⇒ label=slug、pane 不在调用方 ws、无 `label==SESS` 的新 ws；U2 同仓空 scope ⇒ label=slug；U3 worktree 同键（`git worktree add` 后两次 ensure ⇒ slug workspace 仅 1 个）；U4 scope 优先（`--scope b` 与 `.agents/fleet-scope=todo` 各 1 条 ⇒ label=b / todo）；U5 两仓同 core 无 scope ⇒ 第二次 ensure 仍 fail loud（P11 文案不变）。断言作用域 = 单字段（`workspace.label` / `pane.workspace_id`）+ 计数（workspace 条数），禁「整段文本包含」。
- **G5 双向负控（必须真跑）**：① 副本把 G1 改回 `label="${HERDR_SESSION:-}"`（sed + 还原 + md5 一致）⇒ U1 必红；② 副本把 slug 兜底改成 `label=""` ⇒ U1 必红（fail loud，不静默落）；③ 副本摘掉 G3 的反向断言 ⇒ 无红（证反向断言非自证）。
- **G6 静态 lint（D4）**：落 `tests/t4/cases/28` 的 C3 lint 家族，**不进 `check`**（避免 `check` 输出/计数漂移，`check` 仍 `files=54`）。判据 = 抽 `_term_herdr_spawn` 函数体（`awk '/^_term_herdr_spawn\(\)/,/^}/'`）后 `grep -c 'HERDR_SESSION'` **必须 = 0**；**白名单无**（`--session` 注入只在 `_term_herdr_exec`）。现状该函数体内有 **2 处**（键回退 + `无法确定 workspace label` 的 warn 文案，实测 `grep -c` = 2）⇒ G1 必须**连 warn 文案一起改**（例：「scope 空且 slug 计算失败（repo=…）」），否则 lint 恒红。失败文案：`herdr 放置键不得取会话名：label 必须来自 scope 或 fleet_scope_slug(目标仓)（ADR 2026-11-13-herdr-workspace-scope-key）`。负控 = 副本注入该行 ⇒ 必红并点名此文案。
- **G7 `O2` 关闭验收（可观测）**：`awk '/^_term_herdr_spawn\(\)/,/^}/' .agents/scripts/nao-fleet.sh | grep -c 'fleet_scope_slug'` → `1`（恰 1 处；多点重复 = 违规）；U1–U3 绿（slug 真参与放置）；`docs/reports/96a-naming-scope-followups.md` 的 O2 行标「已关闭（T545）」；台账观察项由 PM 移除。
- **G8 迁移与发布（PATCH）**：旧 scope 命名 workspace（如 `todo`）不再复用 ⇒ `herdr --session <s> workspace list` 找到后人工 `workspace close`（运行中会话不迁移：`status`/`close` 归属不看 workspace）；同 slug 两仓（同名仓 / >16 截断）共用 workspace ⇒ 写 `.agents/fleet-scope` 即分离；release notes 两句（**行为**：多仓并行时每仓各自落到自己的 workspace，声明 scope 则用 scope 名，不再把别仓会话塞进当前窗口；**迁移**：旧的按 scope 命名的 workspace 不再复用，可手工关闭）；无开关，回退 = 回勾提交。
- **G9 连带同步清单（改既有条款 · 含 Owner）**：`docs/reports/96p3-layout-p1.md:22` 口径表 → **PM** · `docs/prds/2026-11-10-herdr-base.md` AC3.1 字面（label=scope）加注指向本 ADR → **PM** · `nao-fleet.sh` 头部注释 `:12-14`、help `:36-41`、放置注释 `:1165` → **rd-infra** · `tests/t4/cases/32` 注释 → **rd-infra** · 本 ADR 与本报告 → **arch**（已完成）。

## 五、风险与破坏性判断

- **命名契约 `<core>[@<scope>]` 不破**：builder/parse/13 个解析点零改动；`status`/`close` 归属判据（pane label + pane cwd）不变。
- **删 `HERDR_SESSION` 回退 = 唯一破坏性点**：旧行为「无 scope 时跨仓会话塞进当前/会话名 workspace」消失；靠它把别仓会话拉进当前窗口的用法改为给该仓声明 `.agents/fleet-scope`（声明后落该 scope 的 workspace，仍同 server，可 `workspace focus`）。已获用户 D2 明确接受。
- 下游三仓：nao-todo `0.23.0` 含 scope ⇒ 升级后零配置正确；nao-guesthouse `0.22.6`、nue-ui `0.20.4`、nao-todo-server `0.12.0` **无 scope 机制** ⇒ 升级前行为不变（已知残留），升级后自动按仓放置。
- 同 slug 两仓共用 workspace = 已接受边界（2027-01-31，判据写文档）；**不做**「slug 找不到再回退 scope label」的双键回退（判据不再单一）。
## 六、后续链路

rd-infra 按 G1–G9 实现（含 G5 负控真跑、G6 lint、G3 改判据）→ qa 非作者复核 → PM 验收 → RD squash 合并；门禁 = `check` rc=0 + `npm test` 双后端 rc=0。

- 修订：2026-11-13 首版（诊断复现 + 三候选 + 推荐 A）
- 修订：2026-11-13 拍板生效：状态改「已拍板」· §四 补实施闸门 G1–G9（含 lint 判据 / O2 验收 / 迁移与发布要点）
