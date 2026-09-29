# T401 — 舰队工程基座：close 修复 + 发版 + 布局机制评估 + 跨仓一致性核对

- 状态：已交付 · 更新：2026-09-30 · Owner：rd-infra
- 指针：PR #10（① ② 已合并，`e754ab4`）· 发布说明 `docs/releases/v0.9.3.md` · 脚本 `.agents/scripts/nao-fleet.sh:1002`

## 一句话

① 定位并修复 `close` 回收空闲会话崩溃（`bus` 未绑定，`set -u`）；② 发版 0.9.2 → 0.9.3；
③ 「nao-todo 默认 main-col」推荐 **项目 wrapper + 文档**（不动上游）；④ nao-todo 仅差本修补丁、nue-ui 停在 v0.7.0（含格式化差异）、nao-todo-server 为 roles.yaml 前的旧版。

## ① `close` 崩溃（已修，PR #10）

- **根因（复核确认）**：`pane_busy "$pane" && bus="…"`——`pane_busy` 返回假时 `&&` 短路，`bus` 未赋值；随后 `[[ -n "$bus" && … ]]` 在 `set -u` 下报未绑定。`&&` 列表失败来自被豁免位置，`set -e` **不退出**，故走到下一行才炸（实测 `--foo && x=1` 不触发 `set -e`）。
- **修法**：改为显式 `if pane_busy "$pane"; then bus="…"; else bus=""; fi`，两分支必赋值；闸门与落地逻辑未动。
- **实测（tmux）**：

  | 场景 | 结果 |
  | :--- | :--- |
  | 修复前 · 空闲 `close` | exit=1 · 行 1007 `bus: 未绑定的变量` |
  | 修复后 · 空闲 `close --task` | exit=0 · 已回收 |
  | 修复后 · 重跑（幂等） | exit=0 · 未运行（无需回收） |
  | 修复后 · 在跑 turn | exit=1 · 拒绝 + 提示 |
  | 修复后 · 在跑 turn `--force` | exit=0 · 已回收 |
  | 闸门① tasks-state 进行态 | exit=1 · 拒绝（`--force` → exit=0） |

- **全脚本审计**：`&&`/`||` 变量赋值点 **26 处**（16 处为 `(( … )) && var=` 算术夹取），**仅本处**未绑定；其余 25 处的变量均在引用前赋初值（`found`/`ok`/`seen`/`rc`/`disp`/`repo`/`pct`/`min_w` …），无隐患。

## ② 发版 0.9.3

- `package.json` `0.9.2 → 0.9.3`；新增 `docs/releases/v0.9.3.md`（本仓无 `CHANGELOG.md`，发布说明落 `docs/releases/`；README **无版本 pin**，无需同步）。
- 门禁：`nao-fleet.sh check` → exit=0 · roles=6 · files=39；`check -v` 无 warn；`npm pack --dry-run`（prepack=check）→ exit=0，包 0.9.3 / 43 文件 / 92.1 kB。
- **发布命令（用户/PM 执行）**：
  - 打 tag + Release：`git tag -a v0.9.3 -m "v0.9.3 修复 close 空闲会话崩溃" && git push origin v0.9.3 && gh release create v0.9.3 --title "v0.9.3 修复 close 空闲会话崩溃" --notes-file docs/releases/v0.9.3.md`
  - npm 发布（**由用户本人执行**）：`cd nao-skills && npm publish`（`prepack` 会自动跑 `check`）。
- 角色卡版本不变：`pm v21 / rd-infra v1 / rd-fe v10 / rd-be v10 / qa v11 / arch v10`。

## ③ 「nao-todo 默认 main-col」机制评估

**前置事实（实测，`main_row2_geom`，n=6，pct=35，min=30）**：窄窗口**已被 v0.9.0 自动回退覆盖** —— W=100 最窄列 21、W=120 最窄列 25（均 <30）⇒ 已自动走 `main-col`；仅 W≳146（最窄列 ≥30）才留在 `main-row2`。故「硬默认 main-col」是**偏好调整**，非窄窗口缺陷修复。

| 方案 | 代价 / 风险 |
| :--- | :--- |
| a) 项目 wrapper `nao-up.sh` | 零上游改动、可逆；但**仅当调用方走 wrapper 才生效**，直接 `nao-fleet.sh ensure` 会绕过 |
| b) 脚本读 `<repo>/.agents/config` | 对所有调用路径**权威生效**；但**改上游行为、影响所有下游**，且需定「读哪个 repo / env 优先级 / check 与 spawn 一致性」 |
| c) 仅文档约定（AGENTS.md 带 env） | 零代码；但**靠纪律**，易漏（nao-todo AGENTS.md 已记该 env，仍需人手传） |

**推荐：a + c（不推荐 b）**。理由：a 用项目 wrapper 把 `NAO_TMUX_LAYOUT=main-col` 固化，c 在 AGENTS.md 写明「统一经 `nao-up.sh`」；两者都不改上游、不影响其他仓。**b 需 PM 裁决**（上游行为变更），且即使要做也应单独发版 + 明确「env > config > 默认」优先级与 repo 解析口径。

- **待 PM 拍板**：a/c 落在 **nao-todo**（下游），与你 ④「不改下游、等我说同步」交叉 —— 确认后我即可起分支落地（wrapper 内容与 AGENTS.md 一句话改动，均 <10 行）。

## ④ 跨仓 `.agents` 一致性核对

| 仓库 | 版本 | 角色 | 脚本行/sha |
| :--- | :--- | :--- | :--- |
| nao-skills（本仓@main） | 0.9.3 | 6（含 rd-infra） | 1129 · `9c2d2c46…` |
| nao-todo | 0.9.2 | 6 | 1123 · `e8b58d48…` |
| nue-ui | 0.7.0 | 5（无 rd-infra） | 854 · `f854df71…` |
| nao-todo-server | 无 `.nao-version` | 无 `roles.yaml` | 396 · `59db2b9c…` |

- **nao-todo**：与 nao-skills **唯一差异**= `nao-fleet.sh`（0.9.3 修补丁）+ `.nao-version` + 项目自定义 `skills/nue-ui/`。`roles.yaml` sha 与上游**完全相同**（`6ec44ac5…`）。
- **nue-ui**：`nao-fleet.sh` 与 **v0.7.0 tag 逐字节相同**；但其余机制文件与 v0.7.0 **不同**（抽样 `checklists/pm.md` 26 行、`prompts/product-manager.md` 18 行、`skills/commit.md` 8 行）——抽样均为**格式化/换行**差异（表格对齐、列表缩进、末尾换行），未见语义改动。另有项目自定义目录（`commands/`、`agent-browser`、`find-skills`、`skill-creator`、`nue-ui-dev`）。
- **nao-todo-server**：roles.yaml 之前的**硬编码角色**版本（case 分支写死 5 角色），无 `roles.yaml`/`checklists/`；其 sha 在本仓历史中**无匹配提交**（早于首版或外部来源）。

**同步建议（分级，均建议先备份 + 影子副本试跑）**：

- **nao-todo → 0.9.3（低风险，优先）**：改动面仅 1 个脚本 + `.nao-version`；`nao-skill update` 或直接同源替换即可。**等 PM 发「同步」**（本次未动下游）。
- **nue-ui → 0.9.3（中风险）**：0.7.0 → 0.9.3 跨 4 个 minor，`update` 为**源优先**会覆盖上述格式化差异；先 `diff` 全量确认无本地语义定制（抽样未见），再在影子副本跑 `update` + 全仓 `check`，通过后提交。附带获得 rd-infra 角色（6 角色）、pm-operations/pm-routing、qq-notify 与 v0.9.0 布局守卫、v0.9.3 close 修复。
- **nao-todo-server（高风险）**：等价于**新装**（需新增 `roles.yaml` + 补齐 checklists/prompts frontmatter）；建议 `nao-skill install` 到分支后逐文件 review，或明确「该仓暂不纳入舰队」。

- 修订：2026-09-30 首版。
