# PRD：舰队工具修复批（别名解析 + 守卫 + 跨仓回收）（#19）· T509

> Issue：[#19](https://github.com/Nathan3303/nao-skills/issues/19) · 批次：T509 · 分支：`fix/19-alias-resolution`（base `main`）
> 版本影响：**PATCH `0.12.0 → 0.12.1`**（纯 fix；npm 发布由用户执行，tag/Release 由 PM 出）· 执行：rd-infra · 验证：qa
> 状态：**已开工**（用户 2026-10-08 批准「两批分别」+「close 缺陷并入 #19」+「修完即发 PATCH」）· 正文为权威（Issue 只放摘要与指针）

## 0. 背景

下游三批迁移（T506/T507/T508）期间，PM 实测踩到两类**工具层缺陷**，均已定位到同一文件 `.agents/scripts/nao-fleet.sh`：

1. **#19 别名解析失效**：`ensure arch` / `ensure infra` 报「未知角色」。根因已定位：`load_manifest()` 第 135 行 `ALIAS) ALIAS_ROLE["$v"]="$w"` 把**键值写反**（实际得到「角色 id → 别名」），而消费方（`resolve_role` L276、`close` L1127）按「别名 → 角色 id」取值 ⇒ 同一角色多个别名时后者覆盖前者，`roles.yaml` 中排在 canonical id 之前的别名（`arch`、`infra`）全部丢失。**本会话全程只能使用 canonical id 回避此缺陷。**
2. **（并入本单 · 2026-10-08 用户裁定）`close` 跨仓派生会话回收失败且静默**：T507 / T508 各复现一次 —— 在 nao-skills 仓内执行 `close --task <批次> <别名>`，目标会话在另一仓且 pane 存活（`tmux list-panes` 标题正常，如 `π - qa-T508 - nue-ui`），却报「未运行（无需回收）」⇒ **回收失败且不报错**，PM 只能 `tmux kill-pane` 手工兜底。另一现象：`close --task T508 qa-T508`（用派生会话名）报「未知角色」。

另：`check` 目前只校验「aliases 非空」，**不校验每个别名可解析、也无跨角色重名校验** ⇒ 上述缺陷长期静默（无回归守卫）。

## 1. 问题证据

| 证据 | 数据 |
| :--- | :--- |
| 别名失效 | `ensure arch` / `ensure infra` → `未知角色`（可用列表只列 canonical id）；`ensure arch-designer` / `rd-infra` 正常 |
| 根因 | `nao-fleet.sh:135` 键值方向反；消费方 L276（`resolve_role`）、L1127（`close`）均按反方向消费 |
| 文档与实现不符 | README「用起来（3 步）」示例命令 `ensure pm arch rd-fe rd-be qa rd-infra` 实际**直接失败** |
| 无守卫 | `cmd_check` 仅校验 aliases 非空 ⇒ 键值反写可长期存活（本会话三批开发期间未被告警） |
| 回收静默失败 | `close --task T507 qa` / `close --task T508 qa` → rc=0 + 「未运行（无需回收）」而 pane 存活；**另一症状（QA 发现）**：`close qa-T508`（无 `--task`）→ **rc=0 静默 no-op** |
| 宿主定位链路 | `find_pane_for()` 三级后备（① 标题契约 ② intercom 名册 tmuxPane ③ 本仓未认领 pane 兜底）——**跨仓场景下三级全未命中**；**QA 已定位根因**：repo 恒由 `ROLE_WS=「.」`取本仓 ⇒ 三级均按「本仓」匹配而目标在另一仓；叠加 `offline_verifiable` 为真 ⇒ 走 `log「未运行」+ return 0` 分支（**假阴性不报错**） |
| `close` 目标解析 | 派生会话名（`qa-T508`）不被接受（只认 roles.yaml 角色名） |

## 2. 目标指标

| 指标 | 现状 | 目标 |
| :--- | :--- | :--- |
| 别名可用性 | `arch`/`infra` 失效（仅 canonical id 可用） | **`roles.yaml` 声明的每个别名均可解析**（含 `arch` → `arch-designer`、`infra` → `rd-infra`） |
| 守卫强度 | 仅「aliases 非空」 | 每个别名**可解析** + **无跨角色重名**，违例 `check` 必须非 0 并指名问题 |
| 回收行为 | 跨仓派生会话**静默不回收** | **真实回收**；做不到时必须**非静默**（非 0 + 明确诊断，不得报「未运行」而 pane 仍在） |
| 版本可知性 | 0.12.0 | **0.12.1**（PATCH） |

## 3. 范围 / 非范围

| IN | OUT |
| :--- | :--- |
| `.agents/scripts/nao-fleet.sh`：`ALIAS_ROLE` 修复 + `close` 宿主定位/目标解析修复 + `cmd_check` 守卫 | ❌ 角色语义 / 闸门语义 / 流程变更（BR：不变） |
| `tests/t4/`：新增/扩展用例覆盖「键值反写检出」「别名全可解析」「跨仓回收」 | ❌ `bin/nao-skill.js`（migrate CLI —— 属 **#21 / T510**） |
| `README.md` / 角色卡示例命令与别名一致 | ❌ `.agents/skills/**` 内容 · `.agents/common|checklists|templates` |
| `package.json` 版本 → `0.12.1` + `docs/releases/v0.12.1.md` | ❌ 上游 ADR 语义改写（F3/F4 属 T510） |

## 4. 用户场景

| # | 场景 | 期望 |
| :--- | :--- | :--- |
| S1 | 照 README 示例启动 | `ensure pm arch rd-fe rd-be qa rd-infra` 全部成功（别名可用） |
| S2 | 别名配置写错 | `check` 立即非 0 并指出「哪个别名解析不到 / 哪个别名跨角色重名」 |
| S3 | 跨仓批次收尾 | `close --task T508 qa` 真正关掉目标 pane；若无法定位则非 0 + 明确诊断 |
| S4 | 升级 | `npm i @nathan33/nao-skill@0.12.1` 即得修复（下游无需改动） |

## 5. 业务规则

- **BR1** 只修实现与守卫，**不改**角色定义、闸门语义、流程
- **BR2** 别名与 canonical id 双轨均须可用（向后兼容：现有 canonical id 用法不得回归）
- **BR3** 回收类命令**不得静默失败**（要么真做，要么非 0 + 诊断）
- **BR4** 不改历史归档文档（PRD/ADR/release 旧条目）
- **BR5** tests 与 docs 之外的源码一律不动

## 6. NFRs

| # | 要求 |
| :--- | :--- |
| NFR1 | `npm test`（`check` + `tsc -p tsconfig.agents.json`）exit 0 |
| NFR2 | `tests/t4/run.sh` 全绿（含新增用例），断言数只增不减 |
| NFR3 | `check` 在**正常态**仍 exit 0 且 `roles=6`；仅在违例构造场景非 0 |
| NFR4 | 修复对三批已迁移仓（nao-todo / nao-todo-server / nue-ui）**零影响**（只读校验其 `check` 仍 0） |

## 7. AC

| AC | 类型 | 内容 |
| :--- | :--- | :--- |
| AC1 | 主路径 | `ensure arch` 与 `ensure infra` **实拉成功**（不报未知角色、`--name <role>[-<task>]` 正确、角色卡已注入）—— **PM 已授权实跑**（用派生名如 `--task T509R` 避免撞名，回执需报 pane id 并自行 `tmux kill-pane` 收尾）；同时 6 个 canonical id（`pm`/`arch-designer`/`rd-fe`/`rd-be`/`qa`/`rd-infra`）**全部仍正常**（BR2 不回归） |
| AC2 | 异常 | `check` 守卫有效，**四点夹具均须使 `check` 非 0** 且输出指名问题（PM 2026-10-08 按 QA 实测口径细化）：① **声明的别名无法解析**（`ALIAS_ROLE` 键值反写复现）② **某角色的 canonical id 未登记进 `aliases`** ⇒ 该 id 解析不到（BR2 兼容性）③ **别名跨角色重名** ④ 既有回归：`aliases: []`/字段缺失仍非 0。正常态 `check` exit 0 且 `roles=6` |
| AC3 | 主路径 | **`close` 跨仓派生会话真实回收**：目标会话位于另一仓、pane 存活且 `title` 正常时，`close --task <批次> <别名>` 须关掉该 pane（或至少**非静默**：非 0 + 明确诊断 + 给出可操作提示），**不得出现「未运行（无需回收）」而 pane 仍在**；`close` 对派生会话名（`qa-T508`）的支持与否须在 README 写明（不支持则给出明确报错文案） |
| AC4 | 设计一致性 | `README.md`（及角色卡/help 文案）示例命令与实际别名一致：`ensure arch`/`ensure infra` 类别名示例可用；若 README 有「可用别名」表须与 `roles.yaml` 逐项一致 |
| AC5 | 门禁 | `npm test` exit 0 · `tests/t4/run.sh` 全绿（含新增守卫/回收用例）· `nao-fleet.sh check` exit 0 且 `roles=6` · `status` 无假残留（跨仓派生会话不再误报「仅散文提及/未运行」） |
| AC6 | 负向闭环 | 三批已迁移仓（nao-todo / nao-todo-server / nue-ui）`check` 仍 exit 0（NFR4）；`0.12.1` 版本号在 `package.json` 与 `docs/releases/v0.12.1.md` 一致 |
| AC7 | 治理 | PR 标题用户可读（禁纯编号/类名/路径）· `main` 合并后本批**恰好 1 条**提交、无 `wip()` · 工作区干净 |
| AC8 | 非范围守护 | diff 审查确认未碰 `bin/nao-skill.js` · `.agents/skills/**` · `.agents/{common,checklists,templates}` · 角色语义/闸门语义 · 历史归档文档 |

## 8. 待验证项（实施第一步）

| # | 待验证 | 影响 |
| :--- | :--- | :--- |
| V1 | `ALIAS_ROLE` 修好后，`close`（L1127）与其它消费方语义是否一致（是否还有第三处消费） | 决定修复是否单点 |
| V2 | 跨仓 `close` 三级后备各自失败原因（① 标题契约是否要求「本 tmux 会话/pane 归属」② intercom 名册 `tmuxPane` 是否含跨仓派生会话 ③ fallback 是否限定「本仓」） | 决定 AC3 的实现路径与可行性 |
| V3 | `tests/t4` 现有 8 用例是否已覆盖 `roles.yaml` 解析（新增用例编号与断言数基线） | 决定守卫用例落点 |
| V4 | 三批已迁移仓的 `check` 在 0.12.1 下是否真无影响（NFR4 证据） | AC6 |

## 9. 上线闭环 / 变更治理

| 项 | 内容 |
| :--- | :--- |
| 闭环 | Issue #19 转实施单 → 分支 `fix/19-alias-resolution` + Draft PR → qa 用例先行 → rd-infra 修复 → qa 复跑 + PR 评论门禁数字 → 上游 PM 验收 → RD squash 合并 → PM 出 tag `v0.12.1` + GitHub Release（notes = `docs/releases/v0.12.1.md`）→ 用户执行 npm publish → 发布后核验 |
| Reviewer | 无（单点缺陷 + 守卫；不涉架构/NFR 选型 ⇒ 免 arch 评审） |
| 发布 | **PATCH**：`gh auth status` 可用则 `gh release create v0.12.1 --notes-file docs/releases/v0.12.1.md`；tag 必须指向 `main` 合并提交；npm 由用户执行 |
| 回滚 | `git revert <squash 提交>`；下游无需动作（仅升级依赖） |
| 后续 | **T510（#21）**：migrate 收尾 F3/F4/F7（F4 需 arch 拍板 `--no-shim` vs 自动识别）；本单不夹带 |

## 10. 优先级

| 环节 | 结论 |
| --- | --- |
| 战略筛子 | 通过（**工具可用性缺陷 + 缺守卫**，已实际干扰三批开发） |
| MoSCoW | Must：别名修复 + `check` 守卫 + 跨仓 `close`；Should：文档示例一致性；Won't：#21 F3/F4/F7 |
| RICE | R=4 仓（本仓 + 三批下游）· I=2（消除「示例命令直接失败」+「回收静默失败」）· C=0.9（根因已定位、改动局部）· E=小 → 高 |
| Kano | Must-be（命令不可用 / 静默失败 = 缺失项） |

## 11. 验收结论（待填）

| 项 | 结果 |
| :--- | :--- |
| — | 验收后由 PM 填写 |
