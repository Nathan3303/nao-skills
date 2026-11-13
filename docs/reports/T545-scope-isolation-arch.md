# T545 herdr 多 workspace scope 判定失真 · 架构评审

- 状态：待用户拍板 · 更新：2026-11-13 · Owner：arch-designer
- 指针：Issue [#112](https://github.com/Nathan3303/nao-skills/issues/112) · 既有决定 `docs/prds/2026-11-10-herdr-base.md`（AC3.1）· `docs/reports/96p3-layout-p1.md:22` · ADR `docs/adr/2026-11-13-herdr-workspace-scope-key.md`

## 一、可行性结论

**有条件可行**（条件 = 拍板 §六 D1–D5）；实现面 = `_term_herdr_spawn` 一处键 + 用例/文案，**命名契约零改动**。根因是**键的来源错位**：把可选的身份字段 scope 当必需的放置键，空值只能借无关的会话名兜底 —— 非实现瑕疵。

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

## 三、候选方案（**推荐 A**）

- **A · 双键分离（推荐）**：scope 判定源 `--scope` > `<目标仓>/.agents/fleet-scope` > 空（**不变**，空仍合法）；workspace 键 = 已声明 scope 否则 `fleet_scope_slug(目标仓)`，**删除 `HERDR_SESSION` 回退**。同名冲突沿用 P11（同 core 不同 scope/仓 ⇒ die）；跨 workspace 落 pane **结构上不可能**，无需 fail loud；`status`/`close` 归属不变（pane label + cwd）。下游**零配置**（现场 `w1`/`w2` 的 label 恰等于 slug ⇒ 直接复用），0.22.x 及以下无此机制（升级前后行为不变/自动改善）。
- **B · 禁止跨仓 + fail loud（不派生）**：空 scope 只允许复用「与目标仓同仓」的调用方 workspace，否则建 pane 前 die。判据缺陷：herdr 0.9.1 `WorkspaceInfo` 无 cwd/worktree 字段（本机 `workspace list` 实测），只能靠 pane cwd 启发式（在 A 仓 pane 里 `cd` 到 B 仓再 `ensure` 即可绕过）；迁移成本 = nao-skills 自身未声明 scope ⇒ 从任意 cwd `ensure` 立即受限。
- **C · scope 总是派生（命名也带 `@slug`）**：放置效果同 A，但会话名 `pm`→`pm@nao-skills` ⇒ 破 BR1、用例/文档/下游全量改、旧会话双名期 —— 同收益、代价高一个量级。
- **推荐 A 的理由**：① 键全域（scope 可空、slug 不可空），消灭「未定义键」；② 与 herdr 原生模型一致（workspace = 顶层项目/上下文，label 默认取根 pane 目录名），用户手工命名的 workspace 可被复用；③ 零配置迁移、命名契约零改动、顺带关闭遗留 `O2`（`fleet_scope_slug` 未接生产，到期 2027-01-31）。

## 四、影响面（行段 = `.agents/scripts/nao-fleet.sh`）

- `:1083-1088` `_term_herdr_spawn` label 计算 —— **唯一必改点**（删 `HERDR_SESSION` 回退，改 `fleet_scope_slug "$repo"`）；`:897-908` 按 label 精确匹配不改（空 label 分支不再可达）；`:1165-1200` 放置分支仅 `--label` 取值变。
- `:1710-1738` `fleet_scope_slug`（从「未接生产」变为唯一放置键来源）；`:1740-1780` / `:3936-3957` scope 解析行为不变，仅注释与 help 补「scope 只影响会话名」。
- 用例：`tests/t4/cases/32-real-herdr-roundtrip.sh:147-151` **必须改判据**（现断言「workspace label == 会话名」= 把缺陷写成期望）；新增跨仓空 scope 不落调用方 / 同仓空 scope 落本仓 / worktree 同键 / 两来源都只改名字不改放置 / 两仓同 core 仍 fail loud；负控 = 键改回 `HERDR_SESSION` 必红。门禁 = `check` rc=0（建议加 lint：spawn 内禁 `HERDR_SESSION` 参与放置键）+ `npm test` 双后端 rc=0（T543 修好后 herdr 内可跑）。

## 五、风险与破坏性判断

- **命名契约 `<core>[@<scope>]` 不破**：builder/parse/13 个解析点零改动。
- **删 `HERDR_SESSION` 回退 = 唯一破坏性点**：旧行为「无 scope 时跨仓会话塞进当前/会话名 workspace」消失；靠它拉别仓会话进当前窗口的用法需改用该仓 `.agents/fleet-scope`（声明后落该 scope 的 workspace，仍同 server，可 `workspace focus`）。须写进 release notes。
- 下游三仓：nao-todo `0.23.0` 含 scope ⇒ 升级后零配置正确；nao-guesthouse `0.22.6`、nue-ui `0.20.4`、nao-todo-server `0.12.0` **无 scope 机制** ⇒ 升级前行为不变（已知残留），升级后自动按仓放置。
- 旧 workspace：声明过 scope 的仓（如 `todo`）升级后不再复用该 label ⇒ 每仓最多人工关一个，运行中会话不受影响；不做「slug 找不到再回退 scope label」的双键回退（判据不再单一）。

## 六、需拍板的决策点

- **D1** 方案：A（推荐）/ B / C。**D2** 接受废止 `96p3-layout-p1.md:22` 的 `HERDR_SESSION` 回退？（三案都删，差别只在空 scope 处理）。
- **D3** 已声明 scope 的仓，label 取 scope（A 现口径）还是恒取仓 slug（声明只管名字）？
- **D4** 本期是否加静态 lint（spawn 内禁会话名作放置键）并关闭遗留 `O2`？**D5** 发版形态：PATCH（放置语义变更 + 迁移说明）还是并入下次 MINOR。

- 修订：2026-11-13 首版（诊断复现 + 三候选 + 推荐 A + 影响面 + 待拍板）
