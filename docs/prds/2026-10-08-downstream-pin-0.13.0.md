# PRD：下游三仓 pin 升级到 0.13.0 + 清理废弃标记 · T511

> Issue：[#25](https://github.com/Nathan3303/nao-skills/issues/25)（上游代管批）· 批次：T511 · 三仓各自分支：`chore/<issue>-pin-0.13.0`（nao-todo / nao-todo-server 的 base = `main`；nue-ui 的 base = **`master`**）
> 版本影响：**三仓自身无版本号变化**（仅机制 pin + 删除废弃标记）· 执行：rd-infra ×3（并行）· 验证：qa（统一）
> 状态：**已开工**（用户 2026-10-08 批准「三仓并行」）· 正文为权威

## 0. 背景

上游 `@nathan33/nao-skill` 已发布 **0.13.0**（0.12.1 亦已发布）。三批迁移（T506/T507/T508）把三仓切到 pi 包形态时 pin 的是 **0.12.0**，因此三仓当前仍跑带缺陷的旧版：

- **0.12.1 修复**（#19）：`ensure arch` / `ensure infra` 别名可用、`check` 增别名守卫、`close` 跨仓回收不再静默失败
- **0.13.0 修复**（#21）：`migrate` 按需写 shim（minimal 型不写）、`.nao-migrated` 死标记移除、lock 去重不再受排版影响、B2 去重提前

用户已定：**不逐版升，一次升到 0.13.0**（省 3 个 PR），并**顺手删除 `.agents/.nao-migrated`**（ADR `2026-10-08-migrate-shim-and-marker.md` 决策 1 后果条：存量文件由本批手动删除，代码不自动删）。

## 1. 问题证据

| 证据 | 数据（2026-10-08 实测） |
| :--- | :--- |
| 三仓 pin 陈旧 | `.pi/settings.json` 均 `npm:@nathan33/nao-skill@0.12.0` |
| 旧版缺陷真实存在 | 0.12.0 下 `ensure arch` 报「未知角色」（本会话实测）；`close` 跨仓报「未运行」而 pane 存活（T507/T508 各复现） |
| 废弃标记仍在 | 三仓 `.agents/.nao-migrated`（tracked，内容 `0.12.0`）—— 0.13.0 起不再写入且无任何读取方 |
| 上游已发布 | `dist-tags.latest = 0.13.0` · 0.12.1/0.13.0 的 tarball 与本地 tag pack 逐字节一致（PM 已核验，见 `docs/reports/2026-10-08-T510-postpublish-verify.md`） |

## 2. 目标指标

| 指标 | 现状 | 目标 |
| :--- | :--- | :--- |
| 机制版本 | 三仓 pin 0.12.0 | **pin 0.13.0** 且 `pi install -l` 物化成功 |
| 别名可用性 | 三仓 `ensure arch` 失败 | **可用**（随 0.12.1 修复） |
| 废弃标记 | 三仓 `.agents/.nao-migrated` 存在 | **删除**（tracked → 从索引移除） |
| 机制资产面 | 不变 | **不变**（仅 pin + 删 1 个废弃文件） |

## 3. 范围 / 非范围

| IN | OUT |
| :--- | :--- |
| 三仓 `.pi/settings.json` pin → `0.13.0` | ❌ 任何源码 / 测试 / 构建配置 / CI |
| 三仓删除 `.agents/.nao-migrated`（git rm） | ❌ `.agents/` 其它残留项（shim / 自有 skill / `commands/` / `.nao-obsolete` / `.nao-version`） |
| 三仓 `pi install -l --approve` 物化 + `check` rc0 | ❌ 历史归档文档 · 各仓 AGENTS.md 机制段（T506/T508 已改写，本批不动） |
| 三仓 PR（各自 squash 合并） | ❌ 三仓版本号 / CHANGELOG（无产品变更） |

## 4. 用户场景

| # | 场景 | 期望 |
| :--- | :--- | :--- |
| S1 | 在三仓里指挥舰队 | `ensure arch` / `ensure infra` 直接可用（不再需要 canonical id 绕行） |
| S2 | 跨仓收尾会话 | `close --task <编号> <别名>` 真实回收（不再静默「未运行」） |
| S3 | 新机器 clone | 从 `.pi/settings.json` 得知 pin 0.13.0，一条命令物化 |
| S4 | 读仓内机制痕迹 | 不再看到无用的 `.nao-migrated`（版本唯一由 `.nao-version` + pin 表达） |

## 5. 业务规则

- **BR1** 只动 pin 与废弃标记；**不碰**源码/测试/构建配置/CI（各仓既定红线不变，nao-todo 另含 `packages/`、`apps/`）
- **BR2** 历史归档文档不改
- **BR3** 每仓一个 PR、squash 合并；PR 标题用户可读
- **BR4** 删除 `.nao-migrated` 后，`.agents/` 机制类资产面不得变化（仅 -1 个废弃文件）

## 6. NFRs

| # | 要求 |
| :--- | :--- |
| NFR1 | 三仓 `bash .agents/scripts/nao-fleet.sh check` **rc=0 · roles=6**（物化后） |
| NFR2 | 各仓原有门禁不回归（nao-todo：`vp check` 等；nao-todo-server：Go build/vet/test；nue-ui：`vp fmt --list-different .` = 0 文件 + `test:run`）—— 本批不改代码，**只要求按各仓既有口径复跑关键项并记录** |
| NFR3 | 机制包缺失时仍 `exit 2 + DEGRADED:`（沿用既有 shim 行为，不需重验） |

## 7. AC

| AC | 类型 | 内容 |
| :--- | :--- | :--- |
| **AC1** | 主路径 | 三仓 `.pi/settings.json` 的 `packages` 含 `npm:@nathan33/nao-skill@0.13.0`；`pi install -l --approve` rc=0 且 `.pi/npm` 物化为 0.13.0 |
| **AC2** | 边界 | 三仓 `.agents/.nao-migrated` 已从索引删除（`git ls-files .agents` 不再含它）；**其余 `.agents/` 残留项数量与内容不变**（nao-todo：shim + `nue-ui` 自有 skill；nao-todo-server：shim；nue-ui：shim + `nue-ui-dev` + lock 3 目录 + `commands/commit.md`） |
| **AC3** | 门禁 | 三仓 `check` rc=0 · `roles=6`；各仓既有门禁关键项按 PRD §6 NFR2 口径复跑并记录精确数字 |
| **AC4** | 负向/能力 | 三仓 **`ensure arch` 可用**（不报未知角色；用派生名实拉并自行回收，或经 `check` 别名守卫 + 实拉至少一仓） |
| **AC5** | 非范围守护 | diff 仅含 `.pi/settings.json` + `.agents/.nao-migrated`（+ 可能的 `.pi/npm` 本地物化，gitignored）；源码/测试/CI/历史文档命中 0 |
| **AC6** | 治理 | 每仓 PR 标题用户可读 · 合并后各仓主干（`main`/`master`）本批**恰好 1 条**提交、无 `wip()` · 工作区干净 |

## 8. 待验证项（实施第一步）

| # | 待验证 | 影响 |
| :--- | :--- | :--- |
| V1 | 各仓 `pi install -l --approve npm:@nathan33/nao-skill@0.13.0` 是否会因 `devEngines`（nue-ui pnpm 11.21.0）受阻 | 决定是否需要仓外执行/等价手段 |
| V2 | nue-ui base 是 `master`（非 main）—— 分支与 PR base 需一致 | 决定 PR 创建参数 |
| V3 | 三仓是否另有引用 `.nao-migrated` 的文档/脚本（若有，需同批标注） | 决定 AC2 的完整性 |

## 9. 上线闭环 / 变更治理

| 项 | 内容 |
| :--- | :--- |
| 闭环 | 上游 Issue #25 立项 → 三仓各自分支 + Draft PR → rd-infra 实施（三仓并行）→ qa 统一复核（三仓）→ PM 验收 → 各仓 RD squash 合并 → 归档 |
| Reviewer | 无（纯 pin + 删废弃文件；设计已由 ADR 决策 1 与用户拍板确定） |
| 回滚 | 各仓 `git revert <squash 提交>` + pin 回退 0.12.0（机制包仍在 npm） |
| 后续 | B1（legacy 目录名判定过宽）与 D6（`failWarn` 文案）另议 · D7（未信任目录的 close 语义）仅记录 |

## 10. 优先级

| 环节 | 结论 |
| --- | --- |
| 战略筛子 | 通过（**让三仓吃到 0.12.1/0.13.0 的修复**，消除别名与回收缺陷） |
| MoSCoW | Must：pin 升级 + 删废弃标记；Should：三仓门禁复跑记录；Won't：B1/D6 修复 |
| RICE | R=3 仓 · I=1（工具体验与正确性）· C=0.95（机械变更，上游已核验）· E=**最小** → 高 |
| Kano | Must-be（旧版命令不可用 = 缺失项） |

## 11. 验收结论（待填）

| 项 | 结果 |
| :--- | :--- |
| AC1–AC5 | **全部通过**（三仓） |
| AC6 | **部分偏差（已接受）**：三仓主干提交主题保留了 `wip(T511x):` 前缀（其余治理项全过）——根因：**PR 只有 1 条提交时 `gh pr merge --squash` 取该提交 subject 而非 PR 标题**；nao-todo / nao-todo-server 主干受保护（`allow_force_pushes=false` + `enforce_admins=true`）**不可回溯**，nue-ui 技术可改但按统一口径**不改写历史** ⇒ **流程修正已落 `.agents/skills/github-flow.md`**（合并必须显式 `--subject`） |
| 合并（PM 独立复核） | nao-todo PR [#190](https://github.com/Nathan3303/nao-todo/pull/190) → `main` **`ffc9c4f0`** · nao-todo-server PR [#51](https://github.com/Nathan3303/nao-todo-server/pull/51) → `main` **`1f729cb`** · nue-ui PR [#74](https://github.com/Nathan3303/nue-ui/pull/74) → `master` **`bb5c3901`**；各**恰好 1 条** · 各 **2 文件**（`D .agents/.nao-migrated` + `M .pi/settings.json`）· pin = `0.13.0` · `.agents` 入库 **7 / 2 / 31** 且不含废弃标记 · 分支已删 · 工作区干净 |
| 门禁（RD 自报 + QA 独立复跑） | nao-todo：`check` 0 · `vp check` 0（1544 格式 / 1297 lint+type 0 错）· **`vp test --run` 231 文件 / 1824 例 / 0 红** · 5 个 guard 0 · `webapp build` + `desktop:build` 0 · 移动端红线 0 ｜ nao-todo-server：`check` 0 · go build/vet/test 0（65 包 21 ok/44 no-test/0 FAIL）· `gofmt -l` 空 · `golangci-lint` **0 issues** ｜ nue-ui：`check` 0 · `vp fmt --list-different .` **0 文件** · `test:run` **33 文件/358 例/0 红**（pre-push 亦跑，未 `--no-verify`） |
| AC4 实拉（修复前不可用） | 三仓 `ensure arch` 均 **rc=0**（修复前报「未知角色」）：RD pane `%61`/`%64`/`%65` + QA pane `%66`/`%67`/`%68`，全部经 `close` 回收，**残留 0** |
| AC1 物化一致性 | 三仓 `.pi/npm/.../package.json` version = **0.13.0**，物化 `.agents/` 与 `package.json` 与 tag `v0.13.0` **逐字节一致**（QA 核） |
| 缺陷 | **0**（1 项治理偏差已接受 + 已修流程） |
| 遗留（后续项，均不阻塞） | ① **O1** nao-todo `AGENTS.md:131` 仍把 `.nao-migrated` 列为「0.12.0 起入库面」（本批机制段 OUT）→ 后续收敛 ② **B8** `close` 同名跨仓不可定向（纪律 = 仓级唯一任务号；工具侧可叠加名册 cwd 约束，未开单）③ `.nao-version` 仍 `0.12.0`（0.13.0 无读取方，版本权威 = pin） |
